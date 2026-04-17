# Repository Guidelines

Personal NixOS flake config for a single host (`yavin4`, AMD desktop, dual-monitor DP-1/DP-2).
Single user: `cpuguy83`.

## Build Commands
- `nixos-rebuild build --flake .#yavin4` -- compile without switching; use before PRs.
- `nixos-rebuild switch --flake .#yavin4` -- apply on the live host.
- `nix flake check` -- evaluate all outputs, catches syntax/option regressions.
- Format: `nix run nixpkgs#nixpkgs-fmt -- .`
- Scripts: run directly (e.g., `./msft-vm/scripts/start.sh`); `shellcheck` before pushing.

## Coding Style
- Two-space indentation, trailing commas in attribute sets.
- Hyphenated lowercase filenames (`zen-browser.nix`), lowerCamelCase option names.
- Format with `nixpkgs-fmt` before committing.

## Architecture Overview

### Module Tiers
Three tiers under `modules/`:
- **`modules/nixos/`** -- System-level NixOS modules (greetd, SwayOSD, boot, Intune, 1Password).
- **`modules/home/`** -- Home-manager modules (neovim, waybar, hyprlock, zen-browser, starship, brightnessd).
- **`modules/shared/`** -- Option declarations (`mine.*` namespace) and config visible to both tiers.

### Import Chain (NixOS path)
```
flake.nix → nixosConfigurations.yavin4
  ├── configuration.nix          (base system: networking, locale, audio, users, pkgs, Docker, Steam)
  │     ├── overlays/default.nix (registers all nixpkgs overlays)
  │     ├── modules/shared/      (option decls: mine.desktop.hyprland.*, mine.msft-corp.*)
  │     ├── modules/nixos/       (system services: hyprland, greetd, osd, boot, msft-corp, 1password)
  │     └── home-manager NixOS integration module
  │           ├── home.nix       (base HM: GTK theme, dev tools, calbar, handy, shell)
  │           │     ├── modules/home/     (user services & programs)
  │           │     └── modules/shared/   (same options, HM side)
  │           └── hosts/yavin4/home.nix   (monitor layout, shared.nix → mine.msft-corp.enable)
  └── hosts/yavin4/system.nix    (hostname, hardware, i2c, GPU)
        ├── hardware.nix         (AMD GPU, Bluetooth, kernel params, LACT)
        └── hardware-configuration.nix  (auto-generated: LUKS/XFS, swap)
```

### Standalone Home-Manager Path
`homeConfigurations."cpuguy83@yavin4"` imports the same `home.nix` + `hosts/yavin4/home.nix` + overlays, allowing `home-manager switch` independently of a full NixOS rebuild.

### Key Patterns
- **Option gating**: Custom options live under `mine.*` (declared in `modules/shared/options.nix`). Feature modules use `let cfg = config.mine.<feature>; in { config = lib.mkIf cfg.enable { ... }; }`.
- **Directory modules**: Every module dir has `default.nix` that re-exports children via `imports = [...]`.
- **Sub-module merging**: Some sub-files (e.g., `settings.nix`, `lockscreen.nix`, `shell.nix` in home hyprland) are imported via `import ./file.nix { inherit pkgs ...; }` and merged with `mkMerge`.
- **Unstable packages**: `pkgs-unstable` is passed through `specialArgs`/`extraSpecialArgs`; used for ghostty, hyprland, docker, microsoft-edge, etc.
- **Embedded Go programs**: `brightnessd/` and `linux-entra-sso-host/` contain full Go source trees (`.go`, `go.mod`, `go.sum`) built inline via `buildGoModule` with `src = ./.`.
- **Overlays**: `overlays/default.nix` is a NixOS module that sets `nixpkgs.overlays = [...]`. Individual overlay files are standard `final: prev:` functions; some are curried as `{ inputs }: final: prev:`. Package derivations in `packages/` are wired in via `callPackage`.
- **Shared host config**: `hosts/yavin4/shared.nix` is imported by both `system.nix` and `home.nix` to set toggles (e.g., `mine.msft-corp.enable = true`) once for both tiers.

## Flake Inputs (17 total)

