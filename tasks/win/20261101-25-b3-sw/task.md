# 任务卡 20261101-25-b3-sw：用卡 23 的 bitstream 复测软件和工具修复

## 1. 目标

**不重新综合**。直接用卡 23 已生成的 B3R、B3N、B3V bitstream，测试卡 23 之后只改了软件和上位机工具的修复：

1. **B3R S3**：启动 LVGL WIDGETS 后 CPU store fault（`mepc=0x900663bc`）已修复。根因是菜单焦点回调访问已释放的卡片对象，见 `docs/debug/2026-11-01-s3-widgets-fault.md`。同时恢复 LVGL 软件帧率统计，benchmark 汇总的各场景 fps 不再是 0。
2. **B3R NES**：键盘松开方向键后人物继续移动的问题已修复，改为 UART 中断接收，见 `docs/debug/2026-11-01-nes-key-release.md`。
3. **B3N 图片批量识别**：新版调试工具在回传缺包、或 1 s 未收到结束时，把该张记为失败并继续下一张（卡 23 停在第一张）。
4. **B3V 网口视频**：新版调试工具用独立接收进程。本卡测出卡 23 硬件（无发包间隔）上的帧率和丢失计数，作为后续 `TX_GAP` 硬件版本的对照。
5. **BIOS 网口烧录诊断**：新版 `uart_tool.py` 在发送镜像前检查 ARP，不通直接报错。本卡按调试记录第 7 节采集诊断数据。

不在本卡：
- BIOS 2 Mbaud 修复：需要新 ROM，卡 23 的 bitstream 里是旧 ROM；
- `TX_GAP` 发包间隔、NPU 时序修复：需要新 RTL，留到卡 24。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。从这里拉出 `win/20261101-25-b3-sw`，在 `result.md` 中记录完整哈希。
- **bitstream**：Windows 本地卡 23 的三个工程（`EdRV32-B3R`、`EdRV32-B3N`、`EdRV32-B3V`）现有的 bitstream，**不重新生成**。记录各自的文件路径和修改时间。
- **程序**：直接用卡 24 目录的程序 `tasks/win/20261101-24-b3-rnv/src/`：

| 文件 | 用于 | 说明 |
|---|---|---|
| `s3.elf` | B3R | 修复 WIDGETS 崩溃，恢复 fps 统计（b3 0046345e） |
| `nes.elf` | B3R | UART 中断接收虚拟输入（b3 026b87ef） |
| `demo_npu.bin` | B3N | 入口 0x10000000。程序会写 ETH `TX_GAP`（0x134），卡 23 硬件没有这个寄存器，写入无效，行为与卡 23 相同 |
| `demo_vision.bin` | B3V | 同上 |
| `board_npu.elf` | B3N | 可选，复核 39/39 |

- **NPU 模型**：`tasks/win/20261029-09-b3-software/src/npu/`。**NES ROM**：同卡 23 的做法，ROM 不进仓库。
- **调试工具**：`git pull` 后重启。

## 3. 环境

- 无需 PDS 综合。需要 JTAG 下载 bitstream、USB 串口、HDMI 显示器；B3V 另需 OV5640。
- **网口准备**：同卡 23。PC 有线网卡 `192.168.1.2/24`，放行 UDP 6000；关闭 Mihomo/Clash 等 TUN；工具本机地址显式设为 192.168.1.2。
- 测网口视频和图片识别时，**关闭 Windows 上的仿真虚拟机**，避免占用 CPU 影响帧率测量。

## 4. 需要的 IP

