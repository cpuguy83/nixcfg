-- Native Hyprland Lua config.
--
-- The locals below (micMuteToggle, brightnessPath, getMonitorPath, layout,
-- monitors, workspaceRules) are injected by Home Manager from
-- modules/home/hyprland/settings.nix's `settings` attrset (each entry there
-- is a `_var`, so it renders as a plain `local` here instead of an
-- `hl.<name>()` call). By the time this file runs they are already in scope.

hl.config({
	ecosystem = {
		no_donation_nag = true,
	},
})

local mod = "SUPER"
local terminal = "ghostty +new-window"
-- ghostty +new-windows does not work with `-e` in GTK-land.
-- Instead just execute a new ghostty.
-- See https://github.com/ghostty-org/ghostty/issues/8862
local fileManager = "uwsm app -- ghostty --class=yazi --title=yazi -e ~/.local/bin/exec_yazi"
local cursor = "WhiteSur-cursors-light"
local cursorSize = "24"
local menu = "uwsm app -- fuzzel"

-- `hl.exec_cmd` (unlike `hl.dsp.exec_cmd`, which only builds a dispatcher
-- closure) runs immediately, including under `Hyprland --verify-config` --
-- anything called here must be safe to run during config validation.
hl.on("hyprland.start", function()
	hl.exec_cmd(terminal)
	hl.exec_cmd("hyprctl setcursor " .. cursor .. " " .. cursorSize)
end)

local generalCfg = {
	resize_on_border = false,
	hover_icon_on_border = false,
	gaps_out = 6,
	gaps_in = 6,
}
-- `layout` is nullable (mine.desktop.hyprland.layout); only set the field
-- when there's an actual value so hosts that don't set one fall back to
-- Hyprland's own default instead of an explicit nil.
if layout then
	generalCfg.layout = layout
end

hl.config({ general = generalCfg })

for _, m in ipairs(monitors) do
	hl.monitor(m)
end

for _, w in ipairs(workspaceRules) do
	hl.workspace_rule(w)
end

hl.config({
	scrolling = {
		fullscreen_on_one_column = false,
	},
	render = {
		cm_auto_hdr = 2,
	},
	binds = {
		drag_threshold = 8,
	},
	misc = {
		focus_on_activate = true,
		vrr = 3,
	},
})

hl.env("HYPRCURSOR_THEME", cursor)
hl.env("HYPRCURSOR_SIZE", cursorSize)
hl.env("XCURSOR_THEME", cursor)
hl.env("XCURSOR_SIZE", cursorSize)
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")

---------------
---- BINDS ----
---------------

hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + M", hl.dsp.exit())
hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + P", hl.dsp.window.pseudo())
hl.bind(mod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + L", hl.dsp.exec_cmd("hyprlock"))

-- Alt+Tab enters a submap so that releasing Alt can be bound without
-- capturing Alt globally: a bare `hl.bind("Alt_L", ...)` at top level would
-- consume the key for every application. The submap itself is defined below
-- via `hl.define_submap`.
hl.bind("ALT + TAB", hl.dsp.global("quickshell:switcherNext"))
hl.bind("ALT + TAB", hl.dsp.submap("switcher"))
hl.bind("ALT + SHIFT + TAB", hl.dsp.global("quickshell:switcherPrev"))
hl.bind("ALT + SHIFT + TAB", hl.dsp.submap("switcher"))
-- The overview is a toggle rather than a hold, so it needs none of the
-- switcher's submap handling -- nothing here has to survive a key release.
hl.bind(mod .. " + TAB", hl.dsp.global("quickshell:overviewToggle"))

hl.bind("SHIFT + " .. mod .. " + 4", hl.dsp.exec_cmd("hyprshot -m region --clipboard-only --silent -z"))
hl.bind(
	"CTRL + SHIFT + " .. mod .. " + 4",
	hl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots --silent -z -- xdg-open")
)
hl.bind("SHIFT + " .. mod .. " + m", hl.dsp.exec_cmd("swaync-client -t"))
hl.bind("SHIFT + " .. mod .. " + v", hl.dsp.window.float())
hl.bind("SHIFT + " .. mod .. " + p", hl.dsp.exec_cmd("1password --quick-access"))
hl.bind(mod .. " + F11", hl.dsp.window.fullscreen())
hl.bind(mod .. " + SHIFT + SPACE", hl.dsp.exec_cmd("pkill -USR2 -n handy"))

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag())   -- SUPER+left click to drag windows
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize()) -- SUPER+right click to resize

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("swayosd-client --output-volume raise"),
	{ locked = true, repeating = true })
hl.bind("XF86AudioLowervolume", hl.dsp.exec_cmd("swayosd-client --output-volume lower"),
	{ locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("swayosd-client --output-volume mute-toggle"),
	{ locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(micMuteToggle), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, repeating = true })
hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd(brightnessPath .. " up $(" .. getMonitorPath .. ") 4"),
	{ locked = true, repeating = true }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd(brightnessPath .. " down $(" .. getMonitorPath .. ") 4"),
	{ locked = true, repeating = true }
)

