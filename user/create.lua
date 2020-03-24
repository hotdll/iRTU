--- 模块功能：DTU主逻辑
-- @author openLuat
-- @module create
-- @license MIT
-- @copyright openLuat
-- @release 2018.12.27
require "pm"
require "iic"
require "sms"
require "pins"
require "misc"
require "mqtt"
require "utils"
require "lbsLoc"
require "socket"
require "update"
require "httpv2"
require "gpsv2"
require "common"
require "tracker"
module(..., package.seeall)
---------------------------------------------------------- 这个模块为2G和4G通用部分 ----------------------------------------------------------
local datalink = false
-- 定时采集任务的参数
local interval, samptime = {0, 0}, {0, 0}
-- 获取经纬度
local lat, lng = 0, 0
-- 无网络重启时间，飞行模式启动时间
local rstTim, flyTim = 600000, 300000

-- 保存获取的基站坐标
function setLocation(la, ln)
    lat, lng = la, ln
    log.info("基站定位请求的结果:", lat, lng)
end
function getDatalink()
    return datalink
end
function getTimParam()
    return interval, samptime
end
---------------------------------------------------------- 自动任务列表  ----------------------------------------------------------
-- 用户读取ADC
function getADC(id)
    adc.open(id)
    local adcValue, voltValue = adc.read(id)
    adc.close(id)
    if adcValue ~= 0xFFFF or voltValue ~= 0xFFFF then
        return (voltValue - voltValue % 3) / 3
    end
end
-- 获取纬度
function getLat()
    return lat
end
-- 获取经度
function getLng()
    return lng
end
-- 获取实时经纬度
function getRealLocation()
    lbsLoc.request(function(result, lat, lng, addr)
        if result then
            setLocation(lat, lng)
        end
    end)
    return lat, lng
end
---------------------------------------------------------- DTU的网络任务部分 ----------------------------------------------------------
local function conver(str)
    if str:match("function(.+)end") then return loadstring(str:match("function(.+)end"))() end
    local hex = str:sub(1, 2):lower() == "0x"
    str = hex and str:sub(3, -1) or str
    local tmp = str:split("|")
    for v = 1, #tmp do
        if tmp[v]:lower() == "imei" then tmp[v] = hex and (misc.getImei():toHex()) or misc.getImei() end
        if tmp[v]:lower() == "muid" then tmp[v] = hex and (misc.getMuid():toHex()) or misc.getMuid() end
        if tmp[v]:lower() == "imsi" then tmp[v] = hex and (sim.getImsi():toHex()) or sim.getImsi() end
        if tmp[v]:lower() == "iccid" then tmp[v] = hex and (sim.getIccid():toHex()) or sim.getIccid() end
        if tmp[v]:lower() == "csq" then tmp[v] = hex and string.format("%02X", net.getRssi()) or tostring(net.getRssi()) end
    end
    return hex and (table.concat(tmp):fromHex()) or table.concat(tmp)
end
--登陆报文
local function loginMsg(str)
    if tonumber(str) == 0 then
        return nil
    elseif tonumber(str) == 1 then
        return json.encode({csq = net.getRssi(), imei = misc.getImei(), iccid = sim.getIccid(), ver = _G.VERSION})
    elseif tonumber(str) == 2 then
        return tostring(net.getRssi()):fromHex() .. (misc.getImei() .. "0"):fromHex() .. sim.getIccid():fromHex()
    elseif type(str) == "string" and #str ~= 0 then
        return conver(str)
    else
        return nil
    end
end
-- 用户可用API
local function userapi(str, pios)
    local t = str:match("(.-)\r?\n") and str:match("(.-)\r?\n"):split(',') or str:split(',')
    local rrpc = table.remove(t, 1)
    local reqcmd = table.remove(t, 1)
    log.warn("user api:", rrpc, reqcmd)
    if default.cmd[rrpc] and default.cmd[rrpc][reqcmd] then
        return default.cmd[rrpc][reqcmd](t)
    else
        return "ERROR"
    end
end
---------------------------------------------------------- SOKCET 服务 ----------------------------------------------------------
local function tcpTask(cid, pios, reg, convert, passon, upprot, dwprot, prot, ping, timeout, addr, port, uid, gap, report, intervalTime, ssl, login)
    cid, prot, timeout, uid = tonumber(cid) or 1, prot:upper(), tonumber(timeout) or 120, tonumber(uid) or 1
    if not ping or ping == "" then ping = "0x00" end
    if tonumber(intervalTime) then sys.timerLoopStart(sys.publish, tonumber(intervalTime) * 1000, "AUTO_SAMPL_" .. uid) end
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and loadstring(upprot[cid]:match("function(.+)end"))
    while true do
        local idx = 0
        if not socket.isReady() and not sys.waitUntil("IP_READY_IND", rstTim) then sys.restart("网络初始化失败!") end
        local c = prot == "TCP" and socket.tcp(ssl and ssl:lower() == "ssl") or socket.udp()
        while not c:connect(addr, port) do sys.wait((2 ^ idx) * 1000)idx = idx > 9 and 0 or idx + 1 end
        -- 登陆报文
        if login or loginMsg(reg) then c:send(login or loginMsg(reg)) end
        interval[uid], samptime[uid] = tonumber(gap) or 0, tonumber(report) or 0
        while true do
            datalink = true
            local result, data, param = c:recv(timeout * 1000, "NET_SENT_RDY_" .. (passon and cid or uid))
            if result then
                -- 这里执行用户自定义的指令
                if data:sub(1, 5) == "rrpc," or data:sub(1, 7) == "config," then
                    local res, msg = pcall(userapi, data, pios)
                    if not res then log.error("远程查询的API错误:", msg) end
                    if convert == 0 and upprotFnc then -- 转换为用户自定义报文
                        res, msg = pcall(upprotFnc, msg)
                        if not res then log.error("数据流模版错误:", msg) end
                    end
                    if not c:send(msg) then break end
                elseif convert == 1 then -- 转换HEX String
                    sys.publish("NET_RECV_WAIT_" .. uid, uid, (data:fromHex()))
                elseif convert == 0 and dwprotFnc then -- 转换用户自定义报文
                    local res, msg = pcall(dwprotFnc, data)
                    if not res or not msg then
                        log.error("数据流模版错误:", msg)
                    else
                        sys.publish("NET_RECV_WAIT_" .. uid, uid, res and msg or data)
                    end
                else -- 默认不转换
                    sys.publish("NET_RECV_WAIT_" .. uid, uid, data)
                end
            elseif data == ("NET_SENT_RDY_" .. (passon and cid or uid)) then
                if convert == 1 then -- 转换为Hex String 报文
                    if not c:send((param:toHex())) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                elseif convert == 0 and upprotFnc then -- 转换为用户自定义报文
                    local res, msg = pcall(upprotFnc, param)
                    if not res or not msg then
                        log.error("数据流模版错误:", msg)
                    else
                        if not c:send(res and msg or param) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                    end
                else -- 默认不转换
                    if not c:send(param) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                end
                if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_OK\r\n") end
            elseif data == "timeout" then
                if not c:send(conver(ping)) then break end
            else
                break
            end
        end
        c:close()
        datalink = false
        sys.wait(5000)
    end
