# Wazza Images

A safe local Windows image-filing utility using PowerShell and Ollama vision models.

The tool analyses images locally with `qwen2.5vl:7b`, proposes concise dated filenames, and moves results into two temporary folders:

- `Done` — confidently analysed images, later destined for Synology Vault
- `Undecided` — low-confidence, unreadable, unsupported, or failed analyses

It never deletes or rewrites image contents, never moves files outside the configured root, avoids overwriting existing names, supports dry-run and batch processing, and maintains state plus rollback logs locally. Those runtime files and the image corpus are intentionally excluded from this repository.

See [README-SafeImageFiler.md](README-SafeImageFiler.md) for setup, dry-run, batch, retry, verification, and rollback instructions.

## Quick start

```powershell
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -SampleSize 10
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -Apply -SampleSize 10
```

Retry files previously placed in `Undecided` with the larger vision context:

```powershell
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -RetryUndecided -SampleSize 0
PowerShell -ExecutionPolicy Bypass -File .\Invoke-SafeImageFiler.ps1 -Apply -RetryUndecided -SampleSize 0
```

## License

MIT. See [LICENSE](LICENSE).
