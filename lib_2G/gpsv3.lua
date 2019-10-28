--- 模块功能：GPS模块管理
-- @module gpsv3
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.08.28
require "pm"
require "common"
require "httpv2"
require "utils"
require "lbsLoc"
module(..., package.seeall)

-- 窜口id,发布消息定时器ID,功耗模式标记
local uartID, uartRate, tid, tcnt = 2, 115200, 0, 0, 0
-- 浮点支持
local float = rtos.get_version():upper():find("FLOAT")
-- 写入星历时间
local GPD_TIME = "/ephdat.tim"
-- 设置星历和基站定位的循环定时器时间
local EPH_UPDATE_INTERVAL = 4 * 3600
--GPS定位标志，true表示，其余表示未定位,hdop 水平精度
local pdop, hdop, vdop = 0, 0, 0
-- 基站定位坐标
local lbs_lng, lbs_lat = 0, 0
-- 大地高，度分经度，度分纬度
local sep, ggalng, ggalat = 0, "0.0", "0.0"
-- 海拔，时速, 海里, 方向角
local altitude, speed, mile, azimuth = 0, 0, 0, 0
-- 参与定位的卫星个数,GPS和北斗可见卫星个数
local usedSateCnt, viewBdSateCnt, viewGpSateCnt = 0, 0, 0
-- 定位指示，UTC时间,定位用卫星号，GPGSV解析后的CNO信息
local posType, utcTime, sateSn, cnoBd, cnoGp, gsvBd, gsvGp = 0, 0, {}, {0}, {0}, {}, {}
-- 星历写入标记,GPS开启标记，定位成功标记,日志开关
local ephFlag, openFlag, fixFlag, isLog, fastFixFlag = false, false, false, true, false

local process = {
    ["GGA"] = function(t)
        gpsFind = tonumber(t[6]) or 0
        fixFlag = gpsFind ~= 0
        usedSateCnt = tonumber(t[7]) or 0
        ggalng, ggalat = (t[5] == "W" and "-" or "") .. t[4], (t[3] == "S" and "-" or "") .. t[2]
        if float then
            hdop = tonumber(t[8]) or 0
            sep = tonumber(t[11]) or 0
            altitude = tonumber(t[9]) or 0
        else
            hdop = tonumber(t[8]:match("%d+")) or 0
            sep = tonumber(t[11]:match(".%d*")) or 0
            altitude = tonumber(t[9]:match(".%d*")) or 0
        end
    end,
    ["GSA"] = function(t)
        if t[2] ~= "1" then
            for i = 1, 12 do sateSn[i] = tonumber(t[i + 2]) or 0 end
            if float then
                pdop = tonumber(t[15]) or 0
                hdop = tonumber(t[16]) or 0
                vdop = tonumber(t[17]) or 0
            else
                pdop = tonumber(t[15]:match("%d+")) or 0
                hdop = tonumber(t[16]:match("%d+")) or 0
                vdop = tonumber(t[17]:match("%d+")) or 0
            end
        end
    end,
    ["GPGSV"] = function(t)
        if t[2] == "1" then
            cnoGp, gsvGp = {}, {}
            viewGpSateCnt = tonumber(t[3]) or 0
        end
        for i = 1, 16, 4 do
            table.insert(gsvGp, {tonumber(t[i + 3]) or 0, tonumber(t[i + 4]) or 0, tonumber(t[i + 5]) or 0, tonumber(t[i + 6]) or 0})
            table.insert(cnoGp, tonumber(t[i + 6]) or 0)
        end
    end,
    ["BDGSV"] = function(t)
        if t[2] == "1" then
            cnoBd, gsvBd = {}, {}
            viewBdSateCnt = tonumber(t[3]) or 0
        end
        for i = 1, 16, 4 do
            table.insert(gsvBd, {tonumber(t[i + 3]) or 0, tonumber(t[i + 4]) or 0, tonumber(t[i + 5]) or 0, tonumber(t[i + 6]) or 0})
            table.insert(cnoBd, tonumber(t[i + 6]) or 0)
        end
    end,
    ["RMC"] = function(t)
        if t[2] == "A" then
            fixFlag = true
            speed = mile * 1852 / 1000
            ggalng, ggalat = (t[6] == "W" and "-" or "") .. t[5], (t[4] == "S" and "-" or "") .. t[3]
            local hour = tonumber(t[1]:sub(1, 2)) or 0
            local min = tonumber(t[1]:sub(3, 4)) or 0
            local sec = tonumber(t[1]:sub(5, 6)) or 0
            local day = tonumber(t[9]:sub(1, 2)) or 0
            local month = tonumber(t[9]:sub(3, 4)) or 0
            local year = tonumber(t[9]:sub(5, 6)) or 0
            utcTime = os.date("*t", os.time({year = 2000 + year, month = month, day = day, hour = hour, min = min, sec = sec}) + 28800)
            if float then
                mile = tonumber(t[7]) or 0
                azimuth = tonumber(t[8]) or 0
            else
                mile = tonumber(t[7]:match("%d+")) or 0
                azimuth = tonumber(t[8]:match("%d+")) or 0
            end
        else
            fixFlag = false
        end
    end,
    ["VTG"] = function(t)
        if float then
            azimuth = tonumber(t[1]) or 0
            mile = tonumber(t[5]) or 0
            speed = tonumber(t[7]) or 0
        else
            azimuth = tonumber(t[1]:match("%d+")) or 0
            mile = tonumber(t[5]:match("%d+")) or 0
            speed = tonumber(t[7]:match("%d+")) or 0
        end
    end,
    ["PGKC001"] = function(t)log.warn("$PGKC001,", table.concat(t, ", ")) end,
    other = function(t)log.warn("other:", table.concat(t, ", ")) end,
    __index = function(t, key)
        for k, v in pairs(t) do
            if key:match(k) then return v end
        end
        return t.other
    end
}
setmetatable(process, process)