end
---------------------------------------------------------- MQTT 服务 ----------------------------------------------------------
local function listTopic(str, addImei, ProductKey, deviceName)
    local topics = str:split(";")
    if #topics == 1 and (not addImei or addImei == "") then
        topics[1] = topics[1]:sub(-1, -1) == "/" and topics[1] .. misc.getImei() or topics[1] .. "/" .. misc.getImei()
    else
        local tmp = {}
        for i = 1, #topics, 2 do
            tmp = topics[i]:split("/")
            for v = 1, #tmp do
                if tmp[v]:lower() == "imei" then tmp[v] = misc.getImei() end
                if tmp[v]:lower() == "muid" then tmp[v] = misc.getMuid() end
                if tmp[v]:lower() == "imsi" then tmp[v] = sim.getImsi() end
                if tmp[v]:lower() == "iccid" then tmp[v] = sim.getIccid() end
                if tmp[v]:lower() == "productid" then tmp[v] = ProductKey end
                if tmp[v]:lower() == "messageid" or tmp[v]:lower() == "${messageid}" then tmp[v] = "+" end
                if tmp[v]:lower() == "productkey" or tmp[v]:lower() == "${productkey}" or tmp[v]:lower() == "${yourproductkey}" then tmp[v] = ProductKey end
                if tmp[v]:lower() == "devicename" or tmp[v]:lower() == "${devicename}" or tmp[v]:lower() == "${yourdevicename}" then tmp[v] = deviceName end
            end
            topics[i] = table.concat(tmp, "/")
            log.info("订阅或发布主题:", i, topics[i])
        end
    end
    return topics
end

local function mqttTask(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, addr, port, usr, pwd, cleansession, sub, pub, qos, retain, uid, clientID, addImei, ssl, will, cert)
    cid, keepAlive, timeout, uid = tonumber(cid) or 1, tonumber(keepAlive) or 300, tonumber(timeout), tonumber(uid)
    cleansession, qos, retain = tonumber(cleansession) or 0, tonumber(qos) or 0, tonumber(retain) or 0
    clientID = (clientID == "" or not clientID) and misc.getImei() or clientID
    if timeout then sys.timerLoopStart(sys.publish, timeout * 1000, "AUTO_SAMPL_" .. uid) end
    if type(sub) == "string" then
        sub = listTopic(sub, addImei)
        local topics = {}
        for i = 1, #sub do
            topics[sub[i]] = tonumber(sub[i + 1]) or qos
        end
        sub = topics
    end
    if type(pub) == "string" then pub = listTopic(pub, addImei) end
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and loadstring(upprot[cid]:match("function(.+)end"))
    if not will or will == "" then will = nil else will = {qos = 1, retain = 0, topic = will, payload = misc.getImei()} end
    while true do
        local messageId, idx = false, 0
        if not socket.isReady() and not sys.waitUntil("IP_READY_IND", rstTim) then sys.restart("网络初始化失败!") end
        local mqttc = mqtt.client(clientID, keepAlive, conver(usr), conver(pwd), cleansession, will, "3.1.1")
        while not mqttc:connect(addr, port, ssl == "tcp_ssl" and ssl or nil, cert) do sys.wait((2 ^ idx) * 1000)idx = idx > 9 and 0 or idx + 1 end
        -- 初始化订阅主题
        if mqttc:subscribe(sub, qos) then
            if loginMsg(reg) then mqttc:publish(pub[1], loginMsg(reg), tonumber(pub[2]) or qos, retain) end
            while true do
                datalink = true
                local r, packet, param = mqttc:receive((timeout or 180) * 1000, "NET_SENT_RDY_" .. (passon and cid or uid))
                if r then
                    log.info("订阅的消息:", packet and packet.topic)
                    messageId = packet.topic:match(".+/rrpc/request/(%d+)")
                    -- 这里执行用户自定义的指令
                    if packet.payload:sub(1, 5) == "rrpc," or packet.payload:sub(1, 7) == "config," then
                        local res, msg = pcall(userapi, packet.payload, pios)
                        if not res then log.error("远程查询的API错误:", msg) end
                        if convert == 0 and upprotFnc then -- 转换为用户自定义报文
                            res, msg = pcall(upprotFnc, msg)
                            if not res then log.error("数据流模版错误:", msg) end
                        end
                        if not mqttc:publish(pub[1], msg, tonumber(pub[2]) or qos, retain) then break end
                    elseif convert == 1 then -- 转换为HEX String
                        sys.publish("UART_SENT_RDY_" .. uid, uid, (packet.payload:fromHex()))
                    elseif convert == 0 and dwprotFnc then -- 转换用户自定义报文
                        local res, msg = pcall(dwprotFnc, packet.payload)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        else
                            sys.publish("UART_SENT_RDY_" .. uid, uid, res and msg or packet.payload)
                        end
                    else -- 默认不转换
                        sys.publish("UART_SENT_RDY_" .. uid, uid, packet.payload)
                    end
                elseif packet == 'timeout' then
                    -- sys.publish("AUTO_SAMPL_" .. uid)
                    log.debug('The client timeout actively reports status information.')
                elseif packet == ("NET_SENT_RDY_" .. (passon and cid or uid)) then
                    if convert == 1 then -- 转换为Hex String 报文
                        if not mqttc:publish(pub[1], (param:toHex()), tonumber(pub[2]) or qos, retain) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                    elseif convert == 0 and upprotFnc then -- 转换为用户自定义报文
                        local res, msg, index = pcall(upprotFnc, param)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        else
                            index = tonumber(index) or 1
                            local pub_topic = (pub[index]:sub(-1, -1) == "+" and messageId) and pub[index]:sub(1, -2) .. messageId or pub[index]
                            log.info("-----发布的主题:", pub_topic)
                            if not mqttc:publish(pub_topic, res and msg or param, tonumber(pub[index + 1]) or qos, retain) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                        end
                    else
                        local pub_topic = (pub[1]:sub(-1, -1) == "+" and messageId) and pub[1]:sub(1, -2) .. messageId or pub[1]
                        log.info("-----发布的主题:", pub_topic)
                        if not mqttc:publish(pub_topic, param, tonumber(pub[2]) or qos, retain) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                    end
                    messageId = false
                    if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_OK\r\n") end
                    log.info('The client actively reports status information.')
                else
                    log.warn('The MQTTServer connection is broken.')
                    break
                end
            end
        end
        datalink = false
        mqttc:disconnect()
        sys.wait(1000)
    end
