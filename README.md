# EdRV32：自研 RISC-V 处理器边缘视觉 SoC

本项目参加 **2026 全国大学生嵌入式芯片与系统设计竞赛·FPGA 创新设计赛道**（紫光同创赛道）。系统以自研 EdRV32 处理器为核心，在紫光同创 PG2L200H 上实现完整的边缘视觉 SoC，并已上板运行。

## 系统组成

| 部分 | 内容 |
|---|---|
| CPU | EdRV32：自研顺序双发射 RV32IM 处理器，I$、D$ 各 32 KiB，125 MHz |
| 存储 | 系统总线、Boot ROM、SRAM，DDR3 存储子系统（2 × x16，1 GB） |
| 视觉 | 双路摄像头输入 VIN、像素处理 PIX、几何变换 GEO |
| 推理 | YOLOv8n 推理加速器 NPU，150 MHz |
| 图形与显示 | 2D 绘制引擎 RND（填充、边框、字形、位图、搬运），作为 LVGL 的硬件后端；720p60 HDMI 两层合成显示 DISP |
| 网络 | 千兆以太网 ETH（RGMII），用于图片上传、结果回传、视频与虚拟键鼠 |
| 软件 | Boot ROM BIOS；演示程序 showcase：LVGL 中文界面，包括实时识别、图片识别、图像处理、图形引擎、游戏、CoreMark、系统监控、芯片信息 |
| PC 工具 | 自研调试工具：程序加载、图片识别与参考模型比对、视频接收、虚拟键鼠、性能遥测 |

## 目录

| 路径 | 内容 |
|---|---|
| `rtl/` | SoC RTL（Verilog-2001），文件列表在 `rtl/filelists/` |
| `fpga/` | 板级顶层、约束、PDS 导入脚本、IP 创建说明 |
| `sw/` | BIOS（`sw/boot`）、演示程序（`sw/apps/showcase`）、驱动和库 |
| `tools/` | 自研调试工具（`tools/debug_tool`）和构建脚本 |
| `third_party/` | LVGL、CoreMark、nofrendo（子模块），以及演示用的游戏 ROM |
| `docs/spec/` | 系统和各模块规格书，入口为 `edrv32-soc-spec.md` |
| `初赛/` | 初赛海报和演示视频 |

## 实现结果

PDS 2022.2-SP6.1，PG2L200H-6 FBB676，顶层 `edrv32_fpga_board_full_top`。

| 项 | 值 |
|---|---|
| 资源 | LUT 87151、FF 96124、DRM 277、APM 372 |
| 时钟 | clk_sys 125 MHz、clk_npu 150 MHz、clk_mem 125 MHz、显示 74.25 MHz |
| 慢角 setup WNS | clk_sys +0.087 ns、clk_npu +0.048 ns、clk_mem +0.179 ns、clk_eth +1.864 ns |

性能实测：CoreMark 4.354 CoreMark/MHz；NPU 推理 YOLOv8n 41.7 ms/帧；图片识别从上传到返回结果 88–100 ms。

## 构建

**准备**

```sh
git submodule update --init
```

- RISC-V 工具链：xPack riscv-none-elf-gcc 15.2.0；
- Python 3。

**软件**

```sh
make -C sw PROGRAM=bootloader      # Boot ROM BIOS
make -C sw PROGRAM=monitor         # SRAM 初始程序
make -C sw PROGRAM=showcase        # 演示程序 build/sw/showcase/showcase.elf
python3 tools/fpga/mem_init.py build/sw/bootloader/rom.hex build/sw/monitor/sram.hex
```

最后一条命令生成 Boot ROM 和 SRAM IP 的初始化文件 `build/fpga/*.dat`。

**FPGA**

1. 在 PDS 中新建 PG2L200H-6 FBB676 工程。工程目录放在 `EdRV32-FPGA/<工程名>/`，与本仓库 `EdRV32-Competition-2026/` 位于同一个上级目录下。
2. 按 `fpga/ip/README.md` 生成全部 IP。存储类 IP 的初始化文件选择上一步的 `.dat`。
3. 在 PDS Tcl 控制台中，从工程目录执行 `source ../../EdRV32-Competition-2026/fpga/scripts/import_board_full_top.tcl`。
4. 依次运行综合、布局布线、时序分析，并生成比特流。

**运行**

1. 下载比特流后，板子从 Boot ROM 启动。
2. 安装 `tools/requirements.txt` 中的依赖，然后运行 `python tools/debug_tool/main.py`。
3. 在调试工具中经网口加载 `showcase.elf`。

用法见 `tools/debug_tool/README.md`。
