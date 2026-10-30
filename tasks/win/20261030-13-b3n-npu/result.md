# 20261030-13-b3n-npu 结果

B3N 已完成综合、映射、布局布线、STA 和 bitstream。第一次 GUI 切换到2 Mbaud后乱码；第二次保持115200，ELF加载和运行成功，三个寄存器项通过，首个卷积用例失败，最终 NPU board: FAIL 1/39。实现时序通过，上板功能未通过。

| 项 | 内容 |
|---|---|
| 输入代码 | origin/zc100116/b3，b7519616（当前任务分支基点；未做源码/产物时间核验） |
| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3N，新建，按任务单工程运行 |
| PDS | 2022.2-SP6.1，PG2L200H-6 FBB676 |
| 导入 | 87 源文件，21 种 IP；include 和相对路径已检查 |
| 完成情况 | 实现完成；步骤8已运行NPU测试，首个卷积用例失败 |

## 阶段耗时与内存

以下保存 Real time、CPU time、Process CPU time 和 Peak memory pool 原文；不是由文件时间推算。

### compile

- Action compile: Real time elapsed is 0h:1m:46s
- Action compile: CPU time elapsed is 0h:0m:18s
- Action compile: Process CPU time elapsed is 0h:0m:18s
- Action compile: Peak memory pool usage is 597 MB

### synthesize

- Action synthesize: Real time elapsed is 0h:4m:57s
- Action synthesize: CPU time elapsed is 0h:1m:6s
- Action synthesize: Process CPU time elapsed is 0h:1m:10s
- Action synthesize: Peak memory pool usage is 3,139 MB

### device_map

- Action dev_map: Real time elapsed is 0h:0m:52s
- Action dev_map: CPU time elapsed is 0h:0m:10s
- Action dev_map: Process CPU time elapsed is 0h:0m:11s
- Action dev_map: Peak memory pool usage is 1,591 MB

### place_route

- Action pnr: Real time elapsed is 0h:38m:5s
- Action pnr: CPU time elapsed is 0h:6m:47s
- Action pnr: Process CPU time elapsed is 0h:10m:14s
- Action pnr: Peak memory pool usage is 6,370 MB

### report_timing

- Action report_timing: Real time elapsed is 0h:1m:16s
- Action report_timing: CPU time elapsed is 0h:0m:12s
- Action report_timing: Process CPU time elapsed is 0h:0m:15s
- Action report_timing: Peak memory pool usage is 4,887 MB

### generate_bitstream

- Action gen_bit_stream: Real time elapsed is 0h:1m:33s
- Action gen_bit_stream: CPU time elapsed is 0h:0m:17s
- Action gen_bit_stream: Process CPU time elapsed is 0h:0m:17s
- Action gen_bit_stream: Peak memory pool usage is 3,491 MB

## 布线与 APM 级联

路由进度共 208 条，最后记录：('212', '0.303', '0', '0')；字段依次为迭代、MT原始秒数、未布通数、overused。MT字段不累加成墙钟耗时。

APM/CPI/CPO/cascade 相关 W/C/E 行 3087 条，原文见 apm_warnings.txt；完成布线与 bitstream 不代表上板 NPU 已通过。

apm_placement.pcf 由原生 generate_constraint -db <现有pnr.adf> -device APM 导出，用于 Linux 检查8级链同列连续站点。未修改工程或运行综合/PnR。

## 时序

布线后原生摘要保留全部同域和跨域 Setup/Hold/Recovery/Removal 数据。下表列同域 WNS/TNS/WHS/THS；Fmax=1000/(报告周期−WNS)，仅为该角估算，最终受 slow 角及其他约束共同限制。

