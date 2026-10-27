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

## Help and community

Please [open an Issue](https://github.com/PopeKael/wazza-images/issues) to report a bug or suggest a safer or more useful image-filing workflow. Include your Windows/PowerShell version, local vision model and steps to reproduce, but do not upload private photographs, filenames containing personal details or local credentials.

Part of [Garage Alchemy](https://garage.dia.net.au/): useful tools, practical experiments, and the lessons learned while building them.

**Support is optional:** [Buy Me a Coffee](https://buymeacoffee.com/warrengerdes) · [Join the Tribe on Patreon](https://www.patreon.com/c/chanyawazza). No payment is required to use or contribute to this project under its licence.
