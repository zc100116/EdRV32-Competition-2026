# 视界 · Android 演示 APK

原生 Kotlin / Jetpack Compose Material 3，Media3 播放本地视频；不使用 WebView，仅申请 INTERNET 和 ACCESS_NETWORK_STATE 用于局域网 TCP，不访问外网。横屏、沉浸式全屏、常亮，minSdk 24，首次交付 versionCode 1，后续交付递增。

安装 `build/demo-app/edrv32-demo.apk`，选择首页场景。平板横放，占开发板摄像头画面宽度约 65%，再对焦。点画面显示控制栏，3 秒后隐藏；左右滑动或按前后按钮切换，视频循环，图片播放时每 5 秒切换。来源页逐项列出原作者或来源、许可和地址，地址不会触发网络访问。

| 场景 | 板端应用 | 内容与现场操作 |
|---|---|---|
| 智慧农场 | 智慧农场 | 一整块监控牧场，2 牛、1 马、3 羊、3 鸡；盘点后按“演示”观察走失与人闯入，也可拖动物或按“闯入” |
| 马路车流 | 目标检测计数 | 用户 2 段与 Mixkit 2 段，观察车辆框及分类计数 |
| 舞蹈 | 人体姿态 | 用户 2 段与 Mixkit 2 段，观察全身关键点 |
| 检测图集 | 目标检测计数 | 24 张 COCO 图像和 6 张原创动物园照片 |
| 手势 | 手势识别 | HaGRID 每类 2 张，共 26 张，另有原创 13 张；暂停等待板端稳定 |
| 工地 | 安全帽检测 | 互动工地，复位四戴两未戴；点人摘戴、拖动与剧本演示，Mixkit 视频保留为第二项 |
| 人脸 | 人脸贴纸 | 4 张原创虚构成人照片，分别 1、1、2、3 人 |

农场脚本：0–5 秒静止盘点，5–7 秒羊走出，7–11 秒走失等待，11–13 秒羊归来，13–16 秒人翻越围栏走进，16–21 秒停留，21–24 秒离开。画外动物停留；从它离开的对应画面边缘往里拖可带回，或按“复位”。云影、草木、角色动作、时间戳和噪点完全由时间决定，不使用随机数；拖动坐标也可独立重放。FarmModel.kt 和 FarmCanvas.kt 为运行与 JVM 截图共用的状态及绘制实现。

## 手机遥控

