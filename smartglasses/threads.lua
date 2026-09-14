--
-- Main and render threads for the smart glasses HUD
--

local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue") 
local ppm      = require("scada-common.ppm")
local tcd      = require("scada-common.tcd")
local util     = require("scada-common.util")

local glasses  = require("smartglasses_display.smartglasses")
local renderer = require("smartglasses_display.renderer")

local threads = {}

local MAIN_CLOCK   = 0.5
local RENDER_SLEEP = 100

-- main thread
---@nodiscard
---@param smem glasses_shared_memory
function threads.thread__main(smem)
    ---@class parallel_thread
    local public = {}

    function public.exec()
        log.debug("main thread start")

        local loop_clock = util.new_clock(MAIN_CLOCK)
        loop_clock.start()

        local hud_state    = smem.hud_state
        local pocket_comms = smem.hud_sys.pocket_comms
        local api_wd       = smem.hud_sys.api_wd
        local nic          = smem.hud_sys.nic

        local config       = glasses.config

        local function loop_tick()
            pocket_comms.link_update()

            if pocket_comms.is_api_linked() then
                pocket_comms.api__get_unit(config.UnitID)
                renderer.update_link(true, "")
            else
                renderer.update_link(false, "")
            end

            nic.periodic()
            loop_clock.start()
        end

        api_wd.feed()

        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            if event == "modem_message" then
                local packet = pocket_comms.parse_packet(param1, param2, param3, param4, param5)
                pocket_comms.handle_packet(packet)
                renderer.render_unit()
            elseif event == "timer" then
                if loop_clock.is_clock(param1) then
                    loop_tick()
                elseif api_wd.is_timer(param1) then
                    log.info("coordinator api server timeout")
                    pocket_comms.close_api()
                else
                    tcd.handle(param1)
                end
            elseif event == "glasses_key_pressed" then
                local key = param1
                if pocket_comms.is_api_linked() then
                    if config.HotkeyScram ~= "" and key == config.HotkeyScram then
                        pocket_comms.send_scram(config.UnitID)
                        renderer.flash_message("SCRAM SENT")
                        log.info("hotkey SCRAM sent for unit " .. config.UnitID)
                    elseif config.HotkeyStart ~= "" and key == config.HotkeyStart then
                        pocket_comms.send_start(config.UnitID)
                        renderer.flash_message("START SENT")
                        log.info("hotkey START sent for unit " .. config.UnitID)
                    else
                        renderer.flash_message("KEY: " .. tostring(key))
                    end
                end
            end

            if event == "terminate" or ppm.should_terminate() then
                log.info("terminate requested, main thread exiting")
                hud_state.shutdown = true
            elseif not hud_state.ui_ok then
                hud_state.shutdown = true
                log.info("terminating due to fatal HUD error")
            end

            if hud_state.shutdown then
                log.info("closing coordinator connection...")
                pocket_comms.close_api()
                log.info("connection closed")
                break
            end
        end
    end

    function public.p_exec()
        local hud_state = smem.hud_state

        while not hud_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(util.strval(result))
            end

            if not hud_state.shutdown then
                log.info("main thread restarting now...")
            end
        end
    end

    return public
end

-- render thread (re-renders on queue message)
---@nodiscard
---@param smem glasses_shared_memory
function threads.thread__render(smem)
    ---@class parallel_thread
    local public = {}

    function public.exec()
        log.debug("render thread start")

        local hud_state    = smem.hud_state
        local render_queue = smem.q.mq_render

        local last_update = util.time()

        while true do
            while render_queue.ready() and not hud_state.shutdown do
                local msg = render_queue.pop()

                if msg ~= nil and msg.qtype == mqueue.TYPE.DATA then
                    local cmd = msg.message

                    if cmd.key == "RENDER" then
                        renderer.render_unit()
                    end
                end

                util.nop()
            end

            if hud_state.shutdown then
                log.info("render thread exiting")
                break
            end

            last_update = util.adaptive_delay(RENDER_SLEEP, last_update)
        end
    end

    function public.p_exec()
        local hud_state = smem.hud_state

        while not hud_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(util.strval(result))
            end

            if not hud_state.shutdown then
                log.info("render thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

return threads