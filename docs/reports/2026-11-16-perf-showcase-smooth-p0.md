# Showcase smooth P0（软件测量与修复）

- 固件源码：`e92ebd140`；已 rebase 到 b3 `9a6d89307`，卡 91 对照基线为 `36005f493`。
- 环境：xPack GCC 15.2.0，rv32im_zicsr/ilp32；主机 GCC 13.3.0。
- 上板目标：PG2L200H（速度等级未另采集），卡 75 比特流；本次未上板、未运行 SoC 仿真。
- 本报告记录软件验收，不把 C1/C3/C5/C6 的推断写成硬件实测结论；卡 92 采样确认。

## 改动

- A：视觉报告后一行输出 `sched`，与原识别报告一起按秒取走，不另设打印周期。
- `page` 为视觉管线编号：1 实时、2 图片、4 姿态、5 手势、6 人脸、7 简笔画、8 安全帽、9 抓取/体感。
- `comm/app/gui` 为窗口 busy ticks / 实际窗口时间（%）；`*_max` 为窗口内最长单步（ms），均扣除任务内 WFI。
- `irq` 每源为次数/累计 µs；源为 vin/npu/disp/rnd/eth/uart/gpio，中断只计数和累加 tick。
- `skip` 为 VIN PERF9（vin-spec 2.6/4.4）差值：CH0 全部槽忙跳帧；不包含溢出错误。
- 同步页 `pace` 统计相邻 L0 SWITCH 相隔的 DISP FRAME 数，1/2/3/4/≥5；第一帧不计间隔。
- `gui_wait` 为发布至 GUI 取走的平均 ms；`render` 为取走至最后 flush 的平均 ms。
- `rnd/sw` 分别为同批结果刷新中 RND（含复制）/软件绘制平均 ms；`vsync` 为最后 flush 至 SWITCH1 平均 ms。
- C：人脸/抓取/体感仅在新结果时运行页面定时器并绘制；物理仍按实际 elapsed 时间推进，输入可独立重绘。
- D：脸颊锚点 `A=(眼睛+同侧嘴角)/2 ± 0.30*(右眼−左眼)`，左侧取负、右侧取正，包含倾斜方向。
- E：抓取和体感共用输入在最后可见样本后 ≤200 ms 保持抓/放，按平滑位置的速度外推，超时按丢手处理。
- F：抓取顶栏“曝光 标准/短”即时切换 AEC 设置，沿用到体感；每次输出 `camera exposure=std|short`。
- B：同步页使用六块软件缓冲池，VIN RING_N 仍为 4；完成帧按缓冲引用，硬件槽先写新 SURF_BASE 再清 SLOT_BUSY。
- CH0 池为 6×2 MiB：`[0x06000000,0x06c00000)`；无空闲缓冲时硬件槽保持忙并由 VIN 计 SKIP，暂停/退出在 VIN IDLE 后释放采集引用。

## 曝光计算

- 行时间 `HTS/SCLK=1892/42 MHz=45.0476 µs`；短上限 `floor(420000/1892)=221=0x00dd` 行，约 9.9555 ms。
- `3a02/03` 与 `3a14/15`：标准 `02 e4`（740 行，33.335 ms），短 `00 dd`；`3a0d/0e`：标准 `04/03`，短 `01/01`。
- 增益 `3a18/19`：标准 `00 f8`（15.5×），短 `03 40`（52×，把 `248×740/221` 向上取到 52×）。
- 短模式 `3c00=04,3c01=b4` 固定 50 Hz banding；标准恢复 `00/34` 自动检测，仅写 AEC/增益/防频闪寄存器。
- 依据：[OV5640 v2.03](https://cdn.sparkfun.com/datasheets/Sensors/LightImaging/OV5640_datasheet.pdf) §4.6/4.8/7.8。

## 验收

- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`：通过，0 告警。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`：通过，0 告警。
- `make -C sw/tests/showcase sticker grab games sync`、`make -C sw/tests/sched`：各通过；另验证 WFI 扣除后 busy=31、max=17、idle=20 tick。
- 上述构建/测试全串行；日志 `build/smooth-p0/{build-hw,build-cpu,tests-showcase,tests-sched,tests-busy}.log`；仅 C 软件修改，RTL lint 不适用。
- 硬件后处理 ELF：`build/smooth-p0/showcase-smooth-hw.elf`，39 MiB；生成物不入库。
- 宿主截图工具同步适配采样时间和曝光状态接口；`cc -fsyntax-only`（C11、Wall/Wextra/Werror）通过，日志 `build/smooth-p0/sim-interfaces.log`。
