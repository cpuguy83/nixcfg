# Repository Guidelines

This is a single Nix **flake** that manages an entire machine — both the
system-level NixOS configuration *and* the per-user home-manager configuration —
as one unified thing. Home-manager runs as a NixOS module, so a single
`nixos-rebuild` against this flake builds and applies everything together. There
is no separate `home-manager` workflow in normal use (a standalone
`homeConfigurations` output exists as a secondary path, but prefer the unified
rebuild).

Primary user: `cpuguy83`. Currently one host: `yavin4` (AMD desktop).

## Source of Truth

Do **not** hardcode versions, input lists, or a file index in this document —
they drift. Read the real thing instead:

- `flake.nix` — inputs, their sources, and how outputs are wired together.
- `flake.lock` — exact pinned revisions of every input.
- The module tree itself (see "Organization" below) — current files and options.

When you need to know "what version of X" or "which inputs exist", consult
`flake.nix` / `flake.lock` rather than trusting prose here.

## Build / Check Commands

Replace `<host>` with the target host (e.g. `yavin4`).

- `nixos-rebuild build --flake .#<host>` — compile without switching; use this to
  validate changes (e.g. before a PR). Builds NixOS + home-manager together.
- `nixos-rebuild switch --flake .#<host>` — apply on the live host. (requires sudo -- don't bother)
- `nix flake check` — evaluate all outputs; catches syntax/option regressions.
- Format Nix: `nix run nixpkgs#nixpkgs-fmt -- .`
- Shell scripts: run directly; `shellcheck` before pushing.

## Coding Style

- Two-space indentation, trailing commas in attribute sets.
- Hyphenated lowercase filenames (`zen-browser.nix`), lowerCamelCase option names.
- Format with `nixpkgs-fmt` before committing.

## Organization

The goal is a clean separation along these axes. Exact file/dir names change over
time — treat these as *roles*, not a fixed layout:

- **Packaging** — custom package derivations and overlays. Things that build
  software, independent of how it's configured.
- **Configuration** — system-level (NixOS) config: services, boot, networking,
  hardware-facing system settings.
- **Home-manager (portable)** — per-user config that should stay host-agnostic.
  The aim is portability: this config could reasonably apply to another machine,
  including a macOS laptop. Keep anything machine-specific *out* of here.
- **Machine-specific config** (e.g. `yavin4`) — anything non-portable: hardware,
  monitor layout, host toggles, secure-boot/GPU specifics, and desktop/portal
  details that are tied to a particular machine. Non-portable items belong here,
  not in the shared/portable modules.

### Portability rule of thumb

If a setting only makes sense on one physical machine, it goes in that machine's
config. If it's something you'd want on any of your machines, it belongs in the
portable home-manager (or shared) layer.

To keep portable modules host-agnostic while still letting a host customize them,
pass machine-specific values *down* into otherwise-portable modules rather than
hardcoding them. This is done via the `mine.*` option namespace: the portable
module declares options and reads `config.mine.<feature>.*`; the machine-specific
config sets those options (e.g. feeding host monitor / desktop settings into the
shared Hyprland configuration).

### Module tiers

Modules are grouped roughly into:

- **system (NixOS) modules** — system services and config.
- **home modules** — user services and programs (the portable layer).
- **shared modules** — `mine.*` option declarations and config that both tiers
  consume.

Each module directory typically has a `default.nix` that re-exports its children
via `imports`. Feature modules are gated on options, e.g.:

```nix
let cfg = config.mine.<feature>; in {
  config = lib.mkIf cfg.enable { ... };
}
```

Unstable packages are threaded through `specialArgs` / `extraSpecialArgs`
(e.g. as `pkgs-unstable`) for components that need newer versions than the stable
channel provides.

## Further Docs

- [`docs/frosted-glass.md`](docs/frosted-glass.md) — styling guide and GTK4/Hyprland
  gotchas for the frosted-glass desktop look (swaync, blur, notification CSS).
