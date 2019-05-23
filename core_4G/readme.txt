Air720系列的模块Flash总空间都为128Mb=16MB

目前有2种底层软件，一种支持浮点数和math库，另一种不支持：
Luat_VXXXX_ASR1802：不支持浮点数和math库
Luat_VXXXX_ASR1802_FLOAT：支持浮点数和math库

用户二次开发有两个分区可用，脚本区和文件系统区
脚本区：通过Luatools烧写的所有文件，都存放在此区域，目前总空间为524KB，不同版本的core可能会有差异，以版本每次的更新记录为准
文件系统区：程序运行过程中实时创建的文件都会存放在此区域，目前总空间为800多KB，不同版本的core可能会有差异，可通过rtos.get_fs_free_size()查询剩余的文件系统可用空间







Air720系列模块的RAM总空间都为128Mb=16MB
其中Lua运行可用内存1.5MB，可通过base.collectgarbage("count")查询已经使用的内存空间（返回值单位为KB）

