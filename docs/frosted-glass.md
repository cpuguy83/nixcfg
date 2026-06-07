# Styling Guide: Frosted Glass Effect

This document captures the gotchas and recipe for the frosted-glass look used by
the desktop (swaync, Hyprland blur, etc.). Referenced from `AGENTS.md`.

## GTK4 CSS Gotchas (swaync, etc.)
- **GTK4 does NOT support `!important`**. Using it will silently break the declaration or cause it to be ignored entirely. Never use `!important` in GTK4 CSS.
- **User CSS is additive** on top of the system/default CSS, not a replacement. Both providers load at the same priority. The user stylesheet loads second, so at equal specificity the user rule wins.
- **`cssPriority`** in swaync config controls priority relative to the **GTK theme** (e.g., Adwaita), not between swaync's own default and user CSS. Set `cssPriority = "user"` in swaync settings to ensure swaync CSS (both default and user) overrides the GTK theme.
- The default swaync CSS uses **CSS variables** (`--noti-bg`, `--noti-bg-alpha`, `--border`, etc.) AND **`@define-color`** declarations. Override both in user CSS to control defaults. The last `@define-color` for a given name wins.
- The default swaync CSS uses `background:` (shorthand) for notification backgrounds. If you try to override with `background-color:` (longhand), the shorthand wins. Always use `background:` shorthand when overriding.

## Achieving the Frosted Glass Look
The frosted glass effect is a composition of **Hyprland layer rules** (blur) and **CSS** (translucent backgrounds):

1. **Hyprland layer rules** (`layerrule` array):
   - `blur on, match:namespace swaync-control-center` — enables backdrop blur behind the CC panel.
   - `ignore_alpha 0.3, match:namespace swaync-control-center` — only blurs behind pixels with alpha > 0.3, so transparent areas around the panel don't blur the whole screen.
   - Same pair for `swaync-notification-window` (floating notifications).
   - Note: field names use underscores (`ignore_alpha`, not `ignorealpha`); values like `blur` take `on` not `1`.

2. **Hyprland blur settings** (`decoration.blur`):
   - `size` and `passes` control blur intensity. `size=4, passes=2` is a good baseline; higher = frostier but more GPU cost.

3. **CSS translucent backgrounds** (swaync style CSS):
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

## Terminology
- **CC** = Control Center (the slide-out panel)
- **NC** = Notification Card (individual notifications inside the CC)
- **FC** = Floating Card (popup toast notifications on the desktop)
