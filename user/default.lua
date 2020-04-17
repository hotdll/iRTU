--- 模块功能：DTU主逻辑
-- @author openLuat
-- @module default
-- @license MIT
-- @copyright openLuat
-- @release 2018.12.27
-- require "cc"
require "pm"
require "iic"
require "sms"
require "link"
require "pins"
require "misc"
require "mqtt"
require "utils"
require "lbsLoc"
require "socket"
require "audio"
require "httpv2"
require "common"
require "create"
require "tracker"
require "update"
module(..., package.seeall)

-- 判断模块类型
local ver = rtos.get_version():upper()
local is4gLod = ver:find("ASR1802")
local is1802S = ver:find("ASR1802S")
local is8910 = ver:find("8910")
local isTTS = ver:find("TTS") or ver:find("8955F")
-- 用户的配置参数
local CONFIG = "/CONFIG.cnf"
-- 串口缓冲区最大值
local SENDSIZE = is4gLod and 8192 or 1460
-- 串口写空闲
local writeIdle = {true, true}
-- 串口读缓冲区
local recvBuff, writeBuff = {{}, {}}, {{}, {}}
-- 串口流量统计
local flowCount, timecnt = {0, 0}, 1
-- 定时采集任务的初始时间
local startTime = {0, 0}
-- 定时采集任务缓冲区
local sendBuff = {{}, {}}
-- 基站定位坐标
local lbs = {lat, lng}
-- 配置文件
local dtu = {
    host = "", -- 自定义参数服务器
    passon = 0, --透传标志位
    plate = 0, --识别码标志位
    convert = 0, --hex转换标志位
    reg = 0, -- 登陆注册包
    param_ver = 0, -- 参数版本
    flow = 0, -- 流量监控
    fota = 0, -- 远程升级
    uartReadTime = 500, -- 串口读超时
    netReadTime = 50, -- 网络读超时
    pwrmod = "normal",
    password = "",
    upprot = {}, -- 上行自定义协议
    dwprot = {}, -- 下行自定义协议
    apn = {nil, nil, nil}, -- 用户自定义APN
    cmds = {{}, {}}, -- 自动采集任务参数
    pins = {"", "", ""}, -- 用户自定义IO: netled,netready,rstcnf,
    conf = {{}, {}, {}, {}, {}, {}, {}}, -- 用户通道参数
    preset = {number = "", delay = 1, smsword = "SMS_UPDATE"}, -- 用户预定义的来电电话,延时时间,短信关键字
    uconf = {{1, 115200, 8, uart.PAR_NONE, uart.STOP_1}, {2, 115200, 8, uart.PAR_NONE, uart.STOP_1}}, -- 串口配置表
    gps = {
        fun = {"", "115200", "0", "5", "1", "json", "100", ";", "60"}, -- 用户捆绑GPS的串口,波特率，功耗模式，采集间隔,采集方式支持触发和持续, 报文数据格式支持 json 和 hex，缓冲条数,分隔符,状态报文间隔
        pio = {"", "", "", "", "0", "16"}, -- 配置GPS用到的IO: led脚，vib震动输入脚，ACC输入脚,内置电池充电状态监视脚,adc通道,分压比
    },
    warn = {
        gpio = {},
        adc0 = {},
        adc1 = {},
        vbatt = {}
    },
    task = {}, -- 用户自定义任务列表
}
-- 获取参数版本
io.getParamVer = function()
    return dtu.param_ver
end
---------------------------------------------------------- 开机读取保存的配置文件 ----------------------------------------------------------
-- 自动任务采集
local function autoSampl(uid, t)
    while true do
        sys.waitUntil("AUTO_SAMPL_" .. uid)
        for i = 2, #t do
            local str = t[i]:match("function(.+)end")
            if not str then
                if t[i] ~= "" then write(uid, (t[i]:fromHex())) end
            else
                local res, msg = pcall(loadstring(str))
                if res then sys.publish("NET_SENT_RDY_" .. uid, msg) end
            end
            sys.wait(tonumber(t[1]))
        end
    end
end
if io.exists(CONFIG) then
    -- log.info("CONFIG is value:", io.readFile(CONFIG))
    local dat, res, err = json.decode(io.readFile(CONFIG))
    if res then
        dtu = dat
        if dtu.apn and dtu.apn[1] and dtu.apn[1] ~= "" then link.setAPN(unpack(dtu.apn)) end
        if dtu.cmds and dtu.cmds[1] and tonumber(dtu.cmds[1][1]) then sys.taskInit(autoSampl, 1, dtu.cmds[1]) end
        if dtu.cmds and dtu.cmds[2] and tonumber(dtu.cmds[2][1]) then sys.taskInit(autoSampl, 2, dtu.cmds[2]) end
        if tonumber(dtu.nolog) ~= 1 then _G.LOG_LEVEL = log.LOG_SILENT end
    end
