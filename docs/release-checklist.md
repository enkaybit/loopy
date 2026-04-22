# Release Checklist

## 1) Decide the Version (SemVer)
- Patch: bug fixes only
- Minor: backwards‑compatible features/improvements
- Major: breaking changes

## 2) Update Version
- Update `.claude-plugin/marketplace.json` → `version`

## 3) Update Changelog
- Move items from `[Unreleased]` to the new version section
- Add the release date (YYYY‑MM‑DD)

## 4) Smoke Test
- `make test`
- `make verify`

## 5) Tag and Release on GitHub
- Create a Git tag: `git tag vX.Y.Z`
- Push the tag: `git push origin vX.Y.Z`
- Create a GitHub Release from the tag (attach changelog notes):
  ```bash
  gh release create vX.Y.Z --title "vX.Y.Z" --notes-file CHANGELOG.md
  ```

## 6) Announce
- Share the update notes and upgrade instructions:
  - `git pull`
  - `make install`
  - `make verify`
