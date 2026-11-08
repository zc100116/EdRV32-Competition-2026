# NPU 后处理软件验收（2026-11-08）

- 代码：`dbdb1b0a`；集成基线 `9662de79`（含协调者生成寄存器头及 TOOLS）。
- 工具：xPack GCC 15.2.0、主机 GCC 13.3.0、Python 3.12、Verilator 5.020。
- 对象：RV32IM/Zicsr；本机主机测试/构建/lint，未测 PG2L200H 上板性能。
- 正常配置：POST_CTRL=1，INT8=103/105/103，Q24=4194304；候选双缓冲。
- 删除 showcase 725760 B RND COPY/POST raw 缓冲；板端仅排序/NMS/映射。
- CPU→DMA clean 整个120960 B，DONE后按有效记录向上覆盖完整32B行 invalidate。
- 保存输入、帧号、候选数；上一帧 CPU 与下一帧 NPU 分别持有不同候选槽。
- channel 1 为 u32 count+count×24 B 原始候选快照；PC 以 anchor 对齐逐字段比较。
- UART decode 改为候选接管/快照；硬件 DFL 计入 NPU，EDTM 字段名/偏移不变。
- `make -C sw PROGRAM={showcase,demo,demo_npu,board_npu,pp_sw_01,pp_sw_02} -j 1`
  各程序分别执行并通过；C11 `-Wall -Wextra -Werror` 无告警。
- `make -C sw/apps/demo test`、`make -C sw/tests/drivers_build test`：通过。
- `make -C sw/tests/showcase/vision test runtime network`（分别执行）：通过。
- `python3 -m unittest discover -s tools/npu/tests -p test_yolo_post.py -v`：9/9通过。
- `python3 sw/tests/npu_post/host_test.py`：两帧126候选/100框、128条定向记录通过；
  驱动默认值、clean顺序、1..5040及零计数 invalidate范围通过，identity描述符参考执行通过。
- 新增真实 COCO 帧主机比对：37条候选→5条完整 EDDT，逐字段一致。
- PC 协议42项中39项首轮通过，余3项修正旧raw测试数据后通过；原有Yolo上传测试通过。
- PP-SW-01包含真实帧UI阈值/白名单、严格IoU=.45及两侧、负坐标和100框上限；
  PP-SW-02包含两槽写脏、所有权、重用和帧关联，SoC bench观察CPU/cache/APB事务。
- 新SoC bench `--lint-only --timing -Wall -j 1`：0告警；风格检查0告警，diff检查通过。
- 新ELF text/data/bss：PP-SW-01=5956/16/4072 B；PP-SW-02=4828/0/1272 B。
- 原始日志：`build/npu/post_sw/*.{log}`；oracle和DDR图像：该目录的`data/`。
- **等待联调**：PP-SW-01/02仅完成编写、构建和lint，未运行完整SoC仿真；需后处理RTL就绪。
  复现命令：`flock /tmp/edrv32-sim.lock python3 verif/soc/pp_sw_01/run.py`（02同理）。