end
---------------------------------------------------------- 用户控制 GPIO 配置 ----------------------------------------------------------
-- 用户可用IO列表
if is1802S then
    pmd.ldoset(7, pmd.VLDO6)
    pios = {
        pio10 = pins.setup(10, nil, pio.PULLDOWN),
        pio11 = pins.setup(11, nil, pio.PULLDOWN),
        pio17 = pins.setup(17, nil, pio.PULLDOWN),
        pio18 = pins.setup(18, nil, pio.PULLDOWN),
        pio20 = pins.setup(20, nil, pio.PULLDOWN),
        pio23 = pins.setup(23, nil, pio.PULLDOWN),
        pio24 = pins.setup(24, nil, pio.PULLDOWN),
        pio25 = pins.setup(25, nil, pio.PULLDOWN),
        pio26 = pins.setup(26, nil, pio.PULLDOWN),
        pio27 = pins.setup(27, nil, pio.PULLDOWN),
        pio28 = pins.setup(28, nil, pio.PULLDOWN),
        -- pio29 = pins.setup(29, nil, pio.PULLDOWN),-- UART2 - RXD
        -- pio30 = pins.setup(30, nil, pio.PULLDOWN),-- UART2 - TXD
        pio31 = pins.setup(31, nil, pio.PULLDOWN),
        pio32 = pins.setup(32, 0, pio.PULLUP), -- UART2 485 默认方向脚
        pio33 = pins.setup(33, nil, pio.PULLDOWN),
        pio34 = pins.setup(34, nil, pio.PULLDOWN),
        pio35 = pins.setup(35, nil, pio.PULLDOWN),
        pio36 = pins.setup(36, nil, pio.PULLDOWN),
        pio37 = pins.setup(37, nil, pio.PULLDOWN),
        pio38 = pins.setup(38, nil, pio.PULLDOWN),
        pio39 = pins.setup(39, nil, pio.PULLDOWN),
        pio40 = pins.setup(40, nil, pio.PULLDOWN),
        pio41 = pins.setup(41, nil, pio.PULLDOWN),
        pio42 = pins.setup(42, nil, pio.PULLDOWN),
        pio49 = pins.setup(49, nil, pio.PULLDOWN),
        pio50 = pins.setup(50, nil, pio.PULLDOWN),
        -- pio51 = pins.setup(51, nil, pio.PULLDOWN), -- UART1 rxd
        -- pio52 = pins.setup(52, nil, pio.PULLDOWN), -- uart 1 txd
        pio61 = pins.setup(61, 0, pio.PULLUP), -- UART1 485 默认方向脚
        pio62 = pins.setup(62, nil, pio.PULLDOWN),
        pio63 = pins.setup(63, nil, pio.PULLDOWN),
        pio64 = pins.setup(64, 0, pio.PULLUP), -- NETLED
        pio65 = pins.setup(65, nil, pio.PULLDOWN),
    -- pio66 = pins.setup(66, nil, pio.PULLDOWN),
    }
elseif is4gLod then
    pmd.ldoset(7, pmd.VLDO6)
    pios = {
        pio23 = pins.setup(23, 0, pio.PULLUP), -- 默认UART1的485方向控制脚
        pio26 = pins.setup(26, nil, pio.PULLDOWN),
        pio27 = pins.setup(27, nil, pio.PULLDOWN),
        pio28 = pins.setup(28, nil, pio.PULLDOWN),
        pio33 = pins.setup(33, nil, pio.PULLDOWN),
        pio34 = pins.setup(34, nil, pio.PULLDOWN),
        pio35 = pins.setup(35, nil, pio.PULLDOWN),
        pio36 = pins.setup(36, nil, pio.PULLDOWN),
        pio55 = pins.setup(55, nil, pio.PULLDOWN),
        pio56 = pins.setup(56, nil, pio.PULLDOWN),
        pio59 = pins.setup(59, 0, pio.PULLUP), -- 默认UART2的485方向控制脚
        pio62 = pins.setup(62, nil, pio.PULLDOWN),
        pio63 = pins.setup(63, nil, pio.PULLDOWN),
        pio64 = pins.setup(64, nil, pio.PULLDOWN), -- NETLED
        pio65 = pins.setup(65, nil, pio.PULLDOWN), -- NETREADY
        pio67 = pins.setup(67, nil, pio.PULLDOWN),
        pio68 = pins.setup(68, nil, pio.PULLDOWN), -- RSTCNF
        pio69 = pins.setup(69, nil, pio.PULLDOWN),
        pio70 = pins.setup(70, nil, pio.PULLDOWN),
        pio71 = pins.setup(71, nil, pio.PULLDOWN),
        pio72 = pins.setup(72, nil, pio.PULLDOWN),
        pio73 = pins.setup(73, nil, pio.PULLDOWN),
        pio74 = pins.setup(74, nil, pio.PULLDOWN),
        pio75 = pins.setup(75, nil, pio.PULLDOWN),
        pio76 = pins.setup(76, nil, pio.PULLDOWN),
        pio77 = pins.setup(77, nil, pio.PULLDOWN),
        pio78 = pins.setup(78, nil, pio.PULLDOWN),
        pio79 = pins.setup(79, nil, pio.PULLDOWN),
        pio80 = pins.setup(80, nil, pio.PULLDOWN),
        pio81 = pins.setup(81, nil, pio.PULLDOWN),
    }
