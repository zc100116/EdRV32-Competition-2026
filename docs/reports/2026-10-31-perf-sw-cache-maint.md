# 软件 cache 维护优化

- 基线：`6bab90a0`；优化：本报告所在提交；仅软件，未使用并行任务的新 cache RTL。
- 环境：用户提供的仿真主机（环境不记录）。改前改后均在同一主机运行。
- 条件：原 RN-17 的 1280×720、3 个 widgets 固定时刻及 8 个 benchmark 场景；每行一次完整 RND 重绘，包含首次字形 clean；不是卡 17 的原 110 次/帧场景。
- 非缓存对象：S3 的 32 条绘制命令及 1 条 COPY 命令（2112 B）、NES 单条 BLIT（64 B）、demo overlay 命令列表；首次切换前 clean+invalidate 缓存别名，此后仅写非缓存别名。
- demo 的透明 Surface 和字体保持缓存：初始化 clean 后不可变，移除每帧重复 clean；单批维护 4→1。NES 单批 2/3→1/2（调色板未变/变化）。
- 等待：OP_CMD 后一次 SRAM_BASE 可缓存读；cpu-spec 4.7 保证非推送设备写先完成，cache-spec 5.4 保证读响应在维护结束后返回；保留入口/出口 fence，无 STATUS 轮询。

| RN-17 帧 | 改前 cache_ops | 改后 cache_ops | 命令数（改前/改后） |
|---|---:|---:|---:|
| widgets-16 | 284 | 221 | 302/302 |
| widgets-176 | 191 | 128 | 302/302 |
| widgets-656 | 193 | 130 | 302/302 |
| benchmark-00-empty | 35 | 29 | 70/70 |
| benchmark-02-rectangle | 24 | 18 | 75/77 |
| benchmark-04-rgb-images | 106 | 79 | 97/97 |
| benchmark-05-argb-images | 104 | 77 | 100/98 |
| benchmark-06-rotated-images | 20 | 13 | 76/76 |
| benchmark-07-labels | 132 | 92 | 423/423 |
| benchmark-10-containers | 259 | 180 | 385/385 |
| benchmark-13-opa-layer | 494 | 342 | 525/525 |

- RN-17：两版各 11/11 PASS；rectangle、argb-images 命令数各相差 2，其余 9 帧相同；表中按实际工作量记录，非逐命令配对。
- 字形首帧：主机命令中 93 个唯一 GLYPH 的 `stride×height` 合计 38208 B；非缓存写至少约 9552 次 32 位非推送写，估算等待成本下限为 `9552×单次写响应延迟`，未实测该延迟，保留缓存和首次 clean。
- 未迁移：图像、图层缓冲、NES 像素/调色板、NPU 测试数据/描述符；存在 CPU 读取或未取得精确写量/非缓存写延迟，维持原 clean/invalidate 约定。
- 结论仅为维护调用减少；未测板上 clean/finish 毫秒数及 FPS，不能从主机人工时钟推算。
- 构建：`make -C sw PROGRAM=<s3|rnd_board|board_npu|demo|demo_vision|demo_vnpu>`、`make -C sw PROGRAM=nes MEMORY=ddr_app` 全部 PASS，0 warning；board_npu 生成时 `PYTHONPATH=third_party/ultralytics`。
- 主机入口：`python3 tools/s3/lvgl_host.py && python3 tools/s3/rn17.py --no-build`；基线同样使用本提交的 RN-17 统计入口链接基线库，判据和场景不变。
- 主机其余：`python3 sw/apps/nes/check_blit.py`（921600 像素精确）、`python3 sw/apps/nes/check_trainer.py`、`make -C sw/apps/demo test`、`python3 -m unittest discover -s tools/board/tests`（11 项）全部 PASS。
- SoC：`flock /tmp/edrv32-sim.lock python3 verif/soc/board_render/run.py`、`flock /tmp/edrv32-sim.lock python3 verif/soc/board_npu/run.py` 全部 PASS，lint 0 warning，编译 `-j 1`。
- 数据：本工作树 `build/sw-maint/` 中构建日志、`nes-blit.log`、`nes-trainer.log`、`demo-host.log`、`board-tests.log`、`soc-summary.txt`、`cache-disassembly.log`、`cache-ops-summary.txt`；仿真主机仅回传自行汇总的数字和结论。
