# 卡24 B3R S3上板测试

用户反馈：“s3测试完成，layer正常”。串口加载s3.elf成功，Load result: PASS，Run: 0x90000000。保存工具当前可取得的5000条缓冲（包括ELF加载和S3测试），session.log/entries.json保留原文，不宣称串口自连接以来从未发生截断。

## Benchmark

完整Benchmark Summary已取得，程序汇总平均24fps、CPU 99%，平均时间70、render62、flush8（程序原始表单位以输出说明为准）。16个场景fps均非零。

| 场景 | fps |
|---|---:|
| Empty screen | 60 |
| Moving wallpaper | 30 |
| Single rectangle | 60 |
| Multiple rectangles | 56 |
| Multiple RGB images | 30 |
| Multiple ARGB images | 30 |
| Rotated ARGB images | 29 |
| Multiple labels | 20 |
| Screen sized text | 11 |
| Multiple arcs | 28 |
| Containers | 7 |
| Containers with overlay | 7 |
| Containers with opa | 7 |
| Containers with opa_layer | 3 |
| Containers with scrolling | 5 |
| Widgets demo | 16 |

LVGL split共17条，全部字段保存lvgl_split.tsv，另保留原文。CPU、cache、RND、draw/copy、clean/wait/finish和xbar等数据按程序原值保存。

## RN-17

```
RN-17 full_max_lsb=0 edge_max_lsb=21 over1=1437 pixels=921600 over1_ppm=1559 bins_0_1_2_3to4_5plus=903188,16975,1246,80,111 rnd_tasks=36 sw_tasks=0 PASS
RN-17 type=1 claimed=7 unclaimed=0
RN-17 type=2 claimed=5 unclaimed=0
RN-17 type=5 claimed=17 unclaimed=0
RN-17 type=8 claimed=7 unclaimed=0
```

本次只有上述汇总PASS和类型计数，不将其改写为16项逐项通过数。

## LAYERS与覆盖

LAYERS画面由用户确认正常。日志中LAYERS5 claimed有9、10及交互后增加至336的记录，unclaimed均为0；场景重新进入后的计数重新从9开始，不把跨场景数值相减。未取得照片。

已保存日志中S3 CPU mcause出现次数：0。菜单五项两轮、独立WIDGETS停留30秒及松键结果没有单独操作确认，不将用户总体完成表述细化为未确认的逐项结果。

telemetry.records=0，latest=null；edtm_s3.csv没有有效记录，EDTM数据未取得。ethernet.json中的15包是工具保留的网络会话状态，不能当成S3遥测采集成功。