elseif is8910 then
    pmd.ldoset(15, pmd.LDO_VLCD)
    pmd.ldoset(15, pmd.LDO_VMMC)
    pios = {
        pio0 = pins.setup(0, nil, pio.PULLDOWN),
        pio2 = pins.setup(2, nil, pio.PULLDOWN),
        pio3 = pins.setup(3, nil, pio.PULLDOWN),
        -- pio6 = pins.setup(6, nil, pio.PULLDOWN), // 不能启用该IO，否则虚拟AT口会死掉
        pio7 = pins.setup(7, nil, pio.PULLDOWN),
        pio9 = pins.setup(9, nil, pio.PULLDOWN),
        pio10 = pins.setup(10, nil, pio.PULLDOWN),
        pio11 = pins.setup(11, nil, pio.PULLDOWN),
        pio12 = pins.setup(12, nil, pio.PULLDOWN),
        pio13 = pins.setup(13, nil, pio.PULLDOWN),
        pio14 = pins.setup(14, nil, pio.PULLDOWN),
        pio15 = pins.setup(15, nil, pio.PULLDOWN),
        pio16 = pins.setup(16, nil, pio.PULLDOWN),
        pio17 = pins.setup(17, nil, pio.PULLDOWN),
        pio18 = pins.setup(18, nil, pio.PULLDOWN),
        pio19 = pins.setup(19, nil, pio.PULLDOWN),
        pio24 = pins.setup(24, nil, pio.PULLDOWN),
        pio25 = pins.setup(25, nil, pio.PULLDOWN),
        pio26 = pins.setup(26, nil, pio.PULLDOWN),
        pio27 = pins.setup(27, nil, pio.PULLDOWN),
        pio28 = pins.setup(28, nil, pio.PULLDOWN),
    }
else
    require "cc"
    pmd.ldoset(7, pmd.LDO_VLCD)
    pmd.ldoset(7, pmd.LDO_VMMC)
    pios = {
        pio2 = pins.setup(2, nil, pio.PULLDOWN), -- 默认UART1的485方向控制脚
        pio3 = pins.setup(3, nil, pio.PULLDOWN), -- 默认netready信号
        pio6 = pins.setup(6, nil, pio.PULLDOWN), -- 默认UART2的485方向控制脚
        pio7 = pins.setup(7, nil, pio.PULLDOWN),
        pio8 = pins.setup(8, nil, pio.PULLDOWN),
        pio9 = pins.setup(9, nil, pio.PULLDOWN),
        pio10 = pins.setup(10, nil, pio.PULLDOWN),
        pio11 = pins.setup(11, nil, pio.PULLDOWN),
        pio12 = pins.setup(12, nil, pio.PULLDOWN),
        pio13 = pins.setup(13, nil, pio.PULLDOWN),
        pio14 = pins.setup(14, nil, pio.PULLDOWN),
        pio15 = pins.setup(15, nil, pio.PULLDOWN),
        pio16 = pins.setup(16, nil, pio.PULLDOWN),
        pio17 = pins.setup(17, nil, pio.PULLDOWN),
        pio18 = pins.setup(18, nil, pio.PULLDOWN),
        pio28 = pins.setup(28, nil, pio.PULLDOWN), -- 默认202 NETLED
        pio29 = pins.setup(29, nil, pio.PULLDOWN), -- 默认恢复默认值
        pio33 = pins.setup(33, nil, pio.PULLDOWN), -- 默认800 NETLED
        pio34 = pins.setup(34, nil, pio.PULLDOWN),
    }
end

-- 网络READY信号
if not dtu.pins or not dtu.pins[2] or not pios[dtu.pins[2]] then -- 这么定义是为了和之前的代码兼容
    netready = pins.setup((is4gLod and 65) or (is8910 and 4) or 3, 0)
else
    netready = pins.setup(tonumber(dtu.pins[2]:sub(4, -1)), 0)
    pios[dtu.pins[2]] = nil
end

-- 重置DTU
if not dtu.pins or not dtu.pins[3] or not pios[dtu.pins[3]] then -- 这么定义是为了和之前的代码兼容
    pins.setup((is1802S or is8910 and 17) or (is4gLod and 68) or 29, function(msg)
        if msg ~= cpu.INT_GPIO_POSEDGE then
            if io.exists(CONFIG) then os.remove(CONFIG) end
            if io.exists("/alikey.cnf") then os.remove("/alikey.cnf") end
            if io.exists("/qqiot.dat") then os.remove("/qqiot.dat") end
            if io.exists("/bdiot.dat") then os.remove("/bdiot.dat") end
            sys.restart("软件恢复出厂默认值: OK")
        end
    end, pio.PULLUP)
else
    pins.setup(tonumber(dtu.pins[3]:sub(4, -1)), function(msg)
        if msg ~= cpu.INT_GPIO_POSEDGE then
            if io.exists(CONFIG) then os.remove(CONFIG) end
            if io.exists("/alikey.cnf") then os.remove("/alikey.cnf") end
            if io.exists("/qqiot.dat") then os.remove("/qqiot.dat") end
            if io.exists("/bdiot.dat") then os.remove("/bdiot.dat") end
            sys.restart("软件恢复出厂默认值: OK")
        end
    end, pio.PULLUP)
    pios[dtu.pins[3]] = nil
end
-- NETLED指示灯任务
local function blinkPwm(ledPin, light, dark)
    ledPin(1)
    sys.wait(light)
    ledPin(0)
    sys.wait(dark)
end
local function netled(led)
    local ledpin = pins.setup(led, 1)
    while true do
        -- GSM注册中
        while not link.isReady() do blinkPwm(ledpin, 100, 100) end
        while link.isReady() do
            if create.getDatalink() then
                netready(1)
                blinkPwm(ledpin, 200, 1800)
            else
                netready(0)
                blinkPwm(ledpin, 500, 500)
            end
        end
        sys.wait(100)
    end
end
if not dtu.pins or not dtu.pins[1] or not pios[dtu.pins[1]] then -- 这么定义是为了和之前的代码兼容
    sys.taskInit(netled, (is4gLod and 64) or (is8910 and 1) or 33)
else
    sys.taskInit(netled, tonumber(dtu.pins[1]:sub(4, -1)))
    pios[dtu.pins[1]] = nil
