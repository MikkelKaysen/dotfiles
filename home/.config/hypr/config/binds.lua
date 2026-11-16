local mainMod = "SUPER"
local noctCall = "noctalia msg "
local launchPrefix = "uwsm app -- " -- if you are not using UWSM, make this empty (e.g. "")

-- AZERTY fix: the number-row keys emit symbols (& é " ' ...) without Shift, so
-- binding to the digit characters fails. Bind by physical keycode instead.
-- Digit d -> evdev keycode: 1..9 => 10..18, 0 => 19
local function digitCode(d)
    return "code:" .. (d == 0 and 19 or (9 + d))
end

------------------------------
-- 1. Window Management
------------------------------

-- Window manipulation
hl.bind(mainMod .. " + Escape",      hl.dsp.exec_cmd("hyprctl kill"), { description = "Kill window" })
hl.bind(mainMod .. " + Q",           hl.dsp.window.close(), { description = "Close window" })
hl.bind(mainMod .. " + ALT + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating" })
hl.bind(mainMod .. " + D",           hl.dsp.window.fullscreen({ mode = 1 }), { description = "Toggle maximize" })
hl.bind(mainMod .. " + F",           hl.dsp.window.fullscreen(), { description = "Toggle fullscreen" })
hl.bind(mainMod .. " + J",           hl.dsp.layout("togglesplit"), { description = "Toggle split direction" })

-- Change focus
hl.bind(mainMod .. " + Left",  hl.dsp.focus({ direction = "left" }), { description = "Focus left" })
hl.bind(mainMod .. " + Right", hl.dsp.focus({ direction = "right" }), { description = "Focus right" })
hl.bind(mainMod .. " + Up",    hl.dsp.focus({ direction = "up" }), { description = "Focus up" })
hl.bind(mainMod .. " + Down",  hl.dsp.focus({ direction = "down" }), { description = "Focus down" })
hl.bind("ALT + Tab",           hl.dsp.window.cycle_next(), { description = "Cycle windows" })
hl.bind(mainMod .. " + Tab",   hl.dsp.exec_cmd(noctCall .. "window-switcher"), { description = "Window switcher" })

-- Move active window around workspaces & monitors
hl.bind(mainMod .. " + SHIFT + Up",                   hl.dsp.window.move({ direction = "u" }), { description = "Move window up" })
hl.bind(mainMod .. " + SHIFT + Right",                hl.dsp.window.move({ direction = "r" }), { description = "Move window right" })
hl.bind(mainMod .. " + SHIFT + Left",                 hl.dsp.window.move({ direction = "l" }), { description = "Move window left" })
hl.bind(mainMod .. " + SHIFT + Down",                 hl.dsp.window.move({ direction = "d" }), { description = "Move window down" })
hl.bind(mainMod .. " + SHIFT + " .. digitCode(1),     hl.dsp.window.move({ monitor = MONITOR1 }), { description = "Move window to display 1" })
hl.bind(mainMod .. " + SHIFT + " .. digitCode(2),     hl.dsp.window.move({ monitor = MONITOR2 }), { description = "Move window to display 2" })
hl.bind(mainMod .. " + SHIFT + " .. digitCode(3),     hl.dsp.window.move({ monitor = MONITOR3 }), { description = "Move window to display 3" })
hl.bind(mainMod .. " + SHIFT + mouse_up",             hl.dsp.window.move({ monitor   = "-1" }), { description = "Move window to previous display" })
hl.bind(mainMod .. " + SHIFT + mouse_down",           hl.dsp.window.move({ monitor   = "+1" }), { description = "Move window to next display" })
hl.bind(mainMod .. " + CONTROL + SHIFT + Right",      hl.dsp.window.move({ workspace = "m+1" }), { description = "Move window to next workspace" })
hl.bind(mainMod .. " + CONTROL + SHIFT + Left",       hl.dsp.window.move({ workspace = "m-1" }), { description = "Move window to previous workspace" })
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_up",   hl.dsp.window.move({ workspace = "m-1" }), { description = "Move window to previous workspace" })
hl.bind(mainMod .. " + CONTROL + SHIFT + mouse_down", hl.dsp.window.move({ workspace = "m+1" }), { description = "Move window to next workspace" })
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + CONTROL + " .. digitCode(key), hl.dsp.window.move({ workspace = "m~" .. i }), { description = "Move window to workspace " .. i })
end
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + SHIFT + ALT + " .. digitCode(key), hl.dsp.window.move({ workspace = "m~" .. i, follow = false }), { description = "Move window to workspace " .. i .. " silently" })
end