-- AIR530的校验和算法
local function hexCheckSum(str)
    local sum = 0
    for i = 5, str:len(), 2 do
        sum = bit.bxor(sum, tonumber(str:sub(i, i + 1), 16))
    end
    return string.upper(string.format("%02X", sum))
end
-- AIR530的$语句校验和,格式为"$PGKC149,1,115200*"
local function strCheckSum(str)
    local sum = 0
    for i = 2, str:len() - 1 do
        sum = bit.bxor(sum, str:byte(i))
    end
    return string.upper(string.format("%02X", sum))
end

-- GPS串口写命令操作
-- @string cmd，GPS指令(cmd格式："$PGKC149,1,115200*"或者"$PGKC149,1,115200*XX\r\n")
-- @bool isFull，cmd是否为完整的指令格式，包括校验和以及\r\n；true表示完整，false或者nil为不完整
-- @return nil
-- @usage gpsv2.writeCmd(cmd)
local function writeCmd(cmd, isFull)uart.write(uartID, isFull and cmd or (cmd .. strCheckSum(cmd) .. "\r\n")) end

-- GPS串口写数据操作
-- @string str,HEX形式的字符串
-- @return 无
-- @usage gpsv2.writeData(str)
local function writeData(str)uart.write(uartID, (str:fromHex())) end

-- GSP 设置辅助定位
local function setFastFix(lat, lng)
    if not lat or not lng or not openFlag then return end
    local tm = os.date("*t")
    tm = common.timeZoneConvert(tm.year, tm.month, tm.day, tm.hour, tm.min, tm.sec, 8, 0)
    t = tm.year .. "," .. tm.month .. "," .. tm.day .. "," .. tm.hour .. "," .. tm.min .. "," .. tm.sec .. "*"
    log.info("写入秒定位需要的坐标和时间:", lat, lng, t)
    writeCmd("$PGKC634," .. t .. "*")
    writeCmd("$PGKC635," .. lat .. "," .. lng .. ",0," .. t .. "*")