| 时钟 | 角 | 周期ns | WNS | TNS | WHS | THS | setup违例端点 | Fmax MHz |
|---|---|---|---|---|---|---|---|---|
| clk_sys | Slow | 10.0 | 0.654 | 0.000 | 0.142 | 0.000 | 0 | 106.998 |
| clk_npu | Slow | 6.6667 | 0.157 | 0.000 | 0.138 | 0.000 | 0 | 153.617 |
| rst_clk | Slow | 8.0 | 5.042 | 0.000 | 0.268 | 0.000 | 0 | 338.066 |
| clk_mem | Slow | 8.0 | 0.420 | 0.000 | 0.100 | 0.000 | 0 | 131.926 |
| clk_sys | Fast | 10.0 | 3.980 | 0.000 | 0.100 | 0.000 | 0 | 166.113 |
| clk_npu | Fast | 6.6667 | 2.581 | 0.000 | 0.100 | 0.000 | 0 | 244.756 |
| rst_clk | Fast | 8.0 | 6.316 | 0.000 | 0.168 | 0.000 | 0 | 593.824 |
| clk_mem | Fast | 8.0 | 3.290 | 0.000 | 0.100 | 0.000 | 0 | 212.314 |

补充报告已从现有布线 DB 导出，索引包含 8456 条路径；危险正裕度 setup（0–1 ns）545 条已保留。各时钟 setup、最差20 setup/hold及全部索引见 artifacts；数量少于200时按实际报告保留，不填充。

每个存在 setup 违例的时钟域最差路径（按角各最多10条）：


## 资源

```text
Device Utilization Summary:
+-------------------------------------------------------------------------+
| Logic Utilization     | Used      | Available     | Utilization(%)
+-------------------------------------------------------------------------+
| APM                   | 303       | 740           | 41
| FF                    | 52704     | 319600        | 17
| LUT                   | 50103     | 159800        | 32
| Distributed RAM       | 681       | 39500         | 2
| DRM                   | 210       | 415           | 51
| IO                    | 86        | 400           | 22
| RCKB                  | 2         | 40            | 5
| SCANCHAIN             | 0         | 1             | 0
| USCM                  | 4         | 32            | 13
| CCS                   | 1         | 1             | 100
| ADC                   | 0         | 1             | 0
| DDR_PHY               | 7         | 40            | 18
| HSSTLP                | 0         | 2             | 0
| GPLL                  | 4         | 10            | 40
| PPLL                  | 2         | 10            | 20
| DDRPHY_CPD            | 1         | 20            | 5
| HCKB                  | 0         | 120           | 0
| IOCKB                 | 0         | 40            | 0
| MRCKB                 | 1         | 20            | 5
| PCIE                  | 0         | 1             | 0
| DDRPHY_IOCLK_DIV      | 2         | 10            | 20
| ANALOG                | 0         | 1             | 0
| TSERDES               | 14        | 80            | 18
| KEYRAM                | 0         | 1             | 0
+-------------------------------------------------------------------------+

```

层级完整展开见 resource_hier.txt（post-route）、resource_hier_synthesis.txt。APM按资源报告子单元计数，不混用物理站点数量。

## 第一次尝试：2 Mbaud 切换异常（历史记录）

已通过运行中 GUI 的只读 REST API 取得完整缓冲、原始RX hex、串口配置及加载状态；没有操作桌面，没有向板端发送数据，没有改波特率或重试。用户截图原图亦已保存。

1. COM7 @115200 8N1 正常连接，21:28:24 普通启动，MEM_READY=1，出现 Monitor 菜单。
2. 21:28:53 按 KEY1+复位后正常进入 BIOS。
3. 21:29:12 点击加载，工具发送空行重新请求菜单；Input error 后 BIOS 重新打印菜单。这是现有空行探测行为，不能单凭该行判失败。
4. 随后 Baud: / Baud result: 2000000 正常可读；21:29:12.748 开始乱码。
5. 用户报告此时复位后全是“·”；21:30:13.791 的接收记录实际是 1593 个字节，原始 hex 保存在 rx_hex.tsv，不能仅凭GUI显示判成发送了句点字符。
6. 只读状态快照：connected=True，端口=COM7，主机波特率=2000000；加载器 active=True，phase=wait_menu，sent=8/5177439，programmedBytes=None。
7. 未出现 Load result: OK、Run 成功、任何 NPU A/B/C/D PASS/FAIL，未取得 PASS39/39、LED状态、ms/frame或fps。当前现象更早发生在波特率切换/菜单同步阶段，不能归因到 NPU MAC 运算。

