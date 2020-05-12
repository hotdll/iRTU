--- 模块功能：录音处理
-- @module record
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.11.23

require "log"
require "ril"
module(..., package.seeall)


local ID, FILE = 1, '/record.amr'
local recording
local stoping
local recordCb
local stopCbFnc

--- 开始录音
-- @param seconds 录音时长，单位：秒
-- @param cb 录音结果回调
-- @return result true - 开始录音 其他 - 失败
-- @usage result = record.start()
function start(seconds, cb)
    if recording or stoping or seconds <= 0 or seconds > 50 then
        log.error('record.start', recording, stoping, seconds)
        if cb then cb() end
        return
    end
    delete()
    --param1: 录音保存文件
    --param2: 录音时长 n:单位秒
    --param3: 录音质量 n:0：一般质量 1：中等质量 2：高质量 3：无损质量
    --param4：录音类型 n:1:mic 2:voice 3:voice_dual
    --param5：录音文件类型 n: 1:pcm 2:wav 3:amrnb
    audiocore.record(FILE,seconds,1,1,3)
    log.info("record.start",seconds)
    recording = true
    recordCb = cb
    return true
end

--- 停止录音
-- @function[opt=nil] cbFnc，停止录音的回调函数(停止结果通过此函数通知用户)，回调函数的调用形式为：
--      cbFnc(result)
--      result：number类型
--              0表示停止成功
--              1表示之前已经发送了停止动作，请耐心等待停止结果的回调
-- @usage record.stop(cb)
function stop(cbFnc)
    if not recording then
        if cbFnc then cbFnc(0) end
        return
    end
    if stoping then
        if cbFnc then cbFnc(1) end
        return
    end
    stopCbFnc = cbFnc
    audiocore.stoprecord()
    stoping = true
end

--- 读取录音文件的完整路径
-- @return string 录音文件的完整路径
-- @usage filePath = record.getFilePath()
function getFilePath()
    return FILE
end

--- 读取录音数据
-- @param offset 偏移位置
-- @param len 长度
-- @return data 录音数据
-- @usage data = record.getData(0, 1024)
function getData(offset, len)
    local f = io.open(FILE, "rb")
    if not f then log.error('record.getData', 'open failed') return "" end
    if not f:seek("set", offset) then log.error('record.getData', 'seek failed') f:close() return "" end
    local data = f:read(len)
    f:close()
    log.info("record.getData", data and data:len() or 0)
    return data or ""
end

--- 读取录音文件总长度，录音时长
-- @return fileSize 录音文件大小
-- @return duration 录音时长
-- @usage fileSize, duration = record.getSize()
function getSize()
    local size,duration = io.fileSize(FILE),0
    if size>6 then
        duration = ((size-6)-((size-6)%1600))/1600
    end
    return size, duration
end

--- 删除录音
-- @usage record.delete()
function delete()
    audiocore.deleterecord()
    os.remove(FILE)
end

--- 判断是否存在录音
-- @return result true - 有录音 false - 无录音
-- @usage result = record.exists()
function exists()
    return io.exists(FILE)
end

--- 是否正在处理录音
-- @return result true - 正在处理 false - 空闲
-- @usage result = record.isBusy()
function isBusy()
    return recording or stoping
end


rtos.on(rtos.MSG_RECORD,function(msg)
    log.info("record.MSG_RECORD",msg.record_end_ind,msg.record_error_ind)
    --文件录音，在回调时可以删除录音buf；但是流录音，一定要等buf读取完成后，再删除
    audiocore.deleterecord()
    if msg.record_error_ind then
        delete()
        if recordCb then recordCb(false,0) recordCb = nil end
        recording = false
        stoping = false
        if stopCbFnc then stopCbFnc(0) stopCbFnc=nil end
    end
    if msg.record_end_ind then
        if recordCb then recordCb(true,io.fileSize(FILE)) recordCb = nil end
        recording = false
        stoping = false
        if stopCbFnc then stopCbFnc(0) stopCbFnc=nil end
    end
end)

