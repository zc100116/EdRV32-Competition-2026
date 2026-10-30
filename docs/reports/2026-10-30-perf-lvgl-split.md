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
