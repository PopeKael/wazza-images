[CmdletBinding()]
param(
    [string]$Root = 'D:\Downloads\Images',
    [switch]$Force,
    [switch]$Apply,
    [switch]$RetryUndecided,
    [int]$SampleSize = 5,
    [int]$MaxBytes = 25MB,
    [string]$Model = 'qwen2.5vl:7b',
    [int]$ContextSize = 8192,
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = 'Stop'
$started = Get-Date
$script:Root = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$script:Ollama = 'http://127.0.0.1:11434'
$script:StatePath = Join-Path $script:Root '_image-filer-state.json'
$script:RollbackPath = Join-Path $script:Root '_image-filer-rollback.csv'
$script:ReportMd = Join-Path $script:Root '_image-filer-report.md'
$script:ReportCsv = Join-Path $script:Root '_image-filer-report.csv'
$script:DoneDir = Join-Path $script:Root 'Done'
$script:UndecidedDir = Join-Path $script:Root 'Undecided'
$script:Supported = @('.jpg','.jpeg','.png','.gif','.bmp','.tif','.tiff','.webp')
$script:ImageCandidates = $script:Supported + @('.jfif','.heic','.heif','.avif','.ico','.raw','.cr2','.nef','.orf','.dng')

function Assert-InRoot([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if ($full -ne $script:Root -and -not $full.StartsWith($script:Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Safety stop: path is outside Root: $full" }
    return $full
}
function Get-SafeLeaf([string]$Text) {
    $s = ($Text -replace '[^a-zA-Z0-9]+','-').Trim('-').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($s)) { $s = 'image' }
    if ($s.Length -gt 70) { $s = $s.Substring(0,70).Trim('-') }
    return $s
}
function Get-ImageDate([IO.FileInfo]$File) {
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $img = [Drawing.Image]::FromFile($File.FullName)
        try {
            foreach ($id in 0x9003,0x9004,0x0132) {
                if ($img.PropertyIdList -contains $id) {
                    $raw = [Text.Encoding]::ASCII.GetString($img.GetPropertyItem($id).Value).Trim([char]0)
                    return ([datetime]::ParseExact($raw,'yyyy:MM:dd HH:mm:ss',$null)).ToString('yyyy-MM-dd')
                }
            }
        } finally { $img.Dispose() }
    } catch { }
    return $File.CreationTime.ToString('yyyy-MM-dd')
}
function Read-State {
    if (Test-Path -LiteralPath $script:StatePath) { try { return @(Get-Content -Raw -LiteralPath $script:StatePath | ConvertFrom-Json) } catch { } }
    return @()
}
function Save-State($State) { $State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $script:StatePath -Encoding UTF8 }
function Invoke-Ollama([hashtable]$Body) {
    Invoke-RestMethod -Uri ($script:Ollama + '/api/generate') -Method Post -ContentType 'application/json' -Body ($Body | ConvertTo-Json -Depth 8) -TimeoutSec $TimeoutSec
}
function Show-Stage([string]$Message,[ConsoleColor]$Color=[ConsoleColor]::Gray) {
    Write-Host ("  " + $Message) -ForegroundColor $Color
}
function Ensure-Model {
    try { $tags = Invoke-RestMethod -Uri ($script:Ollama + '/api/tags') -TimeoutSec 10 } catch { throw "Ollama is not reachable at $script:Ollama. Start Ollama and retry." }
    if (-not @($tags.models | Where-Object { $_.name -eq $Model })) {
        Write-Host "Pulling $Model..."
        Invoke-RestMethod -Uri ($script:Ollama + '/api/pull') -Method Post -ContentType 'application/json' -Body (@{name=$Model;stream=$false}|ConvertTo-Json) -TimeoutSec 3600 | Out-Null
    }
}
function Analyze([IO.FileInfo]$File) {
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($File.FullName))
    $prompt = @'
Inspect this image and return ONLY valid JSON with exactly these keys:
{"description":"brief factual description","short_name":"3 to 7 lowercase words","category":"one of people, places, documents, food, nature, technology, screenshots, vehicles, receipts, other","confidence":0.0}
Use confidence from 0 to 1. Set confidence below 0.70 if the image is unreadable, ambiguous, mostly blank, or you cannot identify a useful subject. Do not include dates, file extensions, markdown, or extra keys.
'@
    $r = Invoke-Ollama @{model=$Model;prompt=$prompt;images=@($b64);stream=$false;format='json';options=@{temperature=0;num_ctx=$ContextSize}}
    $json = $r.response | ConvertFrom-Json
    if (-not $json.description -or -not $json.short_name -or $null -eq $json.confidence) { throw 'Model returned incomplete JSON' }
    return $json
}
function New-UniquePath([string]$Directory,[string]$Base,[string]$Ext) {
    $dir = Assert-InRoot $Directory
    if ($Apply) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $candidate = Join-Path $dir ($Base + $Ext); $i=2
    while (Test-Path -LiteralPath $candidate) { $candidate = Join-Path $dir ("{0}-{1}{2}" -f $Base,$i,$Ext); $i++ }
    return $candidate
}
function Append-Rollback($Row) {
    if (-not (Test-Path -LiteralPath $script:RollbackPath)) { 'OriginalPath,NewPath,Timestamp,Confidence,Description,Result' | Set-Content -LiteralPath $script:RollbackPath -Encoding UTF8 }
    $Row | Export-Csv -LiteralPath $script:RollbackPath -Append -NoTypeInformation -Encoding UTF8
}

Assert-InRoot $script:Root | Out-Null
Ensure-Model
$state = @(Read-State); $stateByHash = @{}; foreach ($x in $state) { $stateByHash[$x.Hash] = $x }
if ($RetryUndecided) {
    $files = @(Get-ChildItem -LiteralPath $script:UndecidedDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $script:ImageCandidates -contains $_.Extension.ToLowerInvariant() })
} else {
    $files = @(Get-ChildItem -LiteralPath $script:Root -Recurse -File | Where-Object { $script:ImageCandidates -contains $_.Extension.ToLowerInvariant() -and $_.FullName -notlike "$script:DoneDir\*" -and $_.FullName -notlike "$script:UndecidedDir\*" })
}
if ($SampleSize -gt 0 -and $files.Count -gt $SampleSize) { $files = @($files | Select-Object -First $SampleSize) }
$rows = [Collections.Generic.List[object]]::new(); $counts = @{found=$files.Count;renamed=0;filed=0;undecided=0;skipped=0;failures=0}
foreach ($file in $files) {
    $original = $file.FullName; $hash=''; $newPath=$original; $confidence=''; $description=''; $result='failure'
    $number = [array]::IndexOf($files, $file) + 1
    Write-Host "[$number/$($files.Count)] OPEN: $original" -ForegroundColor Cyan
    Show-Stage ("Size: {0:N0} KB | Extension: {1}" -f ($file.Length / 1KB),$file.Extension.ToLowerInvariant())
    try {
        if ($file.Length -gt $MaxBytes) { throw "File exceeds MaxBytes ($MaxBytes)" }
        Show-Stage "READ: Loading image bytes" DarkGray
        $hash = (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
        if (-not $Force -and $stateByHash.ContainsKey($hash)) { $counts.skipped++; $result='skipped'; Show-Stage "SKIP: Already processed (use -Force to reprocess)" Yellow; $rows.Add([pscustomobject]@{OriginalPath=$original;NewPath=$original;Timestamp=(Get-Date).ToString('o');Confidence=$stateByHash[$hash].Confidence;Description=$stateByHash[$hash].Description;Result=$result}); continue }
        Show-Stage "QUERY: Sending image to Ollama model $Model (context $ContextSize)" DarkGray
        $analysis = Analyze $file; $confidence=[double]$analysis.confidence; $description=[string]$analysis.description
        Show-Stage ("RESPONSE: confidence={0:N2} | {1}" -f $confidence,$description) Green
        $date = Get-ImageDate $file; $base = "$date-$(Get-SafeLeaf $analysis.short_name)"; $ext=$file.Extension.ToLowerInvariant()
        if ($confidence -lt 0.70) { $targetDir=$script:UndecidedDir; $counts.undecided++ } else { $targetDir=$script:DoneDir; $counts.filed++; }
        $newPath=New-UniquePath $targetDir $base $ext
        if ($Apply) { Show-Stage "MOVE: $original" Yellow; Show-Stage "      -> $newPath" Yellow; Move-Item -LiteralPath $original -Destination $newPath -ErrorAction Stop; $result=if ($confidence -lt 0.70){'undecided'}else{'filed'}; if ($newPath -ne $original){$counts.renamed++}; Append-Rollback ([pscustomobject]@{OriginalPath=$original;NewPath=$newPath;Timestamp=(Get-Date).ToString('o');Confidence=$confidence;Description=$description;Result=$result}); $state += [pscustomobject]@{Hash=$hash;OriginalPath=$original;NewPath=$newPath;Confidence=$confidence;Description=$description;ProcessedAt=(Get-Date).ToString('o');Result=$result}; Show-Stage "DONE: $result" Green }
        else { $result='dry-run'; Show-Stage "PLAN ONLY: would move to" Magenta; Show-Stage "            $newPath" Magenta }
    } catch {
        $counts.failures++; $description=$_.Exception.Message; $result='failure'; Show-Stage "ERROR: $description" Red
        if ($Apply -and $original -and (Test-Path -LiteralPath $original) -and $original.StartsWith($script:Root + '\', [StringComparison]::OrdinalIgnoreCase) -and $original -notlike "$script:UndecidedDir\*") {
            try {
                $targetDir=$script:UndecidedDir; $date=(Get-Item -LiteralPath $original).CreationTime.ToString('yyyy-MM-dd')
                $newPath=New-UniquePath $targetDir "$date-unreadable-$(Get-SafeLeaf ([IO.Path]::GetFileNameWithoutExtension($original)))" ([IO.Path]::GetExtension($original).ToLowerInvariant())
                Move-Item -LiteralPath $original -Destination $newPath -ErrorAction Stop
                $counts.undecided++; Append-Rollback ([pscustomobject]@{OriginalPath=$original;NewPath=$newPath;Timestamp=(Get-Date).ToString('o');Confidence=$confidence;Description=$description;Result='undecided-unreadable'}); $result='undecided-unreadable'; Show-Stage "QUARANTINED: $newPath" Yellow
            } catch { $description += "; quarantine failed: $($_.Exception.Message)" }
        } elseif ($original -like "$script:UndecidedDir\*") { Show-Stage "RETAINED: remains in Undecided after retry failure" Yellow }
    }
    $rows.Add([pscustomobject]@{OriginalPath=$original;NewPath=$newPath;Timestamp=(Get-Date).ToString('o');Confidence=$confidence;Description=$description;Result=$result})
}
if ($Apply) { Save-State $state }
$elapsed=((Get-Date)-$started).ToString()
$rows | Export-Csv -LiteralPath $script:ReportCsv -NoTypeInformation -Encoding UTF8
@("# Safe Image Filer report","","- Total files found: $($counts.found)","- Renamed files: $($counts.renamed)","- Filed files: $($counts.filed)","- Undecided files: $($counts.undecided)","- Skipped files: $($counts.skipped)","- Failures: $($counts.failures)","- Model used: $Model","- Context size: $ContextSize","- Processing time: $elapsed","- Mode: $(if($Apply){'APPLY'}else{'DRY-RUN'})","","See the CSV report for per-file details.") | Set-Content -LiteralPath $script:ReportMd -Encoding UTF8
Write-Host "Completed: found=$($counts.found), renamed=$($counts.renamed), filed=$($counts.filed), undecided=$($counts.undecided), skipped=$($counts.skipped), failures=$($counts.failures)"
