--
-- Smart Glasses HUD Integration with Coordinator
--

local comms   = require("scada-common.comms")
local log     = require("scada-common.log")
local psil    = require("scada-common.psil")
local util    = require("scada-common.util")

local PROTOCOL      = comms.PROTOCOL
local DEVICE_TYPE   = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local MGMT_TYPE     = comms.MGMT_TYPE
local CRDN_TYPE     = comms.CRDN_TYPE
local UNIT_COMMAND  = comms.UNIT_COMMAND

local glasses = {}

---@enum GLASSES_LINK_STATE
local LINK_STATE = {
    UNLINKED = 0,
    LINKED   = 3
}

glasses.LINK_STATE = LINK_STATE

---@class glasses_io
local io = {
    version = "unknown",
    ps = psil.create()
}

local config = nil     ---@type glasses_config
local comms_ref = nil  ---@type glasses_comms

---@class glasses_hud_unit
local unit_data = {
    connected = false,
    alarms = {},
    reactor_data = {},
    boiler_data_tbl = {},
    turbine_data_tbl = {},
    tank_data_tbl = {},
    annunciator = {},
    a_group = 0,
}

glasses.unit = unit_data

-- load the glasses configuration
function glasses.load_config()
    if not settings.load("/smartglasses.settings") then return false end

    ---@class glasses_config
    local c = {}

    c.UnitID       = settings.get("UnitID")
    c.CRD_Channel  = settings.get("CRD_Channel")
    c.PKT_Channel  = settings.get("PKT_Channel")
    c.ConnTimeout  = settings.get("ConnTimeout")
    c.TrustedRange = settings.get("TrustedRange")
    c.AuthKey      = settings.get("AuthKey")

    c.HotkeyScram  = settings.get("HotkeyScram")
    c.HotkeyStart  = settings.get("HotkeyStart")
    c.HUDScale     = settings.get("HUDScale")

    c.LogMode      = settings.get("LogMode")
    c.LogPath      = settings.get("LogPath")
    c.LogDebug     = settings.get("LogDebug")

    local cfv = util.new_validator()

    cfv.assert_type_int(c.UnitID)
    cfv.assert_min(c.UnitID, 1)

    cfv.assert_channel(c.CRD_Channel)
    cfv.assert_channel(c.PKT_Channel)

    cfv.assert_type_num(c.ConnTimeout)
    cfv.assert_min(c.ConnTimeout, 2)

    cfv.assert_type_num(c.TrustedRange)
    cfv.assert_min(c.TrustedRange, 0)

    cfv.assert_type_str(c.AuthKey)
    if type(c.AuthKey) == "string" then
        local len = string.len(c.AuthKey)
        cfv.assert(len == 0 or len >= 8)
    end

    cfv.assert_type_str(c.HotkeyScram)
    cfv.assert_type_str(c.HotkeyStart)

    cfv.assert_type_num(c.HUDScale)
    cfv.assert_min(c.HUDScale, 0.5)

    cfv.assert_type_int(c.LogMode)
    cfv.assert_range(c.LogMode, 0, 1)
    cfv.assert_type_str(c.LogPath)
    cfv.assert_type_bool(c.LogDebug)

    if not cfv.valid() then return false end

    config = c
    glasses.config = c

    return true
end

-- initialize components (coordinator watchdog provided by startup)
---@param pkt_comms glasses_comms
---@param cfg glasses_config
function glasses.init_core(pkt_comms, cfg)
    comms_ref = pkt_comms
    config = cfg
end

-- set network link state
---@param state GLASSES_LINK_STATE
function glasses.report_link_state(state)
    io.ps.publish("link_state", state)
end

-- show link error message
function glasses.report_link_error(msg) io.ps.publish("link_msg", msg) end

-- get the IO controller database
function glasses.get_db() return io end

