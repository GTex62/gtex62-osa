# gtex62-osa

`gtex62-osa` is the first native suite for the shared Conky engine architecture.

This repo is now structured as a thin suite repo:

- suite identity and manifest
- OSA-specific layout and rendering
- suite assets and reference material
- optional suite-derived cache helpers

Shared provider logic, runtime config, normalized cache, and launcher behavior belong to the engine layer rather than this suite repo.

Shared binary assets such as wallpapers, reusable icons, and fonts live in
`../gtex62-shared-assets/`.

Engine architecture and normalized schema docs live in:

- `../gtex62-conky-engine/docs/`

## Repo Layout

```text
gtex62-osa/
├── suite.toml
├── README.md
├── LICENSE
├── design/        # OSA visual reference images and concept work
├── docs/          # OSA-specific implementation and reference docs
├── fonts/         # deprecated local copy; shared fonts live outside this repo
├── assets/        # deprecated local copy; shared assets live outside this repo
├── lua/
│   ├── suite/     # suite-only helpers and derived view logic
│   ├── ui/        # OSA chassis/layout drawing
│   └── widgets/   # OSA widget renderers
├── scripts/       # suite-only helpers (not shared providers)
├── theme/         # theme and layout definitions
├── widgets/       # Conky entrypoints
└── legacy/
    └── config/    # archived pre-engine suite-local config for migration reference
```

## Boundary

These concerns belong in the engine, not this repo:

- weather, air, aviation, astro, calendar, network, connectivity, pfSense providers
- normalized shared cache
- engine doctor
- path resolution
- profile binding
- launch/runtime orchestration

These concerns belong in `gtex62-osa`:

- OSA visual identity
- panel composition
- tactical table shaping
- suite-derived compact view models
- suite-only assets

Shared asset root:

- `../gtex62-shared-assets/`

## Local Docs

- [Design Index](design/README.md)
- [Docs Index](docs/README.md)

General engine architecture is maintained by `gtex62-conky-engine`; this repo
only carries OSA-specific references and suite-local implementation notes.

## Runtime Model

Expected engine-era runtime roots:

- config: `~/.config/gtex62-conky/`
- data: `~/.local/share/gtex62-conky/`
- cache: `~/.cache/gtex62-conky/`

Expected suite repo path:

- `~/.config/conky/gtex62-osa/`

Bootstrap helper:

- `scripts/bootstrap-runtime-root.sh`

This copies the tracked templates from `examples/runtime/` into the local runtime root and fills in the local suite path placeholders.

Compatibility launcher:

- `scripts/start-conky.sh`

This exists so existing launchers such as `~/.local/bin/conkystart` can still treat `gtex62-osa` like the older suites. When an engine launcher exists, this wrapper should delegate to it. Until then, it falls back to launching the local OSA Conky config directly.

## Migration Note

The old suite-local `config/` directory was moved to `legacy/config/` so the previous files remain available as reference while the engine-native layout is established.