end
-- 辅助定位功能任务函数
sys.taskInit(function()
    sys.waitUntil("IP_READY_IND")
    while true do
        if fastFixFlag then
            lbsLoc.request(function(result, lat, lng, addr)
                if result and lat and lng then
                    lbs_lat, lbs_lng = lat, lng
                    setFastFix(lbs_lat, lbs_lng)
                end
            end, nil, timeout, "v32xEAKsGTIEQxtqgwCldp5aPlcnPs3K")
            if io.exists(GPD_TIME) then
                local t, res, err = json.decode(io.readFile(GPD_TIME))
                if res and os.time() - t.tim < EPH_UPDATE_INTERVAL then ephFlag = true else ephFlag = false end
            end
            if not ephFlag then
                local code, head, dat = httpv2.request("GET", "download.openluat.com/9501-xingli/brdcGPD.dat_rda", 300000)
                if tonumber(code) and tonumber(code) == 200 then
                    log.info("模块写星历数据开始:", io.writeFile(GPD_TIME, json.encode({tim = os.time()})))
                    writeCmd("$PGKC242,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0*")
                    sys.wait(100)
                    writeCmd("$PGKC149,1," .. uartRate .. "*")-- 切换BINARY模式
                    sys.wait(100)
                    local cnt, data, len = 0, dat:toHex()
                    for i = 1, #data, 1024 do -- 写入星历数据
                        local tmp = data:sub(i, i + 1023)
                        if tmp:len() < 1024 then tmp = tmp .. ("F"):rep(1024 - tmp:len()) end
                        tmp = "AAF00B026602" .. string.format("%04X", cnt):upper() .. tmp
                        tmp = tmp .. hexCheckSum(tmp) .. "0D0A"
                        writeData(tmp)
                        cnt = cnt + 1
                        sys.wait(200)
                    end
                    -- 发送GPD传送结束语句
                    writeData("AAF00B006602FFFF6F0D0A")
                    local nmea = "AAF00E00950000" .. (pack.pack("<i", uartRate):toHex())
                    writeData(nmea .. hexCheckSum(nmea) .. "0D0A")
                    sys.wait(100)
                    writeCmd("$PGKC242,0,1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0*")
                    setFastFix(lbs_lat, lbs_lng)
                    log.info("---------- 模块写星历数据结束 ----------")
                end
            end
        end
        sys.wait(1800000)
    end
end)

-- GPS 串口处理程序
-- @number,uid,串口id，默认2
-- @number，rate，串口波特率,默认115200,可选9600
-- @number, cycl，上报周期,单位秒,低功耗模式为睡眠周期
-- @param, mode ,低功耗模式，boolean值，true 为打开低功耗,false为关闭,默认关闭
-- @param, agps，是否开启辅助定位,打开可以实现秒定位
-- @return 无
-- @usage gpsv3.open()
-- @usage gpsv3.open(2)
-- @usage gpsv3.open(2,115200)
-- @usage gpsv3.open(2,115200,60,true)
-- @usage gpsv3.open(2,115200,60,true,true)
-- @return boolean,true 表示成功,false，表示GPS已经被打开
function open(uid, rate, cycl, mode, agps)
    pm.wake("GPS")
    if openFlag then return end
    local wake, cache = true, ""
    fastFixFlag = agps
    uartID, uartRate, openFlag = uid or 2, rate or 115200, true
    cycl = (tonumber(cycl) and tonumber(cycl) > 0) and tonumber(cycl) or 1
    rtos.sys32k_clk_out(1)
    pmd.ldoset(7, pmd.LDO_VIB)
    pmd.ldoset(7, pmd.LDO_VCAM)
    uart.setup(uartID or 2, uartRate or 115200, 8, uart.PAR_NONE, uart.STOP_1)
    uart.on(uartID, "receive", function(uid, length)
        cache = cache .. uart.read(uid, length or 8192)
        local idx = cache:find("\r\n")
        while idx do
            local str = cache:sub(1, idx - 1)
            cache = cache:sub(idx + 2)
            if str:sub(1, 1) == "$" then
                if isLog then log.info("NEMA:", str) end
                if strCheckSum(str:sub(1, -3)) == str:sub(-2, -1) then
                    local t = str:split(",")
                    local fnc = table.remove(t, 1)
                    process[fnc](t)
                else
                    log.warn("NEMA checkSum error:", strCheckSum(str:sub(1, -3)), str:sub(-2, -1))
                end
            elseif str:sub(1, 5) == "*****" then
                log.info("PPS:", str)
            else
                log.info("BINARY:", str:toHex())
            end
            idx = cache:find("\r\n")
        end
    end)
    log.info("----------------------------------- GPS OPEN -----------------------------------")
    -- 发送GPD传送结束语句,下面几句代码是为了防止上一次GPS写星历异常断电可能出现的情况
    writeData("AAF00B006602FFFF6F0D0A")
    -- 切换为NMEA接收模式
    local nmea = "AAF00E00950000" .. (pack.pack("<i", uartRate):toHex())
    writeData(nmea .. hexCheckSum(nmea) .. "0D0A")
    writeCmd("$PGKC147," .. uartRate .. "*")
    if mode then
        tid = sys.timerLoopStart(function()
            if fixFlag then
                pm.sleep("GPS")
                writeCmd("$PGKC051,1*")
                fixFlag, tcnt, wake = false, 0, false
                sys.publish("GPS_MSG_REPORT", getAllMsg())
                log.info("----------------------------------- GPS SLEEP -----------------------------------")
            else
                tcnt = tcnt + 1
                if tcnt >= cycl and not wake then
                    wake = true
                    pm.wake("GPS")
                    writeCmd("$PGKC105,0*")
                    log.info("----------------------------------- GPS WAKE -----------------------------------")
                end
            end
        end, 1000)
    else
        tid = sys.timerLoopStart(function()
            sys.publish("GPS_MSG_REPORT", getAllMsg())
        end, cycl * 1000)
    end
    return true
