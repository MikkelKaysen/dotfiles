-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
--
-- Numbered workspaces are planned by hyprmoncfg, not here. The "docked" profile
-- pins 1-3 to eDP-1 and 4-6 to DP-4 in
-- ~/.config/hypr/hyprmoncfg-monitors.lua, which loads last and therefore wins.
-- Change them in the `hyprmoncfg` TUI (tab 2, Workspaces) or by re-saving the
-- profile - never by adding hl.workspace_rule calls here.
--
-- Named workspaces are not part of hyprmoncfg's plan, so this one stays ours.
hl.workspace_rule({ workspace = "name:gaming", monitor = PRIMARY_MONITOR, default = true })
