--
-- SCADA System Access on Smart Glasses
--

---@diagnostic disable-next-line: lowercase-global
local _is_glasses_env = smartglasses

require("/initenv").init_env()

local crash     = require("scada-common.crash")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local network   = require("scada-common.network")
local ppm       = require("scada-common.ppm")
local util      = require("scada-common.util")

local configure = require("smartglasses_display.configure")
local glasses   = require("smartglasses_display.smartglasses")
local renderer  = require("smartglasses_display.renderer")
local threads   = require("smartglasses_display.threads")

local HUD_VERSION = "smartglasses_display-1.0.0"

local println    = util.println
local println_ts = util.println_ts

-- environment check (Smart Glasses only)
if not _is_glasses_env then
    println("You can only use this application on a computer wearing Smart Glasses.")
    return
end

----------------------------------------
-- get configuration
----------------------------------------

if not glasses.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not glasses.load_config() then
            println("failed to load a valid configuration, please reconfigure")
            return
        end
    else
        println("configuration error: " .. error)
        return
    end
end

local config = glasses.config

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING smartglasses_display v" .. HUD_VERSION)
log.info("========================================")

crash.set_env("glasses_hud", HUD_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- system startup
    ----------------------------------------

    -- mount connected devices
    ppm.mount_all()

    -- record version for GUI
    glasses.get_db().version = HUD_VERSION

    ----------------------------------------
    -- memory allocation
    ----------------------------------------

    ---@class glasses_shared_memory
    local __shared_memory = {
        ---@class glasses_state
        hud_state = {
            ui_ok = false,
            ui_error = nil,
            shutdown = false
        },

        hud_dev = {
            modem = ppm.get_wireless_modem(),
            overlay = peripheral.find("overlay")
        },

        hud_sys = {
            nic = nil,           ---@type nic
            pocket_comms = nil,  ---@type glasses_comms
            api_wd = nil,        ---@type watchdog
        },

        q = {
            mq_render = mqueue.new()
        }
    }

    local smem_dev   = __shared_memory.hud_dev
    local smem_sys   = __shared_memory.hud_sys
    local hud_state  = __shared_memory.hud_state

    ----------------------------------------
    -- setup system
    ----------------------------------------

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
    end

    glasses.report_link_state(glasses.LINK_STATE.UNLINKED)

    -- get the communications modem
    if smem_dev.modem == nil then
        println("startup> wireless modem not found: please craft the smart glasses with a wireless modem")
        log.fatal("startup> no wireless modem on startup")
        return
    end

    -- get the overlay module
    if smem_dev.overlay == nil then
        println("startup> Advanced Peripherals Overlay Module not found")
        log.fatal("startup> no overlay module on startup")
        return
    end

    -- create connection watchdog (coordinator only)
    smem_sys.api_wd = util.new_watchdog(config.ConnTimeout)
    smem_sys.api_wd.cancel()
    log.debug("startup> conn watchdog created")

    -- create network interface then setup comms
    smem_sys.nic = network.nic(smem_dev.modem)
    smem_sys.pocket_comms = glasses.comms(HUD_VERSION, smem_sys.nic, smem_sys.api_wd)
    log.debug("startup> comms init")

    -- init I/O control
    glasses.init_core(smem_sys.pocket_comms, config)

    ----------------------------------------
    -- start the HUD
    ----------------------------------------

    local hud_message
    hud_state.ui_ok, hud_message = renderer.try_start_hud()
    if not hud_state.ui_ok then
        println(util.c("HUD error: ", hud_message))
        log.error(util.c("startup> HUD render failed with error ", hud_message))
    end

    ----------------------------------------
    -- start system
    ----------------------------------------

    if hud_state.ui_ok then
        -- init threads
        local main_thread   = threads.thread__main(__shared_memory)
        local render_thread = threads.thread__render(__shared_memory)

        log.info("startup> completed")

        -- run threads
        parallel.waitForAll(main_thread.p_exec, render_thread.p_exec)

        renderer.close_hud()

        if not hud_state.ui_ok then
            println(util.c("HUD crashed with error: ", hud_state.ui_error))
        end
    else
        println_ts("HUD creation failed")
    end

    println_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_hud)
    crash.exit()
else
    log.close()
end