end

--- 关闭GPS
-- @return 无
-- @usage gpsv3.close()
function close()
    openFlag = false
    fastFixFlag = false
    sys.timerStop(tid)
    rtos.sys32k_clk_out(0)
    pmd.ldoset(0, pmd.LDO_VIB)
    pmd.ldoset(0, pmd.LDO_VCAM)
    uart.close(uartID)
    pm.sleep("GPS")
    log.info("----------------------------------- GPS CLOSE -----------------------------------")
end

--- 重启GPS模块
-- @number r,重启方式-0:外部电源重置; 1:热启动; 2:温启动; 3:冷启动
-- @return 无
-- @usage gpsv3.restart()
function restart(r)
    r = tonumber(r) or 1
    if r > 0 and r < 4 then writeCmd("$PGKC030," .. r .. "*") end
end

--- 关闭日志开关
-- @param v, boolean值 true 表示关闭，其他表示打开
-- @return 无
-- @usage gpsv3.noLog(true)
function noLog(v)
    isLog = not (v == true)
    log.info("是否打印NEMA的日志:", isLog)
end

--- 设置NMEA消息上报的间隔
-- @number tm，上报消息的间隔时间
-- @return 无
-- @usage gpsv3.setReport(tm)
function setReport(tm)
    if openFlag then
        tm = tonumber(tm) or 1000
        if tm > 10000 then tm = 10000 end
        if tm < 200 then tm = 200 end
        writeCmd("$PGKC101," .. tm .. "*")
    end
end

--- 获取GPS模块是否处于开启状态
-- @return bool result，true表示开启状态，false或者nil表示关闭状态
-- @usage gpsv3.isOpen()
function isOpen() return openFlag end

--- 获取GPS模块是否定位成功
-- @return bool result，true表示定位成功，false或者nil表示定位失败
-- @usage gpsv3.isFix()
function isFix() return fixFlag end

