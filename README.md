# EdRV32：自研 RISC-V 处理器与 NPU 的边缘视觉 SoC

本项目参加 **2026 全国大学生嵌入式芯片与系统设计竞赛·FPGA 创新设计赛道**（紫光同创赛道）。系统以自研 EdRV32 处理器和 NPU 为核心，在紫光同创 PG2L200H 上实现完整的边缘视觉 SoC，已上板运行并完成决赛现场演示。

当前版本：**决赛正式版 `m2-final-release`**，说明见 [`发布/README.md`](发布/README.md)。

## 系统组成

| 部分 | 内容 |
|---|---|
| CPU | EdRV32：自研 RV32IM 顺序双发射，7 级流水线；BTB、gshare、锦标赛预测和返回地址栈；I$、D$ 各 32 KB；125 MHz |
| NPU | 512 个 INT8 乘加单元（32 输出通道 × 8 输入通道 × 2 像素），180 MHz；层描述符驱动；写回流中硬件完成类别筛选和检测框解码 |
| 存储与互连 | 64 位系统 AXI、Boot ROM 16 KB、SRAM 64 KB、CLINT/PLIC；256 位 DDR 交叉开关，7 个主端口，显示和采集实时优先；DDR3 1 GB |
| 视频通路 | 双路摄像头输入 VIN、像素处理 PIX（亮度/对比度/gamma、3×3 滤波）、几何变换 GEO、2D 渲染 RND（LVGL 硬件后端）、两层合成 720p60 HDMI 显示 DISP |
| 网络 | 千兆以太网 ETH（RGMII），UDP 收发直通 DDR |
| 软件 | Boot ROM BIOS；演示程序 showcase：LVGL 中文界面，“现场演示”应用串联 6 章 11 个场景（目标检测、手势、人体姿态、工地安全帽、智慧农场、图像处理、图形引擎、抓取实验、弹弓打靶、CoreMark、NES） |
| 模型 | 板上 5 个 INT8 模型：80 类检测、人体姿态、手势（自训练）、安全帽（自训练）、人脸 |
| PC 与移动端工具 | 调试工具（程序加载、图片识别、视频、虚拟键鼠、遥测、手机中转）；Android 演示 App（平板显示场景、手机遥控） |

## 实现结果

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，顶层 `edrv32_fpga_board_full_top`。

| 项 | 值 |
|---|---|
| 资源 | LUT 89,032（55.7%）、FF 109,052、DRM 298、APM 373 |
| 时钟 | clk_sys 125 MHz、clk_mem 125 MHz、clk_npu 180 MHz、显示 74.25 MHz |
| 时序 | 慢角模型下仍有少量负裕量（最差 clk_sys −0.55 ns），快角全部为正；板子常温长时间运行稳定，决赛演示使用该比特流 |
| CoreMark | 5.57 CoreMark/MHz（125 MHz 下 696 分，板测） |
| YOLOv8n | 640×384 一帧 34.4 ms；实时识别约 27 帧/秒 |

## 目录

| 路径 | 内容 |
|---|---|
| `rtl/` | SoC RTL（Verilog-2001），文件列表在 `rtl/filelists/` |
| `fpga/` | 板级顶层、约束、PDS 导入脚本、IP 创建说明 |
| `sw/` | BIOS（`sw/boot`）、演示程序（`sw/apps/showcase`，模型在 `models/`）、驱动和库 |
| `tools/` | 调试工具 `debug_tool`、BIOS 烧录 `board`、NPU 编译量化工具链 `npu`、Android 演示 App `demo/app`、构建脚本 |
| `third_party/` | LVGL、CoreMark、nofrendo、Ultralytics（子模块），以及演示用的 30 个游戏 ROM |
| `docs/spec/` | 系统和各模块规格书，入口为 `edrv32-soc-spec.md` |
| `发布/` | 预编译的演示程序、Boot ROM/SRAM 初始化文件和演示 App |
| `竞赛资料/` | 初赛、决赛的技术文档、海报、视频、答辩材料和教学视频，索引见 [`竞赛资料/README.md`](竞赛资料/README.md) |

## 构建

**准备**

```sh
git submodule update --init
git lfs pull                        # 发布/ 与 竞赛资料/ 中的大文件
pip install -r tools/requirements.txt
```

- RISC-V 工具链：xPack riscv-none-elf-gcc 15.2.0；
- Python 3.12。构建演示程序需要 PySide6（打包游戏封面）；NPU 工具链还需要 PyTorch 等，见 `tools/requirements.txt`。

**软件**

```sh
make -C sw PROGRAM=bootloader      # Boot ROM BIOS
make -C sw PROGRAM=monitor         # SRAM 初始程序
make -C sw PROGRAM=showcase        # 演示程序 build/sw/showcase/showcase.elf
python3 tools/fpga/mem_init.py build/sw/bootloader/rom.hex build/sw/monitor/sram.hex
```

最后一条命令生成 Boot ROM 和 SRAM IP 的初始化文件 `build/fpga/*.dat`；`发布/` 中有同样的预生成文件。

**FPGA**

1. 在 PDS 中新建 PG2L200H-6 FBB676 工程。工程目录放在 `EdRV32-FPGA/<工程名>/`，与本仓库 `EdRV32-Competition-2026/` 位于同一个上级目录下。
2. 按 `fpga/ip/README.md` 生成全部 IP。存储类 IP 的初始化文件选择上一步的 `.dat`。
3. 在 PDS Tcl 控制台中，从工程目录执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`。
4. 依次运行综合、布局布线、时序分析，并生成比特流。

**运行**

1. 下载比特流后，板子从 Boot ROM 启动。
2. 运行 `python tools/debug_tool/main.py`，经网口加载 `showcase.elf`（或 `发布/showcase.elf`）。
3. 平板和手机安装 `发布/演示App.apk`：平板选“平板显示端”，手机选“手机遥控端”。

用法见 `tools/debug_tool/README.md` 和 `tools/demo/app/README.md`。
