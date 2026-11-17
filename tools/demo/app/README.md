# 视界 · Android 演示 APK

原生 Kotlin / Jetpack Compose Material 3，Media3 播放本地视频；不使用 WebView，不申请网络权限。横屏、沉浸式全屏、常亮，minSdk 24，首次交付 versionCode 1，后续交付递增。

安装 `build/demo-app/edrv32-demo.apk`，选择首页场景。平板横放，占开发板摄像头画面宽度约 65%，再对焦。点画面显示控制栏，3 秒后隐藏；左右滑动或按前后按钮切换，视频循环，图片播放时每 5 秒切换。来源页逐项列出原作者或来源、许可和地址，地址不会触发网络访问。

| 场景 | 板端应用 | 内容与现场操作 |
|---|---|---|
| 智慧农场 | 智慧农场 | 一整块监控牧场，2 牛、1 马、3 羊、3 鸡；盘点后按“演示”观察走失与人闯入，也可拖动物或按“闯入” |
| 马路车流 | 目标检测计数 | 用户 2 段与 Mixkit 2 段，观察车辆框及分类计数 |
| 舞蹈 | 人体姿态 | 用户 2 段与 Mixkit 2 段，观察全身关键点 |
| 检测图集 | 目标检测计数 | 24 张 COCO 图像和 6 张原创动物园照片 |
| 手势 | 手势识别 | HaGRID 每类 2 张，共 26 张，另有原创 13 张；暂停等待板端稳定 |
| 工地 | 安全帽检测 | Mixkit 示范者戴上安全帽的片段，两个类别都出现 |
| 人脸 | 人脸贴纸 | 4 张原创虚构成人照片，分别 1、1、2、3 人 |

农场脚本：0–5 秒静止盘点，5–7 秒羊走出，7–11 秒走失等待，11–13 秒羊归来，13–16 秒人翻越围栏走进，16–21 秒停留，21–24 秒离开。画外动物停留；从它离开的对应画面边缘往里拖可带回，或按“复位”。云影、草木、角色动作、时间戳和噪点完全由时间决定，不使用随机数；拖动坐标也可独立重放。FarmModel.kt 和 FarmCanvas.kt 为运行与 JVM 截图共用的状态及绘制实现。

## 工具链与构建

安装见 `docs/guides/env-setup.md` Android 一节。JDK 17、Gradle wrapper 8.14.3、AGP 8.13.2、Kotlin 2.0.21、Compose BOM 2024.11.00、Media3 1.5.1、Paparazzi 1.3.5。compileSdk 35 用于 JDK 17 的 JVM 渲染兼容，targetSdk 37 使用当前稳定的 Android 行为；测试编译启用 java.desktop 导出图像，不进入 APK。

从仓库根目录执行；用户原始视频位于任务指定的 `b3-int/build/card98/`，只读复制。需要既有 NPU 权重及本机官方图集，不需要账号或 API key。

```sh
export JAVA_HOME=$HOME/.local/opt/android/jdk17
export ANDROID_HOME=$HOME/.local/opt/android/sdk
export PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1
P=$HOME/.local/opt/edrv32-py/bin/python
$P tools/demo/app/select_data.py
flock /tmp/edrv32-sw-build.lock $P tools/demo/app/validate.py data
flock /tmp/edrv32-sw-build.lock $P tools/demo/kit/fetch.py
flock /tmp/edrv32-sw-build.lock $P tools/demo/app/prepare_assets.py
flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon testDebugUnitTest
flock /tmp/edrv32-sw-build.lock $P tools/demo/app/validate.py user farm
flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon assembleDebug
$ANDROID_HOME/build-tools/37.0.0/aapt dump permissions build/demo-app/edrv32-demo.apk
```

prepare_assets.py 可指定 art、video、catalog 阶段，validate.py 可指定 data、user、farm 阶段。ffmpeg、模型、Gradle 与软件构建共用指定锁。Gradle 单 worker、-Xmx1536m、Kotlin in-process、--no-daemon，不运行模拟器。

素材写入 build/demo-app/assets/ 后由 Gradle 打包。用户视频按 user_clips.json 截取，1280×720 H.264 Main、静音、等比留边，不去水印或字幕。旧 Mixkit 与原创照片沿用通过的原素材。牛/马/羊/人物图集按 2×2 分帧，牛2和鸡为单张透明照片；每帧去除透明留白后按共同脚底基线对齐为透明 WebP。视频、数据集图片、APK、中间帧及筛选结果不入库。

