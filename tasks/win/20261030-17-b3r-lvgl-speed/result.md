# 20261030-17-b3r-lvgl-speed 结果

新版S3 benchmark自然结束，已取得16个场景及ALL共17行split、每行52个字段，RN-17 PASS。串口未出现S3 glyph cache full。平均FPS为18，上轮卡16为15；本轮仅换软件，未运行综合、布局布线或STA。

| 项 | 内容 |
|---|---|
| 当前任务检出commit | f64898403828b02789ad0c3d2cb63c6bcf545d53 |
| 任务基点 | f6489840，软件构建来源按任务卡为6bcce541 |
| bitstream | 沿用卡14 B3R，G:/codex_project/EdRV32-FPGA/EdRV32-B3R |
| 加载方式 | GUI，COM7，115200，8N1 |
| 加载程序（GUI状态） | G:/codex_project/EdRV32-Competition-2026/tasks/win/20261030-17-b3r-lvgl-speed/src/s3.elf |
| 加载结果 | programmedBytes=1128992，Run: 0x90000000，error=None |
| 完成情况 | benchmark和RN-17均完成，数据完整 |

## Benchmark Summary 原文

```text
Benchmark Summary (9.6.0 )
Name, Avg. CPU, Avg. FPS, Avg. time, render time, flush time
Empty screen, 95%, 57, 14, 10, 4
Moving wallpaper, 100%, 20, 47, 38, 9
Single rectangle, 100%, 56, 16, 2, 14
Multiple rectangles, 100%, 55, 13, 12, 1
Multiple RGB images, 100%, 20, 37, 31, 6
Multiple ARGB images, 100%, 20, 37, 31, 6
Rotated ARGB images, 100%, 4, 213, 208, 5
Multiple labels, 99%, 13, 61, 55, 6
Screen sized text, 100%, 5, 159, 153, 6
Multiple arcs, 100%, 7, 128, 121, 7
Containers, 100%, 5, 155, 146, 9
Containers with overlay, 100%, 5, 156, 151, 5
Containers with opa, 100%, 6, 122, 118, 4
Containers with opa_layer, 100%, 2, 312, 304, 8
Containers with scrolling, 100%, 4, 245, 232, 13
Widgets demo, 98%, 12, 168, 160, 8
All scenes avg.,99%, 18, 116, 110, 6
```

## split摘要

完整17行52列见artifacts/lvgl_split.tsv，所有字段名及数字按原文保留。实际IPC字段名为cpu_ipc，本报告也使用此原始名称，不改为ipc。

| 场景 | render_ms | rnd_ms | sw_ms | other_ms | perf0_ms | clean_ms | wait_ms | finish_ms | cache_ops | glyph_cpu_ms | cpu_ipc | icache_mpki | dcache_mpki |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Empty screen | 11.713 | 3.159 | 0.000 | 8.553 | 2.425 | 0.441 | 2.444 | 0.188 | 18.011 | 1.721 | 0.431 | 15.851 | 0.855 |
| Moving wallpaper | 39.631 | 25.592 | 0.000 | 14.038 | 10.433 | 10.672 | 10.712 | 3.429 | 444.758 | 1.866 | 0.423 | 9.357 | 0.370 |
| Single rectangle | 2.917 | 0.459 | 0.000 | 2.458 | 0.255 | 0.120 | 0.260 | 0.053 | 5.355 | 0.112 | 0.595 | 3.406 | 0.174 |
| Multiple rectangles | 14.001 | 2.413 | 0.000 | 11.587 | 1.172 | 0.708 | 1.203 | 0.336 | 32.440 | 0.118 | 0.326 | 29.601 | 1.350 |
| Multiple RGB images | 38.694 | 8.136 | 0.000 | 30.558 | 4.312 | 2.474 | 4.392 | 0.842 | 102.000 | 1.886 | 0.329 | 27.824 | 1.865 |
| Multiple ARGB images | 38.533 | 8.205 | 0.000 | 30.328 | 4.384 | 2.475 | 4.464 | 0.845 | 102.000 | 1.951 | 0.333 | 27.303 | 1.777 |
| Rotated ARGB images | 216.472 | 4.846 | 185.193 | 26.432 | 1.518 | 2.158 | 1.573 | 0.812 | 91.461 | 1.030 | 0.554 | 4.001 | 9.076 |
| Multiple labels | 60.820 | 10.685 | 0.000 | 50.134 | 5.314 | 3.311 | 5.430 | 1.358 | 140.157 | 6.797 | 0.314 | 30.399 | 3.281 |
| Screen sized text | 155.601 | 26.307 | 0.000 | 129.294 | 18.995 | 4.758 | 19.146 | 1.769 | 169.241 | 36.372 | 0.366 | 27.094 | 1.234 |
| Multiple arcs | 113.030 | 3.209 | 84.296 | 25.525 | 2.470 | 0.441 | 2.488 | 0.187 | 18.000 | 1.821 | 0.305 | 34.234 | 2.502 |
| Containers | 165.926 | 78.221 | 0.000 | 87.704 | 66.761 | 6.951 | 67.020 | 2.937 | 302.375 | 7.299 | 0.420 | 15.810 | 1.399 |
| Containers with overlay | 171.654 | 81.307 | 0.000 | 90.346 | 68.791 | 7.521 | 69.074 | 3.227 | 328.687 | 7.503 | 0.411 | 16.560 | 1.530 |
| Containers with opa | 137.149 | 17.727 | 33.333 | 86.089 | 7.317 | 6.335 | 7.548 | 2.620 | 270.050 | 7.071 | 0.299 | 34.276 | 2.933 |
| Containers with opa_layer | 330.053 | 152.777 | 0.000 | 177.275 | 130.057 | 14.282 | 130.547 | 5.347 | 559.222 | 9.994 | 0.391 | 14.537 | 4.187 |
| Containers with scrolling | 234.555 | 127.046 | 0.000 | 107.508 | 111.362 | 9.295 | 111.732 | 4.053 | 405.000 | 12.487 | 0.408 | 15.041 | 5.116 |
| Widgets demo | 169.126 | 19.868 | 67.320 | 81.937 | 12.076 | 4.567 | 12.265 | 2.083 | 201.597 | 4.143 | 0.338 | 25.742 | 2.936 |
| ALL | 57.464 | 13.358 | 12.151 | 31.954 | 9.212 | 2.615 | 9.302 | 1.021 | 110.188 | 3.248 | 0.377 | 20.420 | 2.746 |