-- glasses coordinator-only communications (API half of pocket.comms)
---@nodiscard
---@param version string
---@param nic nic
---@param api_watchdog watchdog
function glasses.comms(version, nic, api_watchdog)
    local self = {
        api = {
            linked = false,
            addr = comms.BROADCAST,
            seq_num = util.time_ms() * 10,
            r_seq_num = nil, ---@type nil|integer
            last_est_ack = ESTABLISH_ACK.ALLOW
        },
        establish_delay_counter = 0
    }

    comms.set_trusted_range(config.TrustedRange)

    -- configure network channels
    nic.closeAll()
    nic.open(config.PKT_Channel)

    local function _send_crd(msg_type, msg)
        local frame, mgmt = comms.scada_frame(), comms.mgmt_container()
        mgmt.make(msg_type, msg)
        frame.make(self.api.addr, self.api.seq_num, PROTOCOL.SCADA_MGMT, mgmt.raw_packet())
        nic.transmit(config.CRD_Channel, config.PKT_Channel, frame)
        self.api.seq_num = self.api.seq_num + 1
    end

    local function _send_api(msg_type, msg)
        local frame, crdn = comms.scada_frame(), comms.crdn_container()
        crdn.make(msg_type, msg)
        frame.make(self.api.addr, self.api.seq_num, PROTOCOL.SCADA_CRDN, crdn.raw_packet())
        nic.transmit(config.CRD_Channel, config.PKT_Channel, frame)
        self.api.seq_num = self.api.seq_num + 1
    end

    local function _send_api_establish()
        self.api.r_seq_num = nil
        _send_crd(MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.PKT, comms.api_version })
    end

    local function _send_api_keep_alive_ack(srv_time)
        _send_crd(MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    ---@class glasses_comms
    local public = {}

    function public.close_api()
        api_watchdog.cancel()

        if self.api.linked then
            self.api.linked = false
            _send_crd(MGMT_TYPE.CLOSE, {})
        end

        self.api.r_seq_num = nil
        self.api.addr = comms.BROADCAST
    end

    function public.link_update()
        if not self.api.linked then
            glasses.report_link_state(LINK_STATE.UNLINKED)

            if self.establish_delay_counter <= 0 then
                _send_api_establish()
                self.establish_delay_counter = 4
            else
                self.establish_delay_counter = self.establish_delay_counter - 1
            end
        else
            glasses.report_link_state(LINK_STATE.LINKED)
        end
    end

    function public.send_unit_command(cmd, unit, option)
        _send_api(CRDN_TYPE.UNIT_CMD, { cmd, unit, option })
    end

    function public.api__get_unit(unit)
        if self.api.linked then _send_api(CRDN_TYPE.API_GET_UNIT, { unit }) end
    end

    function public.parse_packet(side, sender, reply_to, message, distance)
        local frame = nic.receive(side, sender, reply_to, message, distance)

        local pkt = nil
        if frame then
            if frame.protocol() == PROTOCOL.SCADA_MGMT then
                pkt = comms.mgmt_container().decode(frame)
            elseif frame.protocol() == PROTOCOL.SCADA_CRDN then
                pkt = comms.crdn_container().decode(frame)
            else
                log.debug("attempted parse of illegal packet type " .. frame.protocol(), true)
            end
        end

        return pkt
    end

    local function _check_length(packet, length, max)
        local ok = util.trinary(max == nil, packet.length == length,
                                packet.length >= length and packet.length <= (max or 0))
        if not ok then
            local fmt = "[comms] RX_PACKET{r_chan=%d,proto=%d,type=%d}: packet length mismatch -> expect %d != actual %d"
            log.debug(util.sprintf(fmt, packet.scada_frame.remote_channel(),
                                   packet.scada_frame.protocol(), packet.type,
                                   length, packet.length))
        end
        return ok
    end

    ---@param packet mgmt_packet|crdn_packet|nil
    function public.handle_packet(packet)
        if packet == nil then return end

        local l_chan   = packet.scada_frame.local_channel()
        local r_chan   = packet.scada_frame.remote_channel()
        local protocol = packet.scada_frame.protocol()
        local src_addr = packet.scada_frame.src_addr()

        if l_chan ~= config.PKT_Channel then
            log.debug("received packet on unconfigured channel " .. l_chan, true)
            return
        end

        if r_chan ~= config.CRD_Channel then
            log.debug("received packet from unconfigured channel " .. r_chan, true)
            return
        end

        -- sequence number check (mirrors pocket.comms)
        if self.api.r_seq_num == nil then
            self.api.r_seq_num = packet.scada_frame.seq_num() + 1
        elseif self.api.r_seq_num ~= packet.scada_frame.seq_num() then
            log.warning("sequence out-of-order (API): next = " .. self.api.r_seq_num ..
                        ", new = " .. packet.scada_frame.seq_num())
            return
        elseif self.api.linked and (src_addr ~= self.api.addr) then
            log.debug("received packet from unknown computer " .. src_addr ..
                      " while linked (API expected " .. self.api.addr .. ")")
            return
        else
            self.api.r_seq_num = packet.scada_frame.seq_num() + 1
        end

        api_watchdog.feed()

        if protocol == PROTOCOL.SCADA_CRDN then
            ---@cast packet crdn_packet
            if self.api.linked then
                if packet.type == CRDN_TYPE.API_GET_UNIT then
                    if _check_length(packet, 13)
                       and type(packet.data[1]) == "number"
                       and packet.data[1] == config.UnitID
                    then
                        glasses.record_unit_data(packet.data)
                    end
                end
            else
                log.debug("discarding coordinator SCADA_CRDN packet before linked")
            end
        elseif protocol == PROTOCOL.SCADA_MGMT then
            ---@cast packet mgmt_packet
            if self.api.linked then
                if packet.type == MGMT_TYPE.KEEP_ALIVE then
                    if _check_length(packet, 1) then
                        _send_api_keep_alive_ack(packet.data[1])
                    end
                elseif packet.type == MGMT_TYPE.CLOSE then
                    api_watchdog.cancel()
                    self.api.linked = false
                    self.api.r_seq_num = nil
                    self.api.addr = comms.BROADCAST
                    log.info("coordinator server connection closed by remote host")
                end
            elseif packet.type == MGMT_TYPE.ESTABLISH then
                if _check_length(packet, 1, 2) then
                    local est_ack = packet.data[1]

                    if est_ack == ESTABLISH_ACK.ALLOW then
                        self.establish_delay_counter = 0
                        self.api.linked = true
                        self.api.addr = src_addr

                        log.info("coordinator connection established")
                        glasses.report_link_state(LINK_STATE.LINKED)
                        glasses.report_link_error("")
                    else
                        if self.api.last_est_ack ~= est_ack then
                            if est_ack == ESTABLISH_ACK.DENY then
                                glasses.report_link_error("denied")
                            elseif est_ack == ESTABLISH_ACK.COLLISION then
                                glasses.report_link_error("collision")
                            elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                                glasses.report_link_error("comms version mismatch")
                            elseif est_ack == ESTABLISH_ACK.BAD_API_VERSION then
                                glasses.report_link_error("API version mismatch")
                            else
                                glasses.report_link_error("unknown reply")
                            end
                        end

                        self.api.addr = comms.BROADCAST
                        self.api.linked = false
                    end

                    self.api.last_est_ack = est_ack
                end
            end
        end
    end

    function public.is_api_linked() return self.api.linked end

    function public.send_scram(unit) public.send_unit_command(UNIT_COMMAND.SCRAM, unit) end
    function public.send_start(unit) public.send_unit_command(UNIT_COMMAND.START, unit) end

    return public
end

-- record unit data from API_GET_UNIT
---@param data table
function glasses.record_unit_data(data)
    local u = glasses.unit

    u.connected         = data[2]
    u.a_group           = data[4]
    u.alarms            = data[5]
    u.annunciator       = data[6]
    u.reactor_data      = data[7]
    u.boiler_data_tbl   = data[8]
    u.turbine_data_tbl  = data[9]
    u.tank_data_tbl     = data[10]

    local mek = u.reactor_data.mek_status or {}

    local ps = io.ps
    ps.publish("temp", mek.temp)
    ps.publish("burn_rate", mek.burn_rate)
    ps.publish("act_burn_rate", mek.act_burn_rate)
    ps.publish("max_burn", u.reactor_data.mek_struct and u.reactor_data.mek_struct.max_burn)
    ps.publish("reactor_status", mek.status)
    ps.publish("connected", u.connected)
end

return glasses