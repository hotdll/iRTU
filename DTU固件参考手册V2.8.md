# DTU 固件参考手册 -- V2.8

## DTU 常见问题

- DTU版本默认上电是透传模式还是非透传模式，两个模式间如何转换?

    答：默认只配置了串口115200,8位数据模式，1个停止位，无校验，通道默认关闭。

- 是否有可能让在第一次去连接server时上报自己ID(可以自定义)功能?

    答：支持自定义，详见“配置保存指令”的register字段。

- 在非透传模式报文也是发的AT命令格式吗?

    答：不用AT,非透传模式参考指令“多通道通信报文

- 恢复默认设置有条件吗？比如低电平保持多长时间？上电前拉低?

    答：拉低25mS以上即可，不需要上电前拉低。使用云参数的话，基本上不会用到这个脚

- 心跳包是否支持自定义，有没有长度限制？

    答：心跳包支持自定义，默认是字符串“ping”,长度最大1460字节

- 是否可以指定透传模式下每次上报添加ID

    答: 支持,详见“配置保存指令”的plate字段。

- MCU配置是否有保存命令？保存以后需要命令重启还是立刻生效？

    答：发送保存指令后，模块自动重启并立刻生效。

- 如果连上server后MCU如何知道已经连上？会不会有字符串提示?

    答：连上server后，透传模式下相当于一条网线，不会有字符提示，MCU不用去维护DTU的状态。

- 可否设置如果一定时间内收不到server的心跳包，dtu自动掉电重连?

    答：内部有自动重连，开关飞行模式，重启模式，线程守护来保证DTU的网络链接正常，用户不需要干预。

- 是否支持定时采集功能?

    答：支持，以后升级会逐渐支持更多的RTU的功能，比如定时采集，定时任务预置指令采集等。

- 如何知道是SIM卡是否欠费，是否连上服务器?

    答：有两个办法：
    1 看指示灯，心跳灯（100ms亮，1900毫秒灭表示脸上服务器），快闪通常表示卡不良或欠费，慢闪表示GSM正常但是网络附着不成功。
    2 读取RDY信号（net ready信号），高电平是服务器链接成功，低电平是未连接。

- 串口是否支持流量控制？

    答：支持，在保存参数配置的“flow"参数设置每分钟最大流量值,如果流量超过，则数据丢弃。
  
- 是否支持短信或电话配置参数或更新？

    答：支持,客户预定义电话,短信，短信内容，指定电话打电话或者发短信内容为指定内容即可远程更新参数。

- 是否发送完成返回标志给MCU？

    答：支持,在MCU控制模式的时候，发送数据成功后会返回"SEND_OK"给MCU,方便MCU关闭模块。

- 网络是否连接能不能通知MCU？

    答：支持
    AIR202U的RDY信号--第6脚(GPIO_3)上电输出低电平，网络链接成功后输出高电平。
    AIR720 的RDY信号--第5脚（GPIO_65）上电输出低电平，网络链接成功后输出高电平。

- 定时采集功能支持透传和非透传模式吗？
  
    答：定时采集功能只有透传模式才能支持，支持串口1和2单独设置。

## DTU功能说明

AIR202U 是上海合宙出品的一款功能强大使用极其简单的DTU模块，借助不到10条交互指令，就可以实现绝大部分物联网的通讯需求，极大简化用户开发物联网产品的步骤，大幅度减少开发时间

- [x] 支持 MQTT/TCP/UDP 双通道透传（串口1和串口2分别对应两个透传通道）
- [x] 支持 MQTT/TCP/UDP 透传模式添加 IMEI 设备识别码(15个字节)
- [x] 支持 MQTT/TCP/UDP 多通道传输模式（非透传模式）
- [x] 支持 数据中心服务器设置，最多支持7个通道，每个通道可以任意指定串口（1,2）和协议
- [x] 支持 单片机初始化设置配置，实现免上位机配置软件配置DTU
- [x] 支持 Luat云批量初始化配置，实现全自动无人操作自动配置DTU
- [x] 支持 Luat云远程升级固件，也就是FOAT功能，可以满足用户在某些新增功能需求的时候免现场维护
- [x] 支持 透传/非透传 模式软件恢复出厂默认值
- [x] 支持 硬件恢复出厂默认值
- [x] 支持 NET 指示灯，方便用户显示各种工作状态
- [x] 支持 VSIM虚拟卡，极大简化用户成本
- [x] 支持 登陆上传DTU模块状态，方便用户获得模块信息以及登陆鉴权
- [x] 支持 DTU配置程序读取
- [x] 支持 HTTP 的GET 和 POST 请求方法
- [x] 支持 获取网络时间
- [x] 支持 获取基站定位返回的当前模块坐标
- [x] 支持 串口1和串口2 配置参数,非透传模式下，随时可以配置DTU

## DTU 配置说明
- 注意：所有串口指令返回结果都带"\r\n"
- 网络守护逻辑：
     - 开机2分钟内不能联网重启，
     - 联网成功后2分钟内不能连接服务器开关飞行模式。
     - 网络正常，服务器连接失败5分钟重启。
     - 网络断开5分钟不能恢复重启。
### 串口配置命令

- demo："config,8,1,115200,8,2,0"


