# 用户追加：VRN/F clk_sys 125MHz对照

用户明确要求：再复制两个工程，将CPU时钟约束及PLL改为125MHz，并执行流程。本追加实验不改变卡48原100MHz工程，不修改共享RTL、共享头文件和共享FDC。

| 标识 | 副本工程 |
|---|---|
| VRN125 | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-VRN-RND1S-CPU125/EdRV32-B3F-VRN-RND1S-CPU125.pds |
| F125 | G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125/EdRV32-B3F-RND1S-CPU125.pds |

完整复制目录，流程状态归零，重新Compile/Synthesize，不能复用100MHz结果。原器件、ADS、源文件及其余实现参数沿用卡48。

- ip_pll_sys：用本机厂商PLL ui.tcl中的clkFreqUpdt、dutyUpdt、phaseUpdt、dutyFracShownUnit_basicPage计算参数（只调用计算过程，没有打开或操控GUI），然后ip_generate.exe -i ... -disable-syn重新生成。参数I=1、M=2、F=15.625、O0=6.75；VCO=843.75MHz；27×2×15.625÷6.75=125MHz。厂商实际显示输出125MHz、相位0°、占空比50%。两个副本生成日志均0error/0warning。未手改生成的PLL Verilog。
- 局部FDC：各副本cpu125/constraints/edrv32_fpga_board_full_top_cpu125.fdc，只将clk_sys生成时钟multiply_by100改125，divide_by27不变，对应8ns。DDR clk_mem125MHz、NPU150MHz及其他时钟沿用原配置。
- 局部头文件：复制rtl/include至各副本cpu125/rtl/include，将私有soc_address_map.json的clk_sys_hz设125000000，调用原tools/gen/soc_map.py生成器（ROOT为副本cpu125目录）生成常量。EDRV32_CLK_SYS_HZ=0x07735940，影响UART复位分频、I2C分频和SYSCTRL频率上报；编译include_path指向这个私有目录。共享100MHz常量未修改。
- ROM/SRAM：沿用副本init目录的卡48初始化数据，IDF指向各自副本init并用官方IP生成器重新生成；无需用户再手动生成这两个副本的三个IP。
- 软件：没有重新编译ELF/BIOS。当前demo从SYSCTRL读取频率；以后上板的具体测试仍需确认实际输出及计时。未宣称125MHz硬件时序或上板已通过。

## 自动运行安排

用户已授权此次自动执行。VRN125的Compile已从真实项目执行（pds_shell -project ... -run compile），日志位于副本cpu125/compile_console.log，分析命令确认include展开到副本cpu125/rtl/include。

当时原100MHz VRN/F两份正在PnR，空闲物理内存约4GiB。125MHz重流程不加入并行争用：后台队列等待这两份已有PnR退出，然后先VRN125、后F125串行Compile、Synthesize、Map、PnR、Report Timing、Generate Bitstream。单工程失败保留错误原文并继续另一工程。新PnR沿用卡48止损：第40轮仍>18000未布通即停止该副本；不终止原100MHz工程。

队列脚本：G:/codex_project/EdRV32-Competition-2026/build/board/card48/run125.py。
队列日志：同目录cpu125_queue.log；后台标准错误queue_stderr.log；每个副本cpu125/<stage>_auto_console.log为该阶段输出。

准备阶段不能视为实现完成；最终频率、资源、时序、是否布通以各副本之后生成的报告为准。

## 用户要求复核125MHz

两个副本的实际生成PLL及综合结构网表均见STATIC_RATIOI=1、STATIC_RATIOM=2、STATIC_RATIO0=6.75（生成IP反馈F=15.625），计算125MHz；PDS指向私有FDC，Device Map原生报告也实际列出clk_sys multiply_by125/divide_by27，等效8ns，Compile实际include路径为私有cpu125/rtl/include，SYS常量125000000。不是仅修改工程名称。尚未取得两份本轮最终Report Timing，不能宣称125MHz时序通过。

用户已从PDS直接启动两个125MHz的PnR；复核时VRN125第174轮0未布通/0过用，F125第72轮1029/1549，属于进度快照。原等待队列PID65900仍在等待100MHz流程，已停止该等待队列，防止之后重复Compile覆盖当前实现；没有终止任何PDS流程。当前不是前述后台串行队列在运行，而是用户直接启动的PDS流程。

布线更快的可能原因是提频导致重新综合、UART/I2C复位常量变化和时序驱动放置变化，使这一轮布局更容易收敛；工具启发式求解的运行时间不随时钟频率单调变化。尚未从日志分离出各因素贡献，不将125MHz本身解释为确定加速原因。
