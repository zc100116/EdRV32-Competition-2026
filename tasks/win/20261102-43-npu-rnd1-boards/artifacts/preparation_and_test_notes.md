# 卡43结果：工程准备阶段

代码输入13a17403，实验分支zc100116/b3f-rnd1-npu-opt；工作分支win/20261102-43-npu-rnd1-boards。尚未运行Compile/综合/Map/PnR或上板测试。

|标识|新工程（G:/codex_project/EdRV32-FPGA/下）|源文件数|IP种类|来源|
|---|---|---:|---:|---|
|N|EdRV32-B3N-Q6-OPT2/EdRV32-B3N-Q6-OPT2.pds|105|24|旧B3N；ETH PLL改用B3F的外部反馈IP|
|VN|EdRV32-B3VN-Q6-OPT2/EdRV32-B3VN-Q6-OPT2.pds|144|29|卡38 EdRV32-B3VN-r3|
|F|EdRV32-B3F-RND1-N/EdRV32-B3F-RND1-N.pds|159|32|卡33 EdRV32-B3F|
|VRN|EdRV32-B3F-VRN-RND1-N/EdRV32-B3F-VRN-RND1-N.pds|142|31|卡33 EdRV32-B3F对应所需IP|

使用现有PDS文件格式构造干净输入列表，未复制旧实现输出；清除旧FIC、PCF及输出数据库引用，阶段状态全部为待运行。F/VRN不含RND v2-only源文件，N/VN不引用RND。源文件、IP IDF及包装源、FDC路径均确认存在，include沿用../../EdRV32-Competition-2026/rtl/include加tab。原工程及比特流未改。

N/VN按卡43不插ILA；F/VRN在综合后生成本卡FIC。卡38已插ILA的VN配置未带入。

四工程在init/复制本卡ip_rom_boot.dat、ip_ram_sram.dat，并只将复制后的ROM/SRAM IDF INIT_FILE改为本工程init文件绝对路径；其余参数未改。生成的Verilog/内部初始化尚未更新，用户必须在IP Compiler重新生成这两个IP后才能Compile，不能把路径修改当成完成初始化。卡43 BIOS/monitor内容不用旧卡dat替代。

旧B3N的ip_pll_eth为内部反馈、没有外部输入clkfb；新N采用B3F已有外部反馈IP。四工程均确认有clkfb输入。其它IP按对应来源复制，不重新生成。NPU LUT容量/读延迟保持2048x8/2拍，Q6的4实例由RTL决定。

高扇出报告1000，ADS综合模式和FPGA_MODE沿用。VN/F/VRN设置decongestion2、拥塞图开启、线程5；N保持默认布局模式，额外开启拥塞图方便诊断，线程5。最终实际运行参数待启动时记录。

内存准备快照约13.2GiB可用，旧卡33 A的PnR仍在运行；未停止其它流程。不预先同时启动四工程，用户完成IP及综合配置后按可用内存安排并发。代理继续按用户已授权的局域网直连配置，不关闭Clash/TUN。

准备过程发现模板带旧Map PCF输入引用，已在生成其余工程前清理并复核全部路径，无旧PCF残留。配置与生成目录仅留Windows工程外置目录，不入库。工程准备记录见artifacts/project_preparation.txt。

## 工程打不开后的修正

用户反馈最初准备的PDS工程无法打开；前次只验证输入路径，没有执行PDS加载验证，不足以宣称可用。现已用PDS官方set_arch/add_design/add_constraint命令重新生成四份PDS，补全工具自身维护的项目元数据，不再使用手工拼接的项目主体。随后分别用相同项目名读取已有PDS、仅执行puts确认脚本，四份均出现Analyzing project file和PROJECT_LOAD_OK，E=0；没有运行Compile/综合/Map/PnR。保留所有IP目录和已设定INIT_FILE路径。尚待用户GUI重新打开确认；未取得原GUI错误详情，因此不把具体元数据差异断言为唯一根因。本地加载日志在build/board/card43/*-load.log。

## 按用户要求改回复制已有工程

先前所谓加载检查使用-file模式，实际上创建空项目覆盖了登记内容，旧PROJECT_LOAD_OK仅为puts输出，不能作为加载验证证据，撤回该结论。用户随后要求按原复制方式。现N复制旧B3N.pds、VN复制卡38的B3VN-r3.pds、F/VRN复制卡33 A的B3F-card31.pds，保留其Logos2/PG2L200H/-6/FBB676及ADS选项2，更新卡43源文件/IP/FDC输入，移除旧FIC和输出记录，所有阶段待重跑。最终源文件105/144/159/142，IP24/29/32/31，所有输入文件路径存在；VRN仍用full_top.fdc。未再用-file模式执行所谓加载检查，尚待用户GUI重开确认。用户已打开的旧空窗口必须不保存关闭后重开，避免回写空配置。

## VN首次上板ETH诊断

用户下载卡43 VN bitstream。2M串口切换乱码，115200加载eth_diag成功并自动运行。PHY复位5轮接收检查5/5，PERF1增量10/8/10/10/10，PERF3增量全0；PC收到板端UDP回复，1000M全双工。细节及原文见artifacts/VN/eth/result.md。GUI和CLI网口加载待测，未宣称完成全部BIOS/ETH验收。

## VN网口加载补测完成

GUI与独立CLI均通过网口加载卡43 eth_diag.bin，各1/1并自动Run0x10000000；4277B单段。真实CLI串口字节与完整解码/控制台日志见artifacts/VN/eth。此前5轮PHY接收全部通过。2M串口失败记录保留，115200串口加载通过。测试结束后停止CLI及UDP探测进程、GUI恢复COM7@115200；未改PHY延迟或代理。

## VN NPU自检结果

用户GUI网口加载本卡board_npu.elf成功，programmedBytes5184584，sent=total5212944，Run0x80000000，error=null。串口NPU board PASS39/39：A3项、B15项、C整网1项及D连续20项全PASS。C-YOLO：PERF0=6105990，MAC=5347440，40.706ms/frame，24.566fps，CRC32=0738f96e。D-01..D-20 CRC均0738f96e。完整串口artifacts/VN/uart/board_npu.log，包含全部小用例周期和连续整网原文。此为VN硬件上的自检，不冒充独立N工程结果；摄像头/上传图片识别尚未测试。

## demo_vnpu PEER显示

应用已接收遥测，但GUI初始PEER未知；工具自动重复发WIN3，尚无串口status回读。发送status后板端打印ETH peer IP0xc0a80102/port6000，GUI PEER立即完成，并接收视频数据。说明此时网络已通，PEER显示依赖串口状态回读；未修改工具源码。当前Scene2、NPU inferences0，识别尚未开始。原文见uart/demo_vnpu_peer_status.log。

## VN网口图片批量异常

3张单图和文件夹前7张成功后，从000000015278.jpg起连续回传超时，详见artifacts/VN/image_batch_issue。不能把上传完成当作推理/回传通过；根因未确认，未擅自改代码或超时设置。
