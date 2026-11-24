# G-2.8 E3 性能补完

结论：减少了实际 CPU 工作；**稳定 60 Hz 未验收，E3 未完成，未进入 E4**。
基线 `9a5e91121`（含 `908da6ff7`）；实现 `dc323266c`。
Linux x86_64 / GCC 13.3.0，C11、O3、Wall/Wextra/Werror、默认 GPU_EMU_THREADS=3。
前后同 coast.txt、seed=20261124、完整 frame1–10800、PC 纹理 262144 B。
串行构建/运行；未与影像捕获并发；Linux 前端不休眠，不含 Windows GDI/waveOut。

保留改动：最近邻三角形和四边形共用原 RGBA 索引缓存，避免重复展开整张图集。
调色板只在 PAL_LOAD 后展开，不再随 SET_TEX/三角形与四边形切换重复展开。
并行绘制在派发前解码一次，共享只读 texels；命令完成前缓存不变。
2048 个 1×1 quad/256² 图集、40 次交错 A/B：CPU 均值 2.045305→1.314201 ms。
DISP 将现有 DDR 越界处理移至行级，分开 X1/X2 循环；保留错误及越界像素为黑的行为。
未恢复 a0f200149 的 u8 缓存；线程数和并行阈值保持原值；无新增优化开关。
应用/模拟/录像/美术/驱动/寄存器语义/Python 参考模型均未修改。

| 完整录像，单位 ms | mean | p95 | p99 | max | >16.667 |
|---|---:|---:|---:|---:|---:|
| 基线墙钟 | 10.463170 | 18.745405 | 27.427691 | 77.577344 | 812/10800 |
| 优化墙钟 | 9.459773 | 19.296892 | 28.377054 | 96.558345 | 894/10800 |
| 基线进程 CPU | 8.717345 | 13.983000 | 16.919000 | 34.934000 | 128/10800 |
| 优化进程 CPU | 6.936893 | 12.037000 | 14.890000 | 26.130000 | 26/10800 |

CPU 均值下降 20.42%，墙钟均值下降 9.59%；墙钟尾延迟和超时数没有改善。
CPU 为 getrusage 用户+内核时间，含帧间日志与首帧初始化；不是 CPU 指令数或硬件周期。
整录像 PERF 源顶点/三角形/四边形/通过像素峰值 288/96/1294/651972，前后相同。
每条 DRAW 的规模低于原并行阈值；完整录像实际执行串行路径，线程调参不能解决此负载。
墙钟超时但 CPU 未超时的帧由 684 增到 868；非自愿切换总数 64762→63181。
基线最慢 frame8420：墙钟 77.577344、CPU 12.349000 ms，非自愿切换 15 次。
优化最慢 frame3922：墙钟 96.558345、CPU 18.686000 ms，非自愿切换 17 次。
共享主机确有抢占；墙钟−CPU 还可能包含 I/O/等待，不能全部精确归因调度。
CPU 仍有 26 帧超预算，不能把所有超时归咎主机，也不能宣称已稳定 60 帧。

同一繁忙段 frame8748–9347（600 帧）：
| 均值 ms | 总墙钟 | 进程 CPU | 模拟 | 表现准备 | GPU | 音频 | DISP |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 基线 | 11.583801 | 8.550222 | .090050 | .082459 | 9.696672 | .046917 | 1.499866 |
| 优化 | 10.080819 | 6.635617 | .095992 | .070932 | 8.689399 | .051265 | 1.014208 |
纹理最高加载结束地址 65600 B；对象提交槽峰值 8000，实际存活峰值 140；19 敌/33 模拟弹。
前后全部 180 组 STATE、10800 行 PERF、END 逐项相同；未改模拟，不重跑 Spike。

目标规模合成 GPU 命令测量：1500 个 32×32 敌精灵、3000 个 18×18 双三角形弹、
8000 个 8×8 存活推进/绘制对象，全部在屏幕内；I8 最近邻、Alpha、两条带。
五次独立帧墙钟 77.736245/68.048412/61.323261/75.383086/77.010300 ms。
平均 DRAW_QUAD/DRAW_TRI/OBJ_STEP/RESOLVE 墙钟 8.618056/55.300282/5.958197/.470708 ms。
三角形路径 CPU 平均 78.651050 ms，跨三个线程累计；满载渲染主要受三角形路径限制。
同一合成目标基线墙钟/CPU 均值 97.784955/84.574612，优化 71.900261/91.627068 ms。
目标 CPU 均值增加 8.34%，未证明目标规模计算提速；不同阶段测量受共享主机影响。
未包含 CPU 战斗模拟和 DISP；实际 1500/3000/8000 游戏场景未测。

默认 192 KiB compare：121 GT、12 组自测共 43863 次操作全部通过；沿用 4 GT/2 自测 AXI 注入跳过。
192/256 KiB 容量定向、PC DISP/AUD/PLIC/输入及帧节拍测试通过；Linux/Windows 构建 0 warning/error。
Windows 为 Zig 0.17.0 交叉构建；Windows 实机交互稳定 60 Hz 未测。
复现（仓库根目录，构建 -j1，程序串行运行）：
```sh
python3 tools/gpu/emu/pc/profile_ember.py --revision 9a5e91121 --frames 10800 --texture-bytes 262144
python3 tools/gpu/emu/pc/profile_ember.py --frames 10800 --texture-bytes 262144
python3 tools/gpu/emu/bench_ember_target.py
python3 tools/gpu/emu/compare.py --threads 3
python3 tools/gpu/emu/capacity_test.py
make -C sw/bsp/pc test -j1
make -C sw/apps/ember_isles linux windows -j1
make -C sw/apps/ember_isles "$PWD/build/ember_isles/pacing-test" -j1
build/ember_isles/pacing-test
```
证据：build/ember-perf/g28/{before,after}/{frames.csv,replay.log}、{before,after}.log。
目标逐命令 CSV：build/ember-perf/g28/target-after.csv；验证日志同目录。
补充复现：`python3 build/ember-perf/g28/cache_jobs.py`、`python3 build/ember-perf/g28/target_before.py`。
补充脚本/日志均在同目录；目标基线 CSV 为 target-before/ember-target.csv。