| Input | Source | Purpose |
|-------|--------|---------|
| `nixpkgs` | `nixos-25.11` | Stable NixOS channel (primary) |
| `nixpkgs-unstable` | `nixos-unstable` | Bleeding-edge packages |
| `home-manager` | `release-25.11` | Per-user config management |
| `hyprland` | `v0.53.3` | Wayland compositor |
| `lanzaboote` | `v0.4.3` | Secure Boot via systemd-boot signing |
| `zen-browser` | `0xc000022070/zen-browser-flake` | Zen Browser (Firefox fork) |
| `rust-overlay` | `oxalica/rust-overlay` | Rust toolchain overlay |
| `firefox-addons` | `rycee/nur-expressions` | Firefox/Zen addon packages |
| `azurevpnclient` | `cpuguy83/nix-azurevpn-client` | Azure VPN client |
| `hyprtasking` | `raybbian/hyprtasking` | Hyprland workspace overview plugin |
| `waybar` | pinned commit | Status bar (pinned for stability) |
| `nixvim` | `nix-community/nixvim` | Neovim config via Nix |
| `nixd` | `nix-community/nixd` | Nix language server |
| `opencode` | `anomalyco/opencode` | OpenCode AI coding tool |
| `handy` | `cjpais/handy` | Handy TTS service |
| `handy-mine` | `cpuguy83/nix-handy-tts` | Fork of handy TTS |
| `calbar` | `cpuguy83/calbar` | Calendar bar widget |

## File Index

### Root
| File | Purpose |
|------|---------|
| `flake.nix` | Entrypoint: 17 inputs, exports nixosConfigurations.yavin4 + homeConfigurations |
| `configuration.nix` | Base NixOS: networking, locale, pipewire, users, Docker/containerd, Steam, fonts, SSH, PAM/U2F |
| `home.nix` | Base home-manager: WhiteSur GTK theme, dev tools, calbar/handy services, shell |
| `update.sh` | Runs `nix flake update` then refreshes VS Code Insiders hash |

### hosts/yavin4/
| File | Purpose |
|------|---------|
| `system.nix` | Host NixOS entry: imports hardware, sets hostname, enables i2c and GPU |
| `home.nix` | Host HM entry: Hyprland monitor layout (DP-1, DP-2), lock screen monitor |
| `shared.nix` | Shared toggles: `mine.msft-corp.enable = true` (imported by both tiers) |
| `hardware.nix` | AMD GPU (amdgpu), Bluetooth, CPU microcode, kernel params, LACT, fstrim |
| `hardware-configuration.nix` | Auto-generated: LUKS/XFS filesystems, initrd modules, swap |

### modules/shared/
| File | Purpose |
|------|---------|
| `default.nix` | Imports options.nix and hyprland.nix |
| `options.nix` | Declares `mine.desktop.hyprland.{enable,monitors,lockScreenMonitor}` and `mine.msft-corp.enable` |
| `hyprland.nix` | XDG portal config (portal-hyprland, portal-gtk, termfilechooser), gated by enable flag |

### modules/nixos/
| File | Purpose |
|------|---------|
| `default.nix` | Imports all NixOS sub-modules |
| `boot.nix` | Lanzaboote (secure boot), latest kernel, binfmt (aarch64, wasm), filesystem support |
| `1password.nix` | 1Password GUI + CLI, polkit, allowed browsers for Zen |
| `hyprland/default.nix` | Cachix substituters, uwsm compositor management, programs.hyprland |
| `hyprland/greetd.nix` | Greetd login manager with tuigreet + UWSM Hyprland launch |
| `osd/default.nix` | SwayOSD server + libinput backend + audio-change watcher service |
| `msft-corp/default.nix` | Intune (Ubuntu OS spoof), identity broker, Azure VPN, DNS dispatcher |

### modules/home/
| File | Purpose |
|------|---------|
| `default.nix` | Imports all home sub-modules |
| `hyprland/default.nix` | Assembles shell/lockscreen/settings, hypridle, hyprpaper, polkit agent |
| `hyprland/settings.nix` | Keybindings, window rules, plugins (hyprbars, hyprtasking), decoration, monitors |
| `hyprland/shell.nix` | Waybar config (taskbar, clock, audio, BT, notifications), swaync, yazi |
| `hyprland/lockscreen.nix` | Hyprlock: time label, blurred background, input field |
| `hyprland/filechooser.nix` | Placeholder xdg-desktop-portal-termfilechooser config (commented out) |
| `brightnessd/default.nix` | Custom Go brightness daemon, systemd socket-activated service |
| `kdeconnect/default.nix` | KDE Connect: kdeconnectd + indicator systemd user services |
| `neovim/default.nix` | Nixvim: LSP (gopls, nixd, lua, docker), copilot, telescope, yazi, DAP, molokai |
| `zen-browser/default.nix` | Zen Browser profile: extensions, Nix search engines, Entra SSO |
| `starship/default.nix` | Starship prompt: LCARS theme with nix_shell, git, status segments |
| `msft-corp/default.nix` | Microsoft Edge, native messaging host for Entra SSO |
| `linux-entra-sso-host/default.nix` | Go package: custom linux-entra-sso native messaging host |

