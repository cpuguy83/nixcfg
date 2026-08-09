---@meta
-- Type declarations for the locals Nix injects into the generated
-- hyprland.lua ahead of this file's content (see settings.nix's `settings`
-- attrset, each entry with an `_var` field). Editor-only: Nix does not read
-- this file, and Hyprland never sees it either -- it exists purely so
-- lua_ls can type-check and complete these names in settings.lua.

---@type string
micMuteToggle = nil

---@type string
brightnessPath = nil

---@type string
getMonitorPath = nil

---@type string|nil
layout = nil

---@type HL.MonitorSpec[]
monitors = {}

---@type HL.WorkspaceRuleSpec[]
workspaceRules = {}
