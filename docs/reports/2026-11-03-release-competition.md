# EdRV32 竞赛正式版本（m1-competition-release）

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-03 |
| 标签 | `m1-competition-release`（本文件所在提交） |
| 器件 | 紫光同创 PG2L200H-6 FBB676 |
| 工具 | PDS 2022.2-SP6.1；xPack riscv-none-elf-gcc 15.2.0 |
| 结论 | 完整 SoC 图像系统，clk_sys 125 MHz，已上板运行（用户 2026-11-03 确认） |

## 1. 版本内容

**硬件**：完整 SoC 顶层 `fpga/rtl/edrv32_fpga_board_full_top.v`，包括：
- EdRV32 自研顺序双发射 RV32 处理器，I$、D$ 各 32 KiB；
- 系统总线和 DDR3 存储子系统；
- 摄像头输入 VIN；
- 像素处理 PIX 和几何变换 GEO；
- 2D 绘制引擎 RND，命令集为填充、边框、字形、位图、搬运，作为 LVGL 的硬件后端；
- YOLOv8n 推理加速器 NPU；
- 720p60 HDMI 两层合成显示 DISP；
- 千兆以太网 ETH。

规格见 `docs/spec/`。

**软件**：
- Boot ROM BIOS：`sw/boot`；
- 演示程序 showcase：`sw/apps/showcase`。showcase 是 LVGL 9.6 中文界面，包括实时识别、图片识别、图像处理、图形引擎、游戏、CoreMark、系统监控和芯片信息；
- PC 调试工具：`tools/debug_tool`。

## 2. 时钟配置

| 时钟 | 频率 |
|---|---|
| clk_sys（CPU 和系统总线） | 125 MHz |
| clk_npu | 150 MHz |
| clk_mem（DDR 控制器用户侧、媒体引擎） | 125 MHz |
| 显示 | 74.25 MHz（720p60） |

clk_sys 的配置记录在以下几处：
- `rtl/include/soc_address_map.json` 中的 `clk_sys_hz` = 125000000；
- `fpga/ip/ip_pll_sys.md`：I=1、M=2、F=15.625、O0=6.75；
- `fpga/constraints/edrv32_fpga_board_full_top.fdc`：multiply_by 125 / divide_by 27。

## 3. 实现结果（卡 48，F125 r2）

| 项 | 值 |
|---|---|
| 资源 | LUT 87151、FF 96124、DRM 277、APM 372、分布式 RAM 2206、IO 137 |
| 慢角 setup WNS | clk_sys +0.087 ns、clk_npu +0.048 ns、clk_mem +0.179 ns、clk_eth +1.864 ns，TNS 均为 0 |
| hold | 内部全部满足；RGMII 输入慢角 hold −0.242 ns（5 个端点），属于已知的板级接口项，上板收发正常 |
| 比特流 | `origin/win/20261103-48-vrn-f-rnd1slim` 中的 `fpga/bitstreams/EdRV32-F-cpu125m-r2.sbit`（9188552 字节） |

原始报告：同一分支的 `tasks/win/20261103-48-vrn-f-rnd1slim/f_cpu125_r2_results.md` 和 `artifacts/F-cpu125m-r2/`。

## 4. 已测性能

| 项 | 值 | 来源 |
|---|---|---|
| CoreMark | 4.354 CoreMark/MHz（-O3 调优编译，代码和数据都在 SRAM） | 卡 40 板测 |
| NPU（YOLOv8n） | 41.7 ms/帧 | 卡 54 第 3 轮 `vision` 行 |
| 图片识别（上传到结果返回） | 88–100 ms | 卡 54 第 2 轮 `image` 行 |
| 实时识别、LVGL benchmark | 用户已在第 4 轮程序上板确认，数字待回传后补入 | 卡 54 第 4 轮 |

## 5. 复现

1. **FPGA**：
   - 在 PDS 中按 `fpga/ip/README.md` 生成全部 IP；
   - 执行 `fpga/scripts/import_board_full_top.tcl`；
   - 综合、布局布线，PnR 参数见第 3 节的原始报告。
2. **软件**：
   ```
   . ~/.local/opt/edrv32/env.sh
   make -C sw PROGRAM=showcase -j 3
   ```
   输出 `build/sw/showcase/showcase.elf`，用调试工具经网口加载。
3. **主机测试**：
   ```
   make -C sw/tests/showcase test
   ```
4. **回归**：`python3 tools/regress.py smoke --parallel 3`。

## 6. 与上一版本的差异

本版本是第一个正式版本。本次相对开发分支的变化：clk_sys 的 125 MHz 配置写入仓库，使仓库内容与上板比特流一致。具体包括：
- `soc_address_map.json` 和生成的头文件；
- 全部板级 `.fdc`；
- `ip_pll_sys` 创建说明；
- `cpu-spec` v0.15，最高频率定稿。

以下单元测试在新常量下通过：`periph_uart`、`periph_i2c`、`periph_sysctrl`。