### overlays/
| File | Purpose |
|------|---------|
| `default.nix` | NixOS module that registers all overlays into `nixpkgs.overlays` |
| `vscode.nix` | Replaces vscode with VS Code Insiders (fetchTarball) |
| `opencode.nix` | Exposes opencode + opencode-desktop from flake input |
| `hyprtasking.nix` | Builds hyprtasking plugin against unstable hyprland |
| `linux-entra-sso-host.nix` | Adds `linux-entra-sso-host` package via callPackage |
| `linux-entra-sso-host-mine.nix` | Adds Go reimplementation of linux-entra-sso-host |

### packages/
| File | Purpose |
|------|---------|
| `linux-entra-sso-host.nix` | Python-based Siemens linux-entra-sso native messaging host |
| `linux-entra-sso-host-mine.nix` | Go reimplementation, compatible with broker 2.0.4+ |

## Styling Guide: Frosted Glass Effect

### GTK4 CSS Gotchas (swaync, etc.)
- **GTK4 does NOT support `!important`**. Using it will silently break the declaration or cause it to be ignored entirely. Never use `!important` in GTK4 CSS.
- **User CSS is additive** on top of the system/default CSS, not a replacement. Both providers load at the same priority. The user stylesheet loads second, so at equal specificity the user rule wins.
- **`cssPriority`** in swaync config controls priority relative to the **GTK theme** (e.g., Adwaita), not between swaync's own default and user CSS. Set `cssPriority = "user"` in swaync settings to ensure swaync CSS (both default and user) overrides the GTK theme.
- The default swaync CSS uses **CSS variables** (`--noti-bg`, `--noti-bg-alpha`, `--border`, etc.) AND **`@define-color`** declarations. Override both in user CSS to control defaults. The last `@define-color` for a given name wins.
- The default swaync CSS uses `background:` (shorthand) for notification backgrounds. If you try to override with `background-color:` (longhand), the shorthand wins. Always use `background:` shorthand when overriding.

### Achieving the Frosted Glass Look
The frosted glass effect is a composition of **Hyprland layer rules** (blur) and **CSS** (translucent backgrounds):

1. **Hyprland layer rules** (`settings.nix`, `layerrule` array):
   - `blur on, match:namespace swaync-control-center` — enables backdrop blur behind the CC panel.
   - `ignore_alpha 0.3, match:namespace swaync-control-center` — only blurs behind pixels with alpha > 0.3, so transparent areas around the panel don't blur the whole screen.
   - Same pair for `swaync-notification-window` (floating notifications).
   - Note: field names use underscores (`ignore_alpha`, not `ignorealpha`); values like `blur` take `on` not `1`.

2. **Hyprland blur settings** (`settings.nix`, `decoration.blur`):
   - `size` and `passes` control blur intensity. `size=4, passes=2` is a good baseline; higher = frostier but more GPU cost.

3. **CSS translucent backgrounds** (`swaync-style.css`):
   - CC panel: `background-color: rgba(16, 16, 18, 0.55)` — dark, ~55% opaque so blur shows through.
   - Notification cards: same color/alpha as CC for "glass on glass" layering. Override via `@define-color noti-bg` and `--noti-bg` / `--noti-bg-alpha` CSS variables, PLUS a catch-all rule block targeting all notification states.
   - Borders: soft `1px solid rgba(255, 255, 255, 0.10)` for a subtle glass edge.
   - Shadows: `inset 0 1px 0 rgba(255, 255, 255, 0.08)` for top-edge light catch; `0 4px 16px rgba(0, 0, 0, 0.4)` for depth/elevation.
   - For floating notifications, add an explicit `box-shadow` for drop shadow since they float over the desktop.

4. **Squircle-ish corners**: Use generous `border-radius` values (24px for panels, 18px for cards, 14px for buttons). GTK4 doesn't support true squircles, but large radii relative to element size produce a more continuous curve.

5. **Glass action buttons**: `background: rgba(255, 255, 255, 0.06)`, `border: 1px solid rgba(255, 255, 255, 0.08)`, `border-radius: 14px`, with `inset 0 1px 0 rgba(255, 255, 255, 0.06)` highlight.

6. **Critical notifications**: Differentiate with a subtle inner glow (`box-shadow: inset 0 0 24px rgba(255, 80, 60, 0.08)`) rather than a solid colored background. Keep text the normal color.

7. **Notification states to override**: The default CSS has different backgrounds for collapsed groups (`background-color: rgba(var(--noti-bg), 1)` — fully opaque), hover, focus, expanded, etc. You must override ALL of these states to get a consistent look. Use a combined selector block targeting:
   ```css
   .notification-row .notification-background .notification,
   .notification-group.collapsed .notification-row .notification,
   .notification-group.collapsed:hover .notification-row:not(:only-child) .notification,
   .control-center .notification,
   .control-center .control-center-list .notification { ... }
   ```

### Terminology
- **CC** = Control Center (the slide-out panel)
- **NC** = Notification Card (individual notifications inside the CC)
- **FC** = Floating Card (popup toast notifications on the desktop)
