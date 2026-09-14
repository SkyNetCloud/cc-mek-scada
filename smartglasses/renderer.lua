--
-- Advanced Peripherals Overlay Module rendering control
-- Compact HUD layout for Smart Glasses
--

local glasses    = require("smartglasses.smartglasses")
local types      = require("scada-common.types")

local ALARM_STATE = types.ALARM_STATE

local ALARM_NAMES = types.ALARM_NAMES or {
    "ContainmentBreach", "ContainmentRadiation", "ReactorLost", "CriticalDamage",
    "ReactorDamage", "ReactorOverTemp", "ReactorHighTemp", "ReactorWasteLeak",
    "ReactorHighWaste", "RPSTransient", "RCSTransient", "TurbineTrip",
    "FacilityRadiation"
}

---@class glasses_renderer
local renderer = {}

-- colors (0xRRGGBB)
local C_FRAME_OK    = 0x00CCFF
local C_FRAME_WARN  = 0xFFAA00
local C_FRAME_ALARM = 0xFF3333
local C_LINK_OK     = 0x33CC33
local C_LINK_WARN   = 0xFFAA00
local C_TEXT        = 0xFFFFFF
local C_LABEL       = 0xAAAAAA
local C_OK          = 0x33CC33
local C_ALARM       = 0xFF3333
local C_FLASH       = 0xFFFF66
local C_HEADER      = 0x33CCFF

-- layout origin and dimensions
local HUD_X, HUD_Y = 10, 10
local HUD_W, HUD_H = 200, 130
local ROW_H = 12

local ui = {
    overlay = nil,
    refs = {},
    scale = 1.0,
    unit_id = 1,
    flash_until = 0,
}

local function tripped(state)
    return state == ALARM_STATE.TRIPPED or state == ALARM_STATE.ACKED
end

local function fmt_num(v, fmt)
    if type(v) ~= "number" then return "--" end
    return string.format(fmt, v)
end

local function pct(v)
    if type(v) ~= "number" then return "--" end
    return string.format("%.0f%%", v * 100)
end

-- =========================================================================
-- Overlay API wrappers
-- =========================================================================

---@param x number
---@param y number
---@param text string
---@param color integer
---@param size number?
---@return table|nil
local function mk_text(x, y, text, color, size)
    local o = ui.overlay
    if o == nil or type(o.createText) ~= "function" then return nil end

    local ok, handle = pcall(o.createText, {
        x = x, y = y,
        content = text,
        color = color,
        fontSize = size or ui.scale,
        shadow = true,
    })
    if ok then return handle end
    return nil
end

---@param x number
---@param y number
---@param w number
---@param h number
---@param color integer
---@return table|nil
local function mk_rect(x, y, w, h, color)
    local o = ui.overlay
    if o == nil or type(o.createRectangle) ~= "function" then return nil end

    local ok, handle = pcall(o.createRectangle, {
        x = x, y = y,
        sizeX = w, sizeY = h,
        color = color,
        filled = false,
    })
    if ok then return handle end
    return nil
end

---@param handle table|nil
---@param text string
local function set_text(handle, text)
    if handle == nil then return end
    if type(handle.setContent) == "function" then
        pcall(handle.setContent, handle, tostring(text))
    end
end

---@param handle table|nil
---@param color integer
local function set_color(handle, color)
    if handle == nil then return end
    if type(handle.setColor) == "function" then
        pcall(handle.setColor, handle, color)
    end
end

-- =========================================================================

