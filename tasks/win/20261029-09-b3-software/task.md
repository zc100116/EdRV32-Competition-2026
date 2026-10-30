# 任务卡 20261029-09-b3-software：B3V / B3VN / B3F 经 BIOS 运行各自的演示程序

## 1. 目标

卡 07（B3V、B3F）和卡 08（B3VN）的 bitstream 点亮、能进入新 BIOS 后，**不重新生成 bitstream**，经 BIOS 把各工程对应的程序烧进 SRAM 运行，并按检查清单上板验收。B3R 的程序在卡 04 中。

| 工程 | 程序（本卡 `src/`） | 内容 |
|---|---|---|
| B3V 图像 | `demo_vision.bin` | 只有 S2：摄像头 → PIX（5 种）→ GEO（3 种）→ HDMI；网口视频和 DDR 监控。不访问 NPU、RND |
| B3VN 图像 + NPU | `demo_vnpu.bin` | S1 + S2。S1 的检测框和标签由 **CPU 画进 L1 图层**（工程中没有 RND）；`status` 打印每帧画框的 CPU 周期 `Overlay CPU cycles` |
| B3F 全部 | `demo.bin`，以及卡 04 的 `rnd_board.elf`、`s3.elf`、`nes.elf`、`nes_nodisplay.elf` | S1 + S2，检测框由 RND 画进 L1；之后跑 RND 自检、S3、NES |

## 2. 输入

- 代码分支 `origin/zc100116/b3`（包含本卡的提交）。Windows Codex 从这里拉出 `win/20261029-09-b3-software`，在 `result.md` 中记录完整哈希。
- 本卡 `src/`：
  - 三个演示程序在 Linux 端从 30f6464 构建，GCC 15.2.0，`make -C sw PROGRAM=<demo|demo_vision|demo_vnpu> MEMORY=sram -j1`，0 告警；
  - `npu/`：YOLO 模型编译输出（`regs.txt`、`mem_desc.hex`、`mem_model.hex`、`quantization.json`），与 20261029-02 相同。
- 三个版本的功能差异、构建方法：`sw/apps/demo/README.md`“按板级工程选择版本（B3-11）”一节。
- 串口命令、KEY、网口约定、上板检查清单：`sw/apps/demo/README.md`。
- 烧录工具：`tools/board/uart_tool.py`（SRAM 烧录用法见 `tools/board/README.md` 开头）。
- 调试工具：`tools/debug_tool/`（建立网口对端、加载模型、YOLO 图像检查、DDR 监控）。
- 前置：卡 07/08 中对应工程已能进入新 BIOS（`BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud`）。哪个工程先点亮就先做哪个。

## 3. 环境

- 卡 07/08 的 bitstream；HDMI 显示器、USB 串口、两路摄像头、网线连 PC（PC 地址与板子同网段，见 README“网口约定”）；Windows 上的 Python 3 和调试工具依赖。

## 4. 需要的 IP

无。

## 5. 操作步骤

