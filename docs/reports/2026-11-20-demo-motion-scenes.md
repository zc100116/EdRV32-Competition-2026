# 平板运动场景与 APK 1.6

- 日期：2026-11-20；基线 c4fbb49a7；实现为本报告所在提交。
- 按最新交付顺序：工地/农场 → 镜像修复 → 手机单页 → PC 默认地址 → APK 1.6。
- 1.6 不含动态街景：首页移除该项，场景 1 仍跟随马路车流；街景另行交付 1.7。
- Python 3.12.3、Gradle 8.14.3、AGP 8.13.2、Paparazzi 1.3.5、JDK 17。
- 1280×720 JVM 实际 Canvas；沿用板端 INT8、原透视/模糊/亮度/种子 17 噪声和阈值。
- 真值扣除裁屏和前景遮挡，露出 ≥70%；低露出目标按完整轮廓框同类 IoU≥0.5 忽略。

| 场景 | 已取得数字 | 状态 |
|---|---|---|
| 工地 | 运动盘点 20/20、告警 11/11、解除 14/14；忽略 0 | 通过，43.02 s |
| 农场 | 最新前景路线待本轮确认；上轮盘点 18/20、人员 10/10、无人 36/36 | 重验中 |

- 工人持续游走；修正白发工人易被当作戴帽的素材，摘戴和访客脚本时间不变。
- 动物持续运动、鸡也移动；人员前景路线不改事件和告警时序。
- 原始数据：build/demo-app/{site,farm}-{frames,results}.json 与 *-validation.log。
- 联系表 outputs/demo-app/{site,farm}-contact.png 不入库。
- JVM 证据：site-{hat-off,visitor-entered}.png、farm-{missing,intruder}.png。
- 所有重任务用 flock /tmp/edrv32-sw-build.lock、OPENBLAS_NUM_THREADS=1 串行执行。
- 本轮完整 JVM 测试通过（133.50 s）；镜像边界值回归通过（89.20 s）。
- 既有 assets 从指定 b3-int/build/demo-app/assets 复制；仅新生成 art 入库。
- 最终 APK 路径、assets 数量和 L13 回归结果在发布构建完成后补记。
