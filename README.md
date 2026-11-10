# ductruongvu23 Repo

APT repo for Sileo / Zebra, hosted on GitHub Pages.

## Add this source

Tap a button on your iPhone / iPad to add the source in one step:

[![Add to Sileo](https://img.shields.io/badge/Add%20to-Sileo-0A84FF?style=for-the-badge)](https://ductruongvu23.github.io/repo/#sileo)
[![Add to Zebra](https://img.shields.io/badge/Add%20to-Zebra-111111?style=for-the-badge)](https://ductruongvu23.github.io/repo/#zebra)
[![Add to Cydia](https://img.shields.io/badge/Add%20to-Cydia-A0522D?style=for-the-badge)](https://ductruongvu23.github.io/repo/#cydia)
[![Add to Installer](https://img.shields.io/badge/Add%20to-Installer-34C759?style=for-the-badge)](https://ductruongvu23.github.io/repo/#installer)

Or add it manually:

```
https://ductruongvu23.github.io/repo/
```

The buttons open [the repo page](https://ductruongvu23.github.io/repo/), which hands the source to your package manager.

## Packages

| Package | Description |
| --- | --- |
| [VietTweak](https://github.com/ductruongvu23/VietTweak) | Translates other tweaks' settings pages into Vietnamese |

## Adding or updating a tweak

1. Put the `.deb` into `debs/` (on GitHub: open `debs/` → **Add file → Upload files**).
2. Commit to `main`.

The **Publish repo** workflow rebuilds `Packages` and `Release` from everything in `debs/` and deploys the site. Old versions can stay in `debs/`; Sileo/Zebra offer the newest one. Delete a `.deb` to remove it from the repo.

The repo icon shown in Sileo/Zebra is `CydiaIcon.png`.
