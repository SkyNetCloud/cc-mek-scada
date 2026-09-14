--
-- SCADA System Access on Smart Glasses
--

---@diagnostic disable-next-line: lowercase-global
smartglasses = smartglasses or periphemu    -- luacheck: ignore smartglasses

local _is_glasses_env = smartglasses

require("/initenv").init_env()

local crash     = require("scada-common.crash")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local network   = require("scada-common.network")
local ppm       = require("scada-common.ppm")
local util      = require("scada-common.util")

local configure = require("smartglasses.configure")
local glasses   = require("smartglasses.smartglasses")
local renderer  = require("smartglasses.renderer")
local threads   = require("smartglasses.threads")

local HUD_VERSION = "1.3.2"

local println    = util.println
local println_ts = util.println_ts

local ERROR_LOG_PATH = "/smartglasses_errors.log"

local function elog(msg)
    local ok, err = pcall(function ()
        local f = fs.open(ERROR_LOG_PATH, "a")
        if f then
            f.writeLine(string.format("[%s] %s", os.date("%Y-%m-%d %H:%M:%S"), tostring(msg)))
            f.flush()
            f.close()
        end
    end)
    if not ok then println("[elog failed] " .. tostring(err)) end
end

local function elog_error(where, err)
    elog("========================================")
    elog("ERROR at " .. where)
    elog("----------------------------------------")
    elog(tostring(err))
    elog("--- traceback ---")
    elog(debug.traceback("", 2))
    elog("========================================")
end

if not _is_glasses_env then
    println("You can only use this application on a computer wearing Smart Glasses.")
    elog("environment check failed: not running with smartglasses global")
    return
end

-- overlay module lives in smartglasses.modules, not as a peripheral
local overlay_module = smartglasses.modules['advancedperipherals:overlay']
if overlay_module == nil then
    println("startup> Advanced Peripherals Overlay Module not equipped")
    elog("overlay module 'advancedperipherals:overlay' not present in smartglasses.modules")
    return
end

----------------------------------------
-- get configuration
----------------------------------------

if not glasses.load_config() then
    local success, error = configure.configure(true)

    if not success then
        elog_error("configure.configure()", error)
        println("configuration error: " .. tostring(error))
        return
    end

    if not glasses.load_config() then
        elog("failed to load a valid configuration after configure() succeeded")
        println("failed to load a valid configuration, please reconfigure")
        return
    end
end

local config = glasses.config

----------------------------------------
-- log init
----------------------------------------

local log_ok, log_err = pcall(log.init, config.LogPath, config.LogMode, config.LogDebug)
if not log_ok then
    elog_error("log.init(" .. tostring(config.LogPath) .. ")", log_err)
    println("log init failed: " .. tostring(log_err))
end

log.info("========================================")
log.info("BOOTING smartglasses v" .. HUD_VERSION)
log.info("========================================")

crash.set_env("glasses_hud", HUD_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ppm.mount_all()

    glasses.get_db().version = HUD_VERSION

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
            overlay = overlay_module,
        },

        hud_sys = {
            nic = nil,
            pocket_comms = nil,
            api_wd = nil,
        },

        q = {
            mq_render = mqueue.new()
        }
    }

    local smem_dev   = __shared_memory.hud_dev
    local smem_sys   = __shared_memory.hud_sys
    local hud_state  = __shared_memory.hud_state

    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        local mac_ok, mac_err = pcall(network.init_mac, config.AuthKey)
        if not mac_ok then elog_error("network.init_mac()", mac_err) end
    end

    glasses.report_link_state(glasses.LINK_STATE.UNLINKED)

    if smem_dev.modem == nil then
        elog("no wireless modem found on startup")
        println("startup> wireless modem not found: please craft the smart glasses with a wireless modem")
        log.fatal("startup> no wireless modem on startup")
        return
    end

    if smem_dev.overlay == nil then
        elog("no overlay module found on startup")
        println("startup> Advanced Peripherals Overlay Module not equipped")
        log.fatal("startup> no overlay module on startup")
        return
    end

    smem_sys.api_wd = util.new_watchdog(config.ConnTimeout)
    smem_sys.api_wd.cancel()
    log.debug("startup> conn watchdog created")

    local nic_ok, nic_err = pcall(function ()
        smem_sys.nic = network.nic(smem_dev.modem)
        smem_sys.pocket_comms = glasses.comms(HUD_VERSION, smem_sys.nic, smem_sys.api_wd)
    end)
    if not nic_ok then
        elog_error("network.nic / glasses.comms init", nic_err)
        println("comms init failed: " .. tostring(nic_err))
        return
    end
    log.debug("startup> comms init")

    glasses.init_core(smem_sys.pocket_comms, config)

    local hud_message
    hud_state.ui_ok, hud_message = renderer.try_start_hud(smem_dev.overlay)
    if not hud_state.ui_ok then
        elog_error("renderer.try_start_hud()", hud_message)
        println(util.c("HUD error: ", hud_message))
        log.error(util.c("startup> HUD render failed with error ", hud_message))
    end

    if hud_state.ui_ok then
        local main_thread   = threads.thread__main(__shared_memory)
        local render_thread = threads.thread__render(__shared_memory)

        log.info("startup> completed")

        parallel.waitForAll(main_thread.p_exec, render_thread.p_exec)

        renderer.close_hud()

        if not hud_state.ui_ok then
            elog("HUD crashed with error: " .. tostring(hud_state.ui_error))
            println(util.c("HUD crashed with error: ", hud_state.ui_error))
        end
    else
        println_ts("HUD creation failed")
    end

    println_ts("exited")
    log.info("exited")
end

local main_ok, main_err = xpcall(main, function (err)
    pcall(crash.handler, err)
    elog_error("main() (fatal)", err)
    return err
end)

if not main_ok then
    pcall(renderer.close_hud)
    elog("xpcall(main) returned false; exiting")
    elog("main_err = " .. tostring(main_err))
    crash.exit()
else
    log.close()
end