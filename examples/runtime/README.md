# Runtime Templates

These files are example templates for the core runtime root.

They are intended to be copied into:

- `~/.config/gtex62-core/`

The bootstrap helper:

- `scripts/bootstrap-runtime-root.sh`

copies these templates into the local runtime root, fills in machine-local path placeholders, and avoids overwriting existing files unless `--force` is used.

These templates are safe to commit because they do not contain live credentials.
