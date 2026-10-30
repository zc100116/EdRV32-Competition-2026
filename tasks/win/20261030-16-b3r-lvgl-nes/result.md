# 20261030-16-b3r-lvgl-nes 结果

S3分场景性能及NES演示ROM测试已完成。之后用户提供自备SMB ROM，已加载并识别mapper 0，但用户观察HDMI“画面全是灰色”，显示测试失败，不能判本卡全部通过。演示ROM此前画面和按键正常。

| 项 | 内容 |
|---|---|
| 当前任务检出commit | 788064d557b3eb02665efe9527b013b275c4e04e |
| bitstream | 复用卡14 B3R，G:/codex_project/EdRV32-FPGA/EdRV32-B3R；未重新实现 |
| S3加载方式 | GUI，COM7，115200、8N1 |
| NES加载方式 | 后台uart_tool.py，COM7，115200；--elf和--rom |
| 完成情况 | 步骤2、3完成；步骤4加载成功但HDMI全灰，记录失败后结束采集 |

## LVGL benchmark

取得16个场景及ALL共17行LVGL split，字段共34列，数值均原样抄录到artifacts/lvgl_split.tsv；没有用计算值替换原文。原始GUI缓冲、全部串口导出及RX十六进制也已保留。

Benchmark Summary原文：

```text
Benchmark Summary (9.6.0 )
Name, Avg. CPU, Avg. FPS, Avg. time, render time, flush time
Empty screen, 96%, 32, 28, 15, 13
Moving wallpaper, 100%, 19, 47, 42, 5
Single rectangle, 100%, 55, 15, 2, 13
Multiple rectangles, 100%, 52, 15, 13, 2
Multiple RGB images, 99%, 18, 40, 36, 4
Multiple ARGB images, 99%, 18, 40, 36, 4
Rotated ARGB images, 99%, 4, 220, 214, 6
Multiple labels, 99%, 12, 85, 80, 5
Screen sized text, 99%, 3, 279, 271, 8
Multiple arcs, 100%, 7, 125, 116, 9
Containers, 100%, 4, 173, 165, 8
Containers with overlay, 100%, 4, 180, 171, 9
Containers with opa, 100%, 5, 141, 136, 5
Containers with opa_layer, 100%, 2, 332, 328, 4
Containers with scrolling, 100%, 3, 270, 263, 7
Widgets demo, 98%, 11, 181, 172, 9
All scenes avg.,99%, 15, 134, 128, 6
```

| 场景 | frames | render_ms | rnd_ms | sw_ms | other_ms | perf0_ms | perf4_rd_wait_cycles | perf5_wr_wait_cycles | copy_rnd_ms |
|---|---|---|---|---|---|---|---|---|---|
| Empty screen | 97 | 17.073 | 5.691 | 0.000 | 11.381 | 2.437 | 79159.948 | 28754.597 | 0.000 |
| Moving wallpaper | 58 | 43.433 | 27.702 | 0.000 | 15.731 | 10.449 | 604821.137 | 431423.586 | 0.000 |
| Single rectangle | 165 | 3.325 | 0.611 | 0.000 | 2.714 | 0.254 | 5083.236 | 1838.248 | 0.059 |
| Multiple rectangles | 154 | 14.604 | 2.537 | 0.000 | 12.067 | 1.177 | 5839.623 | 2136.980 | 0.063 |
| Multiple RGB images | 55 | 43.740 | 10.724 | 0.000 | 33.016 | 4.308 | 204597.563 | 123748.545 | 0.000 |
| Multiple ARGB images | 55 | 43.336 | 10.769 | 0.000 | 32.566 | 4.368 | 211939.818 | 125480.290 | 0.000 |
| Rotated ARGB images | 13 | 223.403 | 6.099 | 188.580 | 28.723 | 1.515 | 46826.461 | 17006.307 | 1.981 |
| Multiple labels | 28 | 90.768 | 21.919 | 0.000 | 68.849 | 5.240 | 363530.214 | 129127.785 | 3.675 |
| Screen sized text | 18 | 272.805 | 81.221 | 0.000 | 191.583 | 19.017 | 1907308.722 | 668613.722 | 0.000 |
| Multiple arcs | 22 | 112.085 | 5.820 | 78.025 | 28.239 | 2.467 | 83190.272 | 30136.863 | 0.000 |
| Containers | 15 | 185.656 | 89.015 | 0.000 | 96.641 | 67.267 | 424649.933 | 356624.266 | 1.580 |
| Containers with overlay | 14 | 191.918 | 92.401 | 0.000 | 99.517 | 69.376 | 464513.357 | 479028.785 | 1.579 |
| Containers with opa | 18 | 155.845 | 28.558 | 29.913 | 97.373 | 7.552 | 402821.944 | 337996.833 | 1.570 |
| Containers with opa_layer | 8 | 354.951 | 166.457 | 0.000 | 188.493 | 130.171 | 682459.500 | 631406.375 | 1.589 |
| Containers with scrolling | 12 | 265.324 | 144.698 | 0.000 | 120.626 | 111.430 | 692955.833 | 566081.166 | 0.000 |
| Widgets demo | 93 | 177.215 | 24.587 | 63.167 | 89.459 | 11.575 | 305488.698 | 428678.096 | 0.224 |
| ALL | 825 | 67.110 | 17.713 | 12.825 | 36.571 | 9.305 | 214138.656 | 155802.996 | 0.310 |

