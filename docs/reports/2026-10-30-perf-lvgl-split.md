# S3 LVGL 场景耗时拆分（T-LVP1）

- 测量代码：本报告所在提交；父提交/基线 `1621a503`（`zc100116/b3`）。
- 工具：xPack RISC-V GCC 15.2.0、主机 GCC 13.3.0、Python 3；C11 `-O2 -Wall -Wextra -Werror`。
- 配置：RV32IM_Zicsr、DDR app、LVGL v9.6.0 原始子模块、1280×720 DIRECT RGB565、batch=32。
- 器件/速度等级：本次仅主机构建与输出冒烟，不涉及器件测量；板上复用卡14 B3R bitstream。
- 每次同步门铃完成后读 PERF0–5 六个寄存器并以 64 位累计；墙钟覆盖 cache 维护和 IRQ 等待。
- SW 用链接 wrap 捕获 SW 单元并包装完整同步 dispatch，任务数按实际执行计数。
- scene timer 经公开 `lv_timer_create` 的 wrap 包装；每场景结束打印一行，最后打印帧数加权 ALL。
- split render = REFR_START→READY − FLUSH/FLUSH_WAIT，包含布局和同步 COPY；原生 Summary 保留原口径。
- 绘制/COPY 分别累计；总 RND 含两者，另列 COPY 门铃、墙钟和 PERF0；字段单位见 LVGL README。
- B3R 顶层已接通 mem_xbar APB 槽8，因此输出 RND P4 / DISP P0 的同窗口 SNAPSHOT|CLEAR 计数。
- 图层缓冲 98304 B（96 KiB）> 一屏的 1/20 = 92160 B；其他 lv_conf 未改。
- RV32 构建通过，0 warning / 0 error；ELF 文件 **1231752 B**。
- `size`：text **1125204 B**，data **1408 B**，bss **53205376 B**，合计 **54331988 B**。
- 主机严格构建 **511** 个源文件通过，0 warning / 0 error；本次只有 C/构建脚本，无 RTL lint 对象。
- 输出冒烟：16 场景 + ALL + 重启首场景，共 **18** 行，每行 **34** 个字段；名称与原生 Summary 一致。
- 首轮共 **28** 渲染帧、**1329** 门铃（绘制 **1314** / COPY **15**）、**8734** 命令、**24** SW 任务。
- ALL 每帧：门铃 **47.464**、命令 **311.928**、SW 任务 **0.857**；截断三位小数。
- 主机桩 PERF/mem_xbar 读零，同步调用不推进 tick，因此时间均为 **0.000 ms**，不代表板上性能。
- 冒烟 batch 回调仅观察门铃、不执行像素模型；验证场景边界、SW/COPY 计数、汇总、重启及 stop 后无后续 split。
- 与基线相比新增上述统计及层缓冲调整，无板上性能对比；未跑 RN-17 全量或 SoC 仿真。
- 日志：`build/s3/lvgl/{target-build,host-build,split-smoke}.log`；ELF：`build/sw/s3/s3.elf`。
- 板上数值待卡片回传，本报告不填写 DDR 路径性能结论。

复现构建：
```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock make -C sw PROGRAM=s3 MEMORY=ddr_app -j1
riscv-none-elf-size build/sw/s3/s3.elf
flock /tmp/edrv32-sim.lock python3 tools/s3/lvgl_host.py
```
输出冒烟（真实 benchmark/绘制调度，省略像素执行）：
```sh
flock /tmp/edrv32-sim.lock python3 - <<'PY' > build/s3/lvgl/split-smoke.log
import ctypes as C
l = C.CDLL('build/s3/lvgl/lvgl_rn17.so')
T = C.CFUNCTYPE(None, C.c_void_p)
cb = T(lambda batch: None)
l.s3_host_install.argtypes = [T]
l.s3_host_install(cb)
l.s3_lvgl_init()
l.s3_lvgl_start_benchmark()
now = 0
for scene in range(16):
    for delta in (16, 16, 20001):
        now += delta; l.s3_host_time(now); l.s3_lvgl_step()
l.s3_lvgl_start_benchmark()
for delta in (16, 16, 3001):
    now += delta; l.s3_host_time(now); l.s3_lvgl_step()
l.s3_lvgl_stop_demo(); l.s3_host_menu()
l.s3_host_time(now + 20001); l.s3_lvgl_step()
PY
rg -c '^LVGL split ' build/s3/lvgl/split-smoke.log # 18
```

