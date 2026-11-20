# 现场演示与识别前处理板端结果

- 结论：按 L1–L5 实现五章十场景，复用现有页面；DEMO/HELLO4/STATE、前处理及返回规则齐备。
- 依据：b3 `990c6259f` 的设计记录及协调者后续 ask 确认；无 RTL/规格/工具修改。
- 代码版本：本报告所属提交；基线 `0e1e56a4c`。
- 平台：GCC 15.2.0、C11；RV32 软件构建与 Linux LVGL 仿真，未进行 FPGA 测量。
- 默认：有 PIX 为档位 1，无 PIX 为 0；目标亮度 110，具名常量在 `board/vision/preprocess.h`。
- 无 PIX 的非零档位禁用并标注原因；协议返回 ACK(3,4)。黑帧需要增益更新时取上限 2.5。
- APP 打开退出演示，暂停/恢复/重试保留；DEMO 重进暂停场景会恢复；无抽屉游戏不加抽屉。
- 场景 6/9/10 到达页面即完成，其余场景等 RUNNING；目录独立保存焦点与最近进入场景。

改动文件（均相对 `sw/apps/showcase/`，测试/驱动另列）：
- `ui/live_demo.{c,h}`、`ui/ui_data.h`：目录、章节横幅、返回路由、档位控件与标签。
- `ui/{shell,widgets,page_home}.c`。
- `board/network.c`、`board/{protocol,state}.{c,h}`、`board/vision/{vision.c,preprocess.h,README.md}`。
- `main.c`、`platform.c`：benchmark 返回规则、VIN MSRC DONE 中断。
- `sim/{Makefile,sim_data.c,main_live_shots.c,README.md}`、`layout/README.md`。
- `sw/drivers/{vin.c,include/vin.h}`：仅新增保持环配置的输入源切换接口。
- `sw/tests/showcase/{Makefile,main.c,live.c,vision/runtime_test.c,vision/network_test.c}`。

验证命令与结果：
- `make -C sw/tests/showcase -j1 test live sling sticker games workshop phys tower farm draw`：PASS。
- 新增：增益死区/半步/上下限/黑帧、网格黑白值、DEMO actions/越界 ACK(3,2)、STATE 5–7 字节。
- runtime 新增：忙时跳帧、MSRC/CH2 独立引用、不同帧号配对、首个新档位帧完成应答。
- `make -C sw/apps/showcase/sim -j1 live-shots`：PASS，四张截图及导航/抽屉/回绕/自定义 ESC 断言。
- `. ~/.local/opt/edrv32/env.sh; make -C sw -j1 PROGRAM=showcase`：PASS，`-Wall -Wextra -Werror`，0 告警；最终界面同命令追加 `-o FORCE` 增量复验 PASS。
- `git diff --check`：PASS；未跑 RTL 仿真。
- 原始日志：`build/live-demo/{host-tests,screenshots,board-build}.log`（不入库）。

截图（PNG 不入库）：
- `outputs/live-demo/home.png`
- `outputs/live-demo/directory.png`
- `outputs/live-demo/helmet-banner.png`
- `outputs/live-demo/preset-drawer.png`

上板关注：
- 验证 CH0 → MSRC → CH2 时序、CH2 槽位空闲和 Surface 在 MSRC DONE 前不回收。
- 量测实际 e2e 延迟与帧率变化；Linux 数值/所有权测试不代表板上性能。
- 暗/亮环境比较档位 0–3 的检测/安全帽置信度与 fps，再定稿默认档位和目标亮度。
