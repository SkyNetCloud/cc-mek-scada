--
-- Configuration GUI System Builder
--

local log         = require("scada-common.log")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local TextBox     = require("graphics.elements.TextBox")

local PushButton  = require("graphics.elements.controls.PushButton")
local TextField   = require("graphics.elements.controls.TextField")
local Toggle      = require("graphics.elements.controls.Toggle")

local cpair = core.cpair
local INPUT_TYPE = core.INPUT_TYPE

local system = {}

-- build the configuration UI (mirrors pocket.config.system.create signature)
---@param tool_ctl any
---@param main_pane any
---@param settings { any, any, any, any, any }
---@param divs any[]
---@param style any
---@param startup function
---@param exit function
function system.create(tool_ctl, main_pane, settings, divs, style, startup, exit)
    local settings_cfg, ini_cfg, tmp_cfg, fields, load_settings = table.unpack(settings)

    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg
    local bw_fg_bg      = style.bw_fg_bg
    local nav_fg_bg     = style.nav_fg_bg

    local ui_cfg  = divs[1]
    local net_cfg = divs[2]
    local hud_cfg = divs[3]
    local log_cfg = divs[4]
    local summary = divs[5]

    local field_map = {}
    for _, f in ipairs(fields) do field_map[f[1]] = f end

    --#region UI Page

    TextBox{parent=ui_cfg,y=2,text=" HUD Settings",fg_bg=style.header}

    local ui_page = Div{parent=ui_cfg,x=2,y=4}

    TextBox{parent=ui_page,y=1,text="Reactor Unit ID:"}
    TextField{parent=ui_page,y=2,width=12,text=tostring(tmp_cfg.UnitID or 1),input_type=INPUT_TYPE.NUM,default="1",callback=function(v) tmp_cfg.UnitID = tonumber(v) or 1 end}

    TextBox{parent=ui_page,y=4,text="HUD Scale (0.5 - 2.0):"}
    TextField{parent=ui_page,y=5,width=12,text=tostring(tmp_cfg.HUDScale or 1.0),input_type=INPUT_TYPE.NUM,default="1.0",callback=function(v) tmp_cfg.HUDScale = tonumber(v) or 1.0 end}

    TextBox{parent=ui_page,y=7,text="SCRAM Hotkey (empty = off):"}
    TextField{parent=ui_page,y=8,width=24,text=tmp_cfg.HotkeyScram or "",default="",callback=function(v) tmp_cfg.HotkeyScram = v end}

    TextBox{parent=ui_page,y=10,text="START Hotkey (empty = off):"}
    TextField{parent=ui_page,y=11,width=24,text=tmp_cfg.HotkeyStart or "",default="",callback=function(v) tmp_cfg.HotkeyStart = v end}

    PushButton{parent=ui_page,y=13,min_width=8,text="\x1b Back",callback=function() main_pane.set_value(1) end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Network Page

    TextBox{parent=net_cfg,y=2,text=" Network Settings",fg_bg=style.header}

    local net_page = Div{parent=net_cfg,x=2,y=4}

    TextBox{parent=net_page,y=1,text="Coordinator Channel:"}
    TextField{parent=net_page,y=2,width=12,text=tostring(tmp_cfg.CRD_Channel or 16243),input_type=INPUT_TYPE.NUM,default="16243",callback=function(v) tmp_cfg.CRD_Channel = tonumber(v) end}

    TextBox{parent=net_page,y=4,text="HUD Packet Channel:"}
    TextField{parent=net_page,y=5,width=12,text=tostring(tmp_cfg.PKT_Channel or 16245),input_type=INPUT_TYPE.NUM,default="16245",callback=function(v) tmp_cfg.PKT_Channel = tonumber(v) end}

    TextBox{parent=net_page,y=7,text="Connection Timeout (s):"}
    TextField{parent=net_page,y=8,width=12,text=tostring(tmp_cfg.ConnTimeout or 5),input_type=INPUT_TYPE.NUM,default="5",callback=function(v) tmp_cfg.ConnTimeout = tonumber(v) or 5 end}

    TextBox{parent=net_page,y=10,text="Trusted Range (0 = no limit):"}
    TextField{parent=net_page,y=11,width=12,text=tostring(tmp_cfg.TrustedRange or 0),input_type=INPUT_TYPE.NUM,default="0",callback=function(v) tmp_cfg.TrustedRange = tonumber(v) or 0 end}

    PushButton{parent=net_page,y=13,min_width=8,text="\x1b Back",callback=function() main_pane.set_value(1) end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region HUD Page

    TextBox{parent=hud_cfg,y=2,text=" Facility Auth",fg_bg=style.header}

    local hud_page = Div{parent=hud_cfg,x=2,y=4}

    TextBox{parent=hud_page,y=1,height=3,text="Auth key must match the supervisor/coordinator facility AuthKey. Leave empty if the facility has none set."}

    TextBox{parent=hud_page,y=4,text="Auth Key (>= 8 chars or empty):"}
    TextField{parent=hud_page,y=5,width=36,text=tmp_cfg.AuthKey or "",default="",callback=function(v) tmp_cfg.AuthKey = v end}

    PushButton{parent=hud_page,y=13,min_width=8,text="\x1b Back",callback=function() main_pane.set_value(1) end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Log Page

    TextBox{parent=log_cfg,y=2,text=" Log Settings",fg_bg=style.header}

    local log_page = Div{parent=log_cfg,x=2,y=4}

    TextBox{parent=log_page,y=1,text="Log Mode:"}
    local log_mode_toggle
    log_mode_toggle = Toggle{parent=log_page,y=2,options={"Append","Overwrite"},default=(tmp_cfg.LogMode or log.MODE.APPEND)+1,callback=function(v) tmp_cfg.LogMode = v-1 end}

    TextBox{parent=log_page,y=4,text="Log Path:"}
    TextField{parent=log_page,y=5,width=30,text=tmp_cfg.LogPath or "/log.log",default="/log.log",callback=function(v) tmp_cfg.LogPath = v end}

    TextBox{parent=log_page,y=7,text="Log Debug Messages:"}
    local log_debug_toggle
    log_debug_toggle = Toggle{parent=log_page,y=8,options={"Disabled","Enabled"},default=tmp_cfg.LogDebug and 2 or 1,callback=function(v) tmp_cfg.LogDebug = (v == 2) end}

    PushButton{parent=log_page,y=13,min_width=8,text="\x1b Back",callback=function() main_pane.set_value(1) end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Summary Page

    TextBox{parent=summary,y=2,text=" Configuration Summary",fg_bg=style.header}

    local summary_div = Div{parent=summary,x=2,y=4,width=24}

    local summary_lines = ListBox{parent=summary_div,y=1,height=13,width=24,scroll_height=100,fg_bg=bw_fg_bg}

    local function refresh_summary()
        summary_lines.remove_all()
        for _, f in ipairs(fields) do
            local name, val = f[1], settings_cfg[f[1]]
            local text
            if name == "AuthKey" then
                text = (val == nil or val == "") and "(none)" or "(set)"
            elseif type(val) == "boolean" then
                text = val and "true" or "false"
            else
                text = tostring(val)
            end
            TextBox{parent=summary_lines,text=string.format("%s: %s", f[2], text),fg_bg=bw_fg_bg}
        end
    end

    tool_ctl.gen_summary = refresh_summary

    PushButton{parent=summary_div,y=15,min_width=8,text="\x1b Back",callback=function() main_pane.set_value(1) end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Page navigation buttons on the main page

    PushButton{
        parent=divs[1].parent,
        x=2, y=16, min_width=8,
        text="Apply",
        callback=function()
            -- copy tmp_cfg into settings_cfg
            for _, f in ipairs(fields) do
                if tmp_cfg[f[1]] ~= nil then settings_cfg[f[1]] = tmp_cfg[f[1]] end
            end

            settings.save("/smartglasses.settings")

            tool_ctl.has_config = true
            tool_ctl.view_cfg.enable()
            tool_ctl.settings_apply.hide(true)
            main_pane.set_value(1)
        end,
        fg_bg=cpair(colors.black, colors.green),
        active_fg_bg=btn_act_fg_bg
    }

    tool_ctl.settings_apply = PushButton{
        parent=divs[1].parent,
        x=12, y=16, min_width=8,
        text="Apply",
        callback=function() end,
        fg_bg=cpair(colors.black, colors.green),
        active_fg_bg=btn_act_fg_bg
    }
    tool_ctl.settings_apply.hide(true)

    --#endregion
end

return system