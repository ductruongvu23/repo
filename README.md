# ductruongvu23 Repo

APT repo for Sileo / Zebra, hosted on GitHub Pages.

## Add this source

In Sileo or Zebra, add:

```
https://ductruongvu23.github.io/repo/
```

## Packages

| Package | Description |
| --- | --- |
| [VietTweak](https://github.com/ductruongvu23/VietTweak) | Translates other tweaks' settings pages into Vietnamese |

## Adding or updating a tweak

1. Put the `.deb` into `debs/` (on GitHub: open `debs/` → **Add file → Upload files**).
2. Commit to `main`.

The **Publish repo** workflow rebuilds `Packages` and `Release` from everything in `debs/` and deploys the site. Old versions can stay in `debs/`; Sileo/Zebra offer the newest one. Delete a `.deb` to remove it from the repo.

The repo icon shown in Sileo/Zebra is `CydiaIcon.png`.