## 板上结果（卡 16）

- 结果：`origin/win/20261030-16-b3r-lvgl-nes`（`788064d5`），代码 `b32f589c`，程序为卡 16 `src/s3.elf`（由 `b64814aa` 构建）；bitstream 复用卡 14 B3R（RTL `1621a503` 起未变），GUI 115200 加载。
- 原始数据：`tasks/win/20261030-16-b3r-lvgl-nes/artifacts/lvgl_split.tsv`（17 行 34 列）、`benchmark_summary.txt`、`uart/s3.log`。
- 原生 Summary 全场景平均 15 fps，opa_layer 由卡 14 的 1 fps（474 ms）变为 2 fps（332 ms），其他场景与卡 14 相差在 ±2 fps 内。

每帧 ms（split 口径）。"驱动"= `rnd_ms − perf0_ms`，即 cache 维护、提交和中断返回；"其余"= `other_ms`：

| 场景 | render | RND 硬件（PERF0） | 驱动 | SW | 其余 | 门铃/帧 | 像素/周期 | 读等待 % | 写等待 % |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Empty screen | 17.1 | 2.4 | 3.3 | 0 | 11.4 | 6.0 | 3.27 | 26 | 9 |
| Single rectangle | 3.3 | 0.3 | 0.4 | 0 | 2.7 | 1.7 | 3.11 | 16 | 6 |
| Multiple RGB images | 43.7 | 4.3 | 6.4 | 0 | 33.0 | 27.0 | 2.24 | 38 | 23 |
| Rotated ARGB images | 223.4 | 1.5 | 4.6 | 188.6 | 28.7 | 25.2 | 2.20 | 25 | 9 |
| Screen sized text | 272.8 | 19.0 | 62.2 | 0 | 191.6 | 56.3 | 0.54 | 80 | 28 |
| Multiple arcs | 112.1 | 2.5 | 3.4 | 78.0 | 28.2 | 6.0 | 3.23 | 27 | 10 |
| Containers | 185.7 | 67.3 | 21.7 | 0 | 96.6 | 94.9 | 0.15 | 5 | 4 |
| Containers with opa_layer | 355.0 | 130.2 | 36.3 | 0 | 188.5 | 171.4 | 0.10 | 4 | 4 |
| Containers with scrolling | 265.3 | 111.4 | 33.3 | 0 | 120.6 | 129.5 | 0.16 | 5 | 4 |
| Widgets demo | 177.2 | 11.6 | 13.0 | 63.2 | 89.5 | 66.7 | 1.66 | 21 | 30 |
| **ALL（帧数加权，825 帧）** | **67.1** | **9.3（14%）** | **8.4（13%）** | **12.8（19%）** | **36.6（55%）** | 34.8 | 0.87 | 18 | 13 |

- 驱动开销平均每次门铃 242 µs（126–1105 µs）。Screen sized text 每次门铃约 30 条 GLYPH，每条字形各登记一个 source，每次门铃约 32 次 cache 维护，开销 1105 µs。
- Empty screen 每帧 RND 写 63235 beat（约 2.0 MB），用时 2.4 ms，约 830 MB/s，3.27 像素/周期。RN-18 仿真（B 延迟 0）为 14.5 像素/周期。
- mem_xbar：RND 端口平均每个事务的仲裁等待 3.2–3.6 周期；DISP 读占 0.028 beat/周期。各场景窗口内 RND 的写 beat 都低于 0.02 beat/周期。
- Container 系列 RND 内部计算受限：读、写等待各约 5%，0.10–0.16 像素/周期，每帧读 24–51 万 beat。
- 文字类 GLYPH 受读延迟限制：读等待 80%，每个读事务约 1.4 beat。


## T-LVP2