| 字段     | 值           | 含义                                                         |
| -------- | ------------ | ------------------------------------------------------------ |
| config   | config       | 配置指令标识                                                 |
| id       | 8            | 通道编号8表示设置串口配置参数                                |
| uartid   | 1-2          | 串口id,1是串口2是串口2                                       |
| baud     | 1200-921600  | 1200,2400,4800,9600,14400,19200,28800,38400,57600,115200,230400,460800,921600 |
| datbits  | 7-8          | 数据位,支持7或8,默认是8                                      |
| parity   | 0-1-2        | 校验位,0是uart.PAR_EVEN,1是uart.PAR_ODD,2是uart.PAR_NONE     |
| stopbits | 0-2          | 停止位,0是1个停止位,2是2个停止位                             |
| 485DIR   | pio0-pio128, | 可选p0-p128,disable禁止485DIR,默认空，使用默认的485方向脚    |

### 用户预定义电话和短信

- demo ："config,9,13211111111,10,SMS_UPDATE"

| 字段    | 值     | 含义                                          |
| ------- | ------ | --------------------------------------------- |
| config  | config | 配置指令标识                                  |
| id      | 9      | 通道编号9表示设置用户预置号码参数             |
| number  | 电话   | 用户预置的电话号码白名单                      |
| delay   | 1-100  | 白名单的振铃延时,其他电话立刻挂断             |
| smsword | string | 短信更新参数的预定义字符串,默认是"SMS_UPDATE" |

###  设置APN
- demo : "config,a,cmiot,,"

| 字段    | 值     | 含义                                          |
| ------- | ------ | --------------------------------------------- |
| config  | config | 配置指令标识                                  |
| id      | a      | 通道编号a表示设置用户手工设置APN             |
| name  |cmiot   | APN 名称                      |
|user   | string  |用户名，没有留空           |
| password | string | 密码，没有留空 |

### 自动采集任务

- 提示：HEX指令和function函数可以同时配置比如cmd1是HEX指令，cmd2就是function指令

####  HEX指令

- demo : "config,b,1000,01 03 00 2A 3B 00 2C FF,01 03 00 2A 3B 00 2C FF"

| 字段    | 值     | 含义                                          |
| ------- | ------ | --------------------------------------------- |
| config  | config | 配置指令标识                                  |
| id      | b      | 通道编号b表示配置自动采集任务             |
| waitRevc  |1-2000   | 单位ms，发送指令后最长等待设备超时                      |
|cmd1   | 指令\|函数 |HexString 指令,例如 01 03 00 2A 3B 00 2C FF           |
|cmdN   | 指令\|函数 |HexString 指令,例如 01 03 00 2A 3B 00 2C FF           |

####  function 指令

- demo: "config,b,1000,function  return "200,ad0,ad," .. create.getADC(0)  end"

| 字段    | 值     | 含义                                          |
| ------- | ------ | --------------------------------------------- |
| config  | config | 配置指令标识                                  |
| id      | b      | 通道编号b表示配置自动采集任务             |
| waitRevc  |1-2000   | 单位ms，发送指令后最长等待设备超时                      |
|fun1   | 用户函数 |function  return "200,ad0,ad," .. create.getADC(0)  end           |
|funN   | 用户函数 |function return "402,"  .. create.getLat() .. "" .. create.getLng() end           |

- 提示：
  - 函数需要用function 开头，用end结尾,用来区别HEX指令。用串口写入该配置参数的时候，注意函数中的分号要转义处理。
  - 函数结尾return返回的数据会被发往用户配置的服务器，用户可以自定义通信报文协议。
  - 如果函数需要写入数据到串口，直接调在函数调用“uart.write(uid,str)” 类似的Luat-API。

### 用户自定义GPIO

### 数据流模版

#### 说明次功能暂时仅支持JSON一次写入

在总参数中插入数据流代码,串口写入代码很麻烦，暂时先不支持，建议大家用云端参数配置，等我想到比较好的解决办法，再更新手册。
upprot是上传通道关键字，值是个数组，数组下标1-7代表1-7通道。
dwprot是下发通道关键字, 值的含义同上。
```
	"upprot": ["function \n    local str = ...\n    local dat, result, errinfo = json.decode(str)\n    local tmp = {}\n    for i = 1, #t.sta do\n        tmp[\"val\" .. i] = dat.sta[i]\n    end\n    return json.encode(tmp)\nend", "", "", "", "", "", ""],
	"dwprot": ["", "", "", "", "", "", ""],
```

####　系统保留GPIO

－　demo: "config,pins,pio33,pio3,pio29"

| 字段    | 值          | 含义                                                    |
| ------- | ----------- | ------------------------------------------------------- |
| config  | config      | 配置指令标识                                            |
| id      | pins        | 通道编号pins表示配置GPIO                                |
| netled  | pio0-pio128 | 网络指示灯GPIO编号，例如GPIO_33 就填pio33，默认空，下同 |
| netdrdy | pio0-pio128 | 网络是否准备好GPIO编号                                  |
| RSTCNF  | pio0-pio128 | 复位DTU参数的GPIO编号                                   |

### 启用GPS功能

- GPS功能目前支持Air530/800 /801/868 以及相应的开发板。

- 启用GPS功能会占用1个串口，另外一个串口依旧可以配置DTU的各种功能

