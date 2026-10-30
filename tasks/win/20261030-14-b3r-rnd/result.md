# 20261030-14-b3r-rnd 结果

B3R 已完成综合、布局布线、STA及bitstream，上板RND/S3/NES测试完成。用户确认画面与按键正常并要求直接上传。CRC比较、benchmark、RN-17及NES实测原文见下；不显示版NES日志未取得，照片未提供，不补造。

| 项 | 内容 |
|---|---|
| 当前任务检出 | 3a344936（含任务14及删除2个RND无用源文件的说明；未核验源码/报告时间） |
| 工程路径 | G:/codex_project/EdRV32-FPGA/EdRV32-B3R，复用本机原工程 |
| PDS | 2022.2-SP6.1，PG2L200H-6 FBB676 |
| 运行方式 | 用户已授权R/N并行；本轮不由agent停止或重跑实现流程 |
| 加载方式 | GUI，COM7，115200，8N1，不切换波特率（沿用用户偏好及此前实测） |

## 阶段耗时、峰值内存

### compile

- Action compile: Real time elapsed is 0h:1m:44s
- Action compile: CPU time elapsed is 0h:0m:12s
- Action compile: Process CPU time elapsed is 0h:0m:12s
- Action compile: Peak memory pool usage is 494 MB

### synthesize

- Action synthesize: Real time elapsed is 0h:4m:35s
- Action synthesize: CPU time elapsed is 0h:0m:52s
- Action synthesize: Process CPU time elapsed is 0h:0m:56s
- Action synthesize: Peak memory pool usage is 2,422 MB

### device_map

- Action dev_map: Real time elapsed is 0h:0m:46s
- Action dev_map: CPU time elapsed is 0h:0m:8s
- Action dev_map: Process CPU time elapsed is 0h:0m:9s
- Action dev_map: Peak memory pool usage is 1,365 MB

### place_route

- Action pnr: Real time elapsed is 0h:33m:14s
- Action pnr: CPU time elapsed is 0h:8m:23s
- Action pnr: Process CPU time elapsed is 0h:11m:28s
- Action pnr: Peak memory pool usage is 6,587 MB

### report_timing

- Action report_timing: Real time elapsed is 0h:1m:16s
- Action report_timing: CPU time elapsed is 0h:0m:20s
- Action report_timing: Process CPU time elapsed is 0h:0m:23s
- Action report_timing: Peak memory pool usage is 4,600 MB

### generate_bitstream

- Action gen_bit_stream: Real time elapsed is 0h:1m:22s
- Action gen_bit_stream: CPU time elapsed is 0h:0m:28s
- Action gen_bit_stream: Process CPU time elapsed is 0h:0m:28s
- Action gen_bit_stream: Peak memory pool usage is 3,514 MB


路由共保存204条迭代进度，末条('207', '0.308', '0', '0')，字段为迭代/MT原始秒数/未布通/overused。实际总耗时以Action Real time为准，不累加MT字段。

## 布线后时序

同域汇总如下，全部同域/跨域Setup、Hold、Recovery、Removal及脉宽摘要见timing_summary.txt。Fmax=1000/(报告周期−WNS)，是各角估算，不能以fast角代替slow角。