ALL的时间字段按程序统计口径记录，不能与Benchmark Summary里的平均fps直接互算替换。mem_xbar的RND/DISP端口统计、draw/copy拆分、PERF0–5完整字段见TSV。RND type=及batch/doorbell原文单独保存在rnd_type_statistics.txt。

## NES外部演示ROM

执行顺序：用户断开GUI串口并按KEY1+复位；Codex在COM7以115200启动uart_tool.py，加载本卡nes.elf，随后把仓库自带nrom-template.nes装入ELF给出的ROM槽，再Run。未操作桌面、未切换高波特率、未重新下载bitstream。

关键原文：

```text
Load bytes: 194356 at 0x90000000
Load result: PASS
Load bytes: 4384 at 0x9002f738
Load result: PASS
Load bytes: 24592 at 0x905e91c0
Load result: PASS
Run: 0x90000000
Head: 0x905e91c0 (4e 45 53 1a)
NES powered on
NES ROM prg=16 chr=8 mapper=0
```

已取得51个fps统计窗口，全部原文在uart/nes-template.log，结构表在nes_template_fps.tsv。下表保留前4窗口；窗口1作为启动窗口，稳定性能比较可用后续窗口。

| 窗口 | fps | shown | cpu% | ppu% |
|---|---|---|---|---|
| 1 | 46.1 | 14.6 | 24 | 55 |
| 2 | 45.0 | 15.0 | 22 | 56 |
| 3 | 44.9 | 14.9 | 22 | 56 |
| 4 | 44.9 | 14.9 | 22 | 56 |

用户试玩反馈：“正常的”（针对演示ROM画面、人物移动和板上按键）。已记录超过30秒，随后仅停止PC端日志采集并释放COM7；未向板端发送复位，板端NES继续运行。

## 用户自备SMB ROM（补测）

用户此前暂无ROM而暂停该项，之后提供本地文件并指定了一个mapper 0版本重试。原文件已是iNES格式，仅在仓库外解压，未修改头或转换mapper。此前按任务卡未提交ROM；用户随后明确要求上传third_party/nes目录，本轮按用户最新指令一并提交，见末尾补充。

串口加载及运行关键原文：

```text
Load bytes: 194356 at 0x90000000
Load result: PASS
Load bytes: 4384 at 0x9002f738
Load result: PASS
Load bytes: 41488 at 0x905e91c0
Load result: PASS
Run: 0x90000000
Head: 0x905e91c0 (4e 45 53 1a)
Read in trainer at $7000
ROM loaded:  [0] 32k/8k VT
NES ROM prg=32 chr=8 mapper=0
```

用户反馈：“画面全是灰色”。因此本项为加载成功、HDMI显示失败；左右移动、跳跃、Start和游戏速度未获得有效验证，不因串口有FPS/shown计数而判显示正常。

标识ROM之后取得165个帧率窗口，全部保留到nes_smb_fps.tsv；日志开头有旧演示程序残留FPS，分析本次游戏只使用NES ROM prg=32 chr=8 mapper=0之后的窗口。

| 窗口 | fps | shown | cpu% | ppu% |
|---|---|---|---|---|
| 1 | 84.5 | 22.5 | 30 | 35 |
| 2 | 84.0 | 22.4 | 30 | 35 |
| 3 | 84.0 | 22.4 | 30 | 35 |
| 4 | 84.0 | 22.4 | 30 | 35 |

可确认事实：ELF和ROM各段Load result均PASS，ROM识别为PRG32KiB、CHR8KiB、mapper0，日志包含Read in trainer at $7000，程序持续报告FPS。当前不能确定灰屏来自该改版ROM/Trainer兼容性、模拟核心还是图像输出链路；没有擅自改ROM、模拟器或RTL，不把猜测写成根因。

测试后只停止本次PC串口辅助进程，释放COM7；板端未被复位。用户ROM目录按最新指令提交到third_party/nes，ROM不重复放入artifacts，原始串口日志uart/nes-smb.log已保留。
## 文件及范围

- uart/s3.log：GUI整个保留缓冲的原始导出，覆盖本次S3到benchmark结束；可能含同会话前后记录，不冒充逐字节串口抓包。
- uart/s3_gui_buffer.json、uart/s3_gui_status.json、s3_rx_hex.tsv：原始条目、状态快照及RX字节证据。
- lvgl_split.tsv：17行、全部字段；benchmark_summary.txt、rnd_type_statistics.txt：相应原文。
- uart/nes-template.log：后台工具直接写出的原始串口字节；nes_template_fps.tsv：全部帧率窗口。
- checklist.md：已完成项、用户观察及SMB灰屏失败说明。

本轮按用户最新指令提交third_party/nes目录；没有提交bitstream。本卡只换软件，没有运行综合、布局布线或STA。未对源码版本或报告时间作额外核验。


## 用户追加要求：上传本地NES目录（2026-10-31）

用户明确要求将灰屏现象与third_party/nes一起上传，覆盖原任务卡不提交ROM的限制。此次提交该目录当前全部926个文件（918个.nes、8个.fds，合计266.27MiB），没有擅自删除或转换文件。目录已由用户整理为两个子目录：FC改版hack 390款 含封面、FC游戏 536款 含封面。

复现入口：使用任务16的nes.elf，以115200、COM7加载“超级马里奥1超级版”ROM，进入Run后ROM识别为mapper0、PRG32KiB、CHR8KiB，含trainer；用户观察HDMI全灰。串口完整原文及fps窗口已在本任务artifacts/uart/nes-smb.log和nes_smb_fps.tsv保存。mapper头与加载成功不等于画面兼容通过。