- 实现：本节所在提交，基线 `e98d739c`；配置、工具和 B3R bitstream 与上文相同，无 RTL 改动。
- 静态 DDR A8 缓存以（resolved font 指针、glyph index）索引，首次转换/复制后 clean 一次，后续直接引用。
- lv_conf 启用 Montserrat 12/14/16/18/20/22/24/26/28/32/40，各 158 个 descriptor。
- 容量 `sum(align64(align32(box_w)*box_h)) = 1046976 B`，索引 13904 B；替代原 524288 B 暂存区。
- 缓存跨场景保留；满时打印 `S3 glyph cache full` 并停止，无暂存回退。
- 非缓存 source 的相邻/重叠范围合并（含 COPY），目标作为 source 的 clean 保留；batch 仍为 32，同步逐任务提交。
- 原 split 字段不变，行尾新增 clean/wait/finish、cache_ops、glyph_cpu_ms，以及周期/指令/HPM/IPC/MPKI。
- clean 包括首次 glyph clean；glyph_cpu 减去其 clean 和回调内同步提交；其他旧字段口径不变。
- wait 从 DOORBELL 写前计至共享中断函数入口时间戳，减 PERF0 ms 得中断延迟（含时间戳边界成本）。
- HPM3–10 配置事件 9–16，和 CY/IR 同时冻结/清零/启用；完整场景窗口含 IRQ/等待，排除场景输出。
- 主机 PERF/mem_xbar/HPM、时间和 IPC/MPKI 均为 0；cache_ops 按调用计数，不代表板上速度。
- 板上计时、HPM 和提速结果留给卡片；本节不填写未经测量的板上数字。
- RV32 严格构建 0 warning / 0 error；ELF **1235372 B**；size：text **1128324**、data **1408**、bss **53742912 B**。
- 主机严格构建 **511** 个源文件通过；本次无 RTL lint 对象；`git diff --check` 通过。
- split 冒烟 **18 行 × 52 字段**，原 34 字段名称/顺序保留；16 场景 + ALL + 重启首场景均正常。
- 首轮 **28 帧 / 1329 门铃 / 8716 命令 / 24 SW 任务**；门铃/SW 与 T-LVP1 相同，命令少 18。
- ALL 每帧门铃 **47.464**、命令 **311.285**、cache_ops **161.750**；所有硬件计数和时间为 0。
- Screen sized text 每帧门铃 **54.500**、命令 **1585.500**、cache_ops **180.000**，即 **3.303 次/门铃**（含冷填充）。
- 该场景冒烟回调中纯 GLYPH 批次 **54 门铃 / 1654 字形 / 162 维护**，即 **3.000 维护/门铃**，约 30.63 字形/门铃。
- 日志：`target-build.log`、`host-build.log`、`split-smoke.log`、`rn17.log`；RN-17 表为 `rn17-results.md`。
- RN-17 **11/11 PASS**，两次 benchmark→menu 生命周期检查通过；最大 >1 LSB 比例 **0.462348%**。
- 改前对照取 `e98d739c` 的 draw/service/host 三个原文件重链，lv_conf/第三方对象相同；也为 **11/11 PASS**。
- 两版每帧 full/edge 最大 LSB、RND/SW 任务数全部一致；**8 帧 SW/RND 图像逐像素相同**。
- 另 3 帧差异均限顶部监控标题（y<48）和右下角 sysmon（x≥1024、y≥656），其余像素完全相同。
- Linux 原生 sysmon 采样主机 CPU；benchmark 标题也显示该值，三帧统计差如下（新−旧；未列帧全相同）：

| 帧 | 改前 >1 像素 | 改后 >1 像素 | Δ bins（0 / 1 / 2 / 3–4 / ≥5） |
|---|---:|---:|---|
| benchmark-02-rectangle | 151 | 128 | +993 / −970 / −23 / 0 / 0 |
| benchmark-05-argb-images | 872 | 885 | −52 / +39 / +13 / 0 / 0 |
| benchmark-06-rotated-images | 135 | 139 | +60 / −64 / +4 / 0 / 0 |