## 验证与来源

Paparazzi 在 JVM 调用实际界面及 Canvas，生成首页、七场景、来源页、每秒农场帧、20 秒静止段及翻越动作帧。界面截图为 1280×720，写入 outputs/demo-app/；逐秒帧和标签在 build/demo-app/farm-frames/ 及 farm-frames.json。用户视频每秒取一帧，人工核对单人片段 1 人、群舞片段 6 人。复用既有拍屏透视、模糊、亮度、种子 17 噪声和 INT8 模型，confidence >0.25、NMS IoU >0.45，不调整阈值。

COCO 只筛官方许可 id 4、5、7、8，最终 24 张为 CC BY / CC BY-SA；统计标注面积占图像至少 2% 的目标召回，小目标正确检出不计误检。HaGRID 官方许可允许署名等条件下再分发，全文随 APK 打包：licenses/hagrid.txt；原许可 https://github.com/hukenovs/hagrid/blob/master/license/en_us.pdf 。APK catalog.json 逐张保留来源与许可，并注明图像缩放、留边、JPEG 转码及改动沿用原许可；Mixkit 来源在 ../kit/clips.json，旧原创图提示词在 ../kit/README.md。用户视频仅按原文件标注来源，用于本次现场演示。未使用 WIDER FACE。

## 农场原创生成提示词

内置 imagegen 生成，背景压 JPEG，角色图集保留透明度并压 WebP。牛为荷斯坦和赫里福德两头不同角色；腿、尾和头通过连续网格运动，羊保留低头采食姿态，母鸡原地轻动头尾，人物使用四帧行走和翻越动作。图标为原生 VectorDrawable 摄像机与镜头图形。

### background

Use case: photorealistic-natural. Asset type: Android farm surveillance simulation background, landscape 16:9. A fixed CCTV camera mounted high looks downward at 40 degrees onto ONE entire rectangular enclosed grassy livestock paddock. Real green short pasture filling most of frame, one continuous rustic wooden perimeter fence all around the edges, one open wooden farm gate at far right edge. At far outside corners only: a small plain water trough at upper left, a small leafy tree casting a soft shadow outside the upper right fence, a tiny corner of a simple wooden shed outside upper left edge. The main central 85 percent of the image is uninterrupted short grass, unobstructed and empty, with realistic texture but not cluttered. Natural bright overcast soft daylight, no horizon. Realistic CCTV perspective but sharp clean photograph. Absolutely no animals, no people, no birds, dogs, vehicles, benches, chairs, signs, lettering, logos, watermarks, timestamp or overlays.

### cow

Use case: photorealistic-natural. Asset type: consistent animation sprite sheet on fully transparent background. Square image arranged as an exact 2 by 2 grid of four equal square cells, no grid lines or text. Every cell shows the SAME one adult black-and-white Holstein dairy cow with visible udder, full body, identical size and lighting, seen from a fixed camera elevated 40 degrees looking downward obliquely from the side. Facing right. Entire body including all feet fits well inside each cell, generous transparent margins, common foot baseline. Top left: walking pose, left legs forward and right legs back. Top right: next walking step, right legs forward and left legs back, visibly different leg positions. Bottom left: lowering head to graze or peck the ground. Bottom right: standing at rest with head turned slightly toward the camera and tail swung slightly outward. Anatomically correct realistic original photography, natural soft daylight and detailed fur or feathers or fabric. Exactly four views of this one consistent character, one view per cell, separated by empty transparency. No grass, no ground, no scenery, no shadows, no text, no watermark, no other creatures or people.

### horse

Use case: photorealistic-natural. Square transparent animation sprite sheet, exact 2 by 2 grid of equal square cells without visible lines. Four full-body views of the SAME lean athletic adult thoroughbred HORSE, clearly equine, with long slender legs, a long elegant neck, distinct elongated horse muzzle, pricked ears, flowing black mane and long black tail, rich bay coat. Avoid stocky barrel shape or bovine appearance. Fixed camera looking down at 35 degrees, mostly side profile facing right, same lighting, body proportions and scale in all four cells. Top left: walking left legs forward, right legs back. Top right: walking opposite stride with right legs forward. Bottom left: head lowered to eat grass, all feet standing. Bottom right: standing with head and ears slightly turned toward camera. Every hoof and entire tail must be visible, transparent margin around each view, feet on the same baseline. Genuine natural horse photography, sharp fine fur, anatomically correct. No rider, saddle, harness, other creatures, objects, ground, grass, shadow, text, watermarks, logos or background. Actual transparent background.

