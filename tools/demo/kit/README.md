# 平板 AI 演示素材包

将 `demo-kit.html` 复制到手机或平板，离线浏览器打开。首页选择七个场景；竖屏自动顺时针旋转 90°，建议横屏观看。支持全屏时场景控制栏显示“全屏”。浏览器的自动播放策略要求通过点击卡片进入视频，视频静音并在页面内循环播放。

底部“返回 / 上一个 / 下一个 / 暂停或播放”控制素材；图片播放时每 5 秒切换，也可沿舞台左右滑动。来源地址仅作为文字显示，不会访问外网。只在进入场景时将当前媒体解码为 Blob URL，切换或返回会释放，首页使用单独的小缩略图。农场 iframe 的 srcdoc 直接来自未修改的 `../farm-sim/farm-sim.html`；农场控制行为保留，左下添加包级返回按钮。

## 现场话术

平板横放，让其占摄像头画面宽度约 65%，对焦清晰后保持固定；可从 30–50 cm 调整，以取景比例为准。素材标注在图像区域下方，取景时保留整个素材区域。

| 场景 | 开发板应用 | 现场演示 |
|---|---|---|
| 智慧农场 | 智慧农场 | 按原农场说明对齐栏位，先盘点，再用剧本或拖动演示走失和串栏 |
| 马路车流 | 目标检测计数 | 观察车辆经过、检测框跟随及车辆分类计数 |
| 动物园 | 目标检测计数 | 先看单只动物，再切换混合场景对照每类数量 |
| 舞蹈 | 人体姿态 | 观察身体关键点随舞步变化；竖幅原片保留全身并留黑边 |
| 手势 | 手势识别 | 暂停在一张图，待板端稳定后依次切换；13 类对应板端手势名称 |
| 工地 | 安全帽检测 | 观察示范者从未戴帽到戴上安全帽，展示两个检测类别；素材为正面职业演示 |
| 人脸 | 人脸贴纸 | 从单人切到双人、三人合影，观察每张脸对应的贴纸 |

## 素材与许可

图片为内置 imagegen 新生成的虚构人物或写实动物，不使用任何数据集图像。`media/` 仅提交压缩 JPEG；原始 PNG 留在生成工具目录中，不入库。首页农场缩略图来自原农场网页截图。
视频取自 Mixkit Stock Video Free License，逐项作者、来源、公开文件 URL、截取起点、时长及慢放倍率见 `clips.json`；同样信息内嵌到来源页。排除标注 Restricted License 的素材；脚本使用 `User-Agent: demo-media-fetch/1.0`，不伪装浏览器、不带项目或个人信息。
视频统一 1280×720、H.264 Main、yuv420p、25 fps、静音、faststart，尾部与头部交叉淡化 0.5 秒以循环；较短原片等比慢放至 20 秒后处理，输出约 19.5 秒。原片和转码结果均在 `build/demo-kit/`，不入库。

## 复现

从仓库根目录执行，ffmpeg 为 `~/.local/opt/video/bin/ffmpeg`：

```sh
~/.local/opt/edrv32-py/bin/python tools/demo/kit/fetch.py
~/.local/opt/edrv32-py/bin/python tools/demo/kit/build.py
PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/demo/kit/validate.py
npm install --prefix build/farm-sim playwright-core@1.65.1
node tools/demo/kit/capture.mjs
```

`fetch.py` 可在末尾指定 clips.json 中的片段 ID，仅重新转码该片段；`validate.py` 可在末尾指定场景 ID，仅复核该场景。一次只运行一个 ffmpeg 或一个模型验证任务。依赖与模型权重沿用 `tools/npu/README.md`，不下载演示数据集。
验证固定使用板端的 INT8 描述符参考执行、confidence >0.25 和同类 NMS IoU >0.45；拍屏沿用农场四角、模糊、亮度和种子 17 的噪声。视频每秒取一帧，输出逐帧 JSON 和六张联系表。`capture.mjs` 拦截网络请求，检查包大小、七个场景、媒体切换与释放、暂停/播放、旋转滑动，并生成 2560×1600 横屏及 1080×1728 竖屏截图。

## 图片生成提示词

内置 imagegen；生成后等比裁成 16:9，再以 JPEG quality 88 保存。

### zebra

