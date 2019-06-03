--- 模块功能：GPS TRACKERE 主逻辑
-- @author openLuat
-- @module default
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.27
require "net"
require "misc"
require "mqtt"
require "gpsv2"
require "utils"
require "update"
module(..., package.seeall)

-- 解除报警的等待时间秒,GPS打开的起始时间utc秒
local clearTime, startTime = 300, 0
-- 轨迹消息缓冲区
local trackFile = {{}, {}, {}, {}, {}, {}, {}, {}, {}, {}}
-- 传感器数据
local sens = {
    vib = false, -- 震动检测
    acc = false, -- 开锁检测
    act = false, -- 启动检测
    chg = false, -- 充电检测
    und = false, -- 剪线检测
    wup = false, -- 唤醒检测
    vcc = 0, -- 电池电压
}
----------------------------------------------------------传感器部分----------------------------------------------------------
-- 配置GPS用到的IO: led脚，vib震动输入脚，ACC输入脚,内置电池充电状态监视脚,adc通道,分压比
function sensMonitor(ledio, vibio, accio, chgio, adcid, ratio)
    -- 点火监测采样队列
    local powerVolt, adcQue, acc, chg = 0, {0, 0, 0, 0, 0}
    -- GPS 定位成功指示灯
    if ledio and default.pios[ledio] then
        default.pios[ledio] = nil
        local led = pins.setup(tonumber(ledio:sub(4, -1)), 0)
        sys.subscribe("GPS_MSG_REPORT", led)
    end
    -- 震动传感器检测
    if vibio and default.pios[vibio] then
        pins.setup(tonumber(vibio:sub(4, -1)), function(msg) if msg == cpu.INT_GPIO_NEGEDGE then sens.vib = true end end, pio.PULLUP)
        default.pios[vibio] = nil
    end
    -- ACC开锁检测
    if accio and default.pios[accio] then
        acc = pins.setup(tonumber(accio:sub(4, -1)), nil, pio.PULLUP)
        default.pios[accio] = nil
    end
    -- 内置锂电池充电状态监控脚
    if chgio and default.pios[chgio] then
        chg = pins.setup(tonumber(chgio:sub(4, -1)), nil, pio.PULLUP)
        default.pios[chgio] = nil
    end
    adc.open(tonumber(adcid) or 0)
    while true do
        local adcValue, voltValue = adc.read(tonumber(adcid) or 0)
        if adcValue ~= 0xFFFF or voltValue ~= 0xFFFF then
            voltValue = voltValue * (tonumber(ratio)) / 3
            -- 点火检测部分
            powerVolt = (adcQue[1] + adcQue[2] + adcQue[3] + adcQue[4] + adcQue[5]) / 5
            table.remove(adcQue, 1)
            table.insert(adcQue, voltValue)
            if voltValue + 1500 < powerVolt or voltValue - 1500 > powerVolt then
                sens.act = true
            else
                sens.act = false
            end
        end
        sens.acc, sens.chg = acc and acc() == 0, chg and chg() == 0
        sens.vcc, sens.und = voltValue, voltValue < 4000
        sys.wait(1000)
        sens.vib = false
    end
    adc.close(tonumber(adcid) or 0)
end

----------------------------------------------------------设备逻辑任务----------------------------------------------------------
-- 上报设备状态,这里是用户自定义上报报文的顺序的
-- sta = {"isopen", "vib", "acc", "act", "chg", "und", "volt", "vbat", "csq"}
function deviceMessage(format)
    if format:lower() ~= "hex" then
        return json.encode({
            sta = {gpsv2.isOpen(), sens.vib, sens.acc, sens.act, sens.chg, sens.und, sens.vcc, misc.getVbatt(), net.getRssi()}
        })
    else
        return pack.pack(">b7IHb", 0x55, gpsv2.isOpen() and 1 or 0, sens.vib and 1 or 0,
            sens.acc and 1 or 0, sens.act and 1 or 0, sens.chg and 1 or 0, sens.und and 1 or 0, sens.vcc, misc.getVbatt(), net.getRssi())
    end
end

-- 上传定位信息
-- [是否有效,经度,纬度,海拔,方位角,速度,载噪比,定位卫星,时间戳]
-- 用户自定义上报GPS数据的报文顺序
-- msg = {"isfix", "stamp", "lng", "lat", "altitude", "azimuth", "speed", "sateCno", "sateCnt"},
function locateMessage(format)
    local isFix = gpsv2.isFix()
    local lng, lat = gpsv2.getIntLocation()
    local altitude = gpsv2.getAltitude()
    local azimuth = gpsv2.getAzimuth()
    local speed = gpsv2.getSpeed()
    local sateCnt = gpsv2.getUsedSateCnt()
    local sateCno = gpsv2.getCno()
    table.sort(sateCno)
    sateCno = table.remove(sateCno) or 0
    if format:lower() ~= "hex" then
        return json.encode({msg = {isFix, os.time(), lng, lat, altitude, azimuth, speed, sateCno, sateCnt}})
    else
        return pack.pack(">b2i3H2b3", 0xAA, isFix and 1 or 0, os.time(), lng, lat, altitude, azimuth, speed, sateCno, sateCnt)
    end
end

-- 用户捆绑GPS的串口,波特率，功耗模式，采集间隔,采集方式支持触发和持续, 报文数据格式支持 json 和 hex，缓冲条数,数据分隔符(不包含,),状态报文间隔分钟
function alert(uid, baud, pwmode, sleep, guard, format, num, sep, interval, cid)
    uid, baud, pwmode, sleep, num = tonumber(uid), tonumber(baud), tonumber(pwmode), tonumber(sleep), tonumber(num) or 0
    guard, interval = tonumber(guard) == 0, (tonumber(interval) or 0) * 60000
    local cnt, report = 0, function(format)sys.publish("NET_SENT_RDY_" .. tonumber(cid) or uid, deviceMessage(format)) end
    while true do
        -- 布防判断
        if not gpsv2.isOpen() and (not guard or sens.vib or sens.acc or sens.act or sens.und or sens.wup) then
            sens.wup = false
            startTime = os.time()
            -- GPS TRACKER 模式
            gpsv2.open(uid, baud, pwmode, sleep)
            -- 布防上报
            report(format)
            if interval ~= 0 then sys.timerLoopStart(report, interval, format) end
        end
        while gpsv2.isOpen() do
            -- 撤防判断
            if os.difftime(os.time(), startTime) > clearTime then
                if guard and sens.vib and sens.acc and sens.act and sens.und and gpsv2.getSpeed() == 0 then
                    sys.timerStopAll(report)
                    gpsv2.close(uid)
                else
                    startTime = os.time()
                end
            end
            -- 上报消息
            if sys.waitUntil("GPS_MSG_REPORT") then
                if num == 0 then
                    sys.publish("NET_SENT_RDY_" .. tonumber(cid) or uid, locateMessage(format))
                else
                    cnt = cnt < num and cnt + 1 or 0
                    table.insert(trackFile, locateMessage(format))
                    if cnt == 0 then sys.publish("NET_SENT_RDY_" .. tonumber(cid) or uid, table.concat(trackFile, sep)) end
                end
            end
            sys.wait(100)
        end
        sys.wait(100)
    end
end

-- NTP同步后清零一次startTime,避免第一次开机的时候utc时间跳变
sys.subscribe("NTP_SUCCEED", function()startTime = os.time() end)
-- 订阅服务器远程唤醒指令
sys.subscribe("REMOTE_WAKEUP", function()sens.wup = true end)