-- Move & Resize with mouse
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { description = "Drag window" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { description = "Resize window" })

-- Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end
hl.bind(mainMod .. " + Minus", function() zoomfunction(-0.3) end, { repeating = true, description = "Zoom out" })
hl.bind(mainMod .. " + Plus", function() zoomfunction(0.3) end, { repeating = true, description = "Zoom in" })

--# Zoom with keypad
hl.bind(mainMod .. " + code:82", function() zoomfunction(-0.3) end, { repeating = true, description = "Zoom out (numpad)" })
hl.bind(mainMod .. " + code:86", function() zoomfunction(0.3) end, { repeating = true, description = "Zoom in (numpad)" })


------------------
-- 2. Launcher
------------------

hl.bind(mainMod .. " + Return",     hl.dsp.exec_cmd(launchPrefix .. TERMINAL), { description = "Terminal" })
hl.bind(mainMod .. " + E",          hl.dsp.exec_cmd(launchPrefix .. FILE_MANAGER), { description = "File manager" })
hl.bind(mainMod .. " + T",          hl.dsp.exec_cmd(launchPrefix .. EDITOR), { description = "Text editor" })
hl.bind(mainMod .. " + C",          hl.dsp.exec_cmd(launchPrefix .. CALCULATOR), { description = "Calculator" })
hl.bind("XF86Calculator",           hl.dsp.exec_cmd(launchPrefix .. CALCULATOR), { description = "Calculator" })
hl.bind(mainMod .. " + W",          hl.dsp.exec_cmd(launchPrefix .. BROWSER), { description = "Browser" })
hl.bind("CONTROL + SHIFT + Escape", hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " -e btop"), { description = "System monitor" })
hl.bind(mainMod .. " + Z",          hl.dsp.exec_cmd(noctCall .. "settings-toggle"), { description = "Noctalia settings" })
hl.bind(mainMod .. " + X",          hl.dsp.exec_cmd(noctCall .. "panel-toggle control-center"), { description = "Control center" })
hl.bind(mainMod .. " + Space",      hl.dsp.exec_cmd(noctCall .. "panel-toggle launcher"), { description = "Application launcher" })
hl.bind(mainMod .. " + period",     hl.dsp.exec_cmd(noctCall .. "panel-toggle launcher /emo"), { description = "Emoji picker" })
hl.bind(mainMod .. " + L",          hl.dsp.exec_cmd(noctCall .. "session lock"), { description = "Lock screen" })
hl.bind(mainMod .. " + ALT + C",    hl.dsp.exec_cmd(noctCall .. "panel-toggle session"), { description = "Session menu" })

------------------------------
-- 3. Hardware Controls
------------------------------

-- Audio
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(noctCall .. "volume-up"),   { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(noctCall .. "volume-down"), { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd(noctCall .. "volume-mute"), { locked = true, description = "Mute audio" })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd(noctCall .. "mic-mute"),    { locked = true, description = "Mute microphone" })

-- Media
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd(noctCall .. "media toggle"),   { locked = true, description = "Play/pause media" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(noctCall .. "media toggle"),   { locked = true, description = "Play/pause media" })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd(noctCall .. "media next"),     { locked = true, description = "Next track" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd(noctCall .. "media previous"), { locked = true, description = "Previous track" })