- GPS 报文JSON定义 

  - 信息 = [是否有效,时间戳,经度,纬度,海拔,方位角,速度,载噪比,定位卫星]
  - 设备 = [是否打开，震动，开锁，点火，充电，剪线，外电电压，电池电压，GPRS信号值]

  ```
  {"msg":[true,1547272725,1136037366,348581216,114,354,1,43,4]}
  {"sta":[true,false,false,false,false,false,65535,4101,11]}
  ```

- GPS报文HEX定义（报文长度固定大端）
- msg报文0xAA开头，设备信息报文0x55开头
  - [信息 | 是否有效|时间戳|经度|纬度|海拔|方位角|速度|载噪比|定位卫星]
  - [1B   |     1B| 4B  | 4B| 4B |2B | 2B  | 1B | 1B | 1B    ] = 21 Byte
  ```
  [AA 01 5C399812 43B68DF6 14C6ED60 0016 001E 0F 32 0E] 
  ```
  - [设备 |是否打开|震动|开锁|点火|充电|剪线|外电电压|电池电压|GPRS信号值]
  - [ 1B |  1B  | 1B | 1B| 1B | 1B| 1B |4B    |2B     |1B  ] = 13 byte
  ```
  [55 00 00 00 00 00 00 00006A10 1011 15]
  ```

#### GPS 的GPIO配置

- demo: "config, gps, pio, pio8 ,pio9, pio10, 0, 16"

| 字段    | 值          | 含义                                                       |
| ------- | ----------- | ---------------------------------------------------------- |
| config  | config      | 配置指令标识                                               |
| id      | gps         | 通道编号gps表示配置gps                                     |
| type    | pio         | GPS 的配置 GPIO 的标志位                                   |
| netdrdy | pio0-pio128 | GPS 定位成功指示灯 GPIO 编号，例如 GPIO_3  就填 pio3，下同 |
| vib     | pio0-pio128 | 振动传感器信号输入GPIO编号                                 |
| acc     | pio0-pio128 | ACC开锁信号输入GPIO编号注意ACC信号电压很高要用分压电阻     |
| chg     | pio0-pio128 | 内置锂电池充电状态输入GPIO编号,可为空                      |
| adc     | 0 or 1      | 检测VCC的ADC通道编号，默认0                                |
| ratio   | 1-50        | VCC/1.8V  + 1的值，是值ADC采集电压和VCC实际电压的比值      |

#### GPS 的报文配置

-- demo: "config, gps, fun, 2, 115200, 0, 5, 1, json, 100, ; ,60" 

| 字段     | 值              | 含义                                                         |
| -------- | --------------- | ------------------------------------------------------------ |
| config   | config          | 配置指令标识                                                 |
| id       | gps             | 通道编号gps表示配置gps                                       |
| type     | fun             | GPS 的配置 fun参数 的标志位                                  |
| uid      | 1 or 2          | GPS 启用的串口波特率，注意不要和socket通道同时启用           |
| buad     | 115200          | 9600-115200，注意和模块的GPS实际波特率一致                   |
| 功耗模式 | 0 or 2 or 8     | GPS工作模式: 正常，低功耗，低功耗跟踪模式                    |
| 采集间隔 | 1-600           | 单位秒，多久采集并记录一次GPS报文                            |
| 采集方式 | 0 or 1          | 0 布防采集（触发上报），1持续采集                            |
| 报文格式 | json or hex     | 设备信息和GPS定位信息上报的报文格式，支持JSON和HEX           |
| 缓冲发送 | 0 - 1000        | 0 表示不缓冲，采集后立刻上报，其他表示先加入缓冲区，然后1次上报 |
| 分隔符   | 除,外的可见字符 | 启用缓冲发送，用来分割报文的标记                             |
| 状态间隔 | 0-1440          | 单位分钟，设备信息报文上报频率，0为不上报                    |

### SOCKET通道配置指令

- demo："config,1,tcp,ping,300,180.97.81.180,57826,1"

### 

| 字段      | 值            | 含义                                              |
| --------- | ------------- | ------------------------------------------------- |
| config    | config        | 配置指令标识                                      |
| id        | 1-7           | 通道编号1-7,表示创建通信的通道                    |
| prot      | tcp-udp       | TCP协议或UDP协议                                  |
| ping      | 字符串        | 用户自定义的心跳包,只支持数字和字母,建议2-4个字节 |
| keepAlive | 60-600        | 链接超时最大时间单位秒,默认300秒                  |
| address   | 地址或域名    | socket的地址或域名                                |
| port      | 1-65536       | socket服务器的端口号                              |
| uid       | 1-2           | TCP通道捆绑的串口ID                               |
| gap       | 1-65535       | 自动采集间隔时长，单位秒。不用该功能填0或空       |
| samp      | 1-15          | 自动采集采样时长，单位秒。不用该功能填0或空       |
| taskTimer | 60-2147483647 | 自动定时采集任务间隔时间,单位秒。不用就填空       |
| SSL       | ssl           | 启用填ssl，不启用留空                             |

### MQTT通道配置指令

- code："config,1,mqtt,30,1800,180.97.80.55,1883,,,1,/company/service/,/company/device/,0,1,1"