-- Submaps are order-sensitive in Hyprlang, but `hl.define_submap` scopes its
-- binds explicitly via the callback, so this is just a function body.
--
-- No reset argument: the original has no `submap, reset` in its
-- `bindru`/global entries, and adding one here would fire on every dispatch
-- inside the submap, including switcherNext/switcherPrev.
hl.define_submap("switcher", function()
	hl.bind("ALT + TAB", hl.dsp.global("quickshell:switcherNext"))
	hl.bind("ALT + SHIFT + TAB", hl.dsp.global("quickshell:switcherPrev"))
	-- `submap_universal = true` is required, not cosmetic. handleKeybinds
	-- matches a bind's submap against `key.submapAtPress.name` -- the submap
	-- recorded when the key went DOWN -- and Alt goes down before Tab enters
	-- this submap, so without it nothing fires on release and the keyboard
	-- stays trapped here.
	--
	-- The cost is that `submap_universal` skips the submap check entirely, so
	-- this fires on every Alt release anywhere. It therefore has to stay
	-- side-effect free: no `hl.dsp.submap("reset")` here. Switcher.close()
	-- resets the submap itself, and only when the switcher was actually open.
	-- Hyprland cannot express "only on release inside this submap" -- the
	-- guard has to live in the client.
	--
	-- `transparent = true` is also required, and for an unrelated reason:
	-- shadowKeybinds() exempts a bind from being shadowed by an intervening
	-- keypress only when `handler == "global"` or `transparent` is set. Legacy
	-- `bindru = ..., global, ...` got that exemption for free because its
	-- `handler` field was literally the dispatcher name ("global"). Every
	-- native Lua bind's handler is unconditionally "__lua" instead (regardless
	-- of which `hl.dsp.*` dispatcher it calls), so that free exemption is
	-- gone -- without `transparent`, pressing Tab while Alt is held would
	-- shadow this release bind and it would never fire.
	hl.bind(
		"ALT + Alt_L",
		hl.dsp.global("quickshell:switcherAccept"),
		{ release = true, submap_universal = true, transparent = true }
	)
	hl.bind(
		"ALT + Alt_R",
		hl.dsp.global("quickshell:switcherAccept"),
		{ release = true, submap_universal = true, transparent = true }
	)
	-- `ignore_mods = true` because Alt is still held: the modmask is still ALT
	-- when the release is dispatched, so a bare "escape" bind (modmask 0) would
	-- never match. Escape is pressed inside the submap, so it needs no
	-- `submap_universal` -- and it dispatches the reset directly, which keeps
	-- it working as the escape hatch even if Quickshell is not running.
	hl.bind("escape", hl.dsp.global("quickshell:switcherCancel"), { ignore_mods = true })
	hl.bind("escape", hl.dsp.submap("reset"), { ignore_mods = true })
end)

----------------------
---- WINDOW RULES ----
----------------------

hl.window_rule({
	match = { title = "^(yazi)$" },
	float = true,
	size = "(monitor_w*0.4) (monitor_h*0.4)",
})
hl.window_rule({
	match = { class = "^com\\.mitchellh\\.ghostty\\.filepicker$" },
	float = true,
	size = "(monitor_w*0.4) (monitor_h*0.4)",
})
hl.window_rule({
	match = { class = "(microsoft-azurevpnclient)" },
	float = true,
})
hl.window_rule({
	match = { class = "^(steam)$", title = "^(Steam)$" },
	size = "(monitor_w*0.4) (monitor_h*0.6)",
})
hl.window_rule({
	match = { class = "^(Intune-portal)$" },
	float = true,
	size = "(monitor_w*0.35) (monitor_h*0.35)",
})
hl.window_rule({
	match = { class = "^(org\\.hyprland\\.xdg-desktop-portal-hyprland)$" },
	float = true,
	size = "(monitor_w*0.4) (monitor_h*0.4)",
})
hl.window_rule({
	match = { class = "^(polkit-gnome-authentication-agent-1)$" },
	opacity = "0.85 0.85",
})
hl.window_rule({
	match = { class = "^(1password)$", float = true },
	opacity = "0.85 0.85",
})

-- NOTE: The zoom app sucks, and so do these rules...
-- Zoom Meeting windows
hl.window_rule({
	match = { class = "^(zoom)$", initial_title = "^(Meeting)$" },
	float = true,
	size = "(monitor_w*0.4) (monitor_h*0.4)",
})
-- Stupid Zoom workplace window that always comes up when you open zoom...
hl.window_rule({
	match = { class = "^(zoom)$", initial_title = "^(Zoom Workplace - Free account)$" },
	float = true,
	size = "(monitor_w*0.4) (monitor_h*0.4)",
})
hl.window_rule({
	match = { class = "^(steam|zoom|Zoom|teams|discord)$" },
	no_vrr = true,
})

