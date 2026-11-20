# 平板动态场景与 APK 1.6

- 日期：2026-11-20；基线 c4fbb49a7，街景实现为本报告所在提交。
- 已提交：运动 bb5ee9f79、边界值 9d1d670ca、单页 ab1f9bdfa、默认地址 9bc2939f6。
- 统一交付 1.6 / versionCode 7，场景 1 跟随动态街景，仍可手选车流/检测图集。
- APK：build/demo-app/edrv32-demo.apk，259 个 assets 文件，77,298,595 B；未新增权限。
- 工具：Python 3.12.3、JDK 17、Gradle 8.14.3、AGP 8.13.2、Paparazzi 1.3.5。
- 条件：1280×720 实际 JVM Canvas，原板端 INT8、透视/模糊/亮度/种子17噪声及阈值。
- 真值按 alpha 扣除裁屏/前景遮挡，露出≥70%；骑手另计 person。
- 忽略目标：原始完整轮廓框裁到屏内，同类投影框 IoU≥0.5；原始检测完整保存。

| 场景 | 最终验收数字 | 结果 / 耗时 |
|---|---|---|
| 街景 | 完全正确 24/40=60%；域外类别 0/40 | **未达 85%**；38.43 s |
| 工地 | 运动盘点 20/20；告警 11/11；解除 14/14 | 通过；38.34 s |
| 农场 | 盘点 18/20；人员 11/11；无人 35/35；限定类别 44/46 | 通过；45.33 s |

- 忽略检测：街景 20、工地 0、农场 0。
- 街景逐类正确帧/40：人34、自行车38、车37、摩托36、公交40、卡车39、灯40、牌39、狗39、盆栽36。
- 街景主要漏计：人7、摩托4、盆栽4；多计：轿车3、卡车1、自行车1（40帧合计）。
- 农场主要多计：羊6、马5、狗2；牛/羊/鸟各漏1（46帧合计）；不改变原验收标准。
- 工地未出现影响三组验收的漏检/误检；白发工人素材已改为清晰深色裸头。
- 街景尝试15类后依授权保留10类：原7类加盆栽、红绿灯、停车牌。
- 移除猫（常报狗）、飞鸟/雨伞/背包（漏检）、长椅（漏检及报椅子）；源图集提示词见 README。
- 街景累计多轮调优仍未达标，按协调者限时保留最佳版交付决定收尾；模型和阈值未改变。
- 工人/动物持续运动；前5秒照常盘点；摘戴、走失/归来/闯入时间及告警逻辑不变。
- 人员改走前景，避免被动物持续遮挡；场景全部由时间决定，运行和截图共用 Model/Canvas。
- 手机为场景选择/四快捷档、三列44dp镜像、固定导航/NES；907×420下12项无需滚动。
- −1/越界选项显示“未选”，min≥max显示只读；PC 地址实际默认192.168.43.1，可修改。
- JVM 21项零失败/错误；PC 11项通过（6.91 s）；Git diff 空白检查通过。

从仓库根目录运行，重任务均串行共用 flock、单 worker 和 OPENBLAS_NUM_THREADS=1：
```sh
export JAVA_HOME=$HOME/.local/opt/android/jdk17 ANDROID_HOME=$HOME/.local/opt/android/sdk
export PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1
P=$HOME/.local/opt/edrv32-py/bin/python
flock /tmp/edrv32-sw-build.lock $P tools/demo/app/prepare_assets.py site street motion-catalog
flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon --max-workers=1 testDebugUnitTest assembleDebug
# JVM 测试与 APK 构建合计 157.32 s，final-gradle.log 显示 BUILD SUCCESSFUL。
flock /tmp/edrv32-sw-build.lock $P tools/demo/app/validate.py farm
flock /tmp/edrv32-sw-build.lock $P tools/demo/app/validate.py site
flock /tmp/edrv32-sw-build.lock $P tools/demo/app/validate.py street
flock /tmp/edrv32-sw-build.lock env QT_QPA_PLATFORM=offscreen PYTHONPATH=.:tools/debug_tool:tools/debug_tool/tests $P -m unittest test_ui_mirror test_live_demo
```
- 原始帧/标签/框/分数：build/demo-app/{street,site,farm}-{frames,results}.json 及对应帧目录。
- 最终日志：build/demo-app/final-{gradle,farm-validation,site-validation,street-validation}.log、pc-release-test.log。
- 联系表：outputs/demo-app/{street,site,farm}-contact.png，不入库。
- 场景截图：street-{4,17,31}.png、site-{hat-off,visitor-entered}.png、farm-{missing,intruder}.png。
- 手机证据：tools/demo/app/screenshots/phone-single-{engine,recognition,nes}.png。
- 已按要求复制 b3-int/build/demo-app/assets；用户/已有素材不入库，仅新增原创 art 和界面证据入库。

## T-STREET-2：APK 1.7

- 基线 0c42b5b43；实现为本追加节所在提交；从 24/40（10类）提高到 **38/40（8类，95%）**，域外 **1/40**、忽略 1，达标。
- 移除仍不稳定的摩托车和盆栽；复用原创 art，无新增素材；模型/阈值、工地/农场/手机界面未改。
- 1秒入/出画、屏内100坐标边距、错峰骑行与行人/狗间距调整；残余第18/19秒自行车漏检，第18秒漏灯并误报网球拍。
- `flock /tmp/edrv32-sw-build.lock $P tools/demo/app/validate.py street`：通过，36.45 s；退化、真值与忽略规则沿用1.6。
- `flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon --max-workers=1 testDebugUnitTest assembleDebug`：通过，106.26 s，22项零失败/错误。
- APK `build/demo-app/edrv32-demo.apk`：versionCode 8 / versionName 1.7，**256 assets**，76,401,149 B；两条命令均沿用上文工具链和 OPENBLAS_NUM_THREADS=1。
- 数据/日志 `build/demo-app/street2/{results.json,iteration2-validation.log,final-gradle.log}`；逐秒帧和联系表沿用上文路径。