-- Keyboard Brightness
hl.bind("XF86KbdBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -d ':white:kbd_backlight' set +10%"),   { locked = true, repeating = true, description = "Keyboard backlight up" })
hl.bind("XF86KbdBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d ':white:kbd_backlight' set 10%-"), { locked = true, repeating = true, description = "Keyboard backlight down" })

-- Brightness
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(noctCall .. "brightness-up"),   { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(noctCall .. "brightness-down"), { locked = true, repeating = true, description = "Brightness down" })

-------------------
-- 4. Utilities
-------------------

-- Screen Capture
hl.bind(mainMod .. " + P",     hl.dsp.exec_cmd("hyprpicker -a -n"), { description = "Color picker" })
hl.bind("Print",               hl.dsp.exec_cmd(noctCall .. "screenshot-region"), { description = "Screenshot region" })
hl.bind(mainMod .. " + Print", hl.dsp.exec_cmd(noctCall .. "screenshot-fullscreen"), { description = "Screenshot fullscreen" })

-- Theming and Wallpaper
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(noctCall .. "panel-toggle wallpaper"), { description = "Wallpaper picker" })
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.exec_cmd("sh -c 'noctalia msg theme-mode-toggle; sleep 0.5; hyprctl reload'"), { description = "Toggle light/dark theme" })

-- Clipboard
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(noctCall .. "panel-toggle clipboard"), { description = "Clipboard history" })

-- Notifications
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd(noctCall .. "panel-toggle control-center notifications"), { description = "Notification center" })

-- Help
hl.bind(mainMod .. " + F1", hl.dsp.exec_cmd(noctCall .. "panel-toggle kenn/keybind-cheatsheet:cheatsheet"), { description = "Keybind cheatsheet" })

---------------------------------
-- 5. Workspaces & Monitors
---------------------------------

-- Focus on monitors
hl.bind(mainMod .. " + " .. digitCode(1), hl.dsp.focus({ monitor = MONITOR1 }), { description = "Focus display 1" })
hl.bind(mainMod .. " + " .. digitCode(2), hl.dsp.focus({ monitor = MONITOR2 }), { description = "Focus display 2" })
hl.bind(mainMod .. " + " .. digitCode(3), hl.dsp.focus({ monitor = MONITOR3 }), { description = "Focus display 3" })

-- Monitor layout editor
hl.bind(mainMod .. " + ALT + M", hl.dsp.exec_cmd(launchPrefix .. TERMINAL .. " -e hyprmoncfg"), { description = "Monitor layout" })

-- Focus on workspace number
-- Absolute
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + ALT + " .. digitCode(key), hl.dsp.focus({ workspace = i }), { description = "Focus workspace " .. i })
end
-- Relative
for i = 1, NUM_WPM do
    local key = i % 10
    hl.bind(mainMod .. " + CONTROL + " .. digitCode(key), hl.dsp.focus({ workspace = "m~" .. i }), { description = "Focus workspace " .. i .. " (relative)" })
end

-- Move to adjacent workspaces and next empty on a given monitor
hl.bind(mainMod .. " + CONTROL + Right",       hl.dsp.focus({ workspace = "m+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + CONTROL + Left",        hl.dsp.focus({ workspace = "m-1" }), { description = "Previous workspace" })
hl.bind(mainMod .. " + CONTROL + Down",        hl.dsp.focus({ workspace = "emptym" }), { description = "Empty workspace" })

-- Scroll through existing workspaces & monitors
hl.bind(mainMod .. " + mouse_down",           hl.dsp.focus({ workspace = "m-1" }), { description = "Previous workspace" })
hl.bind(mainMod .. " + mouse_up",             hl.dsp.focus({ workspace = "m+1" }), { description = "Next workspace" })
hl.bind(mainMod .. " + CONTROL + mouse_up",   hl.dsp.focus({ workspace = "m-1" }), { description = "Previous workspace" })
hl.bind(mainMod .. " + CONTROL + mouse_down", hl.dsp.focus({ workspace = "m+1" }), { description = "Next workspace" })

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special" }), { description = "Move window to scratchpad" })
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special(), { description = "Toggle scratchpad" })