--- 获取GSV解析后的最大Cno
-- @return number，Cno 最大值
-- @usage gpsv3.getMaxCno()
function getMaxCno()
    table.sort(cnoGp)
    table.sort(cnoBd)
    return cnoGp[#cnoGp] > cnoBd[#cnoBd] and cnoGp[#cnoGp] or cnoBd[#cnoBd]
end

--- 获取所有可用卫星号
-- @return table 卫星号的数组
-- @usage gpsv2.getSateSn()
function getSateSn() return sateSn end

--- 获取BDGSV解析结果
-- @return table, GSV解析后的数组
-- @usage gpsv3.getBDGsv()
function getBDGsv() return gsvBd end

--- 获取GPGSV解析结果
-- @return table, GSV解析后的数组
-- @usage gpsv3.getGPGsv()
function getGPGsv() return gsvGp end

--- 统计GSA语句中的可见卫星数量
-- @return number, 可见卫星数量
-- @usage gpsv3.sumViewSate()
function sumViewSate() return viewBdSateCnt + viewGpSateCnt end

--- 获取定位使用的卫星个数
-- @return number count，定位使用的卫星个数
-- @usage gpsv3.sumUsedSate()
function sumUsedSate() return usedSateCnt end

--- 获取RMC语句中的UTC时间
-- @return number utc 时间戳
-- @usage gpsv3.getUtcTime()
function getUtcTime() return utcTime or 0 end

--- 获取位置，水平，垂直精度
-- @return number 多参数 pdop,hdop,vodp
-- @usage gpsv3.getDop()
function getDop() return pdop, hdop, vdop end

--- 获取定位使用的大地高
-- 地球椭球面相对大地水准面的高度
-- @return number sep，大地高
-- @usage gpsv3.getSep()
function getSep() return sep end

--- 获取海拔
-- @return number altitude，海拔，单位米
-- @usage gpsv3.getAltitude()
function getAltitude() return altitude end

--- 获取方向角
-- @return number Azimuth，方位角
-- @usage gpsv3.getAzimuth()
function getAzimuth() return azimuth end

--- 获取速度
-- @return number kmSpeed，第一个返回值为公里每小时的速度
-- @return number nmSpeed，第二个返回值为海里每小时的速度
-- @usage gpsv3.getSpeed()
function getSpeed() return speed, mile end

-- 获取基站定位经纬度
function getLbs() return lbs_lng or 0, lbs_lat or 0 end

--- 获取度分格式的经纬度信息ddmm.mmmm
-- @return string,string,返回度格式的字符串经度,维度,符号(正东负西,正北负南)
-- @usage gpsv3.getCentLocation()
function getCentLocation()
    if float then
        return tonumber(ggalng) or 0, tonumber(ggalat) or 0
    end
    return ggalng or "0.0", ggalat or "0.0"
end

--- 获取返回值为度的10^7方的整数值（度*10^7的值）
-- @return number,number,INT32整数型,经度,维度,符号(正东负西,正北负南)
-- @usage gpsv2.getIntLocation()
function getIntLocation()
    local function centToDeg(str)
        local integer, decimal = str:match("(%d+).(%d+)")
        if tonumber(integer) and tonumber(decimal) then
            local tmp = (integer % 100) * 10 ^ 7 + decimal * 10 ^ (7 - #decimal)
            return ((integer - integer % 100) / 100) * 10 ^ 7 + (tmp - tmp % 60) / 60
        end
        return 0
    end
    return centToDeg(ggalng or "0.0"), centToDeg(ggalat or "0.0")
end

--- 获取度格式的经纬度信息dd.dddddd
-- @return string,string,固件为非浮点时返回度格式的字符串经度,维度,符号(正东负西,正北负南)
-- @return float,float,固件为浮点的时候，返回浮点类型
-- @usage gpsv2.getLocation()
function getDegLocation()
    local function centToDeg(num)
        if tonumber(num) then
            local int, dec = math.modf(num / 100)
            return int + dec * 10 / 6
        end
        return 0
    end
    if float then
        local lng, lat = getCentLocation()
        return centToDeg(lng), centToDeg(lat)
    end
    local lng, lat = getIntLocation()
    return string.format("%d.%07d", lng / 10 ^ 7, lng % 10 ^ 7), string.format("%d.%07d", lat / 10 ^ 7, lat % 10 ^ 7)
end

--- 获取打包的GPS信息
-- return number，定位成功1,失败0, 经度，纬度，速度，海拔，方位角度，定位卫星数量，可见卫星数量，最大信噪比，UTC时间戳
-- @usage local fix,lng,lat,speed,alt = getAllMsg()
-- @usage local fix,lng,lat,speed,alt,azi,used,view,cno = getAllMsg()
function getAllMsg()
    local lng, lat = getDegLocation()
    return fixFlag and 1 or 0, lng, lat, speed, altitude, azimuth, sumUsedSate(), sumViewSate(), getMaxCno(), getUtcTime()
end
