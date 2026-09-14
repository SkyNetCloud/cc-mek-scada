--
-- Configuration GUI for Smart Glasses HUD
--

local log         = require("scada-common.log")
local util        = require("scada-common.util")

local system      = require("smartglasses.config.system")

local core        = require("graphics.core")
local themes      = require("graphics.themes")

local DisplayBox  = require("graphics.elements.DisplayBox")
local Div         = require("graphics.elements.Div")
local ListBox     = require("graphics.elements.ListBox")
local MultiPane   = require("graphics.elements.MultiPane")
local TextBox     = require("graphics.elements.TextBox")

local PushButton  = require("graphics.elements.controls.PushButton")

local println = util.println
local tri = util.trinary

local cpair = core.cpair

local CENTER = core.ALIGN.CENTER

local changes = {
    { "v1.0.0", { "Initial Smart Glasses HUD config" } }
}

---@class gld_configurator
local configurator = {}

local style = {}

style.root          = cpair(colors.black, colors.lightGray)
style.header        = cpair(colors.white, colors.gray)

style.colors        = themes.smooth_stone.colors

style.bw_fg_bg      = cpair(colors.black, colors.white)
style.g_lg_fg_bg    = cpair(colors.gray, colors.lightGray)
style.nav_fg_bg     = style.bw_fg_bg
style.btn_act_fg_bg = cpair(colors.white, colors.gray)
style.btn_dis_fg_bg = cpair(colors.lightGray, colors.white)

---@class _gld_cfg_tool_ctl
local tool_ctl = {
    launch_startup = false,
    ask_config = false,
    has_config = false,
    viewing_config = false,

    view_cfg = nil,
    settings_apply = nil,

    gen_summary = nil,
    load_legacy = nil,
}

---@class glasses_config
local tmp_cfg = {
    UnitID = 1,
    CRD_Channel = nil,
    PKT_Channel = nil,
    ConnTimeout = 5,
    TrustedRange = 0,
    AuthKey = nil,
    HotkeyScram = "",
    HotkeyStart = "",
    HUDScale = 1.0,
    LogMode = 0,
    LogPath = "",
    LogDebug = false,
}

---@class glasses_config
local ini_cfg = {}
---@class glasses_config
local settings_cfg = {}

local fields = {
    { "UnitID",       "Reactor Unit ID",    1 },
    { "CRD_Channel",  "CRD Channel",        16243 },
    { "PKT_Channel",  "PKT Channel",        16245 },
    { "ConnTimeout",  "Connection Timeout", 5 },
    { "TrustedRange", "Trusted Range",      0 },
    { "AuthKey",      "Facility Auth Key",  "" },
    { "HotkeyScram",  "SCRAM Hotkey",       "" },
    { "HotkeyStart",  "START Hotkey",       "" },
    { "HUDScale",     "HUD Scale",          1.0 },
    { "LogMode",      "Log Mode",           log.MODE.APPEND },
    { "LogPath",      "Log Path",           "/smartglasses.log" },
    { "LogDebug",     "Log Debug Messages", false }
}

---@param target glasses_config
---@param raw boolean?
local function load_settings(target, raw)
    for _, v in pairs(fields) do settings.unset(v[1]) end

    local loaded = settings.load("/smartglasses.settings")

    for _, v in pairs(fields) do target[v[1]] = settings.get(v[1], tri(raw, nil, v[3])) end

    return loaded
end

