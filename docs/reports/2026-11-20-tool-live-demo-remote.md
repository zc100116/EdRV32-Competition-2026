# T-LIVE-REMOTE 验收（2026-11-20）

- 基线 commit：0e1e56a4c0958944931647fa532c80d929217b8c；实现见本报告所在提交。
- 依据：b3 990c6259f 的现场演示设计 L1/L3，以及协调端 ask 确认的 busy 行为。
- 范围：PC proto 4 / DEMO / STATE / GUI / REST / CLI / 手机中继；APK 控制条和 NES 手柄。
- 场景：5 章 10 场景；同类 DEMO 等待 ACK(2/3)，忙时不排队，显示原因且保持连接。
- 中继：TCP 47633、每秒重连、分行 JSON、状态及 busy 变化/每秒回传、格式错误断开。
- NES：按键变化发送，PC 100 ms 快照；断开释放手机按键并保留 PC 本地按键。
- APK：versionCode 4 / versionName 1.3；平板 47632 和 PC 47633 独立。

文件：`tools/debug_tool/{core,gui,cli.py,render_shot.py,tests,README.md,assets}`；
`tools/demo/app/{src,build.gradle.kts,README.md,screenshots}`。

环境：Linux、Python 3 / PySide6（`~/.local/opt/edrv32-py/bin/python`）、JDK 17、
Android SDK 35 / build-tools 37.0.0、Gradle 8.14.3；无 RTL/板端改动。

命令与结果：
- `QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests`
  ：145 项 PASS；覆盖假板 UDP、本机假手机 TCP、busy、手柄释放及 GUI 最小化转发。
- 初次 PC 回归缺 LVGL 字体子模块；`git submodule update --init third_party/lvgl` 后重跑。
- `export JAVA_HOME=$HOME/.local/opt/android/jdk17 ANDROID_HOME=$HOME/.local/opt/android/sdk`
- `flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon --max-workers=1 testDebugUnitTest`
  ：13 项 PASS（包括 Paparazzi、JSON、双端口独立及错误后重新接入）。
- 同一 Gradle 入口 `testDebugUnitTest --tests cn.edrv32.demo.LiveDemoTest assembleDebug`
  ：PASS，APK assembleDebug 成功；中继测试 2 项 PASS。
- `$ANDROID_HOME/build-tools/37.0.0/aapt dump permissions build/demo-app/edrv32-demo.apk`
  ：仅 INTERNET、ACCESS_NETWORK_STATE 两项系统权限；既有 AndroidX 私有签名权限保留（ask 确认）。
- 最终中继复验同一 Gradle 入口 `testDebugUnitTest --tests cn.edrv32.demo.LiveDemoTest`：2 项 PASS。
- `git diff --check`：PASS；本次不涉及 RTL，Verilator 不适用。
- 原始日志：`build/live-debug-tests.log`、`build/demo-app/live-tests.log`、`build/demo-app/live-build.log`。

截图（PC 为模拟状态，不是实板测量）：
- `tools/debug_tool/assets/live-demo-1366x768.png`（1366×768）。
- `tools/debug_tool/assets/live-demo-1920x1080.png`（1920×1080）。
- 复现：`QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python tools/debug_tool/render_shot.py <图路径> --main-page 7 --state vision --width <宽> --height <高>`。
- Paparazzi：`tools/demo/app/screenshots/phone-live-demo.png`、`phone-live-nes-gamepad.png`。
- APK 产物：`build/demo-app/edrv32-demo.apk`；截图原始输出在 `outputs/demo-app/`。

现场连线步骤：
1. 手机开启热点，APK 选择“手机遥控端”；平板和 PC 加入该热点。
2. 平板 APK 选择“平板显示端”；手机顶部显示热点地址。
3. PC 有线网卡设为 192.168.1.2/24，连开发板 192.168.1.10，工具建立网口连接。
4. 工具“演示”页填写手机热点地址并点“连接手机”，确认 PC/板端状态。
5. 从手机选场景、切档位；PC 可最小化；场景 10 用 NES 手柄，确认进入、返回退出。
6. 实板现场联调尚未执行；协议与后台行为由本机假板和假手机验证。

## T-LIVE-REMOTE-2 布局返工（2026-11-20）
- 基线：8868d558b；仅手机端布局、位图组合测试、README 和截图调整。
- 场景改为五章分组网格，十项完整展示，短章名/场景名分行，当前场景高亮。
- NES 默认收起场景列表；点“场景 10/10 · NES 经典游戏 ▾”展开网格。
- 手柄主体：左十字、右 112dp A/B 圆键、中间 Select/Start，确认/返回独立。
- 最小触控区域 72dp；按下反色高亮；多点组合与独立松开共用生产位图函数。
- 命令：`JAVA_HOME=$HOME/.local/opt/android/jdk17 ANDROID_HOME=$HOME/.local/opt/android/sdk flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon --max-workers=1 testDebugUnitTest assembleDebug`。
- 结果：14 项测试全部 PASS、assembleDebug 成功；右+A（bit3|bit4）、右+A+B 和独立释放通过。
- 截图自查：十项文字完整且无重叠；十字键/中部功能键/右侧大圆键布局符合要求。
- 两张 Paparazzi 截图更新于 `tools/demo/app/screenshots/phone-live-{demo,nes-gamepad}.png`。
- 日志：`build/demo-app/live-layout-tests.log`；APK：`build/demo-app/edrv32-demo.apk`。

## T-LIVE-REMOTE-3 矮屏手机排布（2026-11-20）
- 基线 e11aa57c7；本节随修复提交，工具链沿用上述 JDK17 / SDK35 / Gradle8.14.3 / Paparazzi1.3.5。
- 手机顶部 40dp 状态条；选角色后默认收起，设置可切换；第一热点常显，其他地址随角色栏展开。
- 场景五列十项，按钮高 48dp、仅序号与场景名；状态与上一/下一/四档共两行。
- NES 主体 192dp，方向键 64dp、确认/返回 56dp、Select/Start 64dp、A/B 96dp。
- 截图自查：907×420dp 下十项完整，展开设置仍完整，手柄完整，文字均无重叠或截断；1280×720 亦正常。
- 证据：`tools/demo/app/screenshots/phone-compact-{grid,settings,nes}.png`、`phone-live-demo.png`（大屏）。
- 环境：`JAVA_HOME=$HOME/.local/opt/android/jdk17 ANDROID_HOME=$HOME/.local/opt/android/sdk`。
- 命令：`flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon --max-workers=1 testDebugUnitTest`；15 项 PASS。
- 同一入口 `assembleDebug` 成功；素材复制自 `b3-int/build/demo-app/assets`；APK 内 assets/ 实测 215 项。
- `aapt dump badging build/demo-app/edrv32-demo.apk`：versionCode 5、versionName 1.4；APK 71,388,182 B。
- 日志：`build/demo-app/compact-{tests,build}.log`；APK：`build/demo-app/edrv32-demo.apk`；`git diff --check` PASS，未改 RTL。