| 时钟 | 角 | 周期ns | WNS | TNS | WHS | THS | setup违例端点 | Fmax MHz |
|---|---|---|---|---|---|---|---|---|
| clk_sys | Slow | 10.0 | 0.541 | 0.000 | 0.144 | 0.000 | 0 | 105.719 |
| clk_pix | Slow | 13.468 | 7.098 | 0.000 | 0.166 | 0.000 | 0 | 156.986 |
| clk_serial | Slow | 2.6936 | 1.706 | 0.000 | 0.346 | 0.000 | 0 | 1012.556 |
| rst_clk | Slow | 8.0 | 5.083 | 0.000 | 0.261 | 0.000 | 0 | 342.818 |
| clk_mem | Slow | 8.0 | 0.072 | 0.000 | 0.110 | 0.000 | 0 | 126.135 |
| clk_sys | Fast | 10.0 | 4.106 | 0.000 | 0.101 | 0.000 | 0 | 169.664 |
| clk_pix | Fast | 13.468 | 9.689 | 0.000 | 0.118 | 0.000 | 0 | 264.620 |
| clk_serial | Fast | 2.6936 | 2.084 | 0.000 | 0.225 | 0.000 | 0 | 1640.420 |
| rst_clk | Fast | 8.0 | 6.213 | 0.000 | 0.164 | 0.000 | 0 | 559.597 |
| clk_mem | Fast | 8.0 | 3.108 | 0.000 | 0.100 | 0.000 | 0 | 204.415 |

补充导出包含8520条路径，危险正裕度setup（0≤slack<1ns）259条。各时钟setup多路径、最差20条setup/hold、完整路径索引均已保存；数量按实际路径，不填充。

### setup违例时钟域最差路径（每角最多10条）

扩展报告未出现setup负裕度路径。

## 资源