---@param display DisplayBox
local function config_view(display)
    local bw_fg_bg      = style.bw_fg_bg
    local g_lg_fg_bg    = style.g_lg_fg_bg
    local nav_fg_bg     = style.nav_fg_bg
    local btn_act_fg_bg = style.btn_act_fg_bg
    local btn_dis_fg_bg = style.btn_dis_fg_bg

    local function exit() os.queueEvent("terminate") end

    local term_w, term_h = term.getSize()

    TextBox{parent=display,y=1,text="Smart Glasses HUD Configurator",alignment=CENTER,fg_bg=style.header}

    local root_pane_div = Div{parent=display,y=2}

    local main_page = Div{parent=root_pane_div,y=1}
    local ui_cfg    = Div{parent=root_pane_div,y=1}
    local net_cfg   = Div{parent=root_pane_div,y=1}
    local hud_cfg   = Div{parent=root_pane_div,y=1}
    local log_cfg   = Div{parent=root_pane_div,y=1}
    local summary   = Div{parent=root_pane_div,y=1}
    local changelog = Div{parent=root_pane_div,y=1}

    local main_pane = MultiPane{
        parent=root_pane_div, y=1,
        panes={main_page, ui_cfg, net_cfg, hud_cfg, log_cfg, summary, changelog}
    }

    local req_space = log.MIN_SPACE
    if fs.exists("/smartglasses.settings") then
        req_space = math.max(0, req_space - fs.getSize("/smartglasses.settings"))
    end

    local low_space = fs.getFreeSpace("/") < req_space

    --#region Main Page

    local main_h = math.max(4, term_h - 3)

    local main_list = ListBox{
        parent=main_page,
        y=1, x=1,
        height=main_h,
        width=term_w,
        scroll_height=64,
        fg_bg=style.root,
        nav_fg_bg=g_lg_fg_bg,
        nav_active=cpair(colors.black, colors.gray),
    }

    local function add_text(text, fg_bg)
        TextBox{ parent=main_list, text=text, fg_bg=fg_bg or style.root }
    end

    local function add_blank()
        TextBox{ parent=main_list, text="", fg_bg=style.root }
    end

    local function add_button(text, opts)
        opts.parent = main_list
        opts.text = text
        return PushButton(opts)
    end

    add_text("Smart Glasses HUD Configurator", style.root)
    add_blank()

    if tool_ctl.ask_config then
        add_text("Please configure before starting up.",
            cpair(colors.red, colors.lightGray))
        add_blank()
    end

    if low_space then
        add_text("Warning: low disk space.",
            cpair(colors.orange, colors.lightGray))
        add_text("Saving config may fail.",
            cpair(colors.orange, colors.lightGray))
        add_blank()
    end

    if fs.exists("/smartglasses.legacy") then
        add_button("Import Legacy Config", {
            min_width=22,
            callback=function() tool_ctl.load_legacy() end,
            fg_bg=cpair(colors.black, colors.cyan),
            active_fg_bg=btn_act_fg_bg
        })
    end

    add_button("Configure HUD", {
        min_width=16,
        callback=function() main_pane.set_value(2) end,
        fg_bg=cpair(colors.black, colors.blue),
        active_fg_bg=btn_act_fg_bg
    })

    local function view_config()
        tool_ctl.viewing_config = true
        tool_ctl.gen_summary(settings_cfg)
        tool_ctl.settings_apply.hide(true)
        main_pane.set_value(6)
    end

    tool_ctl.view_cfg = add_button("View Configuration", {
        min_width=20,
        callback=view_config,
        fg_bg=cpair(colors.black, colors.blue),
        active_fg_bg=btn_act_fg_bg,
        dis_fg_bg=btn_dis_fg_bg
    })

    if not tool_ctl.has_config then tool_ctl.view_cfg.disable() end

    add_button("Change Log", {
        min_width=12,
        callback=function() main_pane.set_value(7) end,
        fg_bg=nav_fg_bg,
        active_fg_bg=btn_act_fg_bg
    })

    add_blank()

    local function startup()
        tool_ctl.launch_startup = true
        exit()
    end

    if tool_ctl.ask_config then
        add_button("Exit", {
            min_width=6,
            callback=exit,
            dis_fg_bg=btn_dis_fg_bg
        }).disable()

        add_button("Resume", {
            min_width=8,
            callback=exit,
            fg_bg=cpair(colors.black, colors.lightBlue),
            active_fg_bg=btn_act_fg_bg
        })
    else
        add_button("Exit", {
            min_width=6,
            callback=exit,
            fg_bg=cpair(colors.black, colors.red),
            active_fg_bg=btn_act_fg_bg
        })

        add_button("Startup", {
            min_width=9,
            callback=startup,
            fg_bg=cpair(colors.black, colors.green),
            active_fg_bg=btn_act_fg_bg,
            dis_fg_bg=btn_dis_fg_bg
        })
    end

    --#endregion

    --#region System Configuration

    local cfg_sys = { settings_cfg, ini_cfg, tmp_cfg, fields, load_settings }
    local divs    = { ui_cfg, net_cfg, hud_cfg, log_cfg, summary }

    system.create(tool_ctl, main_pane, cfg_sys, divs, style, startup, exit)

    --#endregion

    --#region Config Change Log

    local cl = Div{parent=changelog,x=2,y=2,width=24}

    TextBox{parent=changelog,y=1,text=" Config Change Log",fg_bg=bw_fg_bg}

    local c_log_h = math.max(3, main_h - 2)

    local c_log = ListBox{
        parent=cl, y=1,
        height=c_log_h,
        width=24,
        scroll_height=100,
        fg_bg=bw_fg_bg,
        nav_fg_bg=g_lg_fg_bg,
        nav_active=cpair(colors.black, colors.gray)
    }

    for _, change in ipairs(changes) do
        TextBox{parent=c_log,text=change[1],fg_bg=bw_fg_bg}
        for _, v in ipairs(change[2]) do
            local e = Div{parent=c_log,height=#util.strwrap(v,21)}
            TextBox{parent=e,y=1,text="- ",fg_bg=cpair(colors.gray,colors.white)}
            TextBox{parent=e,y=1,x=3,text=v,height=e.get_height(),fg_bg=cpair(colors.gray,colors.white)}
        end
    end

    PushButton{
        parent=c_log,
        text="\x1b Back",
        callback=function() main_pane.set_value(1) end,
        fg_bg=nav_fg_bg,
        active_fg_bg=btn_act_fg_bg
    }

    --#endregion
end

local function reset_term()
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

---@param ask_config? boolean
function configurator.configure(ask_config)
    tool_ctl.ask_config = ask_config == true

    load_settings(settings_cfg, true)
    tool_ctl.has_config = load_settings(ini_cfg)

    reset_term()

    for i = 1, #style.colors do
        term.setPaletteColor(style.colors[i].c, style.colors[i].hex)
    end

    local status, error = pcall(function ()
        local display = DisplayBox{window=term.current(),fg_bg=style.root}
        config_view(display)

        while true do
            local event, param1, param2, param3 = util.pull_event()

            if event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
                local m_e = core.events.new_mouse_event(event, param1, param2, param3)
                if m_e then display.handle_mouse(m_e) end
            elseif event == "char" or event == "key" or event == "key_up" then
                local k_e = core.events.new_key_event(event, param1, param2)
                if k_e then display.handle_key(k_e) end
            elseif event == "paste" then
                display.handle_paste(param1)
            end

            if event == "terminate" then return end
        end
    end)

    for i = 1, #style.colors do
        local r, g, b = term.nativePaletteColor(style.colors[i].c)
        term.setPaletteColor(style.colors[i].c, r, g, b)
    end

    reset_term()
    if not status then
        println("configurator error: " .. error)
    end

    return status, error, tool_ctl.launch_startup
end

return configurator