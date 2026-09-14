--
-- Main and render threads for the smart glasses HUD
--

local log      = require("scada-common.log")
local mqueue   = require("scada-common.mqueue")
local ppm      = require("scada-common.ppm")
local tcd      = require("scada-common.tcd")
local util     = require("scada-common.util")

local glasses  = require("smartglasses.smartglasses")
local renderer = require("smartglasses.renderer")

local threads = {}

local MAIN_CLOCK   = 0.5
local RENDER_SLEEP = 100

local MQ_KEY_RENDER = "RENDER"

-- map of CC:Tweaked key codes to printable letters.
-- built at load time so any missing entries in the 'keys' table don't crash startup.
local LETTER_KEYS = {}
do
    local pairs_list = {
        { "a", "A" }, { "b", "B" }, { "c", "C" }, { "d", "D" }, { "e", "E" },
        { "f", "F" }, { "g", "G" }, { "h", "H" }, { "i", "I" }, { "j", "J" },
        { "k", "K" }, { "l", "L" }, { "m", "M" }, { "n", "N" }, { "o", "O" },
        { "p", "P" }, { "q", "Q" }, { "r", "R" }, { "s", "S" }, { "t", "T" },
        { "u", "U" }, { "v", "V" }, { "w", "W" }, { "x", "X" }, { "y", "Y" },
        { "z", "Z" },
        { "zero", "0" }, { "one", "1" }, { "two", "2" }, { "three", "3" },
        { "four", "4" }, { "five", "5" }, { "six", "6" }, { "seven", "7" },
        { "eight", "8" }, { "nine", "9" },
        { "escape", "ESC" },
    }

    for _, pair in ipairs(pairs_list) do
        local cc_name = pair[1]
        local letter  = pair[2]
        if keys[cc_name] ~= nil then
            LETTER_KEYS[keys[cc_name]] = letter
        end
    end
end

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
        local render_queue = smem.q.mq_render
        local klog         = smem.callbacks and smem.callbacks.klog or function () end

        local config         = glasses.config
        local keyboard_ready = smem.hud_dev.keyboard ~= nil

        local hotkeys_bound = (config.HotkeyScram ~= "" or config.HotkeyStart ~= "")

        if not keyboard_ready then
            log.info("keyboard module not present; key events will not fire")
        elseif not hotkeys_bound then
            log.info("no hotkeys configured; press a key on the keyboard to log it")
        end

        local function request_render()
            render_queue.push_data(MQ_KEY_RENDER, true)
        end

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

        ---@param key_code number
        ---@param is_held boolean
        local function handle_key_event(key_code, is_held)
            local letter = LETTER_KEYS[key_code] or string.format("code=%d", key_code)

            klog(string.format("key=%s code=%s held=%s",
                tostring(letter), tostring(key_code), tostring(is_held)))

            log.info(string.format("key event: letter=%s code=%s held=%s",
                tostring(letter), tostring(key_code), tostring(is_held)))

            -- ignore held-key repeats so a key held down doesn't spam commands
            if is_held then return end

            if not pocket_comms.is_api_linked() then
                return
            end

            -- ESC does nothing special here; just don't send it as a command
            if letter == "ESC" then
                return
            end

            local handled = false

            if config.HotkeyScram ~= "" and letter == config.HotkeyScram then
                pocket_comms.send_scram(config.UnitID)
                renderer.flash_message("SCRAM SENT")
                log.info("hotkey SCRAM sent for unit " .. config.UnitID)
                handled = true
            elseif config.HotkeyStart ~= "" and letter == config.HotkeyStart then
                pocket_comms.send_start(config.UnitID)
                renderer.flash_message("START SENT")
                log.info("hotkey START sent for unit " .. config.UnitID)
                handled = true
            end

            if not handled and not hotkeys_bound then
                renderer.flash_message("KEY: " .. letter)
            end
        end

        api_wd.feed()

        -- suppress rapid repeats of the same event name in the key log
        local EVENT_LOG_DEDUP_MS = 1000
        local last_event_name = nil
        local last_event_ms   = 0

        local function trace_event(event_name)
            local now = util.time_ms()
            if event_name ~= last_event_name or (now - last_event_ms) > EVENT_LOG_DEDUP_MS then
                last_event_name = event_name
                last_event_ms   = now
                klog(string.format("(event) name=%s", tostring(event_name)))
            end
        end

        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            if event == "modem_message" then
                local packet = pocket_comms.parse_packet(param1, param2, param3, param4, param5)
                pocket_comms.handle_packet(packet)
                request_render()
            elseif event == "timer" then
                if loop_clock.is_clock(param1) then
                    loop_tick()
                elseif api_wd.is_timer(param1) then
                    log.info("coordinator api server timeout")
                    pocket_comms.close_api()
                else
                    tcd.handle(param1)
                end
            else
                -- trace every non-modem, non-timer event so we can see what
                -- the keyboard module actually fires on this AP version
                trace_event(event)

                if event == "keyboard_open" then
                    log.info("keyboard opened")
                    klog("(keyboard_open)")
                    renderer.flash_message("KEYBOARD OPEN")
                elseif event == "keyboard_close" then
                    log.info("keyboard closed")
                    klog("(keyboard_close)")
                    renderer.flash_message("KEYBOARD CLOSED")
                elseif event == "key" or event == "key_up" then
                    if keyboard_ready then
                        handle_key_event(param1, param2)
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

function threads.thread__render(smem)
    ---@class parallel_thread
    local public = {}

    function public.exec()
        log.debug("render thread start")

        local hud_state    = smem.hud_state
        local render_queue = smem.q.mq_render

        local dirty = false

        while true do
            while render_queue.ready() and not hud_state.shutdown do
                local msg = render_queue.pop()

                if msg ~= nil and msg.qtype == mqueue.TYPE.DATA then
                    local cmd = msg.message

                    if cmd ~= nil and cmd.key == MQ_KEY_RENDER then
                        dirty = true
                    end
                end

                util.nop()
            end

            if dirty and not hud_state.shutdown then
                local ok, err = pcall(renderer.render_unit)
                if not ok then
                    log.error("render_unit failed: " .. tostring(err))
                end
                dirty = false
            end

            if hud_state.shutdown then
                log.info("render thread exiting")
                break
            end

            util.psleep(0.05)
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