| 字段         | 值                | 含义                                           |
| ------------ | ----------------- | ---------------------------------------------- |
| config       | config            | 配置指令标识                                   |
| id           | 1-7               | 通道编号1-7,表示创建通信的通道                 |
| mqtt         | mqtt              | 表示MQTT协议                                   |
| keepAlive    | 300               | MQTT心跳包的间隔单位秒,默认300                 |
| taskTimer    | 60-2147483647     | 自动定时采集任务间隔时间,单位秒。,默认1800秒   |
| address      | IP地址或域名      | MQTT的地址或域名                               |
| port         | 1-65536           | socket服务器的端口号                           |
| usr          | login             | MQTT的登陆账号默认""                           |
| pwd          | login             | MQTT的登陆密码默认""                           |
| cleanSession | 0-1               | MQTT是否保存会话标志位,0持久会话,1离线自动销毁 |
| sub          | /company/service/ | 订阅消息主题,                                  |
| pub          | /company/device/  | 发布消息主题，                                 |
| qos          | 0-2               | MQTT的QOS级别,默认0                            |
| retain       | 0-1               | MQTT的publish参数retain，默认0                 |
| uid          | 1-2               | MQTT通道捆绑的串口ID                           |
| clentID      | string            | 自定义客户端ID，使用IMEI做客户端ID此处留空     |
| samp         | "" or 1           | 留空主题自动添加IMEI, 1为不添加IMEI            |
| transport    | tcp \| tcp_ssl    | 传输模式，可选tcp或者tcp_ssl                   |
| will         | 字符串            | 遗嘱的主题                                     |

- MQTT订阅主题说明：
  - 单个订阅主题 -- /company/device
  - 单个订阅主题带QOS -- /company/device;1
  - 多个订阅主题带QOS -- /company/device;0;/company/imcp;1
- MQTT主题的IMEI说明:
  - samp 为 “” 或者nil(空) 时（参数意义见上表）：
    - 默认添加/IMEI为主题结尾，格式为 “用户主题/imei“
    - 发布主题和订阅主题都会自动添加/IMEI,系统会自动替换为15位的IMEI字符串
  - samp 为 1 时(参数意义见上表)：
    - 发布和订阅主题自动替换主题中的/imei/ 为模块的实际imei
    - 如果主题中不包含/imei/则不替换
  - 订阅主题带QOS(包括多个订阅), 自动替换主题中的/imei/ 为模块的实际imei,与samp的值无关



### OneNET 的配置

#### DTU协议

- demo: "config,1,onenet,dtu,ping,60,183.230.40.40,1811,RD7hbCxD6pr3t0vj,200652,sample,1"

| 字段      | 值               | 含义                                              |
| --------- | ---------------- | ------------------------------------------------- |
| config    | config           | 配置指令标识                                      |
| id        | 1-7              | 通道编号1-7,表示创建通信的通道                    |
| prot      | onenet           | OneNET 云名称                                     |
| subprot   | dtu              | 子协议                                            |
| ping      | 0x0000           | 用户自定义的心跳包,只支持数字和字母,建议2-4个字节 |
| keepAlive | 60-600           | 链接超时最大时间单位秒,默认300秒                  |
| address   | dtu.heclouds.com | OneNET的DTU模式的地址或域名                       |
| port      | 1811             | OneNET的DTU模式的服务器的端口号                   |
| code      | RD7hbCxD6pr3t0vj | OneNET产品下设备i的正式环境注册码                 |
| pid       | 200652           | OneNET 产品ID                                     |
| script    | sample           | OneNET 数据流解析脚本                             |
| uid       | 1-2              | TCP通道捆绑的串口ID                               |



#### MQTT协议

- demo： "config,1,onenet,mqtt,300,300,mqtt.heclouds.com,6002,WWNqBU2EztYUlj2a,200032,3,1,0,0,1"

| 字段         | 值                | 含义                                           |
| ------------ | ----------------- | ---------------------------------------------- |
| config       | config            | 配置指令标识                                   |
| id           | 1-7               | 通道编号1-7,表示创建通信的通道                 |
| prot         | onenet            | OneNET 云名称                                  |
| subprot      | mqtt              | 子协议                                         |
| keepAlive    | 60-600            | 链接超时最大时间单位秒,默认300秒               |
| taskTimer    | 60-2147483647     | 自动定时采集任务间隔时间,单位秒。默认1800秒    |
| address      | mqtt.heclouds.com | OneNET的MQTT服务器地址或域名                   |
| port         | 6002              | OneNET的MQTT服务器的端口号                     |
| code         | RD7hbCxD6pr3t0vj  | OneNET产品下设备i的正式环境注册码              |
| pid          | 200652            | OneNET 产品ID                                  |
| mode         | 1,3,4             | OneNET 数据流解析格式，只支持1,3,4             |
| cleanSession | 0-1               | MQTT是否保存会话标志位,0持久会话,1离线自动销毁 |
| qos          | 0-2               | MQTT的QOS级别,默认0                            |
| retain       | 0-1               | MQTT的publish参数retain，默认0                 |
| uid          | 1-2               | TCP通道捆绑的串口ID                            |

#### MODBUS协议

- demo : "config,1,onenet,modbus,120,hU6avtHWfytfxO=i7C269OPs6K8=,200652,1"

| 字段      | 值                           | 含义                             |
| --------- | ---------------------------- | -------------------------------- |
| config    | config                       | 配置指令标识                     |
| id        | 1-7                          | 通道编号1-7,表示创建通信的通道   |
| prot      | onenet                       | OneNET 云名称                    |
| subprot   | modbus                       | 子协议                           |
| keepAlive | 60-600                       | 链接超时最大时间单位秒,默认300秒 |
| key       | hU6avtHWfytfxO=i7C269OPs6K8= | 产品的Master-APIkey              |
| pid       | 200652                       | OneNET 产品ID                    |
| uid       | 1-2                          | TCP通道捆绑的串口ID              |



