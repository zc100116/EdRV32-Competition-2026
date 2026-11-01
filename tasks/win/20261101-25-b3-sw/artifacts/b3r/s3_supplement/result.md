# 卡25 B3R：S3/LVGL性能补测（2026-11-01）

用户保留R比特流，仅重新串口加载卡24目录的s3.elf，无重新综合、IP或RTL改动。本次补充adeb9817中缺失的S3性能数据，不宣称卡25全部项目完成。

## 加载与采集

COM7，115200 8N1；工具缓冲239条，从串口连接、启动和ELF加载至用户断开串口完整保存于session.log、entries.json。程序输出Load bytes: 1158436 segments: 2、Load result: PASS、Run: 0x90000000。运行配置为LVGL v9.6.0 DIRECT RGB565 1280x720 batch=32。工具连接、加载、网口和遥测状态同时保存；未主动重跑或改动当前硬件。

## Benchmark

日志已打印Benchmark Summary并返回常规LVGL输出，16个场景fps全部非零，原始汇总平均25fps（保留程序汇总，不另以分项计算替代）。完整CPU、FPS、平均时间、render和flush表见benchmark_summary.txt。

| 场景 | fps |
|---|---:|
| Empty screen | 60 |
| Moving wallpaper | 30 |
| Single rectangle | 60 |
| Multiple rectangles | 57 |
| Multiple RGB images | 30 |
| Multiple ARGB images | 30 |
| Rotated ARGB images | 30 |
| Multiple labels | 20 |
| Screen sized text | 11 |
| Multiple arcs | 28 |
| Containers | 8 |
| Containers with overlay | 7 |
| Containers with opa | 7 |
| Containers with opa_layer | 3 |
| Containers with scrolling | 5 |
| Widgets demo | 16 |

共取得16场景加ALL共17条LVGL split，全部字段导出为lvgl_split.tsv，同时保留lvgl_split_original.txt原文，包括draw/copy、clean/wait/finish、RND PERF、CPU指令/停顿/cache/IPC和xbar计数。数据为程序原值，不把xbar零值解释为无总线流量。

ALL：frames=1361, render_ms=35.420, rnd_ms=16.024, sw_ms=0.168, other_ms=19.227, cpu_ipc=0.582, icache_mpki=4.580, dcache_mpki=0.441.

最低帧率场景为Containers with opa_layer：3fps；Containers with scrolling为5fps；Widgets demo为16fps。S3常规菜单周期日志约3–4fps，不能与benchmark场景fps混为同一指标；切换附近也有fps=0样本，原样保留。

## RN-17、LAYERS及覆盖限制

RN-17实际原文：

```
RN-17 full_max_lsb=0 edge_max_lsb=17 over1=1320 pixels=921600 over1_ppm=1432 bins_0_1_2_3to4_5plus=903312,16968,1224,60,36 rnd_tasks=29 sw_tasks=0 PASS
RN-17 type=1 claimed=7 unclaimed=0
RN-17 type=2 claimed=5 unclaimed=0
RN-17 type=5 claimed=17 unclaimed=0
```

本轮只有上述一条RN-17图像比较汇总及类型计数，没有16项逐项结果，因此不能据此填成15/16或16/16。

取得LAYERS 1–5的预期文字，LAYERS 5连续3条claimed=9 unclaimed=0。没有本轮照片或用户逐项画面确认，不将日志预期文字当成视觉通过证据。

已保存缓冲中未见S3 CPU mcause；但未记录菜单五项两轮的完整操作确认，独立WIDGETS停留30秒及松键检查未确认。GAME日志有59–60fps样本；不据此推断NES性能。

工具telemetry.records=0、latest=null，edtm_s3.csv仅表头，没有可用EDTM样本；网口状态见ethernet.json。未取得截图，保留这些缺项，不将零记录当成带宽或丢失正常。
