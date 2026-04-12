# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [0.4.0] - 2026-04-12

### Highlights

Version aligned with vdsl-mcp 0.4.0. Z-Image compiler, catalog desc() API,
Runtime Store abstraction, and directory restructure.

### Added

- **Z-Image compiler** — Turbo/Base variant support with ZSamplerTurbo2 (`e4c832d`, `29ee3a7`)
- **`desc()` API** — natural language descriptions for Trait and all catalogs (`f37cb54`)
- **3-location file sync engine** — Local/Pod/Cloud (`9b8dd1f`)
- **Trait conflict detection** and resolution strategies (`bef1628`)
- **Fantasy cinema showcase** and RunPod setup script (`e41690e`)
- **Cross-language hash verification tests** (`11f467a`)

### Changed

- **Runtime Store abstraction** — replaced Sync engine (`ee25c04`)
- **Sync separated into Domain and Runtime layers** (`bb1dbc5`)
- **`util/png` moved to `runtime/png_default`** — enforce Runtime boundary (`1db134b`)
- **Directory restructure** — workspaces to projects, output as symlink (`6c616c7`)

## [0.2.0] - 2025-12-15

### Added

- Pipeline engine, catalog system, training framework, and runtime abstraction

## [0.1.0] - 2025-11-01

### Added

- Initial LuaRocks release
- Core DSL: Entity, Trait, Subject, World, Stage, Cast, Post
- ComfyUI compiler with graph builder
- PNG-embedded recipe encode/decode
- Theme system (cinema, anime, architecture)
