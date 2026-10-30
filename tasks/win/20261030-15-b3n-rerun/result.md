# 20261030-15-b3n-rerun 结果

**B3N实现完成，上板原测试ELF运行PASS 39/39。** 此前失败的第一个卷积用例现已通过，整网41.665 ms/frame、24.000 fps，连续20帧CRC均为0738f96e。实际使用GUI、115200和卡13旧ELF，未使用卡15新增诊断ELF；该差异如实记录，不把本轮称为新版诊断程序验收。

| 项 | 内容 |
|---|---|
| 当前任务检出commit | 3a3449369d078e38951201f74caff76489f5c17c |
| 工程 | G:/codex_project/EdRV32-FPGA/EdRV32-B3N，复用 |
| PDS | 2022.2-SP6.1，PG2L200H-6 FBB676 |
| 源文件 | 任务卡要求88个，新增edrv32_mac_npu_int8_head.v；include关系和CMR原文已保存 |
| 运行方式 | 用户授权与B3R并行；agent未停止或重跑实现 |
| 串口 | COM7，115200，8N1，GUI |
| 实际ELF路径（GUI状态） | G:/codex_project/EdRV32-Competition-2026/tasks/win/20261030-13-b3n-npu/src/board_npu.elf |
| 已加载字节 | 5177412；Run: 0x80000000 |
| 结果 | NPU board: PASS 39/39 |
| 整网 | 41.665 ms/frame；24.000 fps |
| LED | 未取得 |

## 实现耗时与峰值内存

### compile

- Action compile: Real time elapsed is 0h:2m:32s
- Action compile: CPU time elapsed is 0h:0m:12s
- Action compile: Process CPU time elapsed is 0h:0m:12s
- Action compile: Peak memory pool usage is 603 MB

### synthesize

- Action synthesize: Real time elapsed is 0h:5m:39s
- Action synthesize: CPU time elapsed is 0h:1m:0s
- Action synthesize: Process CPU time elapsed is 0h:1m:5s
- Action synthesize: Peak memory pool usage is 3,145 MB

### device_map

- Action dev_map: Real time elapsed is 0h:0m:57s
- Action dev_map: CPU time elapsed is 0h:0m:10s
- Action dev_map: Process CPU time elapsed is 0h:0m:11s
- Action dev_map: Peak memory pool usage is 1,599 MB

### place_route

- Action pnr: Real time elapsed is 0h:38m:32s
- Action pnr: CPU time elapsed is 0h:5m:15s
- Action pnr: Process CPU time elapsed is 0h:7m:51s
- Action pnr: Peak memory pool usage is 6,043 MB

### report_timing

- Action report_timing: Real time elapsed is 0h:1m:50s
- Action report_timing: CPU time elapsed is 0h:0m:40s
- Action report_timing: Process CPU time elapsed is 0h:0m:55s
- Action report_timing: Peak memory pool usage is 4,886 MB

### generate_bitstream

- Action gen_bit_stream: Real time elapsed is 0h:2m:12s
- Action gen_bit_stream: CPU time elapsed is 0h:0m:41s
- Action gen_bit_stream: Process CPU time elapsed is 0h:0m:41s
- Action gen_bit_stream: Peak memory pool usage is 3,491 MB


路由共记录208条进度，最后一条('212', '0.356', '0', '0')，字段依次为迭代、MT原始秒数、未布通网络、overused。总耗时取Action Real time，不累加MT字段。

## 布线后时序

每个同域的slow/fast汇总如下；跨域以及Recovery/Removal/脉宽约束见timing_summary.txt原文。Fmax=1000/(报告周期−WNS)，仅作为该角估算。

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

扩展STA从现有pnr数据库导出，8456条路径，危险正裕度setup（0≤slack<1ns）545条。保留每时钟setup多路径、最差20 setup/hold、全部索引，数量按实际报告，不补造。

setup负裕度最差路径（每域/角最多10条）：

未发现setup负裕度路径。

## 资源与APM布局

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

完整post-route/synthesis层级分别为resource_hier.txt、resource_hier_synthesis.txt。APM计数沿用原生资源口径。APM/CPI/CPO/cascade关键字相关警告原文保存在apm_warnings.txt，不能把所有命中行当作级联放置错误。

原生generate_constraint -db <pnr>并指定已有compile/synthesize/devmap数据库导出apm_placement.pcf，包含76条位置约束。级联组可能仅导出根位置，不把约束条数当作实际APM利用量，也不据此声称已逐级检查8级连续性。

## 上板加载与结果

GUI配置115200；Load result: PASS；Run: 0x80000000。与卡13相比，此次同一个旧ELF的首个OP-01已由FAIL变为PASS，全部39项通过。这个事实支持修复对硬件结果有改善，但不是单独证明原故障根因；没有额外做A/B硬件实验。

卡15建议CLI+2 Mbaud及新的诊断ELF；本轮沿用用户GUI偏好和已验证的115200。GUI路径明确指向tasks/win/20261030-13-b3n-npu/src/board_npu.elf，不用文件时间/哈希推测。没有再次验证2 Mbaud，不能报告其已修复。

