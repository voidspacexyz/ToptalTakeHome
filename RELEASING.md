# Releasing

This document defines the release and image tagging strategy for `node-3tier-app2`.

---

## Versioning Convention

All releases follow **Semantic Versioning**: `v<MAJOR>.<MINOR>.<PATCH>`

| Segment | When to increment |
|---------|------------------|
| `MAJOR` | Breaking changes (API contract, incompatible infra changes) |
| `MINOR` | New features, backward-compatible additions |
| `PATCH` | Bug fixes, security patches, config-only changes |

**Examples:** `v1.0.0`, `v1.1.0`, `v1.1.1`, `v2.0.0`

---

## Tagging Rules

1. Tags are **always created on `main`**, never on feature branches.
2. A tag must only be pushed after QA sign-off on the commit being tagged.
3. Tags are **immutable** — do not move or re-use a tag.
4. Pre-release suffixes are allowed for staging validation: `v1.2.0-rc.1`.

---

## Creating a Release

0. Faking an update
   - Ensure you are on main and fully up to date
   - Bump the in-app version string
   - Edit web/routes/index.js and update APP_VERSION to match the new tag, so as to fake an app update
   - then commit: `git commit -am "chore: bump version to v1.2.3"`


Once completed, follow the below release process

```bash
git checkout main
git pull origin main

# 2. Create an annotated tag
git tag -a v1.2.3 -m "Release v1.2.3 — <short description>"

# 3. Push the tag — this triggers the release pipeline
git push origin v1.2.3
```

Pushing the tag automatically triggers `.github/workflows/release.yml`, which:
- Builds and pushes Docker images tagged `v1.2.3` **and** `latest` to ACR
- Updates `appVersion` in both Helm `Chart.yaml` files to `v1.2.3`
- Runs `helm upgrade --install --atomic` against the production AKS cluster
- Creates a GitHub Release with auto-generated release notes

---

## Image Tags in ACR

| Image | Tag pushed by release pipeline |
|-------|-------------------------------|
| `nodeprodacr.azurecr.io/node-api` | `v1.2.3`, `latest` |
| `nodeprodacr.azurecr.io/node-web` | `v1.2.3`, `latest` |

- **`latest`** is always the most recently released semver build.
- **Short-SHA tags** (e.g. `abc1234`) are produced by the CD pipeline on every `main` push — these are not formal releases.

---


For all semantic purposes, it is recommended to follow [SemVer](https://semver.org/)
