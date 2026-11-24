# ST-08 启动回归超时

状态：已解决；环境：用户提供的仿真主机（环境不记录）。

## 1. 现象
W-1a 在真实 GPU 接入后运行 ST-08，1800 s 超时，UART 最后停在 BIOS 编译器信息。

## 2. 复现
实现基线：`1aad898b8`（包含 RESOLVE `7257fa437`、object `382469085`）；超时修订 `06d94ada3`。
命令：`python3 verif/soc/gpu_boot/run.py`；测试不使用随机种子。

## 3. 观察
- 1 ms 时 CPU PC 为 `0x11e0`，对应 `uart_puts` 的 UART 发送等待分支。
- 此后 UART 继续输出启动画面、CHIP_ID、容量和编译器信息。
- GDB 在生成模型的 root eval 入口读取 F1 PC：先后进入 `clint_time`（`0x14e8`）和
  `main` 按键采样循环（`0x6b0`）；CLINT MTIME 从 7,484,784 增至 9,920,095。
- `sw/boot/main.c` 打印信息后执行 `BOOT_BUTTON_WINDOW_MS=100` 的完整采样窗口；
  期间 CPU 持续读取 GPIO 和 CLINT。观察读取生成头文件中对应字段，不修改 RTL 或测试。
- 冷构建段约 270 s；首次仿真因主机重启中断，不作为完成或性能结果。
- 恢复后同一命令完整 PASS：纯仿真 2590.275 s，含缓存构建的 runner 为 2609.58 s；
  硬件时间约 151 ms。菜单选择 Run、SRAM 应用 CHIP_ID 和 SIM_EXIT 全部通过。

## 4. 根因
真实 GPU 的完整 SoC 仿真推进较慢；BIOS 在打印信息后正常执行 100 ms 按键采样。
CPU PC 和 MTIME 均前进，最终完整启动通过，确认原 1800 s 墙钟超时预算不足。

## 5. 修复
仅把 `verif/soc/gpu_boot/test.yaml` 的墙钟超时改为 4291 s。
冷构建段约 270 s，与完整仿真 2590.275 s 分段合计 2860.275 s；
`ceil(2860.275 × 1.5) = 4291`，不把主机中断时段计入预算。

## 6. 防回归
沿用 ST-08 的启动信息、BIOS 菜单选择、SRAM 应用和 SIM_EXIT 检查。

## 7. 同类排查
同一 SoC 的 ST-14 已完整 PASS，仿真耗时 31.563 s，覆盖初始复位顺序和媒体软复位。
