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

local self = {
    importing_legacy = false,

    show_auth_key = nil,
    show_key_btn = nil,
    auth_key_textbox = nil,
    auth_key_value = ""
}

local system = {}

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

    local _, term_h = term.getSize()
    local page_h = math.max(4, term_h - 3)
    local term_w = ({term.getSize()})[1]

    local function make_list(parent)
        return ListBox{
            parent = parent,
            y = 1, x = 1,
            height = page_h,
            width = term_w,
            scroll_height = 64,
            fg_bg = style.root,
            nav_fg_bg = g_lg_fg_bg,
            nav_active = cpair(colors.black, colors.gray),
        }
    end

    local function add_text(list, text, fg_bg)
        TextBox{ parent=list, text=text, fg_bg=fg_bg or style.root }
    end

    local function add_blank(list)
        TextBox{ parent=list, text="", fg_bg=style.root }
    end

    local function add_button(list, text, opts)
        opts.parent = list
        opts.text = text
        return PushButton(opts)
    end

    --#region HUD UI

    local ui_c_1 = make_list(Div{parent=ui_cfg,x=2,y=2,width=term_w - 4})
    local ui_c_2 = make_list(Div{parent=ui_cfg,x=2,y=2,width=term_w - 4})

    local ui_pane = MultiPane{parent=ui_cfg,y=2,panes={ui_c_1,ui_c_2}}

    TextBox{parent=ui_cfg,y=1,text=" HUD Display",fg_bg=cpair(colors.black,colors.lime)}

    add_text(ui_c_1, "Choose which reactor unit to display.", style.root)
    add_blank(ui_c_1)
    add_text(ui_c_1, "Reactor Unit ID", style.root)
    local unit_id = NumberField{parent=ui_c_1,y=5,width=7,default=ini_cfg.UnitID,min=1,max=64,fg_bg=bw_fg_bg}
    add_blank(ui_c_1)
    add_text(ui_c_1, "HUD Scale (0.5 - 2.0)", style.root)
    local hud_scale = NumberField{parent=ui_c_1,y=8,width=7,default=ini_cfg.HUDScale,min=0.5,max=2.0,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}
    add_blank(ui_c_1)

    local uis_err = TextBox{ parent=ui_c_1, text="", fg_bg=cpair(colors.red,colors.lightGray), hidden=true }

    local function submit_hud_opts()
        local u = tonumber(unit_id.get_value())
        local s = tonumber(hud_scale.get_value())
        if u ~= nil and s ~= nil then
            tmp_cfg.UnitID = u
            tmp_cfg.HUDScale = s
            ui_pane.set_value(2)
            uis_err.hide(true)
        else
            uis_err.set_value("Please set unit ID and scale.")
            uis_err.show()
        end
    end

    add_button(ui_c_1, "\x1b Back", { callback=function() main_pane.set_value(1) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(ui_c_1, "Next \x1a", { callback=submit_hud_opts, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    add_text(ui_c_2, "Optionally bind hotkeys for SCRAM/START.", style.root)
    add_text(ui_c_2, "Both target only the Unit ID above.", style.root)
    add_blank(ui_c_2)
    add_text(ui_c_2, "SCRAM Hotkey (empty = off)", style.root)
    local scram_key = TextField{parent=ui_c_2,y=6,width=24,height=1,value=ini_cfg.HotkeyScram or "",max_len=64,fg_bg=bw_fg_bg}
    add_blank(ui_c_2)
    add_text(ui_c_2, "START Hotkey (empty = off)", style.root)
    local start_key = TextField{parent=ui_c_2,y=9,width=24,height=1,value=ini_cfg.HotkeyStart or "",max_len=64,fg_bg=bw_fg_bg}
    add_blank(ui_c_2)

    local function submit_hud_hotkeys()
        tmp_cfg.HotkeyScram = scram_key.get_value()
        tmp_cfg.HotkeyStart = start_key.get_value()
        main_pane.set_value(3)
    end

    add_button(ui_c_2, "\x1b Back", { callback=function() ui_pane.set_value(1) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(ui_c_2, "Next \x1a", { callback=submit_hud_hotkeys, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    --#endregion

    --#region Network

    local net_c_1 = make_list(Div{parent=net_cfg,x=2,y=2,width=term_w - 4})
    local net_c_2 = make_list(Div{parent=net_cfg,x=2,y=2,width=term_w - 4})
    local net_c_3 = make_list(Div{parent=net_cfg,x=2,y=2,width=term_w - 4})
    local net_c_4 = make_list(Div{parent=net_cfg,x=2,y=2,width=term_w - 4})

    local net_pane = MultiPane{parent=net_cfg,y=2,panes={net_c_1,net_c_2,net_c_3,net_c_4}}

    TextBox{parent=net_cfg,y=1,text=" Network Configuration",fg_bg=cpair(colors.black,colors.lightBlue)}

    add_text(net_c_1, "Set network channels.", style.root)
    add_blank(net_c_1)
    add_text(net_c_1, "CRD must match your facility.", g_lg_fg_bg)
    add_text(net_c_1, "PKT must not collide.", g_lg_fg_bg)
    add_blank(net_c_1)
    add_text(net_c_1, "Coordinator Channel", style.root)
    local crd_chan = NumberField{parent=net_c_1,y=7,width=7,default=ini_cfg.CRD_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    add_blank(net_c_1)
    add_text(net_c_1, "HUD Packet Channel", style.root)
    local pkt_chan = NumberField{parent=net_c_1,y=10,width=7,default=ini_cfg.PKT_Channel,min=1,max=65535,fg_bg=bw_fg_bg}
    add_blank(net_c_1)

    local chan_err = TextBox{ parent=net_c_1, text="", fg_bg=cpair(colors.red,colors.lightGray), hidden=true }

    local function submit_channels()
        local crd_c, pkt_c = tonumber(crd_chan.get_value()), tonumber(pkt_chan.get_value())
        if crd_c ~= nil and pkt_c ~= nil then
            tmp_cfg.CRD_Channel, tmp_cfg.PKT_Channel = crd_c, pkt_c
            net_pane.set_value(2)
            chan_err.hide(true)
        else
            chan_err.set_value("Please set all channels.")
            chan_err.show()
        end
    end

    add_button(net_c_1, "\x1b Back", { callback=function() main_pane.set_value(2) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(net_c_1, "Next \x1a", { callback=submit_channels, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    add_text(net_c_2, "Set connection timeout.", style.root)
    add_blank(net_c_2)
    add_text(net_c_2, "Increase on slow servers so the HUD", g_lg_fg_bg)
    add_text(net_c_2, "waits longer before unlinking.", g_lg_fg_bg)
    add_blank(net_c_2)
    add_text(net_c_2, "Connection Timeout (seconds)", style.root)
    local timeout = NumberField{parent=net_c_2,y=8,width=7,default=ini_cfg.ConnTimeout,min=2,max=25,max_chars=6,max_frac_digits=2,allow_decimal=true,fg_bg=bw_fg_bg}
    add_blank(net_c_2)

    local ct_err = TextBox{ parent=net_c_2, text="", fg_bg=cpair(colors.red,colors.lightGray), hidden=true }

    local function submit_timeouts()
        local timeout_val = tonumber(timeout.get_value())
        if timeout_val ~= nil then
            tmp_cfg.ConnTimeout = timeout_val
            net_pane.set_value(3)
            ct_err.hide(true)
        else
            ct_err.set_value("Please set timeout.")
            ct_err.show()
        end
    end

    add_button(net_c_2, "\x1b Back", { callback=function() net_pane.set_value(1) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(net_c_2, "Next \x1a", { callback=submit_timeouts, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    add_text(net_c_3, "Set the trusted range.", style.root)
    add_blank(net_c_3)
    add_text(net_c_3, "Range > 0 prevents connections", g_lg_fg_bg)
    add_text(net_c_3, "with devices that many blocks away.", g_lg_fg_bg)
    add_blank(net_c_3)
    add_text(net_c_3, "Trusted Range (0 = no limit)", style.root)
    local range = NumberField{parent=net_c_3,y=8,width=10,default=ini_cfg.TrustedRange,min=0,max_chars=20,allow_decimal=true,fg_bg=bw_fg_bg}
    add_blank(net_c_3)

    local tr_err = TextBox{ parent=net_c_3, text="", fg_bg=cpair(colors.red,colors.lightGray), hidden=true }

    local function submit_tr()
        local range_val = tonumber(range.get_value())
        if range_val ~= nil then
            tmp_cfg.TrustedRange = range_val
            net_pane.set_value(4)
            tr_err.hide(true)
        else
            tr_err.set_value("Set the trusted range.")
            tr_err.show()
        end
    end

    add_button(net_c_3, "\x1b Back", { callback=function() net_pane.set_value(2) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(net_c_3, "Next \x1a", { callback=submit_tr, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    add_text(net_c_4, "Optionally, set the facility authentication", style.root)
    add_text(net_c_4, "key. Do NOT use one of your passwords.", style.root)
    add_blank(net_c_4)
    add_text(net_c_4, "Must match the supervisor/coordinator AuthKey.", g_lg_fg_bg)
    add_blank(net_c_4)
    add_text(net_c_4, "Facility Auth Key", style.root)
    local key = TextField{parent=net_c_4,y=9,max_len=64,value=ini_cfg.AuthKey,width=24,height=1,fg_bg=bw_fg_bg}

    local function censor_key(enable) key.censor(tri(enable, "*", nil)) end

    local hide_key = Checkbox{parent=net_c_4,x=14,y=9,label="Hide",box_fg_bg=cpair(colors.lightBlue,colors.black),callback=censor_key}
    hide_key.set_value(true)
    censor_key(true)

    add_blank(net_c_4)

    local key_err = TextBox{ parent=net_c_4, text="", fg_bg=cpair(colors.red,colors.lightGray), hidden=true }

    local function submit_auth()
        local v = key.get_value()
        if string.len(v) == 0 or string.len(v) >= 8 then
            tmp_cfg.AuthKey = key.get_value()
            main_pane.set_value(4)
            key_err.hide(true)
        else
            key_err.set_value("Length must be > 7.")
            key_err.show()
        end
    end

    add_button(net_c_4, "\x1b Back", { callback=function() net_pane.set_value(3) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(net_c_4, "Next \x1a", { callback=submit_auth, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    --#endregion

    --#region HUD behavior (placeholder)

    local hud_c_1 = make_list(Div{parent=hud_cfg,x=2,y=2,width=term_w - 4})

    TextBox{parent=hud_cfg,y=1,text=" HUD Behavior",fg_bg=cpair(colors.black,colors.orange)}

    add_text(hud_c_1, "Reserved for future HUD behavior options.", style.root)
    add_text(hud_c_1, "Nothing to configure here yet.", style.root)
    add_blank(hud_c_1)

    add_button(hud_c_1, "\x1b Back", { callback=function() main_pane.set_value(3) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(hud_c_1, "Next \x1a", { callback=function() main_pane.set_value(5) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    --#endregion

    --#region Logging

    local log_c_1 = make_list(Div{parent=log_cfg,x=2,y=2,width=term_w - 4})

    TextBox{parent=log_cfg,y=1,text=" Logging Configuration",fg_bg=cpair(colors.black,colors.pink)}

    add_text(log_c_1, "Configure logging below.", style.root)
    add_blank(log_c_1)
    add_text(log_c_1, "Log File Mode", style.root)
    local mode = RadioButton{parent=log_c_1,y=5,default=ini_cfg.LogMode+1,options={"Append on Startup","Replace on Startup"},radio_colors=cpair(colors.lightGray,colors.black),select_color=colors.pink}
    add_blank(log_c_1)
    add_text(log_c_1, "Log File Path", style.root)
    local path = TextField{parent=log_c_1,y=8,width=24,height=1,value=ini_cfg.LogPath,max_len=128,fg_bg=bw_fg_bg}
    add_blank(log_c_1)
    local en_dbg = Checkbox{parent=log_c_1,y=11,default=ini_cfg.LogDebug,label="Enable Debug Messages",box_fg_bg=cpair(colors.pink,colors.black)}
    add_blank(log_c_1)

    local path_err = TextBox{ parent=log_c_1, text="", fg_bg=cpair(colors.red,colors.lightGray), hidden=true }

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
        else
            path_err.set_value("Provide a log file path.")
            path_err.show()
        end
    end

    add_button(log_c_1, "\x1b Back", { callback=function() main_pane.set_value(4) end, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(log_c_1, "Next \x1a", { callback=submit_log, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    --#endregion

    --#region Summary

    local sum_c_1 = make_list(Div{parent=summary,x=2,y=2,width=term_w - 4})
    local sum_c_2 = make_list(Div{parent=summary,x=2,y=2,width=term_w - 4})
    local sum_c_3 = make_list(Div{parent=summary,x=2,y=2,width=term_w - 4})
    local sum_c_4 = make_list(Div{parent=summary,x=2,y=2,width=term_w - 4})

    local sum_pane = MultiPane{parent=summary,y=2,panes={sum_c_1,sum_c_2,sum_c_3,sum_c_4}}

    TextBox{parent=summary,y=1,text=" Summary",fg_bg=cpair(colors.black,colors.green)}

    local setting_list = ListBox{
        parent = sum_c_1,
        y = 1,
        height = math.max(4, page_h - 5),
        width = 24,
        scroll_height = 100,
        fg_bg = bw_fg_bg,
        nav_fg_bg = g_lg_fg_bg,
        nav_active = cpair(colors.black, colors.gray),
    }

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

            if tool_ctl.view_cfg then tool_ctl.view_cfg.enable() end

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

    self.show_key_btn = add_button(sum_c_1, "Unhide Auth Key", {
        min_width=17,
        callback=function() self.show_auth_key() end,
        fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg, dis_fg_bg=btn_dis_fg_bg
    })

    add_button(sum_c_1, "\x1b Back", {
        callback=back_from_summary,
        fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg
    })

    tool_ctl.settings_apply = add_button(sum_c_1, "Apply", {
        min_width=7,
        callback=save_and_continue,
        fg_bg=cpair(colors.black,colors.green),
        active_fg_bg=btn_act_fg_bg
    })

    add_text(sum_c_2, "Settings saved!", style.root)
    add_blank(sum_c_2)

    local function go_home()
        main_pane.set_value(1)
        net_pane.set_value(1)
        sum_pane.set_value(1)
    end

    add_button(sum_c_2, "Home", { min_width=6, callback=go_home, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })

    if tool_ctl.ask_config then
        add_button(sum_c_2, "Resume", { min_width=8, callback=exit, fg_bg=cpair(colors.black,colors.lightBlue), active_fg_bg=btn_act_fg_bg })
    else
        add_button(sum_c_2, "Startup", { min_width=9, callback=startup, fg_bg=cpair(colors.black,colors.green), active_fg_bg=btn_act_fg_bg })
    end

    add_text(sum_c_3, "The legacy config file will now be deleted,", style.root)
    add_text(sum_c_3, "then the configurator will exit.", style.root)
    add_blank(sum_c_3)

    local function delete_legacy()
        fs.delete("/smartglasses.legacy")
        exit()
    end

    add_button(sum_c_3, "Cancel", { min_width=8, callback=go_home, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(sum_c_3, "OK", { min_width=6, callback=delete_legacy, fg_bg=cpair(colors.black,colors.green), active_fg_bg=cpair(colors.white,colors.gray) })

    add_text(sum_c_4, "Failed to save the settings file.", style.root)
    add_blank(sum_c_4)
    add_text(sum_c_4, "There may not be enough space,", style.root)
    add_text(sum_c_4, "or file permissions are denying writes.", style.root)
    add_blank(sum_c_4)

    add_button(sum_c_4, "Home", { min_width=6, callback=go_home, fg_bg=nav_fg_bg, active_fg_bg=btn_act_fg_bg })
    add_button(sum_c_4, "Exit", { min_width=6, callback=exit, fg_bg=cpair(colors.black,colors.red), active_fg_bg=cpair(colors.white,colors.gray) })

    --#endregion

    --#region Tool Functions

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

    function self.show_auth_key()
        self.show_key_btn.disable()
        self.auth_key_textbox.set_value(self.auth_key_value)
    end

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
                textbox = TextBox{parent=line,x=label_w+1,y=1,text=val,alignment=core.ALIGN.RIGHT}
            end

            if f[1] == "AuthKey" then self.auth_key_textbox = textbox end
        end
    end

    --#endregion
end

return system