---------------------
---- LAYER RULES ----
---------------------

hl.layer_rule({
	match = { namespace = "launcher" },
	animation = "popin 90%",
	blur = true,
	ignore_alpha = 0.3,
})

hl.layer_rule({
	match = { namespace = "swaync-notification-window" },
	animation = "slide right",
	blur = true,
	ignore_alpha = 0.3,
})
hl.layer_rule({
	match = { namespace = "swaync-control-center" },
	animation = "slide right",
	blur = true,
	ignore_alpha = 0.3,
})

-- Waybar is disabled in favour of the Quickshell bar; these are kept so
-- re-enabling it is a one-line change.
hl.layer_rule({
	match = { namespace = "waybar" },
	blur = true,
	blur_popups = true,
	ignore_alpha = 0.3,
})
hl.layer_rule({
	match = { namespace = "quickshell-bar" },
	blur = true,
	blur_popups = true,
	ignore_alpha = 0.3,
})

-- The switcher's layer surface covers the whole screen so the carousel
-- can float over it, so ignore_alpha is doing real work here: without it
-- blur would apply to the entire output rather than just the card strip.
hl.layer_rule({
	match = { namespace = "quickshell-switcher" },
	blur = true,
	ignore_alpha = 0.3,
})

-- Same deal for the overview: its surface covers the whole output, so
-- without the threshold every pixel of the screen would be blurred
-- instead of just the panel.
hl.layer_rule({
	match = { namespace = "quickshell-overview" },
	blur = true,
	ignore_alpha = 0.3,
})

-- The control center panel's surface covers the whole output too (so
-- its dismiss area reaches every pixel), so the same ignore_alpha
-- threshold applies for the same reason.
--
-- No compositor animation: this surface spans the whole output, so
-- Hyprland animates the entire screen-sized layer rather than the
-- 360px panel drawn in one corner of it -- `popin` read as the panel
-- flying up from the bottom-left instead of growing out of the bar
-- button. The panel animates itself client-side instead, anchored to
-- the corner it is attached to.
hl.layer_rule({
	match = { namespace = "quickshell-control-center" },
	blur = true,
	ignore_alpha = 0.3,
	animation = "none",
})

hl.layer_rule({
	match = { namespace = "calbar-popup" },
	blur = true,
	ignore_alpha = 0.3,
})

------------------------------
---- CURVES / ANIMATIONS ----
------------------------------

hl.curve("smoothOut", { type = "bezier", points = { { 0.36, 0 }, { 0.66, -0.56 } } })
hl.curve("smoothIn", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.curve("overshot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("softSnap", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })
hl.curve("fluent", { type = "bezier", points = { { 0.0, 0.0 }, { 0.2, 1.0 } } })
hl.curve("easeInOutExpo", { type = "bezier", points = { { 0.87, 0 }, { 0.13, 1 } } })

-- Windows
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "overshot", style = "popin 80%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 3, bezier = "overshot", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "softSnap", style = "popin 95%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "softSnap" })
-- Layers - defaults; swaync overridden to slide right via layer_rule
hl.animation({ leaf = "layersIn", enabled = true, speed = 3, bezier = "smoothIn" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 4, bezier = "softSnap" })
-- Fade
hl.animation({ leaf = "fade", enabled = true, speed = 2, bezier = "smoothIn" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 2, bezier = "smoothIn" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 2, bezier = "softSnap" })
hl.animation({ leaf = "fadeSwitch", enabled = true, speed = 2, bezier = "smoothIn" })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 2, bezier = "smoothIn" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 2, bezier = "smoothIn" })
hl.animation({ leaf = "fadeDpms", enabled = true, speed = 2, bezier = "smoothIn" })
hl.animation({ leaf = "fadeLayers", enabled = true, speed = 2, bezier = "softSnap" })
-- Workspaces
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "softSnap", style = "slidefade 30%" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "softSnap", style = "slidefadevert 30%" })

---------------------
---- DECORATION ----
---------------------

hl.config({
	decoration = {
		rounding = 16,
		rounding_power = 4,
		active_opacity = 1.0,
		inactive_opacity = 1.0,

		shadow = {
			enabled = true,
			range = 4,
			render_power = 3,
			color = "rgba(1a1a1aee)",
		},

		blur = {
			enabled = true,

			size = 4,
			passes = 2,
			-- Must be a Lua number, not a string: CLuaConfigFloat rejects strings.
			vibrancy = 0.1696,
			popups = true,
			popups_ignorealpha = 0.3,
		},
	},
})

-- hyprbars is not ported: no plugin is loaded anywhere in this flake (the
-- hyprland-plugins input is commented out), and native Lua hard-errors on
-- unknown plugin keys unless the plugin is actually loaded. To bring it
-- back: add `wayland.windowManager.hyprland.plugins`, then
-- `hl.config({ plugin = { hyprbars = { ... } } })` here.