### 各用例结果（全部原文）

```text
NPU A-ID PASS
NPU A-empty PASS
NPU A-reset PASS
NPU B-OP-01-c16_32 PASS PERF0=522 MAC=32
NPU B-OP-01-c48_96 PASS PERF0=1212 MAC=288
NPU B-OP-02-w12 PASS PERF0=1413 MAC=648
NPU B-OP-03-h5 PASS PERF0=717 MAC=162
NPU B-OP-04-c4_cout32_lut0_res0 PASS PERF0=476 MAC=36
NPU B-OP-04-c4_cout16_lut1_res1 PASS PERF0=709 MAC=36
NPU B-OP-05-lut1 PASS PERF0=777 MAC=32
NPU B-OP-06-work PASS PERF0=557 MAC=32
NPU B-OP-06-output PASS PERF0=555 MAC=32
NPU B-OP-07-cout80 PASS PERF0=3590 MAC=2160
NPU B-OP-09-negative_c48 PASS PERF0=56509 MAC=0
NPU B-OP-10-w2 PASS PERF0=559 MAC=0
NPU B-OP-10-w40 PASS PERF0=2754 MAC=0
NPU B-OP-11-concat PASS PERF0=1325 MAC=96
NPU B-OP-12-seed00 PASS PERF0=17379 MAC=11736
NPU C-YOLO PASS PERF0=6249777 MAC=5347440 ms/frame=41.665 fps=24.000 CRC32=0738f96e
NPU D-01 PASS CRC32=0738f96e PERF0=6251955 MAC=5347440
NPU D-02 PASS CRC32=0738f96e PERF0=6249699 MAC=5347440
NPU D-03 PASS CRC32=0738f96e PERF0=6249946 MAC=5347440
NPU D-04 PASS CRC32=0738f96e PERF0=6250899 MAC=5347440
NPU D-05 PASS CRC32=0738f96e PERF0=6249581 MAC=5347440
NPU D-06 PASS CRC32=0738f96e PERF0=6249894 MAC=5347440
NPU D-07 PASS CRC32=0738f96e PERF0=6250185 MAC=5347440
NPU D-08 PASS CRC32=0738f96e PERF0=6249882 MAC=5347440
NPU D-09 PASS CRC32=0738f96e PERF0=6250103 MAC=5347440
NPU D-10 PASS CRC32=0738f96e PERF0=6250994 MAC=5347440
NPU D-11 PASS CRC32=0738f96e PERF0=6249642 MAC=5347440
NPU D-12 PASS CRC32=0738f96e PERF0=6250013 MAC=5347440
NPU D-13 PASS CRC32=0738f96e PERF0=6250882 MAC=5347440
NPU D-14 PASS CRC32=0738f96e PERF0=6249638 MAC=5347440
NPU D-15 PASS CRC32=0738f96e PERF0=6249915 MAC=5347440
NPU D-16 PASS CRC32=0738f96e PERF0=6250984 MAC=5347440
NPU D-17 PASS CRC32=0738f96e PERF0=6249538 MAC=5347440
NPU D-18 PASS CRC32=0738f96e PERF0=6250001 MAC=5347440
NPU D-19 PASS CRC32=0738f96e PERF0=6250943 MAC=5347440
NPU D-20 PASS CRC32=0738f96e PERF0=6249644 MAC=5347440
NPU board: PASS 39/39
```

### 失败用例及出错通道

本次全部39项PASS，没有失败项。由于实际加载旧ELF，不能把无通道行解释为新版诊断输出已经被验证。

## 日志、上板状态及未取得项

GUI缓冲seq 2133–2221，共89条。完整日志uart/b3n_rerun.log，原始JSON/HEX与只读状态快照均保留；没有操作桌面或向板端发送数据。GUI工程下拉显示B3V只是工具状态，不据此判断实际工程。

LED状态未取得；未重测2 Mbaud；卡15诊断ELF未运行。按用户要求直接整理回传，没有为上述缺项重跑上板。已有原ELF PASS39/39、整网fps及20帧CRC证据完整。

各阶段CMR/SNR/DMR/PRR/RTR、约束检查、全部W/C/E、耗时/内存、路由收敛、危险正裕度路径均已归档。完整执行run.log保留在工程对应阶段目录，不提交工程/IP目录、数据库、bitstream或完整执行日志。

本次只从已完成数据库补充导出STA及APM布局，没有重新综合或布局布线；没有核验报告时间或源码版本。

较大原文产物（诊断所需）：

- artifacts/setup_dangerous_positive.txt：4.93MiB
- artifacts/setup_top200_clk_mem.txt：7.88MiB
- artifacts/setup_top200_clk_sys.txt：3.36MiB
- artifacts/setup_top200_phy_dq_sysclk_0.txt：3.82MiB
- artifacts/setup_top200_phy_dq_sysclk_1.txt：3.82MiB
