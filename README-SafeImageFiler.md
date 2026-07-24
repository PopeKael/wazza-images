# Safe Image Filer

`Invoke-SafeImageFiler.ps1` analyses images with Ollama `qwen2.5vl:7b`, using an 8,192-token context by default, and files results into exactly two temporary folders below `D:\Downloads\Images`: `Done` and `Undecided`. It never deletes or overwrites image contents and has a root-containment guard. Confident images are flattened into `Done`; their later move to Synology Vault is outside this tool.

## Setup

1. Install and start Ollama for Windows.
2. The script checks `http://127.0.0.1:11434/api/tags` and pulls `qwen2.5vl:7b` if absent. The first analysis request loads it for use.
3. If PowerShell blocks local scripts, use `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` once, or invoke with `-ExecutionPolicy Bypass`.

## First test: dry-run sample

```powershell
Set-Location 'D:\Downloads\Images'
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -SampleSize 3
```

The default is dry-run and the default sample is five images. This creates only the Markdown/CSV reports; it does not move files or write processing state. Inspect the proposed paths and descriptions.

The console now shows each stage for every image:

```text
[1/10] OPEN: D:\Downloads\Images\some-file.jpg
  READ: Loading image bytes
  QUERY: Sending image to Ollama model qwen2.5vl:7b
  RESPONSE: confidence=0.85 | crowded city street at dusk
  PLAN ONLY: would move to
              D:\Downloads\Images\Done\2026-06-09-urban-evening-scene.jpg
```

In apply mode, `PLAN ONLY` becomes `MOVE`, followed by the exact destination and `DONE`. Dry-run mode does not create output folders.

## Full dry-run

```powershell
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -SampleSize 0
```

## Apply changes

After reviewing the dry-run:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -Apply -SampleSize 3
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -Apply -SampleSize 0
```

The state file makes successful items idempotent by SHA-256 hash. Use `-Force` only when deliberately reprocessing. Images with confidence below `0.70`, unreadable files, oversized files, and model/API errors are reported; low-confidence images are placed in `Undecided` when applying. `Done` and `Undecided` are excluded from later scans.

To retry the existing `Undecided` batch after a context-size change:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -RetryUndecided -SampleSize 0
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -Apply -RetryUndecided -SampleSize 0
```

On retry, successful images move to `Done`; failures remain in `Undecided`.

Moves are verified by SHA-256. The tool tolerates a cloud-sync provider completing a move while PowerShell reports that the old source path has disappeared, and retries other transient move errors up to three times. It never overwrites an existing destination.

## Verification

Check `_image-filer-report.md` and `_image-filer-report.csv`. Confirm image counts and open a few filed images. The script excludes `Undecided` on later scans so uncertain items are not repeatedly reclassified accidentally.

## Rollback

`_image-filer-rollback.csv` records each applied move. Review it before reversing. This safe manual rollback does not overwrite an existing original:

```powershell
Import-Csv .\_image-filer-rollback.csv | Where-Object Result -ne failure | ForEach-Object {
    if ((Test-Path -LiteralPath $_.NewPath) -and -not (Test-Path -LiteralPath $_.OriginalPath)) {
        Move-Item -LiteralPath $_.NewPath -Destination $_.OriginalPath
    }
}
```

Keep the rollback CSV until satisfied with the result. The reports and state file are bookkeeping only; image bytes are not rewritten.

## Notes

EXIF `DateTimeOriginal`, `DateTimeDigitized`, or `DateTime` is used when readable; otherwise the file creation date is used. Names receive `-2`, `-3`, and so on if needed. The model receives image bytes only through the local Ollama endpoint.