end
---------------------------------------------------------- DTU 任务部分 ----------------------------------------------------------
-- 配置串口
if dtu.pwrmod ~= "energy" then pm.wake("mcuUart.lua") end

-- 每隔1分钟重置串口计数
sys.timerLoopStart(function()
    flow = tonumber(dtu.flow)
    if flow and flow ~= 0 then
        if flowCount[1] > flow then
            uart.on(1, "receive")
            uart.close(1)
            log.info("uart1.read length count:", flowCount[1])
        end
        if flowCount[2] > flow then
            uart.on(2, "receive")
            uart.close(2)
            log.info("uart2.read length count:", flowCount[2])
        end
    end
    if timecnt > 60 then
        timecnt = 1
        flowCount = {0, 0}
    else
        timecnt = timecnt + 1
    end
end, 1000)

-- 串口写数据处理
function write(uid, str)
    if not str or str == "" then return end
    if str ~= true then
        for i = 1, #str, SENDSIZE do
            table.insert(writeBuff[uid], str:sub(i, i + SENDSIZE - 1))
        end
        log.warn("uart" .. uid .. ".write data length:", writeIdle[uid], #str)
    end
    if writeIdle[uid] and writeBuff[uid][1] then
        if 0 ~= uart.write(uid, writeBuff[uid][1]) then
            table.remove(writeBuff[uid], 1)
            writeIdle[uid] = false
            log.warn("UART_" .. uid .. " writing ...")
        end
    end
end

local function writeDone(uid)
    if #writeBuff[uid] == 0 then
        writeIdle[uid] = true
        sys.publish("UART_" .. uid .. "_WRITE_DONE")
        log.warn("UART_" .. uid .. "write done!")
    else
        writeIdle[uid] = false
        uart.write(uid, table.remove(writeBuff[uid], 1))
        log.warn("UART_" .. uid .. "writing ...")
    end
end

-- DTU配置工具默认的方法表
cmd = {}
cmd.config = {
    ["pipe"] = function(t, num)dtu.conf[tonumber(num)] = t return "OK" end, -- "1"-"7" 为通道配置
    ["A"] = function(t)dtu.apn = t return "OK" end, -- APN 配置
    ["B"] = function(t)dtu.cmds[tonumber(table.remove(t, 1)) or 1] = t return "OK" end, -- 自动任务下发配置
    ["pins"] = function(t)dtu.pins = t return "OK" end, -- 自定义GPIO
    ["host"] = function(t)dtu.host = t[1] return "OK" end, -- 自定义参数升级服务器
    ["0"] = function(t)-- 读取整个DTU的参数配置
        local password = ""
        dtu.passon, dtu.plate, dtu.convert, dtu.reg, dtu.param_ver, dtu.flow, dtu.fota, dtu.uartReadTime, dtu.pwrmod, password, dtu.netReadTime, dtu.nolog = unpack(t)
        if password == dtu.password or dtu.password == "" or dtu.password == nil then
            dtu.password = password
            io.writeFile(CONFIG, json.encode(dtu))
            sys.timerStart(sys.restart, 1000, "Setting parameters have been saved!")
            return "OK"
        else
            return "PASSWORD ERROR"
        end
    end,
    ["8"] = function(t)-- 串口配置默认方法
        local tmp = "1200,2400,4800,9600,14400,19200,28800,38400,57600,115200,230400,460800,921600"
        if t[1] and t[2] and t[3] and t[4] and t[5] then
            if ("1,2"):find(t[1]) and tmp:find(t[2]) and ("7,8"):find(t[3]) and ("0,1,2"):find(t[4]) and ("0,2"):find(t[5]) then
                dtu.uconf[tonumber(t[1])] = t
                return "OK"
            else
                return "ERROR"
            end
        end
    end,
    ["9"] = function(t)-- 预置白名单
        dtu.preset.number, dtu.preset.delay, dtu.preset.smsword = unpack(t)
        dtu.preset.delay = tonumber(dtu.preset.delay) or 1
        return "OK"
    end,
    ["readconfig"] = function(t)-- 读取整个DTU的参数配置
        if t[1] == dtu.password or dtu.password == "" or dtu.password == nil then
            if io.exists(CONFIG) then return io.readFile(CONFIG) end
            return "ERROR"
        else
            return "PASSWORD ERROR"
        end
    end,
    ["writeconfig"] = function(t, s)-- 读取整个DTU的参数配置
        local str = s:match("(.+)\r\n") and s:match("(.+)\r\n"):sub(20, -1) or s:sub(20, -1)
        local dat, result, errinfo = json.decode(str)
        if result then
            if dtu.password == dat.password or dtu.password == "" or dtu.password == nil then
                io.writeFile(CONFIG, str)
                sys.timerStart(sys.restart, 1000, "Setting parameters have been saved!")
                return "OK"
            else
                return "PASSWORD ERROR"
            end
        else
            return "JSON ERROR"
        end
    end
}
cmd.rrpc = {
    ["getver"] = function(t) return "rrpc,getver," .. _G.VERSION end,
    ["getcsq"] = function(t) return "rrpc,getcsq," .. (net.getRssi() or "error ") end,
    ["getadc"] = function(t) return "rrpc,getadc," .. create.getADC(tonumber(t[1]) or 0) end,
    ["reboot"] = function(t)sys.timerStart(sys.restart, 1000, "Remote reboot!") return "OK" end,
    ["getimei"] = function(t) return "rrpc,getimei," .. (misc.getImei() or "error") end,
    ["getimsi"] = function(t) return "rrpc,getimsi," .. (sim.getImsi() or "error") end,
    ["getvbatt"] = function(t) return "rrpc,getvbatt," .. misc.getVbatt() end,
    ["geticcid"] = function(t) return "rrpc,geticcid," .. (sim.getIccid() or "error") end,
    ["getproject"] = function(t) return "rrpc,getproject," .. _G.PROJECT end,
    ["getcorever"] = function(t) return "rrpc,getcorever," .. rtos.get_version() end,
    ["getlocation"] = function(t) return "rrpc,location," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0) end,
    ["getreallocation"] = function(t)
        lbsLoc.request(function(result, lat, lng, addr)
            if result then
                lbs.lat, lbs.lng = lat, lng
                create.setLocation(lat, lng)
            end
        end)
        return "rrpc,location," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0)
    end,
    ["gettime"] = function(t)
        if ntp.isEnd() then
            local c = misc.getClock()
            return "rrpc,nettime," .. string.format("%04d,%02d,%02d,%02d,%02d,%02d\r\n", c.year, c.month, c.day, c.hour, c.min, c.sec)
        else
            return "rrpc,nettime,error"
        end
    end,
    ["setpio"] = function(t) if pios["pio" .. t[1]] then pios["pio" .. t[1]](tonumber(t[2]) or 0) return "OK" end return "ERROR" end,
    ["getpio"] = function(t) if pios["pio" .. t[1]] then return "rrpc,getpio" .. t[1] .. "," .. pios["pio" .. t[1]]() end return "ERROR" end,
    ["getsht"] = function(t) local tmp, hum = iic.sht(2, tonumber(t[1])) return "rrpc,getsht," .. (tmp or 0) .. "," .. (hum or 0) end,
    ["getam2320"] = function(t) local tmp, hum = iic.am2320(2, tonumber(t[1])) return "rrpc,getam2320," .. (tmp or 0) .. "," .. (hum or 0) end,
    ["netstatus"] = function(t) return "rrpc,netstatus," .. (create.getDatalink() and "RDY" or "NORDY") end,
    ["gps_wakeup"] = function(t)sys.publish("REMOTE_WAKEUP") return "rrpc,gps_wakeup,OK" end,
    ["gps_getsta"] = function(t) return "rrpc,gps_getsta," .. tracker.deviceMessage(t[1] or "json") end,
    ["gps_getmsg"] = function(t) return "rrpc,gps_getmsg," .. tracker.locateMessage(t[1] or "json") end,
    ["upconfig"] = function(t)sys.publish("UPDATE_DTU_CNF") return "rrpc,upconfig,OK" end,
    ["function"] = function(t)log.info("rrpc,function:", table.concat(t, ",")) return "rrpc,function," .. (loadstring(table.concat(t, ","))() or "OK") end,
    ["tts_play"] = function(t)
        if not isTTS then return "rrpc,tts_play,not_tts_lod" end
        local str = string.upper(t[1]) == "GB2312" and common.gb2312ToUtf8(t[2]) or t[2]
        audio.play(1, "TTS", str, tonumber(t[3]) or 7, nil, false, 0)
        return "rrpc,tts_play,OK"
    end
}