Use case: photorealistic-natural. Landscape 16:9. A single adult zebra in full side profile facing right on short open savannah grass, entirely visible from ears to hooves, large centrally positioned animal occupies 70 percent image width and 75 percent image height. Simple distant landscape, bright daylight, realistic wildlife photography, sharp stripes and anatomy. Exactly one zebra, no other animals, no people, no text, logos or watermark.

### giraffe

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. A single adult giraffe, full body including horns and hooves, side view facing left in a simple open savannah. Exactly one giraffe, no other animals. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### elephant

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. A single adult African elephant, full body including trunk and four legs, side view in open grassland. Exactly one elephant, no other animals. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### bear

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. A single large adult brown bear, full body side view standing on all four feet, grassy open landscape. Exactly one bear, no other animals. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### zoo-mixed

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. Exactly two animals well separated, one zebra on the left and one giraffe on the right in open grassland. Both full bodies entirely visible, no overlapping, no other animals. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### zoo-herd

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. Exactly three animals well separated on open grassland, two zebras on left and center, one elephant on right. Full bodies visible, no overlapping, no other animals. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### palm

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: open palm facing camera, all five fingers fully extended and separated. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### fist

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: closed fist facing camera, all four fingers tightly curled, thumb across them. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### peace

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: V sign facing camera: index and middle fingers fully extended and spread, ring and little fingers folded under thumb. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### point

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: one index finger pointing straight upward, middle ring and little fingers folded under thumb. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### grabbing

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: claw shaped hand facing camera, all five fingers bent partway, spread apart, as if grabbing a large ball. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### grip

Use case: photorealistic-natural. Landscape 16:9 realistic studio portrait of one fictional adult with upper body visible from waist to head, plain dark shirt, neutral light gray background. One right hand held large prominently centered in front of chest, entire hand and wrist visible. Hand making a GRIP gesture: palm side faces camera, four fingers held close together and curled down at their middle joints, fingertips gathered facing and almost touching the thumb tip underneath, as if gripping a small invisible ball or squeezing a small object. Side-on thumb opposed to all four curled fingertips, gap between thumb and curled fingers is small, knuckles clearly bent. This is not a fist: the folded fingertips stay apart from the palm. Other hand out of frame. Five anatomically correct digits, bright even lighting, no text, watermarks, logos, extra people or objects.

### thumb_index

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: L shaped hand facing camera with only thumb extended sideways and index finger extended upwards, the other three fingers folded. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### ok

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: OK sign facing camera: thumb and index tips touching in a round circle, other three fingers extended and spread. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### like

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: thumbs up, closed fingers curled into fist, thumb extended straight upward. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### dislike

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: thumbs down, closed fingers curled into fist, thumb extended straight downward. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### three

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: three fingers extended: index middle and ring raised, little finger folded under thumb, palm facing camera. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### four

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: four fingers fully extended and separated upward, thumb folded across palm facing camera. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### call

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. One fictional adult person, upper body from waist up, wearing plain dark t-shirt against a simple light gray studio background. Their single right hand is raised prominently in front of their chest, centered and facing the camera, large hand occupies about 35 percent of image height, clear fingers with anatomically correct five digits. Their other hand is out of frame. The visible hand makes precisely this gesture: shaka call-me hand: thumb and little finger extended widely, index middle ring folded into fist, palm facing camera. Show the person's head, shoulders, torso and entire gesturing hand. No additional hand or person. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### face-one

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. Head and shoulders portrait of one fictional adult East Asian woman age 30 with short black hair, facing camera directly, clearly visible unobstructed face and open eyes, simple light background. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### face-two

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. Head and shoulders portrait of one fictional adult Black man age 55 with short gray hair, facing camera directly, clearly visible unobstructed face and open eyes, simple light background. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### face-pair

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. Portrait of exactly two fictional adults side by side, a white woman age 60 and South Asian man age 35, both facing camera directly, clearly visible unobstructed faces and open eyes, plain studio background. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.

### face-trio

Use case: photorealistic-natural. Asset type: offline computer vision demo photograph, landscape 16:9. Portrait of exactly three fictional adults side by side, Middle Eastern woman age 25, East Asian man age 65, Black woman age 45, all facing camera directly, clearly visible unobstructed faces and open eyes, plain studio background. Subjects large and clearly separated within the frame. Bright even natural lighting, sharp realistic photographic detail. No text, watermarks, logos, borders, collage, extra subjects or children.