无（不重新生成）。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261101-25-b3-sw origin/zc100116/b3`；阅读本卡，把用户步骤整理成清单；记录三个 bitstream 的路径和修改时间。 |
| 1 | 用户（U） | 依次下载 B3R、B3N、B3V 的卡 23 bitstream，按 5R、5N、5V 测试。程序都用串口烧录：115200，`.bin` 加 `--addr 0x10000000 --entry 0x10000000`。 |
| 2 | C | 收集串口日志、工具状态和 EDTM 导出，按第 6 节整理。 |

### 5R：B3R（卡 23 bitstream）

1. **S3 菜单**：烧录 `s3.elf`。5 项依次进入，再按 KEY4 返回，做两轮，记录有没有 `S3 CPU mcause`。
2. **WIDGETS**：停留约 30 秒，用 KEY 或虚拟按键操作几下，拍照。
3. **Benchmark**：跑到自然结束，取串口的 `Benchmark Summary` 原文，确认各场景 fps 非 0；同时导出 `edtm_s3.csv`（需要先在工具里建立网口连接）。
4. **RN-17**：预期 15/16，“opa 容器”一帧 FAIL（约 2.25%，已知）。
5. **LAYERS**：5 个画面逐个拍照，记录串口预期文字；画面 5 的 `claimed/unclaimed` 原文照记。
6. **NES**：烧录 `nes.elf`，按卡 23 的方式加载 ROM。
   - 键盘按住方向键 1~2 秒后松开，人物应立即停下；左右各 5 次。
   - 用鼠标点工具上的虚拟按钮再做一遍。
   - 运行约 30 秒，导出 `edtm_nes.csv`，记录显示帧率（`shown`）。
7. **S3 松键对照**：在 S3 里同样按住、松开方向键，记录是否会粘键。S3 的输入路径本卡没有改。

### 5N：B3N（卡 23 bitstream）

1. 可选：`board_npu.elf` 复核 `NPU board: PASS 39/39`。
2. 烧录 `demo_npu.bin`，在调试工具中上传模型。
3. **单张识别 3 张**：检测框是否画在目标上，截图。
4. **文件夹连续识别 ≥ 20 张**：记录完成张数、失败张数和工具显示的失败原因原文、平均往返时间、fps，以及每张的 NPU 周期和后处理周期；同时导出 `edtm_npu.csv`。
5. **BIOS 网口烧录诊断**：按 `docs/debug/2026-11-01-bios-eth-load.md` 第 7 节第 1–4 步采集：
   - 网卡、路由和 ARP 表；
   - 新版 CLI 用 `--eth --baud 115200 --local-ip 192.168.1.2` 的报错原文和原始串口；
   - `eth_probe.py` 的收发记录；
   - 能抓包时，附上有线网卡上与这次 BIOS 会话相关的包。

   注意：BIOS 不回 UDP 包，所以 probe 没有收到回包不能判定失败；做完要重新进入菜单 2。

### 5V：B3V（卡 23 bitstream）

1. 烧录 `demo_vision.bin`。调试工具填本机地址 192.168.1.2，建立网口连接。
2. 输出设为 **ETH**，保持约 60 秒，记录：
   - 工具显示的视频帧率，开始和结束各一次；
   - 丢失计数，开始和结束各一次；
   - 板端 `Video skips`；
   - 画面是否流畅、有没有成片残缺。
3. 输出设为 **both**，重复一次。
4. 在任务管理器中记录调试工具进程（含接收子进程）的 CPU 占用。
5. 隔约 10 秒发两次 `status`，记录 camera0/1 frames，换算每秒增量。

## 6. 产物

放在 `tasks/win/20261101-25-b3-sw/artifacts/<b3r|b3n|b3v>/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `bitstream.txt` | 三个 bitstream 的路径和修改时间 |
| 2 | `uart/*.log` | 各程序完整串口文本（从烧录开始） |
| 3 | `edtm_*.csv` | `edtm_s3.csv`、`edtm_nes.csv`、`edtm_npu.csv` |
| 4 | `bios_eth_diag/*` | 5N 第 5 步的采集 |
| 5 | `photos/*` | WIDGETS、LAYERS 5 画面、B3N 叠框、B3V 视频截图 |

不提交：ROM、bitstream、完整原始日志以外的大文件。

## 7. 通过判据

| 工程 | 判据 |
|---|---|
| B3R | S3 五项两轮均无 CPU 异常；benchmark 自然结束且各场景 fps 非 0；RN-17 15/16（仅 opa 容器 FAIL）；NES 松键立即停止 |
| B3N | 连续识别不会停在某一张，取得完成数、失败数和 fps |
| B3V | 取得 ETH 和 both 两种输出下的帧率、丢失计数和 CPU 占用（作为对照，没有门槛） |

BIOS 网口诊断只采集数据，不判定通过与否。所有数字取自日志原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261101-25-b3-sw 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| bitstream | B3R / B3N / B3V 路径与修改时间 |
| 完成情况 | |

## B3R
- S3 五项×两轮：是否出现 CPU 异常
- WIDGETS：画面与操作
- Benchmark Summary 原文（各场景 fps）
- RN-17 原文
- LAYERS：5 个画面是否与预期一致；画面 5 的 claimed/unclaimed 原文
- NES：键盘左右各 5 次、鼠标点击，是否立即停下；shown fps
- S3 松键对照
- EDTM 文件

## B3N
- 单张识别（检测框是否正确）
- 连续识别：张数、完成/失败数及原因、往返时间、fps、NPU/后处理周期；EDTM 文件
- BIOS 网口诊断：各步骤结果摘要和文件位置

## B3V
| 输出 | 工具帧率（始/末） | 丢失计数（始/末） | Video skips | CPU | 画面 |
|---|---|---|---|---|---|
- 摄像头：两次 status 的 camera0/1 frames 与时间、每秒增量

## 问题与偏离
```