1. 手机先打开热点，平板连到这个热点；两台设备安装同一份 APK。
2. 两边打开 APK，在首页分别选择「手机遥控端」和「平板显示端」；会记住上次角色。
3. 手机出现「已连接平板」后选择场景，直接拖动物、点工人，或用下方按钮操作。
4. 手机监听 TCP **47632**，平板自动连接当前 Wi-Fi 默认网关；断线后每秒重连。
5. 视频在手机上显示当前条目的封面，图片显示当前图片；暂停/播放控制平板。
6. 手机顶部显示热点 IP 和端口；平板连接标记在控制栏内，随控制栏 3 秒隐藏。
7. 连不上先确认手机热点已开、平板确实连到该热点、角色各选一个，并检查热点的设备隔离设置。
8. 连接或协议错误会显示原因；保持两边 APK 在前台，连接恢复后自动取得平板完整状态。
9. targetSdk 设为 36；[Android 17 对 target≥37 要求本地网络运行时权限](https://developer.android.com/privacy-and-security/local-network-permission)，本 APK 保持只新增上述两项权限。

## 工具链与构建

安装见 `docs/guides/env-setup.md` Android 一节。JDK 17、Gradle wrapper 8.14.3、AGP 8.13.2、Kotlin 2.0.21、Compose BOM 2024.11.00、Media3 1.5.1、Paparazzi 1.3.5。compileSdk 35 用于 JDK 17 的 JVM 渲染兼容，targetSdk 36 允许仅用 INTERNET 进行局域网连接；测试编译启用 java.desktop 导出图像，不进入 APK。

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

prepare_assets.py 可指定 art、video、catalog 阶段，validate.py 可指定 data、user、farm、site 阶段。ffmpeg、模型、Gradle 与软件构建共用指定锁。Gradle 单 worker、-Xmx1536m、Kotlin in-process、--no-daemon，不运行模拟器。

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

## 互动工地（R5-14/15）

工地第一项为 CAM-05 施工区，第二项保留原 Mixkit 视频。六名工人复位为四戴帽、两未戴；点工人摘戴帽，长按拖动。点空地显示控制栏，含前后切换、演示、复位和暂停。演示：0–5 s 全员戴帽静止；5 s 摘帽，6.4–10 s 擦汗并拿帽；10 s 戴回；14–16 s 未戴帽访客进入，16–21 s 停留，21–23 s 离开。环境尘土、塔吊投影、搬运步态、铲土和敲打按时间确定，SiteModel.kt / SiteCanvas.kt 为运行与截图共用实现。

`prepare_assets.py site` 切分原创两张 3×2 角色图集，每人两种状态按共同脚底和相同外框对齐，另备擦汗动作和摘下的帽子。`prepare_assets.py catalog` 将工地插为第一项并更新缩略图。新增素材保存在 `art/site/`，不修改原农场素材。

```sh
$P tools/demo/app/prepare_assets.py site
flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon testDebugUnitTest
flock /tmp/edrv32-sw-build.lock $P tools/demo/app/validate.py site
flock /tmp/edrv32-sw-build.lock tools/demo/app/gradlew -p tools/demo/app --no-daemon assembleDebug
```

Paparazzi 导出 `build/demo-app/site-frames/`，含复位连续 20 s 和剧本 0–24 s 每秒截图；标签在 `site-frames.json`，仅把进入画面的访客头部计为可见。安全帽 INT8 拍屏验证复用原模型、原退化和原阈值，`site-results.json` 保存每帧计数、框和得分，`outputs/demo-app/site-contact.png` 为联系表。验收分别要求复位四戴两未戴、警示阶段至少一未戴、解除阶段零未戴，三个比例均 ≥90%。本次 versionCode 2 / versionName 1.1。

### 工地美术提示词（内置 imagegen）

背景：Use case: photorealistic-natural. Asset: landscape 16:9 CCTV construction site background for compositing six workers later. Fixed security camera elevated 35 degrees looking diagonally downward, no horizon. Realistic Chinese building construction yard in soft daylight. Broad empty dusty compacted earth central working area occupies central 85 percent. Around outer perimeter: scaffold with unfinished concrete columns at upper left, stacked red bricks and rebar upper right, small cement mixer at right edge, corrugated perimeter fence along far edge. Mud tracks, scattered modest gravel, realistic fine earth texture. Keep all central ground clear for large worker cutouts. No people, no helmets on ground, no vehicles, no lettering, no logo, no timestamp or watermarks. Sharp natural photographic textures and coherent perspective.

人物：Use case: photorealistic-natural. Asset: six different construction worker cutouts on actual transparent background, exact 3 columns by 2 rows of equal cells with wide empty gutters. One full body worker in each cell, all feet and head visible, no overlap. Camera elevated 30 degrees looking down, three-quarter front view, heads clearly visible, faces and top of heads large. SAME soft daylight as overcast construction site. ALL SIX WITHOUT ANY HAT OR HELMET, visible natural hair and bare heads. Each wears construction reflective safety vest and work boots. Top left: stocky middle aged Asian man orange vest gray workwear standing hands relaxed. Top center: tall dark skinned man lime vest blue trousers carrying a small brick at waist. Top right: older Asian man orange vest beige clothes holding shovel at waist. Bottom left: woman dark hair tied back lime vest navy workwear holding small hammer low at side. Bottom center: younger Asian man orange vest dark blue clothes standing arms at side. Bottom right: light skinned gray haired male visitor lime vest light shirt dark trousers hands relaxed. Detailed realistic photographic people, accurate anatomy, natural proportions, front three quarter faces easy to see. Every cell equal scale, full figure centered, ample transparent margin, same baseline. No hats, no helmets, no headwear, no ground, no shadows, no scene, no text, no watermark, no cut off limbs.

人物透明边缘编辑：Edit target: these exact six construction worker photographs. Background extraction: remove ALL background pixels completely to actual alpha transparency including dark gray backdrop, halos, and all ground shadows. Keep all six workers, their size, position, clothing, tools, faces, hair, limbs and poses pixel-identical. Preserve exact 3 columns by 2 rows arrangement. Do not change or add any objects. Absolutely transparent empty space everywhere outside the six people. NO dark matte, NO gray backdrop, NO colored backdrop. Output isolated worker sprites on transparent alpha.

戴帽编辑：Edit target: exact six construction worker sprite sheet. Change ONLY the heads: fit a realistic construction HARD HAT snugly onto every person's head, covering all top hair. Top row helmets yellow, white, blue respectively. Bottom row helmets white, yellow, orange respectively. Strong real industrial rigid plastic dome and wide protective brim, realistic shadows on forehead, correct elevated perspective. Keep ALL SIX people bodies, clothing, tools, faces, feet, poses, positions and scale EXACTLY as reference. Same 3 columns by 2 rows. Full bodies. Preserve fully transparent background and remove all background matte and shadows. Output actual alpha transparent cutouts. No other changes or objects, no text.

擦汗编辑：Use the TOP LEFT man only as identity reference. Generate ONE isolated full-body photograph of exactly this stocky middle aged Asian construction worker with short black hair, orange reflective vest over gray work clothes and boots. Same elevated 30 degree camera, same body size/proportions, same face, same outfit, same three-quarter front stance. He is wiping sweat from his forehead with his RIGHT forearm raised across the brow while his LEFT hand holds his removed yellow hard hat low beside his hip. Bare head visible above forearm. All full body including feet, hard hat and elbows in frame. True alpha transparent background outside person. No ground, no shadow, no other people, no scene, no text.

擦汗识别调整：Precise object edit of this same worker photograph. Change ONLY his raised right arm: move his elbow downward and to his right side, bend arm so his right fingertips wipe sweat at the SIDE of his right cheek/temple, BELOW his hairline, beside his ear. Entire top of head, forehead, black hair, and both eyebrows must be fully visible and entirely unobstructed. His hand must NOT touch or cover his forehead or top of head. No arm or fingers across brow or above his head. Keep exactly the same man, face, hairstyle, orange reflective vest, gray clothes, boots, same left hand holding yellow helmet low by left hip. Same elevated camera, same body proportions, pose and full body framing. True fully transparent alpha background; no scene, no ground, no shadow, no text.

新工作树复用已交付 APK 素材和板端量化快照时，以下命令恢复既有输入，之后执行上述 `site`、`catalog` 更新及验证流程（不重新标定）：

```sh
$P - <<'PY'
from pathlib import Path
from zipfile import ZipFile
with ZipFile('/home/workspace/orca/workspaces/EdRV32-Competition-2026/SOC系统设计/outputs/demo-app/edrv32-demo.apk') as apk:
    for name in apk.namelist():
        if name.startswith('assets/'):
            path = Path('build/demo-app') / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(apk.read(name))
PY
flock /tmp/edrv32-sw-build.lock $P - <<'PY'
from pathlib import Path
import shutil
from compile_yolo import read_model_hex
from format import BASES
cache = Path('build/npu/quantized_helmet')
cache.mkdir(parents=True, exist_ok=True)
source = Path('sw/apps/showcase/models/helmet')
(cache / 'model.bin').write_bytes(read_model_hex(source / 'mem_model.hex', BASES['MODEL_BASE']))
shutil.copy2(source / 'quantization.json', cache / 'quantization.json')
PY
```

若已有完整素材则按正常 `prepare_assets.py` 流程打包；复用包时，在 `prepare_assets.py site` 后更新已恢复的 catalog：

```sh
$P - <<'PY'
import json
import sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, 'tools/demo/app')
from prepare_assets import site_catalog
path = Path('build/demo-app/assets/catalog.json')
catalog = json.loads(path.read_text())
site_catalog(catalog['scenes'])
path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2))
Image.open('build/demo-app/assets/site/poster.jpg').resize((480, 270)).save(
    'build/demo-app/assets/thumbnails/helmet.jpg', quality=85)
PY
```

访客：Use case: photorealistic-natural. ONE full body isolated male construction-site visitor, fictional adult Asian man aged 45 wearing a dark red long sleeve polo shirt, tan work trousers and dark work shoes, small clipboard held at waist. NO HELMET, NO HAT, short black hair clearly visible. Average slender build, distinct moustache, dark rectangular eyeglasses. Elevated 30 degree security camera looking down, three quarter front stance facing slightly to right, both feet and full head visible. Natural overcast daylight, sharp real photography detailed skin and cloth. Generous actual alpha transparent margin around full body. No ground, no shadow, no scene, no other people, no lettering or watermark.
