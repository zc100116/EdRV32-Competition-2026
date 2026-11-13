# T-VIS-ISR：协作式视觉流水线中断重启

- 代码版本：本报告所在提交；软件基线 `ea11656c`，最终基于 `zc100116/b3` 的 `520ba3cb`
  （新增卡 70 文档，软件未变）。
- 目标：PG2L200H、卡 70 同一 bitstream 的 B 版 ELF；未取得新的板测 fps/延迟数据。
- 结论：主机测试确认无需应用任务调度即可完成 VIN 配对、DONE 输入释放和下一帧启动；
  两个 DONE 在任务运行前到达时，两个候选快照仍按帧序消费，无第三块候选缓冲。
- 运行时与网络测试通过；图片 CH2→NPU→候选快照→三段 TX、取消及显示引用测试通过。

## 改动与所有权

所有共享状态转移使用 `sched_port_lock()/unlock()`；排序/NMS 与候选 cache 维护在任务中。

| 字段/资源 | 生产/取得 | 消费/释放 |
|---|---|---|
| `page/state/capture/model_ready/model_pending` | 任务设置启动条件 | VIN/NPU IRQ 判断；暂停、离页、换模型关闭启动 |
| `pair_image/pair_input/image_id/input_id/image_tick` | VIN IRQ 保留最新配对 | 启动者转交 NPU，或替换/停止释放 |
| `input_busy` / CH2 busy 位 | VIN IRQ 锁定输入槽 | DONE IRQ 释放 NPU 输入；图片仍由任务释放 |
| `npu_*` 活跃帧 | VIN/DONE IRQ 或任务启动 | DONE IRQ 快照到对应 `done[2]` |
| `done[2]/done_mask` | DONE IRQ 写时刻、候选数、帧/输入/图像关联 | 任务按 `acquire_buffer` 顺序取走 |
| `post_owned` / 两块候选区 | DONE IRQ 保留 CPU 所有权 | 任务 invalidate、排序/NMS、整块 clean 后释放 |
| `refs[]/ready` / CH0 busy 位 | VIN/DONE IRQ、显示与任务转移引用 | DISP SWITCH 后释放扫描引用；后处理完成释放帧引用 |
| 启动周期、DONE→START 计数 | 启动者/DONE IRQ | 任务锁内快照清零，锁外格式化 |

候选区首次使用前 clean 两块；相机 START 只写 POST_BASE、INPUT/OUTPUT 和 DOORBELL。
CPU 释放候选区时若 NPU 停着，由任务立即启动，这是双缓冲流控。
`vision fps=` 保留原字段，行尾追加 `idle=%u%% npu_gap=%u.%u`：
idle 是 `sched_idle_ticks()` 增量/实际采样时长；gap 是 DONE→下一次 START 的平均毫秒数。
设计记录 4.2 后已补充所有权与卡 68 的 wait 2.6→18.3 ms、fps 26→17 背景。

## 复现与结果

- 主机 GCC 13.3.0，C11、`-Wall -Wextra -Werror`、UBSan。
- `make -C sw/tests/showcase/vision test runtime network -j 1`：数值测试 13 项 PASS；
  首次 runtime 编译因未初始化 LVGL 子模块失败，初始化 LVGL/nofrendo/coremark 后执行：
- `make -C sw/tests/showcase/vision runtime network -j 1 > build/vision-runtime.log 2>&1`
  成功：runtime 9 项 PASS、network 1 项 PASS；通过项未重复执行。
- 新增：任务不运行时最新 VIN 配对启动、两块完成快照、输入即时释放、候选占用阻止启动、
  CPU 释放后启动、暂停/退出后的 DONE 不启动；mock 检查嵌套锁平衡和 START 持锁。
- `. /home/workspace/.local/opt/edrv32/env.sh`
- `make -C sw PROGRAM=showcase -j 1 > build/vision-showcase-build.log 2>&1`
- 构建成功，xPack GCC 15.2.0，`rv32im_zicsr/ilp32`，项目 C 启用 `-Werror`，0 告警。
- ELF：`build/sw/showcase/showcase.elf`，文件 12,940,680 B；`riscv-none-elf-size`：
  text=12,759,020 B、data=12,164 B、bss=50,514,188 B、total=63,285,372 B。
  ELF 在本任务工作区构建，内部 `BUILD_COMMIT=ea11656c`（提交前）；源码以本报告提交为准。
- `git diff --check` 通过；RTL 未改，Verilog 风格检查/Verilator lint 不适用。
- 未做 SoC 仿真，以上板为准：现有 `board_showcase` 覆盖启动器/系统状态/NES，
  `timeout: 7200` 且不走实时识别；`board_vision` 运行独立连通性程序，未覆盖 showcase。
  仓库未找到一小时内覆盖 showcase 实时识别路径的现成 SoC 仿真。
