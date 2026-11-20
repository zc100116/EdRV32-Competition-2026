# 平板原生演示 APK（2026-11-17）

原生 Kotlin / Compose Material 3、Media3，本地素材、横屏沉浸常亮，minSdk 24 / targetSdk 37，debug 签名，versionCode 1。
APK：68,258,719 B（65.10 MiB），`build/demo-app/edrv32-demo.apk`；aapt 仅列自身签名权限，无网络权限。
压缩组成：视频 28.65 MiB、展示图与海报 20.68 MiB、农场 4.00 MiB、代码资源约 11.46 MiB；4 个 JVM 测试通过。
素材：9 段视频、73 张展示图片、原创农场背景与透明角色；完整逐项来源与许可在 APK 来源页及 catalog.json。

| 场景 | 素材与许可 | 主机验证 |
|---|---|---|
| 农场 | imagegen 原创背景、牛/马/羊/鸡/成人角色；2 牛 1 马 3 羊 3 鸡 | 静止计数 18/20（90%）；人在场 10/11（90.9%）；无人无误报 35/35；无额外类别 45/46（97.8%） |
| 车流 | 用户 2 段；Mixkit 2 段（Free License） | 用户 20/20、18/20；Mixkit 各 20/20 |
| 舞蹈 | 用户 2 段；Mixkit 2 段（Free License） | 用户 20/20、4/20；Mixkit 各 20/20 |
| 检测图集 | COCO 24 张 CC BY 2.0 / CC BY-SA 2.0；imagegen 动物园 6 张 | 大目标召回 53/56（94.64%），逐图 ≥80%，逐图误检最多 1；原创 6/6 |
| 手势 | HaGRID 26 张（官方署名及保留条件许可）；imagegen 13 张 | HaGRID 26/26，原创 13/13；未去掉手势 |
| 工地 | Mixkit 1 段（Free License） | 19/20（95%），戴帽与未戴帽均出现 |
| 人脸 | imagegen 虚构成人 4 张，1/1/2/3 人 | 4/4 |

COCO 已筛许可 id 4/5/7/8，最终入选仅 4/5，覆盖 50 类；来源逐图列出 Flickr 页。HaGRID 官方许可允许条件再分发，许可全文随包附带，未用 WIDER FACE。
用户视频仅按用户提供注明演示来源，全部保留：车流1 20–40 s、车流2 70–90 s、跳舞1 16–36 s、跳舞2 24–44 s。
群舞按 6 人逐人检出且每人 ≥12 个点置信度 >0.5 评估，遮挡导致 4/20；该素材按任务要求保留，未放宽标准。
用户片段均为 1280×720 H.264 Main、静音，原水印与字幕保留；Mixkit 和旧 imagegen 素材不变，沿用 T-DEMO-KIT 已通过结果。
拍屏退化沿用旧验证的透视、模糊、亮度和固定噪声；同一 INT8 模型、置信度 >0.25、同类 NMS IoU >0.45。
JVM Paparazzi 调用实际 Compose/Canvas；视频页截图以该视频实际首帧代替硬件播放器，视频本身用源文件验证；未运行模拟器。
截图、6 个农场关键时刻、验证联系表和 APK：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/demo-app/`。
旧 farm-sim 和只服务 HTML 的 kit 页面/构建文件已删除；media、clips.json、fetch.py、validate.py 保留。

## 复现

工具链安装见 `docs/guides/env-setup.md`；完整环境和逐阶段命令见 `tools/demo/app/README.md`。
`select_data.py` → `validate.py data` → `kit/fetch.py` → `prepare_assets.py` → `gradlew --no-daemon testDebugUnitTest` → `validate.py user farm` → `gradlew --no-daemon assembleDebug`。
所有 Gradle、ffmpeg、模型命令由 `flock /tmp/edrv32-sw-build.lock` 串行；Gradle -Xmx1536m、Kotlin in-process。
`$ANDROID_HOME/build-tools/37.0.0/aapt dump permissions build/demo-app/edrv32-demo.apk` 检查权限。

## 农场识别问题

- 现象：早期角色比例失真、走路切帧后牛马误识别，前景镜像牛还会产生狗类别重复框。
- 根因：按各帧联合透明外框缩放，留白使身体比例不一致；独立生成的动作帧外形不同，镜像朝向也影响量化模型。
- 修复：逐帧裁去透明留白后按共同脚底对齐；替换马/人物/前景牛/鸡原图；连续网格驱动腿、尾和头，羊采食，母鸡原地轻动头尾并增大呈现尺寸。
- 回归：静止 18/20、人在场 10/11、无人 35/35、无额外类别 45/46；模型、阈值及拍屏退化未改动。

## 工地场景

- 实现 commit `a8e98ea03`；versionCode 2 / versionName 1.1；工地第一项为六工人互动场景，原 Mixkit 视频保留第二项。
- Paparazzi：复位 20 s、剧本 0–24 s 每秒共 45 帧；静止四戴两未戴 19/20（95%），未戴警示 11/11（100%），全员戴帽零未戴 14/14（100%）。
- 沿用 v2 板端 INT8 快照、原拍屏退化、conf>0.25 / NMS IoU>0.45；横臂遮额曾误认帽子，改为擦鬓角并露出完整头发；不改模型和阈值。
- JDK 17 / Gradle 8.14.3 / Paparazzi 1.3.5；`testDebugUnitTest` 全套 7/7，通过后红衣访客版工地/首页重跑 4/4；`validate.py site` 和 `assembleDebug` 通过，均使用指定 flock / --no-daemon。
- APK：71,322,578 B（68.02 MiB），小于 95 MB；构建日志 `build/demo-app/site-apk-build.log`，验证日志与逐帧结果 `build/demo-app/site-final-validation.log`、`site-results.json`。
- 首页、五个剧本时刻、复位图、验证联系表、逐帧结果及新 APK 已覆盖到 `/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/demo-app/`；美术与复现命令见 `tools/demo/app/README.md`。

## 手机遥控

- 实现 commit `af1081dba`（基线 `165293bf6`）；versionCode 3 / versionName 1.2；经协调者同意 targetSdk 36，只新增 INTERNET / ACCESS_NETWORK_STATE。
- 同 APK 记住角色；手机热点 TCP 47632，平板取 Wi-Fi 默认网关并每秒重连；平板权威状态、完整 JSON 快照与同一 FarmModel / SiteModel 保持一致，手机拖动合并至 ≤30 Hz，视频仅显示封面。
- JDK 17 / Gradle 8.14.3 / Paparazzi 1.3.5；`flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon testDebugUnitTest assembleDebug` 成功，10/10（含 2 项遥控测试、4 项 Paparazzi）。
- 真实 localhost TCP 验证指定操作序列、逐字段快照及同一时刻模型帧相同、断线重连恢复、协议解析失败断开并报错；日志 `build/demo-app/phone-validation.log`，XML 在 `build/demo-app/gradle/test-results/testDebugUnitTest/`。
- APK 71,495,504 B（68.18 MiB，<95 MB）；`aapt dump permissions` 对比旧包仅新增指定两项，结果 `build/demo-app/phone-permissions.txt`。
- 六张截图及覆盖的新 `edrv32-demo.apk`：`/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/demo-app/`；截图为 `phone-role-home.png`、`phone-remote-{farm,helmet,traffic}.png`、`phone-disconnected.png`、`tablet-remote-indicator.png`。
