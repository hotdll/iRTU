--必须在这个位置定义PROJECT和VERSION变量
--PROJECT：ascii string类型，可以随便定义，只要不使用,就行
--VERSION：ascii string类型，如果使用Luat物联云平台固件升级的功能，必须按照"X.X.X"定义，X表示1位数字；否则可随便定义
PROJECT = "iRTU"
VERSION = "1.8.11"
PRODUCT_KEY = "DPVrZXiffhEUBeHOUwOKTlESam3aXvnR"

--加载日志功能模块，并且设置日志输出等级
--如果关闭调用log模块接口输出的日志，等级设置为log.LOG_SILENT即可
require "log"
-- LOG_LEVEL = log.LOGLEVEL_INFO
LOG_LEVEL = log.LOGLEVEL_TRACE
require "sys"
require "net"
require "utils"
require "patch"

--每1分钟查询一次GSM信号强度
--每1分钟查询一次基站信息
net.startQueryAll(8000, 60000)
if rtos.get_version():upper():find("ASR1802") then
    ril.request("AT+MEDCR=0,8,1")
    ril.request("AT+MEDCR=0,17,240")
    ril.request("AT+MEDCR=0,19,1")
    rtos.set_trace_port(2)
elseif rtos.get_version():upper():find("8955") then
    require "wdt"
    wdt.setup(pio.P0_30, pio.P0_31)
end
--加载错误日志管理功能模块【强烈建议打开此功能】
--如下2行代码，只是简单的演示如何使用errDump功能，详情参考errDump的api
require "errDump"
errDump.request("udp://ota.airm2m.com:9072")
require "ntp"
ntp.timeSync(24, function()log.info(" AutoTimeSync is Done!") end)
--加载主程序
require "default"

--启动系统框架
sys.init(0, 0)
sys.run()