```text
Device Utilization Summary:
+-------------------------------------------------------------------------+
| Logic Utilization     | Used      | Available     | Utilization(%)
+-------------------------------------------------------------------------+
| APM                   | 102       | 740           | 14
| FF                    | 41122     | 319600        | 13
| LUT                   | 51663     | 159800        | 33
| Distributed RAM       | 233       | 39500         | 1
| DRM                   | 110       | 415           | 27
| IO                    | 94        | 400           | 24
| RCKB                  | 2         | 40            | 5
| SCANCHAIN             | 0         | 1             | 0
| USCM                  | 5         | 32            | 16
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

resource_hier.txt按post-route完整展开CPU/SYS/MEM/RND/DISP及子模块；另存综合层级。资源表APM/DRM使用原生报告口径，不混用站点/子单元。

## RND自检

参考模型expect.py返回码：0。原始RX中16组CRC各被GUI闲置刷新拆成两段；只将相邻的精确 `RND <组名> crc=` 和 `0x<8位hex>` 拼接，合并索引保存在uart/rnd_normalization.txt，原始JSON及HEX保留。未修改任何CRC数值。

```text
PASS fill_rgb565 actual=0xe9358c29 expected=0xe9358c29
PASS border_rgb565 actual=0x1658f064 expected=0x1658f064
PASS glyph_rgb565 actual=0x26bf7139 expected=0x26bf7139
PASS blit_rgb565 actual=0x87b4c9d9 expected=0x87b4c9d9
PASS copy_rgb565 actual=0xd330519b expected=0xd330519b
PASS box_shadow_rgb565 actual=0xaddb98ac expected=0xaddb98ac
PASS blur_rgb565 actual=0x9dc67871 expected=0x9dc67871
PASS tilemap_rgb565 actual=0x763bdd5f expected=0x763bdd5f
PASS fill_argb8888 actual=0x0bda4f5e expected=0x0bda4f5e
PASS border_argb8888 actual=0x2230a20f expected=0x2230a20f
PASS glyph_argb8888 actual=0x004b61a5 expected=0x004b61a5
PASS blit_argb8888 actual=0xaa15e883 expected=0xaa15e883
PASS copy_argb8888 actual=0x6d1538f5 expected=0x6d1538f5
PASS box_shadow_argb8888 actual=0x5ca6e649 expected=0x5ca6e649
PASS blur_argb8888 actual=0x3f13597a expected=0x3f13597a
PASS tilemap_argb8888 actual=0xeecd1aac expected=0xeecd1aac
PASS
```

用户确认RND图案正常；硬件ERR_CODE行原文全部保留。

## S3、RN-17及benchmark

用户确认主界面、游戏、widgets及按键正常。串口benchmark原文（若耗时/CPU数字与即时fps不同，不重算替换）：

```text
Benchmark Summary (9.6.0 )
Name, Avg. CPU, Avg. FPS, Avg. time, render time, flush time
Empty screen, 92%, 32, 29, 15, 14
Moving wallpaper, 99%, 20, 47, 41, 6
Single rectangle, 99%, 56, 15, 2, 13
Multiple rectangles, 99%, 52, 15, 13, 2
Multiple RGB images, 99%, 18, 40, 36, 4
Multiple ARGB images, 99%, 18, 40, 36, 4
Rotated ARGB images, 99%, 4, 228, 215, 13
Multiple labels, 99%, 10, 104, 98, 6
Screen sized text, 99%, 3, 283, 274, 9
Multiple arcs, 99%, 7, 121, 114, 7
Containers, 99%, 4, 173, 166, 7
Containers with overlay, 99%, 5, 179, 170, 9
Containers with opa, 99%, 5, 140, 133, 7
Containers with opa_layer, 99%, 1, 474, 465, 9
Containers with scrolling, 99%, 3, 275, 264, 11
Widgets demo, 97%, 12, 169, 161, 8
All scenes avg.,98%, 15, 145, 137, 8
```

RN-17原文：

```text
RN-17 full_max_lsb=0 edge_max_lsb=17 over1=1029 pixels=921600 over1_ppm=1116 bins_0_1_2_3to4_5plus=905387,15184,937,56,36 rnd_tasks=25 sw_tasks=0 PASS
RN-17 type=1 claimed=6 unclaimed=0
RN-17 type=2 claimed=4 unclaimed=0
RN-17 type=5 claimed=15 unclaimed=0
```

## NES显示版

用户确认画面与按键正常。缓冲中有两次NES运行，均shown>0；首次统计窗口舍弃，表中列窗口2–4。

| 运行 | 窗口 | fps | shown | CPU% | PPU% |
|---|---|---|---|---|---|
| 1 | 2 | 46.6 | 15.5 | 23 | 56 |
| 1 | 3 | 46.6 | 15.5 | 23 | 56 |
| 1 | 4 | 46.5 | 15.5 | 23 | 56 |
| 2 | 2 | 46.6 | 15.5 | 23 | 56 |
| 2 | 3 | 46.6 | 15.5 | 23 | 56 |
| 2 | 4 | 46.6 | 15.5 | 23 | 56 |

NES不显示版：未取得。两次运行的加载段大小相同，shown均非零，不能把第二次认定为nes_nodisplay；完整日志及全部窗口表已保存。

## 证据范围与未取得项

GUI缓冲seq范围193–1019，共827条。只读API抓取，不操作桌面、不向串口发送命令。GUI工程下拉仍是B3V，仅记录工具状态，不据此判断实际bitstream。

uart/gui_all.log、gui_buffer.json及rx_hex.tsv保留全部取得的原始记录；按程序提取rnd.log、s3.log、nes.log。用户要求直接上传，本次不要求补测或照片。未取得不显示版NES实测和实物照片，见checklist.md。

完整实现日志仍在本地工程compile/synthesize/device_map/place_route/report_timing/generate_bitstream目录；已回传原生报告、各阶段全部W/C/E、耗时内存、路由迭代。未上传工程/IP/数据库/bitstream或完整执行日志。补充STA仅从已有布线DB导出，不重跑实现。

任务14采用本机B3R目录，任务卡中的B3R-r2未另建。构建时源文件已由PDS引用仓库；本轮不核对源码/报告时间，也不由当前HEAD推断正在或已经完成的构建版本。

较大产物（保留多路径与警告诊断原文）：

- artifacts/setup_top200_clk_mem.txt：7.94MiB
- artifacts/setup_top200_clk_sys.txt：3.46MiB
- artifacts/setup_top200_phy_dq_sysclk_0.txt：3.82MiB
- artifacts/setup_top200_phy_dq_sysclk_1.txt：3.77MiB