**烧录方法**（每个程序都一样）：
1. Codex 运行 `py tools/board/uart_tool.py tasks/win/20261029-09-b3-software/src/<程序>.bin --port COMx --log build/board/<工程>_demo.log`；
2. 用户按住 KEY1 并按复位，等工具显示 `Program SRAM result:` PASS；
3. 用户松开 KEY1 再按复位运行。工具继续记录串口；要手动输入命令时关闭工具，用串口终端打开同一端口。

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261029-09-b3-software origin/zc100116/b3`。阅读本卡、`sw/apps/demo/README.md`、`tools/board/README.md`，把用户步骤整理成清单交给用户。 |
| 1 | 用户（U） + Codex（C） | **B3V**：烧录 `demo_vision.bin`。<br>启动日志应出现 `Demo: demo_vision (B3V ...)`、VIN/PIX/GEO/DISP/ETH 等实际引擎 ID（没有 NPU、RND）、两路摄像头 chip ID。<br>按 README“上板检查清单”执行 **S2 相关的行**：S2 画面、`status` 两次、5 种 PIX、3 种 GEO、KEY3/KEY4、建立网口对端、三种输出、`fps`、`sample`、DDR 监控页、复位重跑。<br>另外确认：`s1` 和 KEY2 打印 `this board requires s2` 并保持 S2。<br>模型加载、S1、YOLO 页三行不做。 |
| 2 | 用户（U） + Codex（C） | **B3VN**：烧录 `demo_vnpu.bin`。启动日志应出现 `demo_vnpu (B3VN vision + NPU)`，有 NPU ID，没有 RND ID。<br>按 README“上板检查清单”**逐行全部执行**，模型用本卡 `src/npu/`。<br>S1 下重点看 CPU 画的框：框、COCO 类名、置信度标签、移走目标后旧框清除、无残影。<br>S1 运行时执行 `status` 至少 3 次，记录 `Overlay CPU cycles`、NPU 推理次数和检测数（检测数尽量取不同值，例如画面中 0 个、1 个、多个目标）。 |
| 3 | 用户（U） + Codex（C） | **B3F**：烧录 `demo.bin`。启动日志应出现 `demo (B3F ...)` 和全部八个引擎 ID。<br>按 README“上板检查清单”**逐行全部执行**，模型用本卡 `src/npu/`；S1 的框由 RND 绘制。 |
| 4 | 用户（U） + Codex（C） | **B3F 渲染程序**：按卡 04 第 5 节步骤 2–4，在 B3F 上依次运行 `rnd_board.elf`、`s3.elf`、`nes.elf`、`nes_nodisplay.elf`（ELF 用卡 04 的 `src/`，经 BIOS 加载到 DDR）。日志文件名前加 `b3f_`。 |
| 5 | Windows Codex（C） | 填写 `result.md`，提交 `result.md` 和 `artifacts/`，提交信息 `win: 20261029-09-b3-software results`，推送 `win/20261029-09-b3-software`，告诉用户完成并给出分支名。某个工程先做完可以先回传，其余追加提交。 |

某一行异常时记下现象继续下一行，不调试。程序启动就停在错误时，保留日志，跳到下一个工程。

## 6. 产物

放在 `tasks/win/20261029-09-b3-software/artifacts/<B3V|B3VN|B3F>/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/*.log` | 各程序的串口原始日志（含 `status` 输出） |
| 2 | `checklist.md` | README 上板检查清单逐行结果（正常 / 异常 + 现象）；B3F 另含卡 04 三份 README 的检查结果 |
| 3 | `photos/*.jpg`、`*.png` | HDMI 画面照片（S2 各 PIX/GEO 档、S1 检测框）；调试工具 YOLO / 视频 / DDR 监控页截图 |
| 4 | `*.csv` | DDR 监控导出的 CSV（每个工程 S1/S2 各几十秒即可） |

## 7. 通过判据

- B3V：S2 画面正常，5 种 PIX、3 种 GEO 有效，网口视频和 DDR 监控有数据，无引擎错误。
- B3VN、B3F：README 检查清单全部正常；S1 有检测框和标签，YOLO 页 CH2/OUTPUT/EDDT 与参考逐字节/逐项一致。
- B3F 渲染程序：判据同卡 04 第 7 节。
- 帧率、带宽、`Overlay CPU cycles` 不作为通过条件，如实记录。
- 所有数字来自串口日志和调试工具原文，找不到的写“未取得”。

## 8. result.md 模板

```markdown
# 20261029-09-b3-software 结果

| 项 | 内容 |
|---|---|
| 代码 commit（origin/zc100116/b3） | <完整哈希> |
| bitstream 来源 | B3V/B3F：卡 07（commit）；B3VN：卡 08（commit） |
| 完成情况 | 全部完成 / 在步骤 N 停止（原因） |

## B3V（demo_vision）
- 启动信息、引擎 ID：
- 检查清单（正常 / 异常行数，异常行现象）：
- cam0 帧率（status 换算）：
- s1 / KEY2 拒绝：

## B3VN（demo_vnpu）
- 启动信息、引擎 ID：
- 检查清单：
- CPU 画框：
| 检测数 | Overlay CPU cycles | NPU 推理次数 |
|---|---|---|
- YOLO 页比对（CH2 / OUTPUT / EDDT 差异）：

## B3F（demo）
- 启动信息、引擎 ID：
- 检查清单：
- YOLO 页比对：

## B3F 渲染程序（卡 04 内容）
- RND 自检（PASS 组数 / 16）：
- S3（主界面、游戏、widgets、benchmark、RN-17）：
| NES 版本 | fps（窗口 2–4） | shown | cpu% | ppu% |
|---|---|---|---|---|

## 备注
```
