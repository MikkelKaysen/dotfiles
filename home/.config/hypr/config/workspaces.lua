-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
--
-- Numbered workspaces are planned by hyprmoncfg, not here. The active profile
-- ("docked": strategy sequential, group size 3) generates 1-3 on eDP-1 and
-- 4-6 on DP-4 into ~/.config/hypr/hyprmoncfg-monitors.lua, which loads last and
-- therefore wins. Change them in the `hyprmoncfg` TUI (tab 2, Workspaces) or by
-- re-saving the profile - never by adding hl.workspace_rule calls here.
--
-- Named workspaces are not part of hyprmoncfg's plan, so this one stays ours.
hl.workspace_rule({ workspace = "name:gaming", monitor = PRIMARY_MONITOR, default = true })