end
---------------------------------------------------------- OneNet 云服务器 ----------------------------------------------------------
-- OneNET注册设备，仅限于EDP|MQTT|HTTP|DTU
-- regcode:生产环境注册码
-- uid : 串口id
local function regOneNet(regcode, uid)
    for i = 1, 3 do
        local code, head, body = httpv2.request("POST", "http://api.heclouds.com/register_de", 10000, {register_code = regcode}, {title = tostring(os.time()), mac = misc.getImei() .. uid}, 2, nil)
        if tonumber(code) == 200 and body then
            log.info("OneNET返回的设备ID:", body)
            local dat, res, err = json.decode(body)
            if res and tonumber(dat.errno) == 0 then
                return dat
            end
        end
        sys.wait(5000)
    end

end
-- OneNET注册设备,Modbus
-- key: Master-APIkey
-- uid: 串口id
local function regModbus(key, uid)
    local headers = {
        ['User-Agent'] = 'Mozilla/4.0',
        ['Accept'] = '*/*',
        ['Accept-Language'] = 'zh-CN,zh,cn',
        ['Content-Type'] = 'application/x-www-form-urlencoded',
        ['Content-Length'] = '0',
        ['Connection'] = 'Keep-alive',
        ["Keep-Alive"] = 'timeout=20',
    }
    headers["api-key"] = key
    for i = 1, 3 do
        local code, head, body = httpv2.request("POST", "http://api.heclouds.com/devices", 10000, nil, {title = misc.getImei() .. uid, auth_info = {[sim.getIccid():sub(-10, -1) .. uid] = misc.getImei():sub(-7, -1) .. uid}}, 2, nil, headers)
        if tonumber(code) == 200 and body then
            log.info("OneNET返回的设备ID:", body)
        end
        local code, head, body = httpv2.request("GET", "http://api.heclouds.com/s?t=5", 10000, nil, 1, nil, headers)
        if tonumber(code) == 200 and body then
            log.info("OneNET返回的MODBUS设备的IP和地址:", body)
            return body:split(":")
        end
        sys.wait(5000)
    end
end
-- onenet DTU 协议支持
-- cid,通道ID
-- prot::"EDP | MQTT | HTTP | DTU",  //选择一种接入协议（可选，默认为HTTP,DTU对应TCP透传协议）
-- regcode: 设备注册码(正式生产环境注册码)
-- ParserName：脚本名称(上传脚本的时候指定的名称)
local function oneNet_DTU(cid, pios, reg, convert, passon, upprot, dwprot, ping, timeout, addr, port, regcode, pid, ParserName, uid, intervalTime, ssl)
    -- 获取注册的设备ID
    local dat = regOneNet(regcode, uid)
    local login = "*" .. pid .. "#" .. misc.getImei() .. uid .. "#" .. ParserName .. "*"
    tcpTask(cid, pios, reg, convert, passon, upprot, dwprot, "TCP", ping, timeout, addr, port, uid, nil, nil, intervalTime, ssl, login)
end