### 阿里云配置

- 阿里云自定义主题说明：

  - 自定义主题格式(可以直接从阿里云主题类列表)：

    /a1aWLNgJ395/${deviceName}/get
    /a1aWLNgJ395/deviceName/get
    /productKey/${deviceName}/get
    /productKey/deviceName/get

  - 订阅主题支持多个主题

    - 格式为topic;qos;topic;qos;topic;qos

  - 发布主题只支持单个主题

#### 自动注册模式

demo： "config,1,aliyun,otok,300,300,cn-shanghai,ProductKey,AccessKeyID ,AccessKeySecret,basic,0,0,1"

| 字段              | 值                    | 含义                                         |
| ----------------- | --------------------- | -------------------------------------------- |
| config            | config                | 配置指令标识                                 |
| id                | 1-7                   | 通道编号1-7，表示创建通信的通道              |
| prot              | aliyun                | 阿里云IOT的名称                              |
| type              | atuo                  | 自动注册，自动登陆，自动激活设备(一键阿里云) |
| keepAlive         | 60-600                | 链接超时最大时间单位秒,默认300秒             |
| taskTimer         | 60-2147483647         | 自动定时采集任务间隔时间,单位秒。默认1800秒  |
| 地域代码          | cn-shanghai           | RegionID,阿里云提供的地域代码值              |
| ProductKey        | 字符串                | 阿里云产品项目ID                             |
| AccessKey ID      | 字符串                | 阿里云API安全密钥ID（可用子密钥）            |
| Access Key Secret | 字符串                | 阿里云API安全密钥Secret（可用子密钥）        |
| 产品版本类型      | basic                 | 可选basic(基础班),plus(高级版)               |
| cleanSession      | 0-1                   | MQTT 保存会话标志位                          |
| QOS               | 0-1-2                 | MQTT 的 QOS 级别 :                           |
| UID               | 1-2                   | MQTT 通道捆绑的串口 ID:                      |
| subTopic          | topic\|多个"主题;qos" | 订阅主题或订阅多个主题;qos                   |
| pubTopic          | topic                 | 发布的主题                                   |

#### 一型一密

demo："config,1,aliyun,otok,300,300,cn-shanghai,ProductKey,ProductSecret,basic,0,0,1"

| 字段          | 值                    | 含义                                         |
| ------------- | --------------------- | -------------------------------------------- |
| config        | config                | 配置指令标识                                 |
| id            | 1-7                   | 通道编号1-7，表示创建通信的通道              |
| prot          | aliyun                | 阿里云IOT的名称                              |
| type          | atuo                  | 自动注册，自动登陆，自动激活设备(一键阿里云) |
| keepAlive     | 60-600                | 链接超时最大时间单位秒,默认300秒             |
| taskTimer     | 60-2147483647         | 自动定时采集任务间隔时间,单位秒。默认1800秒  |
| 地域代码      | cn-shanghai           | RegionID,阿里云提供的地域代码值              |
| ProductKey    | 字符串                | 阿里云产品项目ID                             |
| ProductSecret | 字符串                | 阿里云产品项目密钥                           |
| 产品版本类型  | basic                 | 可选basic(基础班),plus(高级版)               |
| cleanSession  | 0-1                   | MQTT 保存会话标志位                          |
| QOS           | 0-1-2                 | MQTT 的 QOS 级别 :                           |
| UID           | 1-2                   | MQTT 通道捆绑的串口 ID:                      |
| subTopic      | topic\|多个"主题;qos" | 订阅主题或订阅多个主题;qos                   |
| pubTopic      | topic                 | 发布的主题                                   |


#### 一机一密

demo："config,1,aliyun,otok,300,300,cn-shanghai,ProductKey,DeviceSecret,DeviceName,basic,0,0,1"

| 字段         | 值                    | 含义                                         |
| ------------ | --------------------- | -------------------------------------------- |
| config       | config                | 配置指令标识                                 |
| id           | 1-7                   | 通道编号1-7，表示创建通信的通道              |
| prot         | aliyun                | 阿里云IOT的名称                              |
| type         | atuo                  | 自动注册，自动登陆，自动激活设备(一键阿里云) |
| keepAlive    | 60-60                 | 链接超时最大时间单位秒,默认300秒             |
| taskTimer    | 60-2147483647         | 自动定时采集任务间隔时间,单位秒。默认1800秒  |
| 地域代码     | cn-shanghai           | RegionID,阿里云提供的地域代码值              |
| ProductKey   | 字符串                | 阿里云产品项目ID                             |
| DeviceSecret | 字符串                | 阿里云设备密钥                               |
| DeviceName   | 字符串                | 阿里云设备名称                               |
| 产品版本类型 | basic                 | 可选basic(基础班),plus(高级版)               |
| cleanSession | 0-1                   | MQTT 保存会话标志位                          |
| QOS          | 0-1-2                 | MQTT 的 QOS 级别 :                           |
| UID          | 1-2                   | MQTT 通道捆绑的串口 ID:                      |
| subTopic     | topic\|多个"主题;qos" | 订阅主题或订阅多个主题;qos                   |
| pubTopic     | topic                 | 发布的主题                                   |

