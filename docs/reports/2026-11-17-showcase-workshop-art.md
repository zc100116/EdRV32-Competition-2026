# 方块工坊原创美术资源

- 日期：2026-11-17；基线：`c90d8b46c`；美术提交为本报告所属提交。
- 资源目录：`sw/apps/showcase/assets/workshop/`，110 张 straight-alpha RGBA8 PNG。
- 清单：17 方块、5 门梁柱、8 斜坡、8 裂纹、28 小兔帧、28 小鸭帧、
  4 光标、5 工具/昼夜图标、1 光晕、3 扬尘、3 碎片。
- ARGB8888 实际总量：**1,370,112 字节**（宽×高×4 求和），小于 2,000,000 字节。
- 小兔 walk 步幅 24 px/8 帧；小鸭 16 px/8 帧；支撑脚底均为画布 y=52。
- 10 fps 对应 30/20 px/s；左朝向逐帧镜像；裂纹固定种子 20261117。
- 新图全由 Pillow 4 倍绘制缩小；扬尘和碎片从 tower 原样复制。
- imagegen 新源图：无；完整复用提示词、尺寸和重生成说明见资源 README。
- 生成命令：`~/.local/opt/edrv32-py/bin/python tools/sw/compose_workshop_art.py --preview-dir /home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/workshop-art`。
- 预览目录：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/workshop-art/`。
- 预览：blocks.png、cracks.png、animals.png、bunny-walk.gif、duck-walk.gif（10 fps）。
- 房屋背景为本地绘制、模糊并调暗的摄像头室内示例，非真实相机采集。
- 构建命令：`. ~/.local/opt/edrv32/env.sh; flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`。
- 构建日志：`build/showcase/workshop-art-build.log`；PASS，0 告警（首次缺子模块，经协调者许可补齐后重跑）。
- 嵌入使用 `ws` 前缀、根目录 PNG glob，排除离线 source/；tower 规则保留。
- 本任务不涉及 RTL，Verilog 风格检查及 Verilator lint 不适用。
- 验收 PASS：110 张尺寸/RGBA/镜像、五份预览及 10 fps GIF；C 中全部 110 个 ws 描述符。
