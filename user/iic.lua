--- AM2320 温湿度传感器驱动
-- @module AM2320
-- @author 稀饭放姜
-- @license MIT
-- @copyright openLuat.com
-- @release 2017.10.19
require "utils"
require "log"
module(..., package.seeall)

local float = rtos.get_version():upper():find("FLOAT")
-- 初始化并打开I2C操作
-- @param I2C 内部ID
-- @return number ,I2C的速率
local function i2c_open(id)
    if i2c.setup(id, i2c.SLOW) ~= i2c.SLOW then
        i2c.close(id)
        return i2c.setup(id, i2c.SLOW)
    end
    return i2c.SLOW
end

--- 读取AM2320的数据
-- @number id, 端口号0-2
-- @return string，string，第一个参数是温度，第二个是湿度
-- @usage tmp, hum = read()
function am2320(id, addr)
    id, addr = id or 2, addr or 0x5C
    if not i2c_open(id) then return end
    i2c.send(id, addr, 0x03)
    i2c.send(id, addr, {0x03, 0x00, 0x04})
    local data = i2c.recv(id, addr, 8)
    if data == nil or data == 0 then return end
    log.info("AM2320 HEX data: ", data:toHex())
    i2c.close(id)
    local _, crc = pack.unpack(data, '<H', 7)
    data = data:sub(1, 6)
    if crc == crypto.crc16_modbus(data, 6) then
        local _, hum, tmp = pack.unpack(string.sub(data, 3, -1), '>H2')
        if tmp == nil or hum == nil then return 0, 0 end
        if tmp >= 0x8000 then tmp = 0x8000 - tmp end
        if float then
            tmp, hum = tmp / 10, hum / 10
        else
            tmp = tmp / 10 .. "." .. tmp % 10
            hum = hum / 10 .. "." .. hum % 10
        end
        log.info("AM2320 data: ", tmp, hum)
        return tmp, hum
    end
end

--- 读取SHT21的数据
-- @number id, 端口号0-2
-- @return string，string，第一个参数是温度，第二个是湿度
-- @usage tmp, hum = read()
function sht(id, addr)
    local _, tmp, hum
    id, addr = id or 2, addr or 0x40
    if not i2c_open(id) then return end
    i2c.send(id, addr, 0xE3)
    tmp = i2c.recv(id, addr, 2)
    log.info("SHT读取到的温度寄存器24位值:", tmp:toHex())
    i2c.send(id, addr, 0xE5)
    hum = i2c.recv(id, addr, 2)
    log.info("SHT读取到的湿度寄存器24位值:", hum:toHex())
    i2c.close(id)
    _, tmp = pack.unpack(tmp, '>H')
    _, hum = pack.unpack(hum, '>H')
    if tmp == nil or hum == nil then return 0, 0 end
    tmp = bit.band(tmp, 0xFFFC)
    hum = bit.band(hum, 0xFFFC)
    if float then
        hum = (hum * 12500 / 65536 - 600) / 100
        tmp = (tmp * 17572 / 65536 - 4685) / 100
    else
        tmp = tmp * 17572 / 65536 - 4685
        hum = hum * 12500 / 65536 - 600
        tmp = tmp / 100 .. "." .. tmp % 100
        hum = hum / 100 .. "." .. hum % 100
    end
    log.info("当前温度是:", tmp, "当前湿度是:", hum .. "%")
    return tmp, hum
end