---@param overlay table
---@return boolean success, any error_msg
function renderer.try_start_hud(overlay)
    local status, msg = true, nil

    if ui.overlay == nil then
        if overlay == nil then return false, "overlay module not provided" end

        ui.overlay = overlay
        ui.scale = glasses.config.HUDScale or 1.0
        ui.unit_id = glasses.config.UnitID or 1

        status, msg = pcall(function ()
            local R = ui.refs

            R.frame = mk_rect(HUD_X, HUD_Y, HUD_W, HUD_H, C_FRAME_OK)

            R.title  = mk_text(HUD_X + 8, HUD_Y + 4, "REACTOR " .. ui.unit_id, C_HEADER, ui.scale * 1.5)
            R.link   = mk_text(HUD_X + 8, HUD_Y + 20, "SEARCHING...", C_LINK_WARN, ui.scale)

            local y = HUD_Y + 40
            R.temp_lbl = mk_text(HUD_X + 8,  y, "TEMP", C_LABEL, ui.scale)
            R.temp_val = mk_text(HUD_X + 60, y, "-- K", C_TEXT,  ui.scale)

            R.burn_lbl = mk_text(HUD_X + 8,  y + ROW_H, "BURN", C_LABEL, ui.scale)
            R.burn_val = mk_text(HUD_X + 60, y + ROW_H, "-- / --", C_TEXT, ui.scale)

            R.dmg_lbl  = mk_text(HUD_X + 8,  y + ROW_H * 2, "DMG",  C_LABEL, ui.scale)
            R.dmg_val  = mk_text(HUD_X + 60, y + ROW_H * 2, "-- %", C_TEXT, ui.scale)

            local y2 = HUD_Y + 40
            R.fuel_lbl = mk_text(HUD_X + 110, y2, "FUEL", C_LABEL, ui.scale)
            R.fuel_val = mk_text(HUD_X + 165, y2, "--",   C_TEXT, ui.scale)

            R.ccool_lbl = mk_text(HUD_X + 110, y2 + ROW_H, "COOL", C_LABEL, ui.scale)
            R.ccool_val = mk_text(HUD_X + 165, y2 + ROW_H, "--",   C_TEXT, ui.scale)

            R.waste_lbl = mk_text(HUD_X + 110, y2 + ROW_H * 2, "WASTE", C_LABEL, ui.scale)
            R.waste_val = mk_text(HUD_X + 165, y2 + ROW_H * 2, "--",   C_TEXT, ui.scale)

            R.status1 = mk_text(HUD_X + 8, HUD_Y + 78, "", C_TEXT, ui.scale)
            R.status2 = mk_text(HUD_X + 8, HUD_Y + 90, "", C_LABEL, ui.scale)

            R.rcs     = mk_text(HUD_X + 8,  HUD_Y + 104, "RCS: --", C_LABEL, ui.scale)
            R.rps     = mk_text(HUD_X + 80, HUD_Y + 104, "RPS: --", C_LABEL, ui.scale)

            R.alarm   = mk_text(HUD_X + 8, HUD_Y + 118, "", C_OK, ui.scale)

            if type(ui.overlay.update) == "function" then
                pcall(ui.overlay.update)
            end
        end)

        if not status then ui.overlay = nil end
    end

    return status, msg
end

function renderer.close_hud()
    if ui.overlay ~= nil then
        pcall(function ()
            if type(ui.overlay.clear) == "function" then ui.overlay.clear() end
        end)
        ui.overlay = nil
        ui.refs = {}
    end
end

function renderer.hud_ready() return ui.overlay ~= nil end

---@param linked boolean
---@param err string
function renderer.update_link(linked, err)
    if ui.overlay == nil then return end
    local R = ui.refs

    if linked then
        set_text(R.link, "LINKED")
        set_color(R.link, C_LINK_OK)
    else
        local text = "SEARCHING..."
        if err and err ~= "" then text = "LINK FAILED: " .. err end
        set_text(R.link, text)
        set_color(R.link, C_LINK_WARN)

        set_text(R.temp_val,  "-- K")
        set_text(R.burn_val,  "-- / --")
        set_text(R.dmg_val,   "-- %")
        set_text(R.fuel_val,  "--")
        set_text(R.ccool_val, "--")
        set_text(R.waste_val, "--")
        set_text(R.status1,   "")
        set_text(R.status2,   "")
        set_text(R.rcs,       "RCS: --")
        set_text(R.rps,       "RPS: --")
        set_text(R.alarm,     "")
        set_color(R.frame,    C_FRAME_OK)
    end
end