- 实际 rnd_ref 总量：改前 **541 / 2682 / 21164283**、改后 **541 / 2678 / 21162779**（门铃/命令/像素）。
- README 历史表早于 T-LVP1 的 96 KiB layer buffer 调整；opa_layer 的 278/0 任务在改前 e98 已为 **151/0**。
- 对照原始表/图：`build/s3/lvgl-before/`；逐像素检查：`build/s3/lvgl/compare-before.py` / `.log`。

复现（单线程，生成物均在本 worktree 的 `build/s3/lvgl/`）：
```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock make -C sw PROGRAM=s3 MEMORY=ddr_app -j1
riscv-none-elf-size build/sw/s3/s3.elf
flock /tmp/edrv32-sim.lock python3 tools/s3/lvgl_host.py
flock /tmp/edrv32-sim.lock python3 tools/s3/rn17.py --no-build
```
冒烟使用上文相同的 16 场景/重启/退出序列；另在 batch 回调解码 opcode=3 统计 GLYPH，
从 `s3_rnd_last_timing()` 读取 driver cache_ops（主机桩按 batch source/target 数计数）。
冒烟/像素对照命令：`flock /tmp/edrv32-sim.lock python3 build/s3/lvgl/split-smoke.py`、
`python3 build/s3/lvgl/compare-before.py`；改前可在 `e98d739c` 检出上用上述 host/RN-17 命令复现。

## 板上结果（卡 17，T-LVP2）

- 结果分支 `origin/win/20261030-17-b3r-lvgl-speed`（`570c1934`）；程序为卡 17 的 `src/s3.elf`，由 `6bcce541` 构建；bitstream 沿用卡 14 B3R，GUI 115200 加载。原始数据在 `tasks/win/20261030-17-b3r-lvgl-speed/artifacts/lvgl_split.tsv`（17 行 × 52 列）和 `comparison_card16.tsv`。
- 原生 Summary 全场景平均 15 → **18 fps**。几个场景的变化：

  | 场景 | 卡 16 | 卡 17 |
  |---|---|---|
  | Empty screen | 32 fps | 57 fps |
  | Screen sized text | 3 fps | 5 fps |
  | Multiple labels | 12 fps | 13 fps |

- 板上 RN-17 PASS：全覆盖区 0 LSB；超过 1 LSB 的像素 1094 ppm，卡 14 为 1116 ppm。未出现 `S3 glyph cache full`。

ALL（943 帧加权，每帧 ms）：

| 字段 | 卡 16 | 卡 17 |
|---|---:|---:|
| render | 67.110 | 57.464 |
| rnd（墙钟） | 17.713 | 13.358 |
| RND 硬件 perf0 | 9.305 | 9.212 |
| 驱动（rnd − perf0） | 8.408 | 4.146 |
| sw | 12.825 | 12.151 |
| other | 36.571 | 31.954 |

- 驱动细分（ALL，每帧 ms）：clean 2.615，wait 9.302（与 perf0 9.212 基本相同，中断延迟可忽略），finish 1.021。
- Screen sized text：render 272.8 → 155.6 ms，glyph_cpu 36.4 ms，other 129.3 ms。

CPU 计数器（ALL，每帧；窗口包含等待 RND 和 SWITCH 时的空转）：

| 计数 | 值 | 占周期 |
|---|---:|---:|
| 周期 | 7249296 | — |
| 退休指令 | 2736863（IPC 0.377；B1 板上 CoreMark 为 1.04） | — |
| 前端空 | 3143346 | 43% |
| load-use | 695496 | 9.6% |
| 设备访问等待 | 273177 | 3.8% |
| I$ 缺失 | 55888（20.4 MPKI；CoreMark 为 1.08） | — |
| D$ 缺失 | 7517（2.7 MPKI） | — |
| 分支预测错误 | 124873 | — |

前端空周期 ÷ I$ 缺失 ≈ 56 周期/次，这是 DDR 取指缺失代价的**估算**，假设前端空全部来自 I$ 缺失。按 100 MHz 计，前端空约 31.4 ms/帧，与 other 的 32.0 ms 相当。
