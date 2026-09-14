--
-- Advanced Peripherals Overlay Module rendering control
--

local glasses    = require("smartglasses_display.smartglasses")

local types      = require("scada-common.types")

local ALARM_STATE = types.ALARM_STATE

local FALLBACK_ALARM_NAMES = {
    "ContainmentBreach", "ContainmentRadiation", "ReactorLost", "CriticalDamage",
    "ReactorDamage", "ReactorOverTemp", "ReactorHighTemp", "ReactorWasteLeak",
    "ReactorHighWaste", "RPSTransient", "RCSTransient", "TurbineTrip"
}
local ALARM_NAMES = types.ALARM_NAMES or FALLBACK_ALARM_NAMES

---@class glasses_renderer
local renderer = {}

local C_FRAME_OK    = 0x00CCFF
local C_FRAME_ALARM = 0xFF3333
local C_LINK_OK     = 0x33CC33
local C_LINK_WARN   = 0xFFAA00
local C_TEXT        = 0xFFFFFF
local C_ALARM       = 0xFF3333
local C_OK          = 0x33CC33
local C_FLASH       = 0xFFFF66

local HUD_X, HUD_Y = 10, 10
local HUD_W, HUD_H = 170, 110

local ui = {
    overlay = nil,
    objects = {},
    scale = 1.0,
    unit_id = 1,
    flash_until = 0
}

local function tripped(state)
    return state == ALARM_STATE.TRIPPED or state == ALARM_STATE.ACKED
end

local function fmt_temp(k) if k == nil then return "--" end return string.format("%.0f", k) end
local function fmt_rate(v) if v == nil then return "--" end return string.format("%.1f", v) end

local function avg_state_field(list, field)
    if type(list) ~= "table" or #list == 0 then return nil end
    local sum, n = 0, 0
    for i = 1, #list do
        local st = list[i] and list[i].state or nil
        if st and st[field] ~= nil then sum = sum + st[field]; n = n + 1 end
    end
    if n == 0 then return nil end
    return sum / n
end

-- try to start the HUD
---@return boolean success, any error_msg
function renderer.try_start_hud()
    local status, msg = true, nil

    if ui.overlay == nil then
        local overlay = peripheral.find("overlay")
        if overlay == nil then
            return false, "Advanced Peripherals Overlay Module not found"
        end

        ui.overlay = overlay
        ui.scale = glasses.config.HUDScale or 1.0
        ui.unit_id = glasses.config.UnitID or 1

        status, msg = pcall(function ()
            local o = ui.overlay

            ui.objects.frame = o.addBox({
                x = HUD_X, y = HUD_Y, width = HUD_W, height = HUD_H,
                color = C_FRAME_OK, opacity = 0.6, filled = false,
            })

            ui.objects.title = o.addText({
                x = HUD_X + 8, y = HUD_Y + 4,
                text = "REACTOR " .. ui.unit_id, size = ui.scale * 1.5, color = C_FRAME_OK,
            })

            ui.objects.link = o.addText({
                x = HUD_X + 8, y = HUD_Y + 26,
                text = "SEARCHING...", size = ui.scale, color = C_LINK_WARN,
            })

            ui.objects.temp = o.addText({
                x = HUD_X + 8, y = HUD_Y + 42,
                text = "TEMP: -- K", size = ui.scale, color = C_TEXT,
            })

            ui.objects.burn = o.addText({
                x = HUD_X + 8, y = HUD_Y + 58,
                text = "BURN: -- / -- mB/t", size = ui.scale, color = C_TEXT,
            })

            ui.objects.coolant = o.addText({
                x = HUD_X + 8, y = HUD_Y + 74,
                text = "COOLANT: -- %", size = ui.scale, color = C_TEXT,
            })

            ui.objects.waste = o.addText({
                x = HUD_X + 8, y = HUD_Y + 90,
                text = "WASTE: -- %", size = ui.scale, color = C_TEXT,
            })

            ui.objects.alarm = o.addText({
                x = HUD_X + 8, y = HUD_Y + 104,
                text = "", size = ui.scale, color = C_OK,
            })
        end)

        if not status then
            ui.overlay = nil
        end
    end

    return status, msg
end

-- close out the HUD
function renderer.close_hud()
    if ui.overlay ~= nil then
        pcall(function () ui.overlay.clear() end)
        ui.overlay = nil
        ui.objects = {}
    end
end

-- is the HUD ready?
function renderer.hud_ready() return ui.overlay ~= nil end

-- update the link line
---@param linked boolean
---@param err string
function renderer.update_link(linked, err)
    if ui.overlay == nil then return end
    local o = ui.objects

    if linked then
        o.link:setText("LINKED")
        o.link:setColor(C_LINK_OK)
    else
        local text = "SEARCHING..."
        if err and err ~= "" then text = "LINK FAILED: " .. err end
        o.link:setText(text)
        o.link:setColor(C_LINK_WARN)

        o.temp:setText("TEMP: -- K")
        o.burn:setText("BURN: -- / -- mB/t")
        o.coolant:setText("COOLANT: -- %")
        o.waste:setText("WASTE: -- %")
        o.alarm:setText("")
        o.frame:setColor(C_FRAME_OK)
    end
end

-- render the current unit record (called by thread__main on each poll)
function renderer.render_unit()
    if ui.overlay == nil then return end

    local u = glasses.unit
    local o = ui.objects

    local connected = u.connected
    local alarms    = u.alarms or {}
    local reactor   = u.reactor_data or {}
    local mek       = reactor.mek_status or {}
    local boilers   = u.boiler_data_tbl or {}
    local tanks     = u.tank_data_tbl or {}

    if connected then
        o.link:setText("LINKED")
        o.link:setColor(C_LINK_OK)
    else
        o.link:setText("LINKED (RCT OFFLINE)")
        o.link:setColor(C_LINK_WARN)
    end

    o.temp:setText("TEMP: " .. fmt_temp(mek.temp) .. " K")
    o.burn:setText("BURN: " .. fmt_rate(mek.act_burn_rate) .. " / " ..
                             fmt_rate(mek.burn_rate) .. " mB/t")

    local coolant = mek.ccool_fill or avg_state_field(boilers, "ccool_fill")
    if coolant ~= nil then
        o.coolant:setText(string.format("COOLANT: %.0f %%", coolant * 100))
    else
        o.coolant:setText("COOLANT: -- %")
    end

    local waste = mek.waste_fill or avg_state_field(tanks, "waste_fill")
    if waste ~= nil then
        o.waste:setText(string.format("WASTE: %.0f %%", waste * 100))
    else
        o.waste:setText("WASTE: -- %")
    end

    local active = {}
    for i = 1, #ALARM_NAMES do
        if tripped(alarms[i]) then table.insert(active, ALARM_NAMES[i]) end
    end

    if os.clock() < ui.flash_until then
        o.alarm:setColor(C_FLASH)
        return
    end

    if #active == 0 then
        o.alarm:setText("ALL NOMINAL")
        o.alarm:setColor(C_OK)
        o.frame:setColor(C_FRAME_OK)
    else
        local text = active[1]
        if #active > 1 then text = text .. " (+" .. (#active - 1) .. ")" end
        o.alarm:setText(text)
        o.alarm:setColor(C_ALARM)
        o.frame:setColor(C_FRAME_ALARM)
    end
end

-- transient status line for hotkey feedback
---@param text string
function renderer.flash_message(text)
    if ui.overlay == nil then return end
    ui.objects.alarm:setText(text)
    ui.objects.alarm:setColor(C_FLASH)
    ui.flash_until = os.clock() + 1.5
end

return renderer