### 百度云配置

#### 设备型项目物接入

demo： "config,1,bdiot,devicetype,300,300,gz,aaaa,bbbb,cccc,1,0,1,tcp"

| 字段              | 值             | 含义                                            |
| ----------------- | -------------- | ----------------------------------------------- |
| config            | config         | 配置指令标识                                    |
| id                | 1-7            | 通道编号1-7，表示创建通信的通道                 |
| prot              | bdiot          | 百度天工物联的名称                              |
| type              | devicetype     | 注册设备型项目并自动激活                        |
| keepAlive         | 60-600         | 链接超时最大时间单位秒,默认300秒                |
| taskTimer         | 60-2147483647  | 自动定时采集任务间隔时间,单位秒。默认1800秒     |
| 地域代码          | cn-shanghai    | 百度云提供的区域代码，如gz,bj                   |
| schemaID          | 字符串         | 百度云的设备型物模型的uid（不知道的看视频教程） |
| AccessKey ID      | 字符串         | 百度云API安全密钥ID（可用子密钥）               |
| Access Key Secret | 字符串         | 云API安全密钥Secret（可用子密钥）               |
| cleanSession      | 0-1            | MQTT 保存会话标志位                             |
| QOS               | 0-1-2          | MQTT 的 QOS 级别 :                              |
| UID               | 1-2            | MQTT 通道捆绑的串口 ID:                         |
| transport         | tcp \| tcp_ssl | 传输模式，可选tcp或者tcp_ssl                    |

#### 数据型项目物接入

demo："config,1,bdiot,datatype,300,300,gz,bbbb,cccc,xxxx,yyyy,1,0,1,tcp_ssl，/will"

| 字段              | 值             | 含义                                        |
| ----------------- | -------------- | ------------------------------------------- |
| config            | config         | 配置指令标识                                |
| id                | 1-7            | 通道编号1-7，表示创建通信的通道             |
| prot              | bdiot          | 百度天工物联的名称                          |
| type              | datatype       | 数据型项目接入标志位                        |
| keepAlive         | 60-600         | 链接超时最大时间单位秒,默认300秒            |
| taskTimer         | 60-2147483647  | 自动定时采集任务间隔时间,单位秒。默认1800秒 |
| 地域代码          | cn-shanghai    | 百度云提供的区域代码，如gz,bj               |
| AccessKey ID      | 字符串         | 百度云API安全密钥ID（可用子密钥）           |
| Access Key Secret | 字符串         | 百度云API安全密钥ID（可用子密钥）           |
| 产品版本类型      | basic          | 数据型设备捆绑的身份名称                    |
| 身份密码          | 字符串         | 数据型设备捆绑的身份密码                    |
| cleanSession      | 0-1            | MQTT 保存会话标志位                         |
| QOS               | 0-1-2          | MQTT 的 QOS 级别 :                          |
| UID               | 1-2            | MQTT 通道捆绑的串口 ID:                     |
| transport         | tcp \| tcp_ssl | 传输模式，可选tcp或者tcp_ssl                |
| will              | 字符串         | 遗嘱的主题                                  |

### 配置保存指令

- code："config,0,1,0,0,0,100,0,1,500,normal,1234567890"

| 字段     | 值         | 含义                                                         |
| -------- | ---------- | ------------------------------------------------------------ |
| config   | config     | 配置文件标识                                                 |
| id       | 0          | 通道编号0表示存储配置                                        |
| passon   | 0-1        | 1表示透传,0单片机控制(发送完成返回"SEND_OK")                 |
| plate    | 0-1        | 透传模式下是否加设备识别码imei,0表示不加，1表示加            |
| convert  | 0-1        | 是否将下发和上传的报文进行转换(bin <--> hex)，0不转换，1转换 |
| register | 0-2,string | 是否发送注册报文，0不发送,1发送JSON注册报文{"csq":rssi,"imei":imei,"iccid":iccid,"ver":Version},2发送HEX报文"131234512345"，填字符串为用户自定义注册包 |
| paramver | 1-n        | 参数版本号，如果启用远程参数，注意本地配置和远程配置的版本号要一致 |
| flow     | 0-n        | 每分钟最大串口流量(Byte),超过设定字节关闭串口,0为不启用      |
| fota     | 0-1        | 是否启用FOTA自动更新，1是启用，0是禁用。默认0                |
| overtime | 10-2000    | 单位ms，默认25ms，串口接收数据最大等待超时时长               |
| pwrmod   | normal     | 电源模式切换,"normal"为正常功耗,"energy"为低功耗模式(外设关闭，降频联网) |
| password | string     | 用户读写配置的密码,默认无密码。约定字符为数字，字母，_       |

### 恢复出厂默认值指令

- demo："+++"

- 重启模块并恢复出厂默认值

- 当串口配置错误的时候，可以用另外一个串口配置,也可以云端配置

### 硬件恢复出厂默认值

- AIR202 拉低模块的PIN12（GPIO_29)脚为低电平,DTU重启并恢复出厂默认值
- AIR720 拉低模块的PIN4 （GPIO_68)脚为低电平,DTU重启并恢复出厂默认值

### 读取DTU的参数配置

- demo："config,readconfig"
- demo :  "config,readconfig,1234567890"
### 写入DTU的参数配置

