# E3 平台、容量与性能

结论：平台实现和测量完成；**稳定 60 Hz 未验收**；不进入下一里程碑。
最终代码 `10f5e5b12`；接口 `f33181ace`；平台/直接 RGB565 优化 `a20fe0023`。
密集 u8 缓存候选 `a0f200149` 全量逐位通过，但未证明提速，已撤回。
环境：Linux x86_64、GCC 13.3.0、C11、O3、Wall/Wextra/Werror、GPU 三线程。
Windows 用 Zig 0.17.0 交叉构建；板上用 xPack GCC 15.2.0；均仅编译，未实际运行。

协调者确认：旧 `PLAT_*`、`plat_keys()` 和 `VI_*` 原有数值/含义保留。
游戏调用 `plat_game_keys()`：W/A/S/D 为 bit0/1/2/3，J/K/L/U 为 bit4/5/6/7，
Q/F/Space/Esc/Enter 为 bit8/9/10/11/12；bit13–15 保留 0；PC 支持方向键别名。
PC 前端通过 `pc_soc_game_input(keys, pointer)` 发布；02 已接入游戏和录像前端。
`plat_pointer()` 为 640×360 菜单坐标，buttons bit0/1/2 = 左/右/中键；鼠标不进录像。
线上仍为 8 字节：keys16 LE、x/y s16 LE（1280×720）、mouse、wheel；active 不在线上。
VI bit12–15 新增 L/U/Q/F；UP/LEFT/DOWN/RIGHT/A/B 映射 W/A/S/D/J/K，
SELECT/ESC/ENTER 映射 Space/Esc/Enter；START/NEXT/PREV 游戏不用；指针坐标除 2。
GPIO RIGHT/LEFT/A/START 对应游戏 D/A/J/Enter；现有发送工具同步扩展。

PM 构建补丁：仅 Ember Isles `PCFLAGS` 加 `-DGPU_EMU_TEXTURE_BYTES=262144`。
不定义时为硬件 196608 B；板上不变；18 位纹理起点字段、驱动和渲染路径不变。
`profile_ember.py` 替换已有容量宏，避免 PM 集成后重复定义。
`pc_soc_gpu_usage()` 报告纹理最高已加载结束地址、提交对象槽峰值、存活对象峰值。
全录像：纹理布局需 65600 B；提交对象槽峰值 8000；实际存活粒子峰值 140。
模拟峰值：19 敌人、33 发弹；本次未达到 tech 的 1500/3000/8000 存活规模。
纹理统计包含布局空隙；不把主机缓存大小算成 GPU 纹理用量；统计跨软复位保留。

默认 192 KiB 全量 compare：121 GT、12 组自测共 43863 次操作通过。
沿用工具原有跳过：4 个 GT、2 个自测注入 AXI 错误场景，C API 不提供该注入。
平台测试通过：13 游戏键位、旧位图、8 字节帧、指针/释放、DISP/AUD/PLIC。
容量定向通过：192 KiB 报错 3/4；256 KiB 在字节 196608 起加载并绘制红色纹理。
真实时间驱动测试通过：30 Hz 渲染/60 Hz 模拟、四 tick 上限、FPS/tick HUD。
Windows/board 构建通过，0 warning/error；Python 参考模型未修改；GPU 周期计数仍为 0。

同一 seed=20261124、10800 帧 coast 录像；180 组 STATE 逐项相同：
| GPU 缓存版本 | mean | p50 | p95 | p99 | max | >16.667 ms |
|---|---:|---:|---:|---:|---:|---:|
| 保留的 RGBA 索引缓存 | 9.955824 | 8.815530 | 16.556992 | 23.172677 | 62.689457 | 510/10800，4.722% |
| 撤回的密集 u8 候选 | 10.854475 | 9.845907 | 16.663796 | 24.294289 | 93.837702 | 539/10800，4.991% |
单位 ms；共享主机墙钟包含调度，单次前后数据不足以把差异全部归因缓存。
繁忙段取候选运行敌人首次最多（frame9048，19 敌）附近 frame8748–9347，共 600 帧：
平均 11.498203 ms；GPU 9.692093 ms（84.29%），模拟 0.080170 ms（0.70%），
表现准备 0.067818 ms（0.59%），DISP 1.445931 ms（12.58%），音频 0.039463 ms（0.34%）。
此段只代表现有录像最高敌数，不代表 E4/E5 满载；瓶颈主要在 GPU 模拟器和显示合成。

复现（仓库根目录，构建 -j1，每次仅运行一个较大程序）：
```sh
make -C sw/bsp/pc test -j1
python3 tools/gpu/emu/capacity_test.py
python3 tools/gpu/emu/compare.py --threads 3
make -C sw/apps/ember_isles windows -j1
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/ember_isles board -j1
make -C sw/apps/ember_isles "$PWD/build/ember_isles/pacing-test" -j1
build/ember_isles/pacing-test
python3 tools/gpu/emu/pc/profile_ember.py --frames 10800 --texture-bytes 262144
python3 tools/gpu/emu/pc/profile_ember.py --revision a0f200149 --frames 10800 --texture-bytes 262144
```
原始数据：`build/ember-perf/e3-before/{profile.log,frames.csv,replay.log}`、`build/ember-perf/profile/`。
回归日志：`build/{compare-e3-final,compare-e3-dense,platform-e3-retained,capacity-e3-retained,pacing-e3-final,windows-e3-build,board-e3-build}.log`。
Linux 测实际模拟/GPU/音频补充/DISP 工作，不休眠，不含 GDI、waveOut 或 Windows 调度。
Windows 每 600 帧及退出输出实际 FPS/帧时间/用量；保持绝对 60 Hz 截止时间，避免 Sleep 舍入累积。
未完成：Windows 实机稳定 60 Hz、E4/E5 满载、PM 的 PCFLAGS 与菜单指针消费集成；等待 E3 集成确认。
