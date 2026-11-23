-- Input configuration

hl.config({
    input = {
        -- sensitivity = -0.25,
        accel_profile = "flat",
    },
    -- Uncomment the section below to enable software cursors; this can help with cursor display or behavior issues
    cursor = {
        no_hardware_cursors = 1,
    },
})

hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "down",       action = "close" })
hl.gesture({ fingers = 3, direction = "up",         action = "fullscreen" })
hl.gesture({ fingers = 3, direction = "left",       action = "float" })

-- Trackpad: keep tap-to-click, but never turn a stray tap into a drag.
hl.config({
    input = {
        touchpad = {
            tap_to_click = true,
            tap_and_drag = false,
            disable_while_typing = true,
        },
    },
})
