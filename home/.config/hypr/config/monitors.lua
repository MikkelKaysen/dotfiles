-- Monitor wiki https://wiki.hypr.land/Configuring/Basics/Monitors/
-- Example: output can be found with hyprctl monitors. Edit variables.lua for the monitor outputs instead of here directly
-- hl.monitor({
--     output    = MONITOR1,
--     mode      = "1920x1080@60",
--     position  = "0x0",
--     scale     = "1",
-- })

-- eDP-1 (laptop, 2880x1800): auto-placed at the origin, 120% scale.
-- Not "auto": that derives 2.0 from this panel's ~221 PPI.
hl.monitor({
    output    = MONITOR1,
    mode      = "preferred",
    position  = "auto",
    scale     = "1.2",
})

-- DP-4 (Dell, 2560x1440): auto-placed to the right of MONITOR1,
-- vertically centered, 100% scale.
hl.monitor({
    output    = MONITOR2,
    mode      = "preferred",
    position  = "auto-center-right",
    scale     = "1",
})

-- Fallback for any display without an explicit rule: keep it at 1x too.
hl.monitor({
    output    = "",
    mode      = "preferred",
    position  = "auto",
    scale     = "1",
})
