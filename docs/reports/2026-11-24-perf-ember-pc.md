# P-1：《余烬群岛》PC 性能

基线：`001327290b5b0cf3b3374244995a83a2a468774e`。
GPU：`4b1ab8c408f27f4059012376e16201b3361dc8cc`；游戏/DISP：本报告所在提交，
用 `git log -1 --format=%H -- docs/reports/2026-11-24-perf-ember-pc.md` 取得。
主机：KVM，AMD EPYC 7742，3 vCPU；gcc 13.3.0、Zig 0.17.0、xPack GCC 15.2.0。
C11、`-Wall -Wextra -Werror`；PC 从 -O2 改 -O3，板端/Spike 保持 -O2。
验收时仅串行运行本任务程序；下列负载均为 uptime 的 1/5/15 分钟值。

1200 帧 coast 原版程序耗时 **10.755075 s，即 8.962563 ms/帧**（含初始化）。
该次负载 **2.57/3.20/2.50**；满足 ≤12 ms。
三线程压力场景仅测三次：**18.717814、14.499708、14.681650 ms**，
中位数 **14.681650 ms**，满足 ≤16 ms；负载 **3.41/3.40/2.53**。
压力内容保持原样：640×360 两条，各 1000 四边形、500 双线性三角形、2000 对象。

下表来自另一次 1200 帧墙钟分段采样，单位 ms/帧；分布为整帧统计。
基线负载 3.50/3.37/2.44，优化后负载 3.34/3.40/2.50。

| 项目 | 优化前 | 优化后 |
|---|---:|---:|
| 整帧 mean / p50 | 37.502 / 36.559 | 9.008 / 8.356 |
| 整帧 p95 / max | 49.132 / 80.816 | 13.020 / 32.817 |
| 模拟 | 0.046161 | 0.043950 |
| gfx 准备 | 0.028713 | 0.025414 |
| 音频（含混音/IRQ） | 0.034009 | 0.032167 |
| DISP 合成 | 16.779227 | 1.040963 |
| 平台等待 | 0.000188 | 0.000160 |
| GPU CLEAR | 0.831796 | 0.847883 |
| GPU DRAW_TRI | 1.940459 | 1.719893 |
| GPU DRAW_QUAD | 17.159010 | 4.298569 |
| GPU OBJ_STEP | 0.053319 | 0.500171 |
| GPU TEX_LOAD / PAL_LOAD | 0.008154 / 0.003326 | 0.008444 / 0.003379 |
| GPU RESOLVE / 状态设置 | 0.493617 / 0.002333 | 0.400330 / 0.002164 |

gprof 单次采样热点：quad 53.00%、draw_triangle 18.33%、command_body 11.12%、
pc_soc_vsync 9.38%、alpha_over 4.87%；-pg 的时间不用于验收。
Windows 按墙钟补 60 Hz tick，每轮最多 4 次，超额欠账丢弃；FPS/T 均为实测。
节拍测试：33 ms 渲染间隔下 HUD 为 FPS 31、T 60；另验证四 tick 上限及欠账丢弃。
Linux 无显示设备，GDI 显示耗时和 Windows 实机节拍未测；Windows exe 交叉编译通过。

逐位回归：threads=1/3 各 121 GT、12 自测组、43863 原生操作全部一致；
各保留 4 个 GT AXI 注错和 2 个自测 AXI 注错跳过，均为原有同步 API 限制。
四种游戏构建 0 告警，游戏/音频/节拍/DISP 全像素测试通过；`git diff --check` 通过。
完整 coast 10800 帧：PC/Spike 180 条 STATE 逐项一致，均 END,10800,3,5，音频欠载 0。

复现（仓库根目录，逐条串行，构建用 -j1）：
```sh
. ~/.local/opt/edrv32/env.sh
make -f sw/apps/ember_isles/Makefile -j1 all test
make -C sw/bsp/pc -j1 test
python3 tools/gpu/emu/compare.py --threads 1  # 再运行 --threads 3
python3 tools/gpu/emu/pc/profile_ember.py --revision 001327290b5b0cf3b3374244995a83a2a468774e
python3 tools/gpu/emu/pc/profile_ember.py     # 另运行 --gprof 查看热点
python3 tools/gpu/emu/bench_stress.py
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt --frames 1200
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt > build/ember_isles/pc.log
python3 sw/apps/ember_isles/tools/measure.py
```
原始日志：`build/ember-perf/takeover-*`；gprof：`build/ember-perf/profile/gprof.txt`；
三次压力数据：`build/gpu-emu/stress-acceptance.json`；完整录像：`build/ember_isles/{pc,spike}.log`。
