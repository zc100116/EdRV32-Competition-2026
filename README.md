# EdRV32 Competition 2026

本项目参加 **2026 全国大学生嵌入式芯片与系统设计竞赛·FPGA 创新设计赛道**，选择紫光同创赛道的 RISC-V 指令集 CPU 设计题目。项目目标是以自研 EdRV32 处理器为核心，构建具备边缘视觉处理能力的 SoC。

## 项目目标

系统包括带缓存和异常中断处理的 EdRV32 CPU、YOLO 推理加速器、摄像头图像处理单元，以及 HDMI 图形渲染器；通过软硬件协同设计和性能测评验证系统能力。

## 硬件平台

目标 FPGA 为紫光同创 Logos-2 PG2L200H（盘古 676 系列），外设包括 OV5640 双目摄像头、HDMI、DDR3 和 UART；开发工具为 RISC-V GCC 工具链和 Pango Design Suite（PDS）。

## 开发入口

开发规则见 [CLAUDE.md](CLAUDE.md)，系统规格见 [docs/spec/edrv32-soc-spec.md](docs/spec/edrv32-soc-spec.md)，进度见 [docs/plan/roadmap.md](docs/plan/roadmap.md)。旧工程位于 `legacy/`，仅供只读参考。