function renderer.render_unit()
    if ui.overlay == nil then return end

    local u = glasses.unit
    local R = ui.refs

    local connected = u.connected == true
    local alarms    = type(u.alarms) == "table" and u.alarms or {}
    local reactor   = type(u.reactor_data) == "table" and u.reactor_data or {}
    local mek       = type(reactor.mek_status) == "table" and reactor.mek_status or {}
    local annunc    = type(u.annunciator) == "table" and u.annunciator or {}

    if connected then
        set_text(R.link, "LINKED")
        set_color(R.link, C_LINK_OK)
    else
        set_text(R.link, "LINKED (RCT OFFLINE)")
        set_color(R.link, C_LINK_WARN)
    end

    set_text(R.temp_val, fmt_num(mek.temp, "%.0f K"))
    set_text(R.burn_val, string.format("%s / %s",
        fmt_num(mek.act_burn_rate, "%.1f"),
        fmt_num(mek.burn_rate, "%.1f")))
    set_text(R.dmg_val, fmt_num(mek.damage, "%.0f %%"))

    set_text(R.fuel_val,  pct(mek.fuel_fill))
    set_text(R.ccool_val, pct(mek.ccool_fill))
    set_text(R.waste_val, pct(mek.waste_fill))

    local reactor_active = mek.status == true
    local auto_ctrl = annunc.AutoControl == true
    local scrammed  = reactor.rps_tripped == true

    local state_str = "IDLE"
    if scrammed then state_str = "SCRAM"
    elseif reactor_active then state_str = "RUNNING" end

    local ctrl_str = auto_ctrl and "AUTO" or "MANUAL"
    set_text(R.status1, string.format("%s  [%s]", state_str, ctrl_str))
    set_color(R.status1, reactor_active and C_OK or C_LABEL)

    local ag_names = types.AUTO_GROUP_NAMES or { "Manual" }
    local ag_id = (type(u.a_group) == "number" and u.a_group or 0) + 1
    set_text(R.status2, "Group: " .. (ag_names[ag_id] or "?"))

    local rcs_hazard = annunc.RCPTrip == true
    local rcs_warn   = annunc.RCSFlowLow or annunc.CoolantLevelLow or annunc.RCSFault
                    or annunc.MaxWaterReturnFeed or annunc.CoolantFeedMismatch
                    or annunc.BoilRateMismatch or annunc.SteamFeedMismatch

    if rcs_hazard then
        set_text(R.rcs, "RCS: HAZARD"); set_color(R.rcs, C_ALARM)
    elseif rcs_warn then
        set_text(R.rcs, "RCS: WARN");   set_color(R.rcs, C_LINK_WARN)
    else
        set_text(R.rcs, "RCS: OK");     set_color(R.rcs, C_OK)
    end

    if reactor.rps_tripped == true then
        set_text(R.rps, "RPS: TRIP"); set_color(R.rps, C_ALARM)
    else
        set_text(R.rps, "RPS: OK");   set_color(R.rps, C_OK)
    end

    local active = {}
    for i = 1, #ALARM_NAMES do
        if tripped(alarms[i]) then table.insert(active, ALARM_NAMES[i]) end
    end

    if os.clock() < ui.flash_until then
        set_color(R.alarm, C_FLASH)
        set_color(R.frame, C_FRAME_WARN)
        return
    end

    if #active == 0 then
        set_text(R.alarm, "ALL NOMINAL")
        set_color(R.alarm, C_OK)
        set_color(R.frame, C_FRAME_OK)
    else
        local text = active[1]
        if #active > 1 then text = text .. " (+" .. (#active - 1) .. ")" end
        set_text(R.alarm, text)
        set_color(R.alarm, C_ALARM)
        set_color(R.frame, C_FRAME_ALARM)
    end
end

---@param text string
function renderer.flash_message(text)
    if ui.overlay == nil then return end
    set_text(ui.refs.alarm, text)
    set_color(ui.refs.alarm, C_FLASH)
    ui.flash_until = os.clock() + 1.5
end

return renderer