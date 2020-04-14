--- 模块功能：阿里云物联网套件客户端OTA功能.
-- 目前固件签名算法仅支持MD5
-- @module aLiYunOta
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.04.16

require"log"
require"http"

module(..., package.seeall)

--gVersion：固件版本号字符串，如果用户没有调用本文件的setVer接口设置，则默认为_G.PROJECT.."_".._G.VERSION.."_"..sys.getcorever()
--gName：阿里云iot网站上配置的新固件文件下载后，在模块中的保存路径，如果用户没有调用本文件的setName接口设置，则默认为/luazip/update.bin
--gCb：新固件下载成功后，要执行的回调函数
local gVersion,gName,gCb = _G.PROJECT.."_".._G.VERSION.."_"..rtos.get_version()
local gFilePath,gFileSize
local processed = 0
--productKey：产品标识
--deviceName：设备名称
local productKey,deviceName

--verRpted：版本号是否已经上报
local verRpted,sConnected
--lastStep：最后一次上报的下载新固件的进度
local lastStep
--下载中标志
local downloading

local function otaCb(result,filePath,md5,size)
    log.info("aLiYunOta.otaCb",gCb,result,filePath,size,(type(gName) =="string") and io.fileSize(filePath) or "function")
    downloading = false
    --校验MD5
    if result then
        if type(gName) == "string" then
            local calMD5 = crypto.md5(filePath,"file")
            result = (string.upper(calMD5) == string.upper(md5))
            log.info("aLiYunOta.otaCb cmp md5",result,calMD5,md5)
        else
            rtos.fota_end()
            log.info("aLiYunOta.otaCb",result,size)
        end
    end
    if gCb then
        gCb(result,filePath)
    else
        if result then sys.restart("ALIYUN_OTA") end
    end
end

--[[
函数名：upgradeStepRpt
功能  ：新固件文件下载进度上报
参数  ：
        step：1到100代表下载进度比；-2代表下载失败
        desc：描述信息，可为空或者nil
返回值：无
]]
local function upgradeStepRpt(step,desc)
    log.info("aLiYunOta.upgradeStepRpt",step,desc,sConnected)
    if sConnected then
        if step<=0 or step==100 then sys.timerStop(getPercent) end
        lastStep = step
        aLiYun.publish("/ota/device/progress/"..productKey.."/"..deviceName,"{\"id\":1,\"params\":{\"step\":\""..step.."\",\"desc\":\""..(desc or "").."\"}}")
    end
end

function getPercent()    
    local step
    if type(gName) == "string" then
        step = io.fileSize(gName)*100/gFileSize
    else
        step = processed*100/gFileSize
    end
    log.info("aLiYunOta.getPercent",step)
    if step~=0 and step~=lastStep then
        upgradeStepRpt(step)
    end
    sys.timerStart(getPercent,5000)
end

local function downloadCbFnc(result,prompt,head,filePath)
    log.info("aLiYunOta.downloadCbFnc",result,prompt,filePath)
    sys.publish("ALIYUN_OTA_DOWNLOAD_IND",result)
end

local function saveUpdata(pdata,binlen,statusCode)
    log.info("saveUpdata",binlen,statusCode)
    if statusCode == "206" and pdata and binlen then
        if rtos.fota_process(pdata,binlen) ~=0 then  --返回-94表示没有进行初始化，需要调用rtos.fota_start()进行更新初始化
            log.info("updata.fota_process","fail!!")
            return
        else
            --打印此升级包的长度跟总包长度
            processed = processed + pdata:len()
            log.info("updata.fota_process",processed,binlen)
        end
    end    
end