- demo: "config,writeconfig,{
	"fota": 0,
	"uartReadTime": 25,
	"flow": "",
	"paramver": 1,
	"pwrmod": "normal",
	"password": "",
	"passon": 1,
	"plate": 0,
	"reg": 0,
	"convert": 0,
	"uconf": [
	​	[1, "115200", 8, 2, 0],
	​	[]
	],
	"conf": [
	​	["mqtt", 300, 1800, "180.97.80.55", "1883", "", "", 1, "/server", "/device", 0, 0, 1, "", "1"],
	​	[],
	​	[],
	​	[],
	​	[],
	​	[],
	​	[]
	],
	"preset": {
	​	"number": "",
	​	"delay": "",
	​	"smsword": ""
	},
	"apn": ["", "", ""],
	"cmds": [
	​	["1000", "00 AA BB CC DD EE FF 11 22 33 44 55 00", "00 AA BB CC DD EE FF 11 22 33 44 55 11", "00 AA BB CC DD EE FF 11 22 33 44 55 22", "00 AA BB CC DD EE FF 11 22 33 44 55 33", "00 AA BB CC DD EE FF 11 22 33 44 55 44", "00 AA BB CC DD EE FF 11 22 33 44 55 55", "00 AA BB CC DD EE FF 11 22 33 44 55 66", "00 AA BB CC DD EE FF 11 22 33 44 55 77"],
	​	[]
	],
	"param_ver": 20,
	"source": "web"
}"

## 发送数据说明：

### 透传通道报文

- 直接发送即可,串口1对应通道ID1，串口2对应通道ID2

### 多通道通信报文

- cmd ："send,id,data"

- code："send,1,data"


| 字段 | 值     | 含义                                            |
| ---- | ------ | ----------------------------------------------- |
| send | send   | 发送数据的标志位                                |
| id   | 1-7    | 通信使用的通道ID,串口通道会自动和对应的通道捆绑 |
| data | string | 要上传的串口数据                                |

### HTTP 报文

- cmd："http,method,url,timeout,body,type,basic"

- code："http,get,www.openluat.com,30"

| 字段   | 值        | 含义                                            |
| ------ | --------- | ----------------------------------------------- |
| http   | http      | 通信方式http                                    |
| method | get-post  | 提交请求的方法                                  |
| url    | 域名/参数 | HTTP请求的地址和参数,参数需要自己urlencode处理  |
| timeou | 30        | HTTP请求最长等待时间,超过这个时间,HTTP将返回    |
| body   | string    | get或者post提交的body内容，只能是字符串         |
| type   | 1,2,3     | body的提交类型，1是urlencode,2是json，3是stream |
| basic  | usr:pwd   | HTTP的BASIC验证,注意账号密码之间用:连接         |

## API指令功能说明：

### 基站定位功能：

- 发送："rrpc,getlocation"
- 返回："rrpc,getlocation,lat,lng"
- 失败： ”ERROR"

### 实时基站定位功能

- 发送："rrpc,getreallocation"
- 返回："rrpc,getreallocation,lat,lng"
- 失败： ”rrpc,getreallocation,error"
- 
### NTP 对时功能：

​	此功能远程不可用

- 发送： "rrpc,gettime"
- 返回： "rrpc,nettime,year,month,day,hour,min,sec"
- 失败： “rrpc,nettime,error"

### 获取IMEI

- 发送： "rrpc,getimei"
- 返回:  "rrpc,getimei,123456789012345"
- 失败:  "ERROR"
  
### 获取ICCID

- 发送： "rrpc,geticcid"
- 返回：  "rrpc,geticcid,1234567890123456789"
- 失败： "ERROR"

### 获取CSQ

- 发送： "rrpc,getcsq"
- 返回： "rrpc,getcsq,17"
- 失败： "ERROR"

### 获取ADC的值

- 发送： "rrpc,getadc,id" 
- 例子： "rrpc,getadc,0" 
- 返回： "rrpc,getadc,1848"
- 失败： "ERROR"

### 获取GPIO的值

- 发送： "rrpc,getpio,pin"
- 例子： "rrpc,getpio,8"
- 返回： "rrpc,getpio8,1"
- 失败： "ERROR"
- 可用 GPIO 见手册底部GPIO列表

### 设置GPIO的值

- 发送： "rrpc,setpio,pin,val"
- 例子： "rrpc,setpio,8,1"
- 返回： "OK"
- 失败： "ERROR"
- 可用 GPIO 见手册底部GPIO列表

### 远程编程指令下发

- 发送： "rrpc,function,cmdString"
- 例子： "rrpc,function,print(1) return 'ok'"
- 返回： "rrpc,function,'ok"
- 失败： 返回错误代码

### 远程获取I2C温湿度传感器数据

- 发送： "rrpc,getSensor,addr"
- 例子： "rrpc,getam2320" 或 "rrpc,getam2320,0x5C"
- 例子： "rrpc,getsht" 或 "rrpc,getsht,0x40"
- 返回： "rrpc,getam2320,25.3,64.1"

### 远程唤醒GPS

- 发送： "rrpc,gps_wakeup"
- 返回： "rrpc,gps_wakeup,OK"

### 远程获取GPS设备信息

- 发送： "rrpc,gps_getsta,format"

- 例子： "rrpc,gps_getsta,json" 或 "rrpc,gps_getsta,hex"

- 返回： "rrpc,gps_getsta,{"sta":[true,false,false,false,false,false,65535,4113,15]}"

