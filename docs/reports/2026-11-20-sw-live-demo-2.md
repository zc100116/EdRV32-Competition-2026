# 板端现场演示第二轮验证（2026-11-20）

- 版本：`17bdd2e24` 加本报告所在提交；xPack GCC 15.2.0，RV32IM/Zicsr。
- 主机 GCC 13.3.0、LVGL 9.6.0；1280×720 离屏渲染，无 FPGA 实测。
- 对比 L4：删除自动增益，改为 L9 百分位色阶、一半平滑、gamma 双组切换和 AEC。
- L7：默认输入组生成镜像，按协调者修订的 1000 B payload 上限分片。
- L9：高级区显示自动值、禁用对应手动滑块；无 PIX 时只保留传感器曝光调节。
- 默认快捷档 1、目标亮度 110、曝光目标 44 均为具名常量。
- AEC 为摄像头全局设置；图像处理页使用独立 PIX/GEO 参数。
- L10：六章十一场景，含图像处理；目录、横幅、远程范围与回绕已更新。

| 验收命令 | 结果 |
|---|---|
| `. ~/.local/opt/edrv32/env.sh; make -C sw PROGRAM=showcase -j1` | PASS，0 告警 |
| 同上加 `-o FORCE`（最终增量链接） | PASS，0 告警 |
| `make -C sw/tests/showcase -j1 test live tower` | PASS |
| `make -C sw/apps/showcase/sim -j1 live-shots pages-shots tower-shots` | PASS |

- 主机新增覆盖：暗/亮/窄动态范围百分位、BC 与 BRIGHTNESS 限幅、gamma 公式/死区。
- 实际 AEC 驱动的六个寄存器在 t=44/80/120 全部匹配预期。
- 镜像用真实 LVGL 控件验证多分片编码、四种 kind、revision、ACK 与输入接管。
- 截图命令另设置 `PAGES_OUTPUT=$PWD/outputs/live-demo-2/pages`、
  `TOWER_OUTPUT=$PWD/outputs/live-demo-2/tower`（`$PWD` 为仓库根目录）。
- 截图：`outputs/live-demo-2/`，包括 `advanced-drawer.png`；自动色阶开、自动 gamma 关。
- 高级区、六章目录及左上角标签文字完整；截图和日志不入库。
- 原始日志：`build/live-demo-2/{build,build-final,tests,shots}.log`。
- 尚需上板定稿 L5 的默认快捷档和 T；本任务未作识别置信度或帧率实测。