### sheep

Use case: photorealistic-natural. Asset type: consistent animation sprite sheet on fully transparent background. Square image arranged as an exact 2 by 2 grid of four equal square cells, no grid lines or text. Every cell shows the SAME one woolly white adult sheep with dark face and dark lower legs, full body, identical size and lighting, seen from a fixed camera elevated 40 degrees looking downward obliquely from the side. Facing right. Entire body including all feet fits well inside each cell, generous transparent margins, common foot baseline. Top left: walking pose, left legs forward and right legs back. Top right: next walking step, right legs forward and left legs back, visibly different leg positions. Bottom left: lowering head to graze or peck the ground. Bottom right: standing at rest with head turned slightly toward the camera and tail swung slightly outward. Anatomically correct realistic original photography, natural soft daylight and detailed fur or feathers or fabric. Exactly four views of this one consistent character, one view per cell, separated by empty transparency. No grass, no ground, no scenery, no shadows, no text, no watermark, no other creatures or people.

### chicken

Edit this original photographic hen cutout into a clean realistic surveillance farm character. Keep the same healthy adult reddish brown domestic hen, bright red comb and wattle, short pointed yellow beak, two distinct yellow legs and toes, unmistakable bird silhouette. Camera elevated 35 degrees looking down, mostly broadside facing right. Full body including tail, both feet and beak, fills about 90 percent of a landscape image. Bright even natural light and sharp feather texture. Clean actual transparent background, remove all residual stray halo speckles around legs and feathers. Only one hen, no ground, no shadow, no grass, no other creatures, text or objects.

### person

Use case: photorealistic-natural. Square transparent animation sprite sheet in exact 2 by 2 equal square cells, no lines. SAME fictional adult man throughout, normal healthy human proportions, average muscular build, wearing a bright red plain short-sleeve t-shirt, navy blue jeans and dark work shoes. Full body clearly visible including head and both feet in every cell. Camera elevated 35 degrees looking down. THREE-QUARTER FRONT view: body walks toward the right but chest and both shoulders face diagonally toward the camera, NOT thin side profile. Natural balanced lighting, sharply detailed real skin and fabric. Four poses at identical scale and common foot baseline: top left walking with left leg forward and arms naturally swinging; top right opposite walking stride with right leg forward; bottom left stepping over an invisible low fence, one knee raised high and arms forward balancing; bottom right standing upright facing three-quarter toward camera. Exactly one full person per cell with generous transparent margins. No hat, helmet, tools, badges, graphics, accessories, ground, scenery, shadows, text, logos, watermarks or other people. Actual fully transparent background.

### cow2

参考旧农场 imagegen 原创赫里福德牛（4f710df4b 中的 cow2），视角与透明边缘编辑提示词：

Edit this original photographic cow cutout into a clean realistic surveillance farm character. Keep exactly the same adult reddish brown Hereford dairy cow, white face, broad unmistakably bovine pink muzzle, visible udder and short horns. Preserve the broad side-on body and sharply recognizable cow silhouette, all four legs, full long tail. Change viewpoint to a fixed camera elevated 35 degrees looking down, still broadside, facing right, head turned slightly toward camera. Bright even natural daylight, detailed realistic fur, correct anatomy. The entire cow fills about 90 percent of the rectangular landscape image with a modest transparent margin around every hoof and tail. Remove all stray white halos and any background debris; output ONLY the single cow on true fully transparent background. No ground, shadows, grass, other creatures, text or objects.

Remove the entire background from this exact photographic cow. Preserve the cow, fur, head, udder, tail, legs and hooves exactly as shown, without changing its pose, appearance, lighting or proportions. Output the isolated full cow with an ACTUAL ALPHA TRANSPARENT background: every pixel that is not the cow must be transparent, including all space between its legs, around the tail and under its belly. No colored background, gradient, blur, floor or shadow. Do not crop any part of the cow. This is a transparent cutout for compositing over grass.