-- onenet modbus 协议支持
local function oneNet_modbus(cid, pios, reg, convert, passon, upprot, dwprot, timeout, key, pid, uid, intervalTime, ssl)
    local host = regModbus(key, uid)
    local phone = (sim.getIccid():sub(-10, -1) .. uid .. "\0"):toHex()
    local pwd = (misc.getImei():sub(-7, -1) .. uid .. "\0"):toHex()
    local pid = (pid .. string.rep("\0", 11 - #pid)):toHex()
    local login = "74797065000000000000006e616d650000000000" .. phone .. pwd .. pid
    tcpTask(cid, pios, reg, convert, passon, upprot, dwprot, "TCP", "\0\0", timeout, host[1], host[2], uid, nil, nil, intervalTime, ssl, login:fromHex())
end

-- onenet mqtt 协议支持
local function oneNet_mqtt(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, addr, port, regcode, pid, ptype, cleansession, qos, retain, uid)
    cid, keepAlive, timeout, uid = tonumber(cid) or 1, tonumber(keepAlive) or 300, tonumber(timeout), tonumber(uid)
    cleansession, qos, retain, ptype = tonumber(cleansession) or 0, tonumber(qos) or 0, tonumber(retain) or 0, tonumber(ptype) or 3
    if timeout then sys.timerLoopStart(sys.publish, timeout * 1000, "AUTO_SAMPL_" .. uid) end
    local dat = regOneNet(regcode, uid)
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and loadstring(upprot[cid]:match("function(.+)end"))
    while true do
        local idx, rsp = 0, false
        if not socket.isReady() and not sys.waitUntil("IP_READY_IND", rstTim) then sys.restart("网络初始化失败!") end
        local mqttc = mqtt.client(dat.data.device_id, keepAlive, pid, dat.data.key, cleanSession)
        while not mqttc:connect(addr, port) do sys.wait((2 ^ idx) * 1000)idx = idx > 9 and 0 or idx + 1 end
        if mqttc:subscribe("$creq/#", qos) then
            while true do
                datalink = true
                local r, packet, param = mqttc:receive((timeout or 180) * 1000, "NET_SENT_RDY_" .. (passon and cid or uid))
                -- log.info("MQTT 订阅的消息:", convert, packet.payload)
                if r then
                    rsp = packet.topic:match("$creq/(%g+)")
                    -- 主题类型-rrpc请求
                    if packet.payload:sub(1, 5) == "rrpc," or packet.payload:sub(1, 7) == "config," then
                        local res, msg = pcall(userapi, packet.payload, pios)
                        if not res then log.error("远程查询的API错误:", msg) end
                        if convert == 0 and upprotFnc then -- 转换为用户自定义报文
                            res, msg = pcall(upprotFnc, msg)
                            if not res then log.error("数据流模版错误:", msg) end
                        end
                        if msg then msg = pack.pack("b>HA", ptype, #msg, msg) end
                        if not mqttc:publish(rsp and "$crsp/" .. rsp or "$dp", msg, qos, retain) then break end
                        rsp = false
                    else
                        if convert == 1 then -- 转换为HEX String
                            sys.publish("UART_SENT_RDY_" .. uid, uid, (packet.payload:fromHex()))
                        elseif convert == 0 and dwprotFnc then -- 转换用户自定义报文
                            local res, msg = pcall(dwprotFnc, packet.payload)
                            if not res or not msg then
                                log.error("数据流模版错误:", msg)
                            else
                                sys.publish("UART_SENT_RDY_" .. uid, uid, res and msg or packet.payload)
                            end
                        else
                            sys.publish("UART_SENT_RDY_" .. uid, uid, packet.payload)
                        end
                    end
                elseif packet == 'timeout' then
                    -- sys.publish("AUTO_SAMPL_" .. uid)
                    log.debug('The client timeout actively reports status information.')
                elseif packet == ("NET_SENT_RDY_" .. (passon and cid or uid)) then
                    if convert == 1 then -- 转换为Hex String 报文
                        if param then param = pack.pack("b>HA", ptype, #param, param) end
                        if not mqttc:publish(rsp and "$crsp/" .. rsp or "$dp", (param:toHex()), qos, retain) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                    elseif convert == 0 and upprotFnc then -- 转换为用户自定义报文
                        local res, msg = pcall(upprotFnc, param)
                        if not res or not msg then
                            log.error("数据流模版错误:", msg)
                        else
                            if msg then msg = pack.pack("b>HA", ptype, #msg, msg) end
                            if not mqttc:publish(rsp and "$crsp/" .. rsp or "$dp", msg, qos, retain) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                        end
                    else -- 不转换报文
                        if param then param = pack.pack("b>HA", ptype, #param, param) end
                        if not mqttc:publish(rsp and "$crsp/" .. rsp or "$dp", param, qos, retain) then if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_ERROR\r\n") end break end
                    end
                    rsp = false
                    if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_OK\r\n") end
                    log.info('The client actively reports status information.')
                else
                    log.warn('The MQTTServer connection is broken.')
                    break
                end
            end
        end
        datalink = false
        mqttc:disconnect()
        sys.wait(1000)
    end
end
---------------------------------------------------------- 阿里IOT云 ----------------------------------------------------------
local alikey = "/alikey.cnf"
-- 处理表的RFC3986编码
function table.rawurlEncode(t)
    local msg = {}
    for k, v in table.gsort(t) do
        table.insert(msg, string.rawurlEncode(k) .. '=' .. string.rawurlEncode(v))
        table.insert(msg, '&')
    end
    table.remove(msg)
    return table.concat(msg)
end
local function aliCommonParam(Action, RegionId, ProductKey, AccessKeyId, AccessKeySecret)
    AccessKeySecret = AccessKeySecret .. "&"
    local param = {
        Format = "JSON",
        Version = "2018-01-20",
        AccessKeyId = AccessKeyId,
        SignatureMethod = "HMAC-SHA1",
        Timestamp = "",
        SignatureVersion = "1.0",
        SignatureNonce = os.time() .. "",
        RegionId = RegionId,
        Action = Action,
        ProductKey = ProductKey,
        DeviceName = misc.getImei()
    }
    local c = os.date("!*t")
    param.Timestamp = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", c.year, c.month, c.day, c.hour, c.min, c.sec)
    local StringToSign = "GET&%2F&" .. table.rawurlEncode(param):rawurlEncode()
    local Signature = crypto.hmac_sha1(StringToSign, #StringToSign, AccessKeySecret, #AccessKeySecret)
    param.Signature = crypto.base64_encode(Signature:fromHex())
    return table.rawurlEncode(param)
end
local function registerDevice(RegionId, ProductKey, AccessKeyId, AccessKeySecret)
    if io.exists(alikey) then
        local dat, res, err = json.decode(io.readFile(alikey))
        if res then return dat.Data.DeviceName, dat.Data.DeviceSecret end
    end
    local param = aliCommonParam("RegisterDevice", RegionId, ProductKey, AccessKeyId, AccessKeySecret)
    for i = 1, 3 do
        local code, head, body = httpv2.request("GET", "https://iot." .. RegionId .. ".aliyuncs.com/?" .. param, 10000, nil, nil, 2)
        if tonumber(code) == 200 and body then
            local dat, result, errinfo = json.decode(body)
            if result then
                if dat.Success and dat.Data then
                    io.writeFile(alikey, body)
                    return dat.Data.DeviceName, dat.Data.DeviceSecret
                elseif dat.Code == "iot.device.AlreadyExistedDeviceName" then
                    break
                end
            end
        end
        log.warn("阿里云注册请求失败:", code, body)
        sys.wait(5000)
    end
    param = aliCommonParam("QueryDeviceDetail", RegionId, ProductKey, AccessKeyId, AccessKeySecret)
    for i = 1, 3 do
        local code, head, body = httpv2.request("GET", "https://iot." .. RegionId .. ".aliyuncs.com/?" .. param, 10000, nil, nil, 2)
        if tonumber(code) == 200 and body then
            local dat, result, errinfo = json.decode(body)
            if result and dat.Success and dat.Data then
                io.writeFile(alikey, body)
                return dat.Data.DeviceName, dat.Data.DeviceSecret
            end
        end
        sys.wait(5000)
    end
end
local function getOneSecret(RegionId, ProductKey, ProductSecret)
    if io.exists(alikey) then
        local dat, res, err = json.decode(io.readFile(alikey))
        if res then
            return dat.data.deviceName, dat.data.deviceSecret
        end
    end
    local random = rtos.tick()
    local data = "deviceName" .. misc.getImei() .. "productKey" .. ProductKey .. "random" .. random
    local sign = crypto.hmac_md5(data, #data, ProductSecret, #ProductSecret)
    local body = "productKey=" .. ProductKey .. "&deviceName=" .. misc.getImei() .. "&random=" .. random .. "&sign=" .. sign .. "&signMethod=HmacMD5"
    for i = 1, 3 do
        local code, head, body = httpv2.request("POST", "https://iot-auth." .. RegionId .. ".aliyuncs.com/auth/register/device", 10000, nil, body, 1)
        if tonumber(code) == 200 and body then
            local dat, result, errinfo = json.decode(body)
            if result and dat.message and dat.data then
                io.writeFile(alikey, body)
                return dat.data.deviceName, dat.data.deviceSecret
            end
        end
        log.warn("阿里云查询请求失败:", code, body)
        sys.wait(5000)
    end
end

-- 一机一密方案，所有方案最终都会到这里执行
local function aliyunOmok(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, RegionId, ProductKey, deviceSecret, deviceName, ver, cleansession, qos, uid, sub, pub)
    cid, keepAlive, timeout, uid = tonumber(cid) or 1, tonumber(keepAlive) or 300, tonumber(timeout), tonumber(uid)
    cleansession, qos = tonumber(cleansession) or 0, tonumber(qos) or 0
    local data = "clientId" .. sim.getIccid() .. "deviceName" .. deviceName .. "productKey" .. ProductKey
    local usr = deviceName .. "&" .. ProductKey
    local pwd = crypto.hmac_sha1(data, #data, deviceSecret, #deviceSecret)
    local clientID = sim.getIccid() .. "|securemode=3,signmethod=hmacsha1|"
    local addr = ProductKey .. ".iot-as-mqtt." .. RegionId .. ".aliyuncs.com"
    local port = 1883
    if type(sub) ~= "string" or sub == "" then
        sub = ver:lower() == "basic" and "/" .. ProductKey .. "/" .. deviceName .. "/get" or "/" .. ProductKey .. "/" .. deviceName .. "/user/get"
    else
        sub = listTopic(sub, "addImei", ProductKey, deviceName)
        local topics = {}
        for i = 1, #sub do
            topics[sub[i]] = tonumber(sub[i + 1]) or qos
        end
        sub = topics
    end
    if type(pub) ~= "string" or pub == "" then
        pub = ver:lower() == "basic" and "/" .. ProductKey .. "/" .. deviceName .. "/update" or "/" .. ProductKey .. "/" .. deviceName .. "/user/update"
    else
        pub = listTopic(pub, "addImei", ProductKey, deviceName)
    end
    local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and loadstring(dwprot[cid]:match("function(.+)end"))
    local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and loadstring(upprot[cid]:match("function(.+)end"))
    mqttTask(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, addr, port, usr, pwd, cleansession, sub, pub, qos, retain, uid, clientID, "addImei", ssl, will)

end
-- API 自动注册方案
local function aliyunAuto(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, RegionId, ProductKey, AccessKeyId, AccessKeySecret, ver, cleansession, qos, uid, sub, pub)
    local deviceName, deviceSecret = registerDevice(RegionId, ProductKey, AccessKeyId, AccessKeySecret, uid)
    if not deviceName or not deviceSecret then
        log.error("阿里云注册失败:", AccessKeyId, AccessKeySecret)
        return
    end
    log.warn("自动注册返回三元组:", deviceName ~= nil, deviceSecret ~= nil)
    aliyunOmok(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, RegionId, ProductKey, deviceSecret, deviceName, ver, cleansession, qos, uid, sub, pub)
end
-- 一型一密认证方案
local function aliyunOtok(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, RegionId, ProductKey, ProductSecret, ver, cleansession, qos, uid, sub, pub)
    local deviceName, deviceSecret = getOneSecret(RegionId, ProductKey, ProductSecret)
    if not deviceName or not deviceSecret then
        log.error("阿里云注册失败:", AccessKeyId, AccessKeySecret)
        return
    end
    log.warn("一型一密动态注册返回三元组:", deviceName ~= nil, deviceSecret ~= nil)
    aliyunOmok(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, RegionId, ProductKey, deviceSecret, deviceName, ver, cleansession, qos, uid, sub, pub)
end

---------------------------------------------------------- 百度天工 ----------------------------------------------------------
-- 设备型注册
local function bdiotDeviceReg(regio, schemaId, ak, sk)
    local host = "iotdm." .. regio .. ".baidubce.com"
    if not socket.isReady() and not sys.waitUntil("IP_READY_IND", rstTim) then sys.restart("网络初始化失败!") end
    local data = {
        deviceName = misc.getImei(),
        description = sim.getIccid(),
        schemaId = schemaId,
    }
    local function getHeader(host, ak, sk, action)
        local headers = {Host = host}
        local canonicalURI = action == "update" and "/v3/iot/management/device/" .. misc.getImei() or "/v3/iot/management/device"
        local canonicalHeaders = "host:" .. host:rawurlEncode()
        local canonicalRequest = (action == "update" and "PUT\n" or "POST\n") .. canonicalURI .. "\n" .. (action == "update" and "updateSecretKey=" or "") .. "\n" .. canonicalHeaders
        local c = os.date("!*t")
        local Timestamp = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", c.year, c.month, c.day, c.hour, c.min, c.sec)
        local authStringPrefix = "bce-auth-v1/" .. ak .. "/" .. Timestamp .. "/1800"
        local singinKey = crypto.hmac_sha256(authStringPrefix, sk):lower()
        local Signature = crypto.hmac_sha256(canonicalRequest, singinKey):lower()
        headers["Authorization"] = authStringPrefix .. "/host/" .. Signature
        return headers, host .. canonicalURI
    end
    if io.exists("/bdiot.cnf") then
        local dat, res, err = json.decode(io.readFile("/bdiot.cnf"))
        if res then return dat end
    end
    for i = 1, 3 do
        -- 注册设备
        local header, url = getHeader(host, ak, sk, "reg")
        local code, head, body = httpv2.request("POST", url, 10000, nil, data, 2, nil, header)
        log.info("BaiDu返回的设备注册信息:", body)
        if body then
            local dat, result, errinfo = json.decode(body)
            if result and dat.username then
                io.writeFile("/bdiot.cnf", body)
                return dat
            end
        end
        -- 如果设备已经存在就重置设备密码
        local header, url = getHeader(host, ak, sk, "update")
        local code, head, body = httpv2.request("PUT", url .. "?updateSecretKey", 10000, nil, data, 2, nil, header)
        log.info("BaiDu返回的设备更新信息:", body)
        if body then
            local dat, result, errinfo = json.decode(body)
            if result and dat.username then
                io.writeFile("/bdiot.cnf", body)
                return dat
            end
        end
        sys.wait(5000)
    end
end
-- 数据型注册
local function bdiotDataReg(regio, endpoint, ak, sk, principal, pk)
    local host = "iot." .. regio .. ".baidubce.com"
    local login = {}
    login.tcpEndpoint = "tcp://" .. endpoint .. ".mqtt.iot." .. regio .. ".baidubce.com:1883"
    login.sslEndpoint = "ssl://" .. endpoint .. ".mqtt.iot." .. regio .. ".baidubce.com:1884"
    if not socket.isReady() and not sys.waitUntil("IP_READY_IND", rstTim) then sys.restart("网络初始化失败!") end
    local data = {
        thingName = misc.getImei(),
        endpointName = endpoint,
        principalName = principal
    }
    local function getHeader(host, endpoint, ak, sk, action)
        local headers = {Host = host}
        local canonicalURI = action == "attach" and "/v1/action/attach-thing-principal" or "/v1/endpoint/" .. endpoint .. "/thing"
        local canonicalHeaders = "host:" .. host:rawurlEncode()
        local canonicalRequest = "POST\n" .. canonicalURI .. "\n" .. "" .. "\n" .. canonicalHeaders
        local c = os.date("!*t")
        local Timestamp = string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", c.year, c.month, c.day, c.hour, c.min, c.sec)
        local authStringPrefix = "bce-auth-v1/" .. ak .. "/" .. Timestamp .. "/1800"
        local singinKey = crypto.hmac_sha256(authStringPrefix, sk):lower()
        local Signature = crypto.hmac_sha256(canonicalRequest, singinKey):lower()
        headers["Authorization"] = authStringPrefix .. "/host/" .. Signature
        return headers, host .. canonicalURI
    end
    if io.exists("/bdiot.dat") then
        local dat, res, err = json.decode(io.readFile("/bdiot.dat"))
        if res then return dat end
    end
    for i = 1, 3 do
        -- 注册设备
        local header, url = getHeader(host, endpoint, ak, sk, "reg")
        local code, head, body = httpv2.request("POST", url, 10000, nil, data, 2, nil, header)
        log.info("BaiDu返回的设备注册信息:", body)
        if body then
            local dat, result, errinfo = json.decode(body)
            if result and dat.username then
                login.username = dat.username
                login.key = pk
            end
        end
        -- 如果设备已经存在就重置设备密码
        local header, url = getHeader(host, endpoint, ak, sk, "attach")
        local code, head, body = httpv2.request("POST", url, 10000, nil, data, 2, nil, header)
        log.info("BaiDu返回的设备更新信息:", body)
        if body then
            local dat, result, errinfo = json.decode(body)
            if result and dat.message then
                io.writeFile("/bdiot.dat", json.encode(login))
                return login
            end
        end
        sys.wait(5000)
    end
end
-- sys.taskInit(bdiotDeviceReg, "gz", "6b70b03b-ef76-4966-8aed-79ddb068afb3", "d046057ca2664ef6a0b785407a94e6ff", "03a1f3358a7c457a92040d3cd79526ea")
-- sys.taskInit(bdiotDataReg, "gz", "91k8gp4", "d046057ca2664ef6a0b785407a94e6ff", "03a1f3358a7c457a92040d3cd79526ea", "device", "l5t4chXaoFclITJQ")
local function bdiotDevice(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, regio, schemaId, ak, sk, cleansession, qos, uid, ssl)
    local msg = bdiotDeviceReg(regio, schemaId, ak, sk)
    if not msg then
        log.warn("-------------------百度天工物接入失败-----------------------", "fail")
        return
    end
    ssl = ssl:lower()
    local host = ssl == "tcp_ssl" and msg.sslEndpoint or msg.tcpEndpoint
    local addr, port = host:match("//(.+):(%d+)")
    local sub = "$baidu/iot/shadow/" .. misc.getImei() .. "/delta"
    local pub = "$baidu/iot/shadow/" .. misc.getImei() .. "/update"
    mqttTask(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, addr, port, msg.username, msg.key, cleansession, sub, pub, qos, retain, uid, nil, "addImei", ssl)
end
local function bdiotData(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, regio, endpoint, ak, sk, principal, pk, sub, pub, cleansession, qos, uid, ssl, will)
    local msg = bdiotDataReg(regio, endpoint, ak, sk, principal, pk)
    if not msg then
        log.warn("-------------------百度天工物接入失败-----------------------", "fail")
        return
    end
    ssl = ssl:lower()
    local host = ssl == "tcp_ssl" and msg.sslEndpoint or msg.tcpEndpoint
    local addr, port = host:match("//(.+):(%d+)")
    mqttTask(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, addr, port, msg.username, msg.key, cleansession, sub, pub, qos, retain, uid, nil, "addImei", ssl, will)
end
---------------------------------------------------------- 腾讯IOT云 ----------------------------------------------------------
function txiot(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, Region, ProductId, SecretId, SecretKey, sub, pub, cleansession, qos, uid)
    if not io.exists("/qqiot.dat") then
        local version = (not ver or ver == "") and "2018-06-14" or ver
        local data = {ProductId = ProductId, DeviceName = misc.getImei()}
        local timestamp = os.time()
        local head = {
            ["X-TC-Action"] = "CreateDevice",
            ["X-TC-Timestamp"] = timestamp,
            ["X-TC-Version"] = (not ver or ver == "") and "2018-06-14" or ver,
            ["X-TC-Region"] = (not Region or Region == "") and "ap-guangzhou" or Region,
            ["Content-Type"] = "application/json",
            Authorization = "TC3-HMAC-SHA256 Credential=" .. SecretId .. "/"
        }
        local SignedHeaders = "content-type;host"
        local CanonicalRequest = "POST\n/\n\ncontent-type:application/json\nhost:iotcloud.tencentcloudapi.com\n\n" .. SignedHeaders .. "\n" .. crypto.sha256(json.encode(data)):lower()
        local c = os.date("!*t")
        local date = string.format("%04d-%02d-%02d", c.year, c.month, c.day)
        local CredentialScope = date .. "/iotcloud/tc3_request"
        local StringToSign = "TC3-HMAC-SHA256\n" .. timestamp .. "\n" .. CredentialScope .. "\n" .. crypto.sha256(CanonicalRequest):lower()
        local SecretDate = crypto.hmac_sha256(date, "TC3" .. SecretKey):fromHex()
        local SecretService = crypto.hmac_sha256("iotcloud", SecretDate):fromHex()
        local SecretSigning = crypto.hmac_sha256("tc3_request", SecretService):fromHex()
        local Signature = crypto.hmac_sha256(StringToSign, SecretSigning):lower()
        head.Authorization = head.Authorization .. CredentialScope .. ",SignedHeaders=" .. SignedHeaders .. ",Signature=" .. Signature
        for i = 1, 3 do
            local code, head, body = httpv2.request("POST", "https://iotcloud.tencentcloudapi.com", 10000, nil, data, 2, nil, head)
            if body then
                local dat, result, errinfo = json.decode(body)
                if result then
                    if not dat.Response.Error then
                        io.writeFile("/qqiot.dat", body)
                    -- log.info("腾讯云注册设备成功:", body)
                    else
                        log.info("腾讯云注册设备失败:", body)
                    end
                    break
                end
            end
            sys.wait(5000)
        end
    end
    if not io.exists("/qqiot.dat") then
        log.warn("腾讯云设备注册失败或不存在设备信息!")
        return
    end
    if type(sub) ~= "string" or sub == "" then
        sub = ProductId .. "/" .. misc.getImei() .. "/control"
    else
        sub = listTopic(sub, "addImei", ProductId, misc.getImei())
        local topics = {}
        for i = 1, #sub do
            topics[sub[i]] = tonumber(sub[i + 1]) or qos
        end
        sub = topics
    end
    if type(pub) ~= "string" or pub == "" then
        pub = ProductId .. "/" .. misc.getImei() .. "/event"
    else
        pub = listTopic(pub, "addImei", ProductId, misc.getImei())
    end
    local dat = json.decode(io.readFile("/qqiot.dat"))
    local clientID = ProductId .. misc.getImei()
    local connid = rtos.tick()
    local expiry = tostring(os.time() + 3600)
    local usr = string.format("%s;12010126;%s;%s", clientID, connid, expiry)
    local raw_key = crypto.base64_decode(dat.Response.DevicePsk, #dat.Response.DevicePsk)
    local pwd = crypto.hmac_sha256(usr, raw_key):lower() .. ";hmacsha256"
    local addr, port = "iotcloud-mqtt.gz.tencentdevices.com", 1883
    mqttTask(cid, pios, reg, convert, passon, upprot, dwprot, keepAlive, timeout, addr, port, usr, pwd, cleansession, sub, pub, qos, retain, uid, clientID, addImei, ssl, will)
end
---------------------------------------------------------- 参数配置,任务转发，线程守护主进程----------------------------------------------------------
function connect(pios, conf, reg, convert, passon, upprot, dwprot)
    local flyTag = false
    if not socket.isReady() and not sys.waitUntil("IP_READY_IND", rstTim) then sys.restart("网络初始化失败!") end
    sys.waitUntil("DTU_PARAM_READY", 120000)
    -- 自动创建透传任务并填入参数
    for k, v in pairs(conf or {}) do
        -- log.info("Task parameter information:", k, pios, reg, convert, passon, upprot, dwprot, unpack(v))
        if v[1] and (v[1]:upper() == "TCP" or v[1]:upper() == "UDP") then
            log.warn("----------------------- TCP/UDP is start! --------------------------------------")
            sys.taskInit(tcpTask, k, pios, reg, convert, passon, upprot, dwprot, unpack(v))
        elseif v[1] and v[1]:upper() == "MQTT" then
            log.warn("----------------------- MQTT is start! --------------------------------------")
            sys.taskInit(mqttTask, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 2))
        elseif v[1] and v[1]:upper() == "HTTP" then
            log.warn("----------------------- HTTP is start! --------------------------------------")
            sys.taskInit(function(cid, convert, passon, upprot, dwprot, uid, method, url, timeout, way, dtype, basic, headers, iscode, ishead, isbody)
                cid, timeout, uid = tonumber(cid) or 1, tonumber(timeout) or 30, tonumber(uid) or 1
                way, dtype = tonumber(way) or 1, tonumber(dtype) or 1
                local dwprotFnc = dwprot and dwprot[cid] and dwprot[cid] ~= "" and loadstring(dwprot[cid]:match("function(.+)end"))
                local upprotFnc = upprot and upprot[cid] and upprot[cid] ~= "" and loadstring(upprot[cid]:match("function(.+)end"))
                while true do
                    datalink = socket.isReady()
                    local result, msg = sys.waitUntil("NET_SENT_RDY_" .. (passon and cid or uid))
                    if result and msg then
                        if convert == 1 then -- 转换为Hex String 报文
                            msg = msg:toHex()
                        elseif convert == 0 and upprotFnc then -- 转换为用户自定义报文
                            local res, dat = pcall(upprotFnc, msg)
                            if not res or not msg then log.error("数据流模版错误:", msg) end
                            msg = res and dat or msg
                        end
                        if passon then sys.publish("UART_SENT_RDY_" .. uid, uid, "SEND_OK\r\n") end
                        local code, head, body = httpv2.request(method:upper(), url, timeout * 1000, way == 0 and msg or nil, way == 1 and msg or nil, dtype, basic, headers)
                        local headstr = ""
                        if type(head) == "table" then
                            for k, v in pairs(head) do headstr = headstr .. k .. ": " .. v .. "\r\n" end
                        else
                            headstr = head
                        end
                        if convert == 1 then -- 转换HEX String
                            local str = (tonumber(iscode) ~= 1 and code .. "\r\n" or "") .. (tonumber(ishead) ~= 1 and headstr or "") .. (tonumber(isbody) ~= 1 and body and (body:fromHex()) or "")
                            sys.publish("NET_RECV_WAIT_" .. uid, uid, str)
                        elseif convert == 0 and dwprotFnc then -- 转换用户自定义报文
                            local res, code, head, body = pcall(dwprotFnc, code, head, body)
                            if not res or not msg then
                                log.error("数据流模版错误:", msg)
                            else
                                local str = (tonumber(iscode) ~= 1 and code .. "\r\n" or "") .. (tonumber(ishead) ~= 1 and headstr or "") ~= 1 .. (tonumber(isbody) ~= 1 and body or "")
                                sys.publish("NET_RECV_WAIT_" .. uid, uid, res and str or code)
                            end
                        else -- 默认不转换
                            sys.publish("NET_RECV_WAIT_" .. uid, uid, (tonumber(iscode) ~= 1 and code .. "\r\n" or "") .. (tonumber(ishead) ~= 1 and headstr or "") .. (tonumber(isbody) ~= 1 and body or ""))
                        end
                    end
                    sys.wait(100)
                end
            end, k, convert, passon, upprot, dwprot, unpack(v, 2))
        elseif v[1] and v[1]:upper() == "ONENET" then
            log.warn("----------------------- OneNET is start! --------------------------------------")
            if v[2]:upper() == "DTU" then
                sys.taskInit(oneNet_DTU, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            elseif v[2]:upper() == "MQTT" then
                sys.taskInit(oneNet_mqtt, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            elseif v[2]:upper() == "HTTP" then
                sys.taskInit(oneNet_http, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            elseif v[2]:upper() == "EDP" then
                sys.taskInit(oneNet_edp, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            elseif v[2]:upper() == "MODBUS" then
                sys.taskInit(oneNet_modbus, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            end
        elseif v[1] and v[1]:upper() == "BDIOT" then
            log.warn("----------------------- BaiDu iot is start! --------------------------------------")
            while not ntp.isEnd() do sys.wait(1000) end
            if v[2]:upper() == "DEVICETYPE" then
                sys.taskInit(bdiotDevice, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            elseif v[2]:upper() == "DATATYPE" then
                sys.taskInit(bdiotData, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            end
        elseif v[1] and v[1]:upper() == "ALIYUN" then
            log.warn("----------------------- Aliyun iot is start! --------------------------------------")
            while not ntp.isEnd() do sys.wait(1000) end
            if v[2]:upper() == "AUTO" then
                sys.taskInit(aliyunAuto, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            elseif v[2]:upper() == "OTOK" then -- 一型一密
                sys.taskInit(aliyunOtok, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            elseif v[2]:upper() == "OMOK" then -- 一机一密
                sys.taskInit(aliyunOmok, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 3))
            end
        elseif v[1] and v[1]:upper() == "TXIOT" then
            log.warn("----------------------- tencent iot is start! --------------------------------------")
            while not ntp.isEnd() do sys.wait(1000) end
            sys.taskInit(txiot, k, pios, reg, convert, passon, upprot, dwprot, unpack(v, 2))
        end
    end
    -- 守护进程
    while true do
        -- 这里是网络正常,但是链接服务器失败重启
        if datalink then sys.timerStart(sys.restart, rstTim, "Server connection failed") end
        sys.wait(1000)
    end
end
net.switchFly(false)
-- NTP同步失败强制重启
local tid = sys.timerStart(function()
    net.switchFly(true)
    sys.timerStart(net.switchFly, 5000, false)
end, flyTim)
sys.subscribe("IP_READY_IND", function()
    sys.timerStop(tid)
    log.info("---------------------- 网络注册已成功 ----------------------")
end)
