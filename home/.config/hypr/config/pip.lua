-- Zen/Firefox PiP windows are mapped with initialTitle "Zen Browser" and are
-- only renamed to "Picture-in-Picture" afterwards. Hyprland applies static
-- window effects against initialTitle, so static rules miss every PiP after
-- the first one. Re-apply float/pin/size/move when the real title arrives.

local PIP_TITLE = "^[Pp]icture[%-%s]?[Ii]n[%-%s]?[Pp]icture"

local placed = {}

local function is_pip(w)
    return w ~= nil and w.title ~= nil and w.title:find(PIP_TITLE) ~= nil
end

local function place(w)
    local mon = w.monitor or hl.get_active_monitor()
    if mon == nil then return end

    -- Monitor width/height are pixels; window geometry is logical.
    local scale = mon.scale or 1
    local mw, mh = mon.width / scale, mon.height / scale
    local width  = math.floor(mh * 0.32)
    local height = math.floor(width * 9 / 16)
    local margin = 32

    hl.dispatch(hl.dsp.window.float({ window = w, action = "enable" }))
    hl.dispatch(hl.dsp.window.pin({ window = w, action = "enable" }))
    hl.dispatch(hl.dsp.window.set_prop({ window = w, prop = "keep_aspect_ratio", value = "1" }))
    hl.dispatch(hl.dsp.window.resize({ window = w, x = width, y = height }))
    hl.dispatch(hl.dsp.window.move({
        window = w,
        x = mw - width - margin,
        y = mh - height - margin,
    }))
end

local function on_window(w)
    if not is_pip(w) then return end

    local addr = w.address
    if addr == nil or placed[addr] then return end
    placed[addr] = true

    -- Give the client one frame to settle its own geometry before overriding it.
    hl.timer(function()
        if w.address == nil then return end -- window is gone
        place(w)
    end, { timeout = 50, type = "oneshot" })
end

hl.on("window.title", on_window)
hl.on("window.open", on_window)
hl.on("window.close", function(w)
    if w ~= nil and w.address ~= nil then placed[w.address] = nil end
end)