### 远程获取GPS定位信息

- 发送： "rrpc,getSensor,format"
- 例子： "rrpc,gps_getmsg,json" 或 "rrpc,gps_getmsg,hex"
- 返回： "rrpc, gps_getmsg, {"msg":[true,1547272715,1136036500,348579350,133,42,1,43,4]}"

### 远程重启模块

- 发送： "rrpc,reboot"

### 远程更新参数

- 发送： "rrpc,upconfig"
- 返回： "rrpc,upconfig,OK"

### 获取固件版本

- 发送： "rrpc,getver"
- 返回： "rrpc,getver,1.5.3"

### 获取项目名称

- 发送： "rrpc,getproject"
- 返回： "rrpc,getproject,DTU-AIR720-MODUL"

### 获取VBATT电压

- 发送： "rrpc,getvbatt"
- 返回： "rrpc,getvbatt,4200"

## 自动采集任务可用API

### Luat API

- 参考 http://wiki.openluat.com

### create库API

#### 实时查询基站定位

- local lat,lng = create.getRealLocation()
#### 获取纬度

- local lat = create.getLat()
#### 获取经度

- local lng = create.getLng()
#### 获取ADC的电压值

- local val = create.getADC(adcid)

### tracker库的api

#### 获取GPS的设备信息

- local str = tracker.locateMessage(format)
- format 为“json” or "hex"
#### 获取GPS设备信息

- local str = tracker.deviceMessage(format)
- format 为“json” or "hex"

## Luat云功能说明

- 地址：<http://dtu.openluat.com>
- 借助Luat云可以实现远程FOTA和自动参数配置，用户无需用上位机配置程序来逐个配置DTU，此方式可以极大减少人工费用和时间。使用远程固件更新和远程参数下发需要用户注册Luat云,用户注册自己的IMEI到云端，指定不同的IMEI到对应的参数版本，DTU模块自动请求参数并保存到到DTU模块中存储。

- 远程固件更新

- 远程参数下发

## 硬件说明

### Air202/208/800 硬件说明

#### AIR202-GPIO

- 看门狗：
  - WDI —— 10脚 ( GPIO_31 )
  - RWD —— 11脚 ( GPIO_30 )

- NET_LED：
  - NET_LED —— 13脚 ( GPIO_33 )

- 重置参数：
  - RSP —— 12 脚（GPIO_29)

- 网络连接通知：
  - RDY —— 6脚（GPIO_3）

#### 485 控制脚 (UART1)

    RXD —— 9脚 (GPIO_0)
    TXD —— 8脚 (GPIO_1)
    DIR —— 7脚 (GPIO_2)

### AIR720/H/D/M/T/U 硬件说明

#### AIR720-GPIO

- NET_LED：
  - NET_LED ——  PIN6 ( GPIO_64 )

- 重置参数：
  - RSP —— PIN4（GPIO_68）

- 网络连接通知：
  - RDY —— PIN5 （GPIO_65）

### TTL 输出脚

    UART1_RXD —— PIN11 （GPIO_51）
    UART1_TXD —— PIN12 （GPIO_52）
    UART2_RXD —— PIN68 （GPIO_57）
    UART2_TXD —— PIN67 （GPIO_58）

### 485 控制脚

    UART1_DIR —— PIN13 （GPIO_23）
    UART2_DIR —— PIN64 （GPIO_59）

### LED 闪烁规则

    100ms 闪烁 —— 注册GSM
    500ms 闪烁 —— 附着GPRS
    100ms 亮, 1900ms 灭 —— 已连接到服务器

## 附表可远程控制GPIO表

### Air202表

| PIN | GPIO    | PIN | GPIO    |
| --- | ------- | --- | ------- |
| 29  | GPIO_6  | 5   | GPIO_12 |
| 30  | GPIO_7  | 11  | GPIO_30 |
| 3   | GPIO_8  | 10  | GPIO_31 |
| 2   | GPIO_10 | 4   | GPIO_11 |

### Air800表

| PIN | GPIO    | PIN | GPIO    |
| --- | ------- | --- | ------- |
| 4   | GPIO_6  | 21  | GPIO_11 |
| 3   | GPIO_7  | 22  | GPIO_12 |
| 19  | GPIO_8  | 28  | GPIO_31 |
| 20  | GPIO_10 | 27  | GPIO_30 |
| 18  | GPIO_9  | 29  | GPIO_29 |
| 17  | GPIO_13 | 41  | GPIO_18 |
| 37  | GPIO_14 | 47  | GPIO_34 |
| 38  | GPIO_15 | 40  | GPIO_17 |
| 39  | GPIO_16 |     |         |

### Air720系列表

| PIN | GPIO  | PIN | GPIO  |
| --- | ----- | --- | ----- |
| 26  | pio26 | 23  | pio70 |
| 25  | pio27 | 29  | pio71 |
| 24  | pio28 | 28  | pio72 |
| 39  | pio33 | 33  | pio73 |
| 40  | pio34 | 32  | pio74 |
| 38  | pio35 | 30  | pio75 |
| 37  | pio36 | 31  | pio76 |
| 65  | pio55 | 66  | pio77 |
| 62  | pio56 | 63  | pio78 |
| 1   | pio62 | 61  | pio79 |
| 2   | pio63 | 113 | pio80 |
| 115 | pio69 | 114 | pio81 |
