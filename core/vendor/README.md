# core/vendor/

Code under this directory is vendored from upstream third-party projects, not authored by nSelf.

## Exemption from the nSelf CI-masking sweep

The nSelf CI/CD-100%-Green hard rule (never `continue-on-error: true` without an ACCEPTED/Expiry
justification, never `if: false` without a tracked gate reference) applies to nSelf-authored
workflows only. Vendored subtrees under `core/vendor/*/` — including their own `.github/workflows/`
— are excluded from this sweep: we do not own the CI decisions upstream made for their own
release/fuzz/test pipelines, and rewriting them here would silently drift from what upstream
actually ships and tests.

If a vendored workflow's masking (or any other issue) matters to nSelf's own build, fix it by
patching the vendored files directly for our fork's needs and documenting the patch here, or file
the issue upstream — do not "fix" it silently in place as part of an nSelf-wide sweep.

## Vendored subtrees

- `sqlite-vec/` — added in a single commit (8b6c14f, P102), no independent nSelf history.
  Its `.github/workflows/{fuzz,test,release}.yaml` contain `continue-on-error: true` /
  `if: false` entries that are intentionally out of scope for P6-E11-W2-S3-T15's CI-masking sweep.