推断（尚未验证）：复位会令 BIOS 恢复115200，而主机快照仍为2000000，足以解释复位后无法正常解码；最初从115200切换到2000000为何失败，还需检查板端分频/时序与GUI切换及菜单握手。GUI工程选择仍为B3V，此项仅为工具状态记录，不能当成实际bitstream标识。

## 第二次尝试：115200 加载成功，NPU功能失败

用户在GUI选择不切换波特率后重试。COM7、115200、8N1；Load bytes: 5177412 at 0x80000000；Load result: PASS；Run: 0x80000000。加载器 active=false、phase=done、error=null，确认已经完成加载并运行，不能再把本次故障归为ELF没有加载成功。

板端逐项原文：

```text
NPU A-ID PASS
NPU A-empty PASS
NPU A-reset PASS
NPU B-OP-01-c16_32 FAIL desc=0 addr=1102000d expected=00000002 actual=00000001 mismatches=160 PERF0=522 MAC=32 passed=3
NPU board: FAIL 1/39
```

三个A项通过（ID、空描述符完成、复位寄存器），首个B项 B-OP-01-c16_32 失败：desc=0；首错地址0x1102000d；期望0x02，实际0x01；mismatches=160；PERF0=522；MAC=32；失败前passed=3。程序按设计首错停止，未运行后续小用例、整网和连续20帧，ms/frame、fps及LED状态未取得。最终 FAIL 1/39 按板端原文保留，不擅自解释为39项全部跑完。

该错误发生在真实NPU输出数据比对阶段，和第一次2 Mbaud解码/菜单同步异常是独立现象。保留完整数据差异作为Linux侧排查APM级联/符号/量化/存储等问题的输入，目前不凭首错值认定根因。

第二次完整缓冲：uart/b3n_board_npu_115200.log；原始条目与HEX：gui_buffer_115200.json、rx_hex_115200.tsv；配置和加载状态快照：gui_status_115200.json、gui_program_status_115200.json。

## 日志与限制

uart/b3n_board_npu.log 是GUI当前全部缓冲的原文导出（包含NUL），gui_buffer.json / rx_hex.tsv保留原始字节证据；uart/b3n_boot.log是普通启动片段。其他json为只读状态快照，截图为用户提供原图。

各阶段全部W/C/E原文、动作耗时和路由进度已保存；原始完整run.log保留在本地工程对应阶段目录。没有提交工程/IP目录、数据库、bitstream或完整执行日志。时序扩展导出仅用于报告，不触发实现流程。

ROM/SRAM源IP配置的初始化dat与本卡dat此前已逐字节比较一致；当前启动打印的Build commit 9510c64是BIOS/监控镜像自报版本，不等同于本轮RTL提交。

本轮同时回传2 Mbaud握手异常和115200下真实NPU数据比对失败，两者分别分析。没有擅自修改GUI、RTL或重新烧录。

## APM相关警告分类补充

apm_warnings.txt 的3087行是按 APM/CPI/CPO/cascade 关键字筛选的日志行，不是3087个级联放置错误。其中Public-4008为3045行，Sdm-2003为42行。完整原文已保存；其中Sdm-2003包括CPU ip_mul_s33x33的cpo未驱动告警。实现流程没有因级联连接/放置错误中止。

扩展导出记录：使用现有DB补充STA 8456条路径，并成功导出APM布局；首次APM导出因未传映射DB失败，补入compile/synthesize/devmap DB后原生命令成功。仅导出报告，无实现重跑。大文件setup_top200_clk_mem.txt约7.9MiB，保留多路径逐级原文用于分析。


## APM导出覆盖说明

原生APM PCF共有76条 def_inst_site；MAC级联部分显示 g_lane[0] 根位置，未显式列出每条链全部8级。因此该文件可用于后续分析，但本轮未据此声称8级全部连续，资源303与导出约束76不能直接对等。
