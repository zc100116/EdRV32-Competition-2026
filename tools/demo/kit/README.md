# 演示素材与 INT8 识别基线

Android APK 已取代 HTML 素材包；工程、使用方法及复现命令见 `../app/README.md`。
`media/` 保留 23 张原创 imagegen 照片和旧缩略图；`media.json` 记录原素材及识别预期。
`clips.json` 逐项记录 Mixkit Free License 视频的作者、公开来源、截取与慢放参数。
`fetch.py` 仍将原片与转码结果放在 `build/demo-kit/`，脚本使用 `demo-media-fetch/1.0`。
`validate.py` 保留 T-DEMO-KIT 的拍屏几何、退化与同阈值 INT8 参考执行，供 APK 验证复用。
素材未改变时沿用 `docs/reports/2026-11-17-showcase-demo-kit.md` 的验证结果。

```sh
flock /tmp/edrv32-sw-build.lock ~/.local/opt/edrv32-py/bin/python tools/demo/kit/fetch.py
PYTHONPATH=tools/npu:third_party/ultralytics OPENBLAS_NUM_THREADS=1 flock /tmp/edrv32-sw-build.lock ~/.local/opt/edrv32-py/bin/python tools/demo/kit/validate.py
```

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