-- 串口读指令
local function read(uid)
    local s = table.concat(recvBuff[uid])
    recvBuff[uid] = {}
    -- 串口流量统计
    flowCount[uid] = flowCount[uid] + #s
    -- log.info("UART_" .. uid .. "read length:", #s)
    log.info("UART_" .. uid .. "read:", #s, (s:sub(1, 100):toHex()))
    log.info("串口流量统计值:", flowCount[uid])
    -- 根据透传标志位判断是否解析数据
    if s:sub(1, 3) == "+++" or s:sub(1, 5):match("(.+)\r\n") == "+++" then
        write(uid, "OK\r\n")
        if io.exists(CONFIG) then os.remove(CONFIG) end
        if io.exists("/alikey.cnf") then os.remove("/alikey.cnf") end
        if io.exists("/qqiot.dat") then os.remove("/qqiot.dat") end
        if io.exists("/bdiot.dat") then os.remove("/bdiot.dat") end
        sys.restart("Restore default parameters:", "OK")
    end
    -- DTU的参数配置
    if s:sub(1, 7) == "config," or s:sub(1, 5) == "rrpc," then
        local t = s:match("(.+)\r\n") and s:match("(.+)\r\n"):split(',') or s:split(',')
        local first = table.remove(t, 1)
        local second = table.remove(t, 1) or ""
        if tonumber(second) and tonumber(second) > 0 and tonumber(second) < 8 then
            write(uid, cmd[first]["pipe"](t, second) .. "\r\n")
            return
        else
            if cmd[first][second] then write(uid, cmd[first][second](t, s) .. "\r\n") return end
        end
    end
    -- 执行单次HTTP指令
    if s:sub(1, 5) == "http," then
        local str = ""
        local idx1, idx2, jsonstr = s:find(",[\'\"](.+)[\'\"],")
        if jsonstr then
            str = s:sub(1, idx1) .. s:sub(idx2, -1)
        else
            -- 判是不是json，如果不是json，则是普通的字符串
            idx1, idx2, jsonstr = s:find(",([%[{].+[%]}]),")
            if jsonstr then
                str = s:sub(1, idx1) .. s:sub(idx2, -1)
            else
                str = s
            end
        end
        local t = str:match("(.+)\r\n") and str:match("(.+)\r\n"):split(',') or str:split(',')
        if not socket.isReady() then write(uid, "NET_NORDY\r\n") return end
        sys.taskInit(function(t, uid)
            local code, head, body = httpv2.request(t[2]:upper(), t[3], (t[4] or 10) * 1000, nil, jsonstr or t[5], tonumber(t[6]) or 1, t[7], t[8])
            log.info("uart http response:", body)
            write(uid, body)
        end, t, uid)
        return
    end
    -- 执行单次SOCKET透传指令
    if s:sub(1, 4):upper() == "TCP," or s:sub(1, 4):upper() == "UDP," then
        -- local t = s:match("(.+)\r\n") and s:match("(.+)\r\n"):split(',') or s:split(',')
        s = s:match("(.+)\r\n") or s
        if not socket.isReady() then
            write(uid, "NET_NORDY\r\n")
            return
        end
        sys.taskInit(function(uid, prot, ip, port, ssl, timeout, data)
            local c = prot:upper() == "TCP" and socket.tcp(ssl and ssl:lower() == "ssl") or socket.udp()
            while not c:connect(ip, port) do sys.wait(2000) end
            if c:send(data) then
                write(uid, "SEND_OK\r\n")
                local r, s = c:recv(timeout * 1000)
                if r then write(uid, s) end
            else
                write(uid, "SEND_ERR\r\n")
            end
            c:close()
        end, uid, s:match("(.-),(.-),(.-),(.-),(.-),(.+)"))
        return
    end
    -- 添加设备识别码
    if tonumber(dtu.passon) == 1 then
        local interval, samptime = create.getTimParam()
        if interval[uid] > 0 then -- 定时采集透传模式
            -- 这里注意间隔时长等于预设间隔时长的时候就要采集,否则1秒的采集无法采集
            if os.difftime(os.time(), startTime[uid]) >= interval[uid] then
                if os.difftime(os.time(), startTime[uid]) < interval[uid] + samptime[uid] then
                    table.insert(sendBuff[uid], s)
                elseif startTime[uid] == 0 then
                    -- 首次上电立刻采集1次
                    table.insert(sendBuff[uid], s)
                    startTime[uid] = os.time() - interval[uid]
                else
                    startTime[uid] = os.time()
                    if #sendBuff[uid] ~= 0 then
                        sys.publish("NET_SENT_RDY_" .. uid, tonumber(dtu.plate) == 1 and misc.getImei() .. table.concat(sendBuff[uid]) or table.concat(sendBuff[uid]))
                        sendBuff[uid] = {}
                    end
                end
            else
                sendBuff[uid] = {}
            end
        else -- 正常透传模式
            sys.publish("NET_SENT_RDY_" .. uid, tonumber(dtu.plate) == 1 and misc.getImei() .. s or s)
        end
    else
        -- 非透传模式,解析数据
        if s:sub(1, 5) == "send," then
            sys.publish("NET_SENT_RDY_" .. s:sub(6, 6), s:sub(8, -1))
        else
            write(uid, "ERROR\r\n")
        end
    end
end

-- uart 的初始化配置函数
function uart_INIT(i, uconf)
    if not is8910 and i == 3 then return end
    uart.setup(i, uconf[i][2], uconf[i][3], uconf[i][4], uconf[i][5], nil, 1)
    uart.on(i, "sent", writeDone)
    uart.on(i, "receive", function(uid, length)
        table.insert(recvBuff[uid], uart.read(uid, length or 8192))
        sys.timerStart(sys.publish, tonumber(dtu.uartReadTime) or 500, "UART_RECV_WAIT_" .. uid, uid)
    end)
    -- 处理串口接收到的数据
    sys.subscribe("UART_RECV_WAIT_" .. i, read)
    sys.subscribe("UART_SENT_RDY_" .. i, write)
    -- 网络数据写串口延时分帧
    sys.subscribe("NET_RECV_WAIT_" .. i, function(uid, str)
        if tonumber(dtu.netReadTime) and tonumber(dtu.netReadTime) > 5 then
            for j = 1, #str, SENDSIZE do
                table.insert(writeBuff[uid], str:sub(j, j + SENDSIZE - 1))
            end
            sys.timerStart(sys.publish, tonumber(dtu.netReadTime) or 30, "UART_SENT_RDY_" .. uid, uid, true)
        else
            sys.publish("UART_SENT_RDY_" .. uid, uid, str)
        end
    end)
    -- 485方向控制
    if not dtu.uconf[i][6] or dtu.uconf[i][6] == "" then -- 这么定义是为了和之前的代码兼容
        if i == 1 then
            if is8910 then
                default["dir1"] = 18
            elseif is1802S then
                default["dir1"] = 61
            elseif is4gLod then
                default["dir1"] = 23
            else
                default["dir1"] = 2
            end
        elseif i == 2 then
            if is8910 then
                default["dir2"] = 23
            elseif is1802S then
                default["dir2"] = 32
            elseif is4gLod then
                default["dir2"] = 59
            else
                default["dir2"] = 6
            end
        end
    else
        if pios[dtu.uconf[i][6]] then
            default["dir" .. i] = tonumber(dtu.uconf[i][6]:sub(4, -1))
            pios[dtu.uconf[i][6]] = nil
        else
            default["dir" .. i] = nil
        end
    end
    if default["dir" .. i] then
        pins.setup(default["dir" .. i], 0)
        uart.set_rs485_oe(i, default["dir" .. i])
    end
end
------------------------------------------------ 远程任务 ----------------------------------------------------------
-- 远程自动更新参数和更新固件任务每隔24小时检查一次
sys.taskInit(function()
    local rst, code, head, body, url = false
    while true do
        rst = false
        if not socket.isReady() and not sys.waitUntil("IP_READY_IND", 600000) then sys.restart("Network initialization failed!") end
        if dtu.host and dtu.host ~= "" then
            local param = {product_name = _G.PROJECT, param_ver = dtu.param_ver, imei = misc.getImei()}
            code, head, body = httpv2.request("GET", dtu.host, 30000, param, nil, 1)
        else
            url = "dtu.openluat.com/api/site/device/" .. misc.getImei() .. "/param?product_name=" .. _G.PROJECT .. "&param_ver=" .. dtu.param_ver
            code, head, body = httpv2.request("GET", url, 30000, nil, nil, 1, misc.getImei() .. ":" .. misc.getMuid())
        end
        if tonumber(code) == 200 and body then
            -- log.info("Parameters issued from the server:", body)
            local dat, res, err = json.decode(body)
            if res and tonumber(dat.param_ver) ~= tonumber(dtu.param_ver) then
                io.writeFile(CONFIG, body)
                rst = true
            end
        end
        
        -- 检查是否有更新程序
        if tonumber(dtu.fota) == 1 then
            log.info("----- update firmware:", "start!")
            -- if (is4gLod) and rtos.fota_start() == 0 then
            --     if is8910 then
            --         local coreVer = rtos.get_version()
            --         local coreName1, coreName2 = coreVer:match("(.-)_V%d+(_.+)")
            --         local coreVersion = tonumber(coreVer:match(".-_V(%d+)"))
            --         url = "iot.openluat.com/api/site/firmware_upgrade?project_key=" .. _G.PRODUCT_KEY
            --             .. "&imei=" .. misc.getImei()
            --             .. "&firmware_name=" .. _G.PROJECT .. "_" .. coreName1 .. coreName2 .. "&core_version=" .. coreVersion .. "&dfota=1&version=" .. _G.VERSION
            --     else
            --         url = "iot.openluat.com/api/site/firmware_upgrade?project_key=" .. _G.PRODUCT_KEY
            --             .. "&imei=" .. misc.getImei() .. "&device_key=" .. misc.getSn()
            --             .. "&firmware_name=" .. _G.PROJECT .. "_" .. rtos.get_version() .. "&version=" .. _G.VERSION
            --     end
            --     code, head, body = httpv2.request("GET", url, 30000, nil, nil, nil, nil, nil, nil, rtos.fota_process)
            --     if tonumber(code) == 200 or tonumber(code) == 206 then rst = true end
            --     rtos.fota_end()
            -- elseif not is4gLod then
            --     url = "iot.openluat.com/api/site/firmware_upgrade?project_key=" .. _G.PRODUCT_KEY
            --         .. "&imei=" .. misc.getImei() .. "&device_key=" .. misc.getSn()
            --         .. "&firmware_name=" .. _G.PROJECT .. "_" .. rtos.get_version() .. "&version=" .. _G.VERSION
            --     code, head, body = httpv2.request("GET", url, 30000)
            --     if tonumber(code) == 200 and body and #body > 1024 then
            --         io.writeFile("/luazip/update.bin", body)
            --         rst = true
            --     end
            -- end
            update.request(function(res)
                sys.publish("IRTU_UPDATE_RES", res == true)
            end, nil, 86400000)
            local res, val = sys.waitUntil("IRTU_UPDATE_RES")
            rst = rst or val
            log.info("----- update firmware:", "end!")
        end
        if rst then sys.restart("DTU Parameters or firmware are updated!") end
        ---------- 基站坐标查询 ----------
        lbsLoc.request(function(result, lat, lng, addr)
            if result then
                lbs.lat, lbs.lng = lat, lng
                create.setLocation(lat, lng)
            end
        end)
        ---------- 启动网络任务 ----------
        sys.publish("DTU_PARAM_READY")
        log.warn("短信或电话请求更新:", sys.waitUntil("UPDATE_DTU_CNF", 86400000))
    end
end)

local callFlag = false
sys.subscribe("CALL_INCOMING", function(num)
    log.info("Telephone number:", num)
    if num:match(dtu.preset.number) then
        if not callFlag then
            callFlag = true
            sys.timerStart(cc.hangUp, dtu.preset.delay * 1000, num)
            sys.timerStart(sys.publish, (dtu.preset.delay + 5) * 1000, "UPDATE_DTU_CNF")
        end
    else
        cc.hangUp(num)
    end
end)

sys.subscribe("CALL_DISCONNECTED", function()
    callFlag = false
    sys.timerStopAll(cc.hangUp)
end)

sms.setNewSmsCb(function(num, data, datetime)
    log.info("Procnewsms", num, data, datetime)
    if num:match(dtu.preset.number) and data == dtu.preset.smsword then
        sys.publish("UPDATE_DTU_CNF")
    end
end)

-- 初始化配置UART1和UART2
local uidgps = dtu.gps and dtu.gps.fun and tonumber(dtu.gps.fun[1])
if uidgps ~= 1 and dtu.uconf and dtu.uconf[1] and tonumber(dtu.uconf[1][1]) == 1 then uart_INIT(1, dtu.uconf) end
if uidgps ~= 2 and dtu.uconf and dtu.uconf[2] and tonumber(dtu.uconf[2][1]) == 2 then uart_INIT(2, dtu.uconf) end
if is8910 and uidgps ~= 3 and dtu.uconf and dtu.uconf[3] and tonumber(dtu.uconf[3][1]) == 3 then uart_INIT(3, dtu.uconf) end
-- 启动GPS任务
if uidgps then
    -- 从pios列表去掉自定义的io
    if dtu.gps.pio then
        for i = 1, 3 do if pios[dtu.gps.pio[i]] then pios[dtu.gps.pio[i]] = nil end end
    end
    sys.taskInit(tracker.sensMonitor, unpack(dtu.gps.pio))
    sys.taskInit(tracker.alert, unpack(dtu.gps.fun))
end

---------------------------------------------------------- 预警任务线程 ----------------------------------------------------------
if dtu.warn and dtu.warn.gpio and #dtu.warn.gpio > 0 then
    for i = 1, #dtu.warn.gpio do
        pins.setup(tonumber(dtu.warn.gpio[i][1]:sub(4, -1)), function(msg)
            if (msg == cpu.INT_GPIO_NEGEDGE and tonumber(dtu.warn.gpio[i][2]) == 1) or (msg == cpu.INT_GPIO_POSEDGE and tonumber(dtu.warn.gpio[i][3]) == 1) then
                if tonumber(dtu.warn.gpio[i][6]) == 1 then sys.publish("NET_SENT_RDY_" .. dtu.warn.gpio[i][5], dtu.warn.gpio[i][4]) end
                if dtu.preset and tonumber(dtu.preset.number) then
                    if tonumber(dtu.warn.gpio[i][7]) == 1 then sms.send(dtu.preset.number, common.utf8ToGb2312(dtu.warn.gpio[i][4])) end
                    if tonumber(dtu.warn.gpio[i][8]) == 1 then
                        if cc and cc.dial then
                            cc.dial(dtu.preset.number, 5)
                        else
                            ril.request(string.format("%s%s;", "ATD", dtu.preset.number), nil, nil, 5)
                        end
                    end
                end
            end
        end, pio.PULLUP)
    end
end

local function adcWarn(adcid, und, lowv, over, highv, diff, msg, id, sfreq, upfreq, net, note, tel)
    local upcnt, scancnt, adcValue, voltValue = 0, 0, 0, 0
    diff = tonumber(diff) or 1
    lowv = tonumber(lowv) or 1
    highv = tonumber(highv) or 4200
    while true do
        -- 获取ADC采样电压
        scancnt = scancnt + 1
        if scancnt == tonumber(sfreq) then
            if adcid == 0 or adcid == 1 then
                adc.open(adcid)
                adcValue, voltValue = adc.read(adcid)
                if adcValue ~= 0xFFFF or voltValue ~= 0xFFFF then
                    voltValue = (voltValue - voltValue % 3) / 3
                end
                adc.close(adcid)
            else
                voltValue = misc.getVbatt()
            end
            scancnt = 0
        end
        -- 处理上报
        if ((tonumber(und) == 1 and voltValue < tonumber(lowv)) or (tonumber(over) == 1 and voltValue > tonumber(highv))) then
            if upcnt == 0 then
                if tonumber(net) == 1 then sys.publish("NET_SENT_RDY_" .. id, msg) end
                if tonumber(note) == 1 and dtu.preset and tonumber(dtu.preset.number) then sms.send(dtu.preset.number, common.utf8ToGb2312(msg)) end
                if tonumber(tel) == 1 and dtu.preset and tonumber(dtu.preset.number) then
                    if cc and cc.dial then
                        cc.dial(dtu.preset.number, 5)
                    else
                        ril.request(string.format("%s%s;", "ATD", dtu.preset.number), nil, nil, 5)
                    end
                end
                upcnt = tonumber(upfreq)
            else
                upcnt = upcnt - 1
            end
        end
        -- 解除警报
        if voltValue > tonumber(lowv) + tonumber(diff) and voltValue < tonumber(highv) - tonumber(diff) then upcnt = 0 end
        sys.wait(1000)
    end
end
if dtu.warn and dtu.warn.adc0 and dtu.warn.adc0[1] then
    sys.taskInit(adcWarn, 0, unpack(dtu.warn.adc0))
end
if dtu.warn and dtu.warn.adc1 and dtu.warn.adc1[1] then
    sys.taskInit(adcWarn, 1, unpack(dtu.warn.adc1))
end
if dtu.warn and dtu.warn.vbatt and dtu.warn.vbatt[1] then
    sys.taskInit(adcWarn, 9, unpack(dtu.warn.vbatt))
end

---------------------------------------------------------- 参数配置,任务转发，线程守护主进程----------------------------------------------------------
sys.taskInit(create.connect, pios, dtu.conf, dtu.reg, tonumber(dtu.convert) or 0, (tonumber(dtu.passon) == 0), dtu.upprot, dtu.dwprot)

---------------------------------------------------------- 用户自定义任务初始化 ---------------------------------------------------------
if dtu.task and #dtu.task ~= 0 then
    for i = 1, #dtu.task do
        if dtu.task[i] and dtu.task[i]:match("function(.+)end") then
            sys.taskInit(loadstring(dtu.task[i]:match("function(.+)end")))
        end
    end
end

sys.timerLoopStart(function()
    log.info("打印占用的内存:", _G.collectgarbage("count"))-- 打印占用的RAM
    log.info("打印可用的空间", rtos.get_fs_free_size())-- 打印剩余FALSH，单位Byte
-- socket.printStatus()
end, 10000)
