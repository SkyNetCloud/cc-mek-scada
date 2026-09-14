--
-- Configuration GUI System Builder
--

local log         = require("scada-common.log")
local util        = require("scada-common.util")

local core        = require("graphics.core")

local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local Checkbox    = require("graphics.elements.controls.Checkbox")
local PushButton  = require("graphics.elements.controls.PushButton")
local RadioButton = require("graphics.elements.controls.RadioButton")

local NumberField = require("graphics.elements.form.NumberField")
local TextField   = require("graphics.elements.form.TextField")

local tri = util.trinary

local cpair = core.cpair

local RIGHT = core.ALIGN.RIGHT

local self = {
    importing_legacy = false,

    show_auth_key = nil,    ---@type function
    show_key_btn = nil,     ---@type PushButton
    auth_key_textbox = nil, ---@type TextBox
    auth_key_value = ""
}

local system = {}

-- create the system configuration view
---@param tool_ctl _gld_cfg_tool_ctl
---@param main_pane MultiPane
---@param cfg_sys [ glasses_config, glasses_config, glasses_config, { [1]: string, [2]: string, [3]: any }[], function ]
---@param divs Div[]
---@param style { [string]: cpair }
---@param startup function
---@param exit function
function system.create(tool_ctl, main_pane, cfg_sys, divs, style, startup, exit)
    local settings_cfg, ini_cfg, tmp_cfg, fields, load_settings = cfg_sys[1], cfg_sys[2], cfg_sys[3], cfg_sys[4], cfg_sys[5]
    local ui_cfg, net_cfg, hud_cfg, log_cfg, summary = divs[1], divs[2], divs[3], divs[4], divs[5]

    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    --#region HUD UI (unit ID, scale, hotkeys)

    local ui_c_1 = Div{parent=ui_cfg,x=2,y=4,width=24}
    local ui_c_2 = Div{parent=ui_cfg,x=2,y=4,width=24}

    local ui_pane = MultiPane{parent=ui_cfg,y=4,panes={ui_c_1,ui_c_2}}

    TextBox{parent=ui_cfg,y=2,text=" HUD Display",fg_bg=cpair(colors.black,colors.lime)}

    TextBox{parent=ui_c_1,y=1,height=3,text="Choose which reactor unit to display."}

    TextBox{parent=ui_c_1,y=4,text="Reactor Unit ID"}
    local unit_id = NumberField{parent=ui_c_1,y=5,width=7,default=ini_cfg.UnitID,min=1,max=64,fg_bg=bw_fg_bg}

    TextBox{parent=ui_c_1,y=8,text="HUD Scale"}
    local hud_scale = NumberField{parent=ui_c_1,y=9,width=7,default=ini_cfg.HUDScale,min=0.5,max=2.0,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=ui_c_1,x=9,y=9,height=2,text="(0.5 - 2.0)\n(default 1.0)",fg_bg=g_lg_fg_bg}

    local uis_err = TextBox{parent=ui_c_1,y=14,width=24,text="Please set unit ID and scale.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_hud_opts()
        local u = tonumber(unit_id.get_value())
        local s = tonumber(hud_scale.get_value())
        if u ~= nil and s ~= nil then
            tmp_cfg.UnitID = u
            tmp_cfg.HUDScale = s
            ui_pane.set_value(2)
            uis_err.hide(true)
        else uis_err.show() end
    end

    PushButton{parent=ui_c_1,y=15,text="\x1b Back",callback=function()main_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=ui_c_1,x=19,y=15,text="Next \x1a",callback=submit_hud_opts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=ui_c_2,y=1,height=3,text="Optionally bind hotkeys for emergency SCRAM/START. Both target only the Unit ID above."}

    TextBox{parent=ui_c_2,y=5,text="SCRAM Hotkey"}
    local scram_key = TextField{parent=ui_c_2,y=6,width=24,height=1,value=ini_cfg.HotkeyScram or "",max_len=64,fg_bg=bw_fg_bg}
    TextBox{parent=ui_c_2,x=3,y=7,height=2,text="e.g. key.hotkeyperipheral.1\n(empty = disabled)",fg_bg=g_lg_fg_bg}

    TextBox{parent=ui_c_2,y=10,text="START Hotkey"}
    local start_key = TextField{parent=ui_c_2,y=11,width=24,height=1,value=ini_cfg.HotkeyStart or "",max_len=64,fg_bg=bw_fg_bg}
    TextBox{parent=ui_c_2,x=3,y=12,height=2,text="(empty = disabled)",fg_bg=g_lg_fg_bg}

    local function submit_hud_hotkeys()
        tmp_cfg.HotkeyScram = scram_key.get_value()
        tmp_cfg.HotkeyStart = start_key.get_value()
        main_pane.set_value(3)
    end

    PushButton{parent=ui_c_2,y=15,text="\x1b Back",callback=function()ui_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=ui_c_2,x=19,y=15,text="Next \x1a",callback=submit_hud_hotkeys,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Network

    local net_c_1 = Div{parent=net_cfg,x=2,y=4,width=24}
    local net_c_2 = Div{parent=net_cfg,x=2,y=4,width=24}
    local net_c_3 = Div{parent=net_cfg,x=2,y=4,width=24}
    local net_c_4 = Div{parent=net_cfg,x=2,y=4,width=24}

    local net_pane = MultiPane{parent=net_cfg,y=4,panes={net_c_1,net_c_2,net_c_3,net_c_4}}

    TextBox{parent=net_cfg,y=2,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    TextBox{parent=net_c_1,y=1,text="Set network channels."}
    TextBox{parent=net_c_1,y=3,height=4,text="The coordinator channel must match your facility. The HUD channel must not collide with another device.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,y=8,width=18,text="Coordinator Channel"}
    local crd_chan = NumberField{parent=net_c_1,y=9,width=7,default=ini_cfg.CRD_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=9,height=4,text="[CRD_CHANNEL]",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_1,y=10,width=18,text="HUD Packet Channel"}
    local pkt_chan = NumberField{parent=net_c_1,y=11,width=7,default=ini_cfg.PKT_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    TextBox{parent=net_c_1,x=9,y=11,height=4,text="[PKT_CHANNEL]",fg_bg=g_lg_fg_bg}

    local chan_err = TextBox{parent=net_c_1,y=14,width=24,text="Please set all channels.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_channels()
        local crd_c, pkt_c = tonumber(crd_chan.get_value()), tonumber(pkt_chan.get_value())
        if crd_c ~= nil and pkt_c ~= nil then
            tmp_cfg.CRD_Channel, tmp_cfg.PKT_Channel = crd_c, pkt_c
            net_pane.set_value(2)
            chan_err.hide(true)
        else chan_err.show() end
    end

    PushButton{parent=net_c_1,y=15,text="\x1b Back",callback=function()main_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_1,x=19,y=15,text="Next \x1a",callback=submit_channels,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_2,y=1,text="Set connection timeout."}
    TextBox{parent=net_c_2,y=3,height=7,text="You generally should not need to modify this. On slow servers, you can try to increase this to make the HUD wait longer before assuming a disconnection.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_2,y=11,width=19,text="Connection Timeout"}
    local timeout = NumberField{parent=net_c_2,y=12,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}

    TextBox{parent=net_c_2,x=9,y=12,height=2,text="seconds\n(default 5)",fg_bg=g_lg_fg_bg}

    local ct_err = TextBox{parent=net_c_2,y=14,width=24,text="Please set timeout.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_timeouts()
        local timeout_val = tonumber(timeout.get_value())
        if timeout_val ~= nil then
            tmp_cfg.ConnTimeout = timeout_val
            net_pane.set_value(3)
            ct_err.hide(true)
        else ct_err.show() end
    end

    PushButton{parent=net_c_2,y=15,text="\x1b Back",callback=function()net_pane.set_value(1)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_2,x=19,y=15,text="Next \x1a",callback=submit_timeouts,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_3,y=1,text="Set the trusted range."}
    TextBox{parent=net_c_3,y=3,height=4,text="Setting this to a value larger than 0 prevents connections with devices that many blocks away.",fg_bg=g_lg_fg_bg}
    TextBox{parent=net_c_3,y=8,height=4,text="This is optional. You can disable this functionality by setting the value to 0.",fg_bg=g_lg_fg_bg}

    local range = NumberField{parent=net_c_3,y=13,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg}

    local tr_err = TextBox{parent=net_c_3,y=14,width=24,text="Set the trusted range.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_tr()
        local range_val = tonumber(range.get_value())
        if range_val ~= nil then
            tmp_cfg.TrustedRange = range_val
            net_pane.set_value(4)
            tr_err.hide(true)
        else tr_err.show() end
    end

    PushButton{parent=net_c_3,y=15,text="\x1b Back",callback=function()net_pane.set_value(2)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=net_c_3,x=19,y=15,text="Next \x1a",callback=submit_tr,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    TextBox{parent=net_c_4,y=1,height=4,text="Optionally, set the facility authentication key. Do NOT use one of your passwords."}
    TextBox{parent=net_c_4,y=6,height=6,text="This must match the supervisor and coordinator AuthKey. It is intended for security on multiplayer servers.",fg_bg=g_lg_fg_bg}

    TextBox{parent=net_c_4,y=12,text="Facility Auth Key"}
    local key, _ = TextField{parent=net_c_4,y=13,max_len=64,value=ini_cfg.AuthKey,width=24,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) key.censor(tri(enable, "*", nil)) end

    PushButton{parent=net_c_4,y=15,text="\x1b Back",callback=function()net_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    local hide_key = Checkbox{parent=net_c_4,x=8,y=15,label="Hide Key",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}

    hide_key.set_value(true)
    censor_key(true)

    local key_err = TextBox{parent=net_c_4,y=14,width=24,text="Length must be > 7.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(4)
            key_err.hide(true)
        else key_err.show() end
    end

    PushButton{parent=net_c_4,x=19,y=15,text="Next \x1a",callback=submit_auth,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region HUD behavior page (placeholder)

    local hud_c_1 = Div{parent=hud_cfg,x=2,y=4,width=24}

    TextBox{parent=hud_cfg,y=2,text=" HUD Behavior",fg_bg=cpair(colors.black,colors.orange)}

    TextBox{parent=hud_c_1,y=1,height=3,text="Reserved for future HUD behavior options. Nothing to configure here yet."}

    PushButton{parent=hud_c_1,y=15,text="\x1b Back",callback=function()main_pane.set_value(3)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=hud_c_1,x=19,y=15,text="Next \x1a",callback=function()main_pane.set_value(5)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Logging

    local log_c_1 = Div{parent=log_cfg,x=2,y=4,width=24}

    TextBox{parent=log_cfg,y=2,text=" Logging Configuration",fg_bg=cpair(colors.black,colors.pink)}

    TextBox{parent=log_c_1,y=1,text="Configure logging below."}

    TextBox{parent=log_c_1,y=3,text="Log File Mode"}
    local mode = RadioButton{parent=log_c_1,y=4,default=ini_cfg.LogMode+1,options={"Append on Startup","Replace on Startup"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}

    TextBox{parent=log_c_1,y=7,text="Log File Path"}
    local path = TextField{parent=log_c_1,y=8,width=24,height=1,value=ini_cfg.LogPath,max_len=128,fg_bg=bw_fg_bg}

    local en_dbg = Checkbox{parent=log_c_1,y=10,default=ini_cfg.LogDebug,label="Enable Debug Messages",box_fg_bg=cpair(colors.pink,colors.black)}
    TextBox{parent=log_c_1,x=3,y=11,height=4,text="This results in much larger log files. Use only as needed.",fg_bg=g_lg_fg_bg}

    local path_err = TextBox{parent=log_c_1,y=14,width=24,text="Provide a log file path.",fg_bg=cpair(colors.red,colors.lightGray),hidden=true}

    local function submit_log()
        if path.get_value() ~= "" then
            path_err.hide(true)
            tmp_cfg.LogMode = mode.get_value() - 1
            tmp_cfg.LogPath = path.get_value()
            tmp_cfg.LogDebug = en_dbg.get_value()
            tool_ctl.gen_summary(tmp_cfg)
            tool_ctl.viewing_config = false
            self.importing_legacy = false
            tool_ctl.settings_apply.show()
            main_pane.set_value(6)
        else path_err.show() end
    end

    PushButton{parent=log_c_1,y=15,text="\x1b Back",callback=function()main_pane.set_value(4)end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=log_c_1,x=19,y=15,text="Next \x1a",callback=submit_log,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    --#endregion

    --#region Summary and Saving

    local sum_c_1 = Div{parent=summary,x=2,y=4,width=24}
    local sum_c_2 = Div{parent=summary,x=2,y=4,width=24}
    local sum_c_3 = Div{parent=summary,x=2,y=4,width=24}
    local sum_c_4 = Div{parent=summary,x=2,y=4,width=24}

    local sum_pane = MultiPane{parent=summary,y=4,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4}}

    TextBox{parent=summary,y=2,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{parent=sum_c_1,y=1,height=11,width=24,scroll_height=100,fg_bg=bw_fg_bg,nav_fg_bg=g_lg_fg_bg,nav_active=cpair(colors.black,colors.gray)}

    local function back_from_summary()
        if tool_ctl.viewing_config or self.importing_legacy then
            main_pane.set_value(1)
            tool_ctl.viewing_config = false
            self.importing_legacy = false
            tool_ctl.settings_apply.show()
        else
            main_pane.set_value(5)
        end
    end

    ---@param element graphics_element
    ---@param data any
    local function try_set(element, data)
        if data ~= nil then element.set_value(data) end
    end

    local function save_and_continue()
        for _, field in ipairs(fields) do
            local k, v = field[1], tmp_cfg[field[1]]
            if v == nil then settings.unset(k) else settings.set(k, v) end
        end

        if settings.save("/smartglasses.settings") then
            load_settings(settings_cfg, true)
            load_settings(ini_cfg)

            try_set(unit_id, ini_cfg.UnitID)
            try_set(hud_scale, ini_cfg.HUDScale)
            try_set(scram_key, ini_cfg.HotkeyScram)
            try_set(start_key, ini_cfg.HotkeyStart)
            try_set(crd_chan, ini_cfg.CRD_Channel)
            try_set(pkt_chan, ini_cfg.PKT_Channel)
            try_set(timeout, ini_cfg.ConnTimeout)
            try_set(range, ini_cfg.TrustedRange)
            try_set(key, ini_cfg.AuthKey)
            try_set(mode, ini_cfg.LogMode)
            try_set(path, ini_cfg.LogPath)
            try_set(en_dbg, ini_cfg.LogDebug)

            tool_ctl.view_cfg.enable()

            if self.importing_legacy then
                self.importing_legacy = false
                sum_pane.set_value(3)
            else
                sum_pane.set_value(2)
            end
        else
            sum_pane.set_value(4)
        end
    end

    PushButton{parent=sum_c_1,y=15,text="\x1b Back",callback=back_from_summary,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    self.show_key_btn = PushButton{parent=sum_c_1,y=13,min_width=17,text="Unhide Auth Key",callback=function()self.show_auth_key()end,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg,dis_fg_bg=btn_dis_fg_bg}
    tool_ctl.settings_apply = PushButton{parent=sum_c_1,x=18,y=15,min_width=7,text="Apply",callback=save_and_continue,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}

    TextBox{parent=sum_c_2,y=1,text="Settings saved!"}

    local function go_home()
        main_pane.set_value(1)
        net_pane.set_value(1)
        sum_pane.set_value(1)
    end

    PushButton{parent=sum_c_2,y=15,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}

    if tool_ctl.ask_config then
        PushButton{parent=sum_c_2,x=17,y=15,min_width=8,text="Resume",callback=exit,fg_bg=cpair(colors.black,colors.lightBlue),active_fg_bg=btn_act_fg_bg}
    else
        PushButton{parent=sum_c_2,x=16,y=15,min_width=9,text="Startup",callback=startup,fg_bg=cpair(colors.black,colors.green),active_fg_bg=btn_act_fg_bg}
    end

    TextBox{parent=sum_c_3,y=1,height=4,text="The legacy config file will now be deleted, then the configurator will exit."}

    local function delete_legacy()
        fs.delete("/smartglasses.legacy")
        exit()
    end

    PushButton{parent=sum_c_3,y=15,min_width=8,text="Cancel",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_3,x=19,y=15,min_width=6,text="OK",callback=delete_legacy,fg_bg=cpair(colors.black,colors.green),active_fg_bg=cpair(colors.white,colors.gray)}

    TextBox{parent=sum_c_4,y=1,height=8,text="Failed to save the settings file.\n\nThere may not be enough space for the modification or server file permissions may be denying writes."}
    PushButton{parent=sum_c_4,y=15,min_width=6,text="Home",callback=go_home,fg_bg=nav_fg_bg,active_fg_bg=btn_act_fg_bg}
    PushButton{parent=sum_c_4,x=19,y=15,min_width=6,text="Exit",callback=exit,fg_bg=cpair(colors.black,colors.red),active_fg_bg=cpair(colors.white,colors.gray)}

    --#endregion

    --#region Tool Functions

    -- load a legacy config file
    function tool_ctl.load_legacy()
        if not fs.exists("/smartglasses.legacy") then return end

        local legacy = require("smartglasses.legacy")

        tmp_cfg.CRD_Channel  = legacy.CRD_CHANNEL
        tmp_cfg.PKT_Channel  = legacy.PKT_CHANNEL
        tmp_cfg.ConnTimeout  = legacy.COMMS_TIMEOUT
        tmp_cfg.TrustedRange = legacy.TRUSTED_RANGE
        tmp_cfg.AuthKey      = legacy.AUTH_KEY or ""
        tmp_cfg.UnitID       = legacy.UNIT_ID or 1
        tmp_cfg.HUDScale     = legacy.HUD_SCALE or 1.0
        tmp_cfg.HotkeyScram  = legacy.HOTKEY_SCRAM or ""
        tmp_cfg.HotkeyStart  = legacy.HOTKEY_START or ""

        tmp_cfg.LogMode      = legacy.LOG_MODE or log.MODE.APPEND
        tmp_cfg.LogPath      = legacy.LOG_PATH or "/smartglasses.log"
        tmp_cfg.LogDebug     = legacy.LOG_DEBUG or false

        tool_ctl.gen_summary(tmp_cfg)
        sum_pane.set_value(1)
        main_pane.set_value(6)
        self.importing_legacy = true
    end

    -- expose the auth key on the summary page
    function self.show_auth_key()
        self.show_key_btn.disable()
        self.auth_key_textbox.set_value(self.auth_key_value)
    end

    -- generate the summary list
    ---@param cfg glasses_config
    function tool_ctl.gen_summary(cfg)
        setting_list.remove_all()

        local alternate = false
        local inner_width = setting_list.get_width() - 1

        self.show_key_btn.enable()
        self.auth_key_value = cfg.AuthKey or ""

        for i = 1, #fields do
            local f = fields[i]
            local height = 1
            local label_w = string.len(f[2])
            local val_max_w = (inner_width - label_w) - 1
            local raw = cfg[f[1]]
            local val = util.strval(raw)

            if f[1] == "AuthKey" then
                val = string.rep("*", string.len(val))
            elseif f[1] == "LogMode" then
                val = tri(raw == log.MODE.APPEND, "append", "replace")
            end

            if val == "nil" then val = "<not set>" end

            local c = tri(alternate, g_lg_fg_bg, cpair(colors.gray,colors.white))
            alternate = not alternate

            if (string.len(val) > val_max_w) or string.find(val, "\n") then
                local lines = util.strwrap(val, inner_width)
                height = #lines + 1
            end

            local line = Div{parent=setting_list,height=height,fg_bg=c}
            TextBox{parent=line,text=f[2],width=string.len(f[2]),fg_bg=cpair(colors.black,line.get_fg_bg().bkg)}

            local textbox
            if height > 1 then
                textbox = TextBox{parent=line,y=2,text=val,height=height-1}
            else
                textbox = TextBox{parent=line,x=label_w+1,y=1,text=val,alignment=RIGHT}
            end

            if f[1] == "AuthKey" then self.auth_key_textbox = textbox end
        end
    end

    --#endregion
end

return system