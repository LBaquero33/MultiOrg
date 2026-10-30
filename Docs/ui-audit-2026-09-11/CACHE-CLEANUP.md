# Approved cache cleanup — 2026-09-11

The user approved these exact cache candidates. Both Home Plate simulators were shut down first. No open handles were reported on any candidate immediately before moving them. DHD-QR-Test remained booted.

Moved to `/Users/lb33/.Trash/HomePlate UI Cache Cleanup 2026-09-11`:

| Original | Trash child |
|---|---|
| `/Users/lb33/Library/Developer/CoreSimulator/Devices/57B55A71-574D-4B59-B423-8BEAD29CEDF0/data/Library/Caches` | `iPhone-Caches` |
| `/Users/lb33/Library/Developer/CoreSimulator/Devices/02CA5B66-457A-4370-AFBB-8C7E3D9A4F22/data/Library/Caches` | `iPad-Caches` |
| `/Users/lb33/Library/Developer/Xcode/DerivedData/ModuleCache.noindex` | `Xcode-ModuleCache` |
| `/Users/lb33/Library/Developer/Xcode/DerivedData/HomePlate-eyedfbmszcqhagboucdzawnhnduo/Build/Intermediates.noindex/ArchiveIntermediates` | `ArchiveIntermediates` |

App containers, login data, source code, and the completed release archive were not moved. These moves are recoverable until the dated Trash folder is emptied. Restore only with the relevant simulators/build processes stopped, and do not overwrite a newly generated cache directory.