local function downloadTask(url,size,md5)
    log.info("aLiYunOta.downloadTask1",downloading,url,size,md5)
    if not downloading then
        downloading = true
        gFileSize = size
        
        local rangeBegin,retryCnt = 0,0
        sys.timerStart(getPercent,5000)
        while true do
            if not gName then
                gName = saveUpdata
            end
            http.request("GET",url,nil,{["Range"]="bytes="..rangeBegin.."-"},"",20000,downloadCbFnc,gName)
            --if rangeBegin==0 then os.remove(gName) end
            local _,result = sys.waitUntil("ALIYUN_OTA_DOWNLOAD_IND")
            log.info("aLiYunOta.downloadTask2",result) 
            if result then
                upgradeStepRpt(100,0)
                sys.timerStart(otaCb,5000,true,gName,md5,size)
                break
            else
                retryCnt = retryCnt+1
                if retryCnt>=30 then
                    upgradeStepRpt(-2,"timeout")
                    otaCb(false,gName)
                    break
                end
            end
            if type(gName) == "string" then
                rangeBegin = io.fileSize(gName)
            else
                rangeBegin = processed
            end
        end
    end
end


--[[
函数名：upgrade
功能  ：收到云端固件升级通知消息时的回调函数
参数  ：
        payload：消息负载（原始编码，收到的payload是什么内容，就是什么内容，没有做任何编码转换）
返回值：无
]]
function upgrade(payload)
    local result
    local jsonData,result = json.decode(payload)
    log.info("aLiYunOta.upgrade",result,payload)
    if rtos.fota_start() ~=0 then 
        log.info("fota_start fail")
        sys.timerStart(verRpt,10000)
        return
    end     
    if result and jsonData.data and jsonData.data.url then
        sys.taskInit(downloadTask,jsonData.data.url,jsonData.data.size,jsonData.data.md5)
    end
end


--[[
函数名：verRptCb
功能  ：上报固件版本号给云端后，收到PUBACK时的回调函数
参数  ：
        result：true表示上报成功，false或者nil表示失败
返回值：无
]]
local function verRptCb(result)
    log.info("aLiYunOta.verRptCb",result)
    verRpted = result
    if not result then sys.timerStart(verRpt,20000) end
end

--[[
函数名：verRpt
功能  ：上报固件版本号给云端
参数  ：无
返回值：无
]]
function verRpt()
    log.info("aLiYunOta.verRpt",sConnected,gVersion)
    if sConnected then
        aLiYun.publish("/ota/device/inform/"..productKey.."/"..deviceName,"{\"id\":1,\"params\":{\"version\":\""..gVersion.."\"}}",1,verRptCb)
    end
end

function connectCb(result,key,name)
    sConnected = result
    if result then
        log.info("aLiYunOta.connectCb",verRpted)
        productKey,deviceName = key,name
        --订阅主题
        aLiYun.subscribe({["/ota/device/upgrade/"..key.."/"..name]=0, ["/ota/device/upgrade/"..key.."/"..name]=1})
        if not verRpted then        
            --上报固件版本号给云端
            verRpt()
        end
    else
        sys.timerStop(verRpt)
    end
end

--- 设置当前的固件版本号
-- @string version，当前固件版本号
-- @return nil
-- @usage
-- aLiYunOta.setVer("MCU_VERSION_1.0.0")
function setVer(version)
    local oldVer = gVersion
    gVersion = version
    if verRpted and version~=oldVer then        
        verRpted = false
        verRpt()
    end
end

--- 设置新固件保存的文件名
-- @string name，新固件下载后保存的文件名；注意此文件名并不是保存的完整路径，完整路径通过setCb设置的回调函数去获取
-- @return nil
-- @usage
-- aLiYunOta.setName("MCU_FIRMWARE.bin")
function setName(name)
    gName = name
end

--- 设置新固件下载后的回调函数
-- @function cbFnc，新固件下载后的回调函数
-- 回调函数的调用形式为：cbFnc(result,filePath)，result为下载结果，true表示成功，false或者nil表示失败；filePath为新固件文件保存的完整路径
-- @return nil
-- @usage
-- aLiYunOta.setCb(cbFnc)
function setCb(cbFnc)
    gCb = cbFnc
end