## 与卡16数据对照

来源为任务16提交788064d5的已上传原始TSV，并非重新测量。逐场景原值并排保存在comparison_card16.tsv。两个benchmark统计帧数不同，比较时应结合各场景字段，不能把ALL帧数或累计xbar计数直接当成相同工作量。

| ALL字段 | 卡16 | 卡17 |
|---|---|---|
| frames | 825 | 943 |
| render_ms | 67.110 | 57.464 |
| rnd_ms | 17.713 | 13.358 |
| sw_ms | 12.825 | 12.151 |
| other_ms | 36.571 | 31.954 |
| perf0_ms | 9.305 | 9.212 |
| copy_rnd_ms | 0.310 | 0.258 |

Benchmark Summary的All scenes avg.整数FPS为15→18，按该汇总计算提升20%；ALL render_ms为67.110→57.464。这是两轮上板观测值对照，不把程序不同口径的时间和平均FPS强行互算。

## CPU与RND观察

ALL：cpu_ipc=0.377、icache_mpki=20.420、dcache_mpki=2.746；clean_ms=2.615、wait_ms=9.302、finish_ms=1.021、glyph_cpu_ms=3.248。

原始CPU计数：cycles=7249296.327、instructions=2736863.374、frontend_empty_cycles=3143345.933、icache_misses=55887.625、dcache_misses=7516.878。load-use/divide/device-wait/branch等完整字段及mem_xbar端口统计见TSV。

上述计数供Linux端分析CPU瓶颈；本轮没有改cache容量或进行控制变量实验，不能据一次测量断言扩大cache一定改善性能。cache_ops字段保留程序打印值，不能用它直接替代每次门铃的cache维护调用数。

## RN-17 原文

```text
RN-17 full_max_lsb=0 edge_max_lsb=17 over1=1009 pixels=921600 over1_ppm=1094 bins_0_1_2_3to4_5plus=905425,15166,917,56,36 rnd_tasks=25 sw_tasks=0 PASS
RN-17 type=1 claimed=6 unclaimed=0
RN-17 type=2 claimed=4 unclaimed=0
RN-17 type=5 claimed=15 unclaimed=0
```

RN-17结果为PASS；完整差异统计按板端原文保存，未在主机重新计算或替换。

## 产物与范围

取得GUI缓冲seq范围2850–3059，共210条。uart/s3.log为完整GUI文本导出，gui_buffer.json与rx_hex.tsv保留条目和字节证据，状态快照也已保存。采集时GUI已断开，读取缓冲不重新连接、不发送串口数据。

benchmark_summary.txt、lvgl_split.tsv、rn17.txt、rnd_statistics.txt、glyph_cache_status.txt及comparison_card16.tsv均已保存。S3 glyph cache full出现次数：0。

GUI工程下拉显示B3V仅为工具状态，不据此判定bitstream。未核验源码版本或报告时间，未修改RTL、软件或工程配置，未重跑任何FPGA流程。本轮没有新增照片或用户主观显示结论，报告只依据实际串口结果。
