-- Hyprland default apps

TERMINAL     = "ghostty"
FILE_MANAGER = "dolphin"
BROWSER      = "zen-browser"
-- nvim in a fresh terminal window, always starting in $HOME.
-- --window-inherit-working-directory=false is required: ghostty runs
-- single-instance here, otherwise a new window inherits the focused window's cwd.
EDITOR       = TERMINAL .. " --working-directory=home --window-inherit-working-directory=false -e nvim"
CALCULATOR   = "gnome-calculator"

-- Monitors
MONITOR1 = "eDP-1"
MONITOR2 = "DP-4"
MONITOR3 = ""
PRIMARY_MONITOR = MONITOR1

-- Workspaces
NUM_WPM = 3 -- Number of workspaces per monitor (Max 10)
