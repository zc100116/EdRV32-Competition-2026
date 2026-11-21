# 原创手机人脸贴纸

2026-11-16 用内置 imagegen 生成，未使用网络图片。每套一个组合元素。
保留透明 alpha，后处理裁切 alpha>32 的包围框、双线性缩至 156 px 长边，
居中到 160×160 RGBA8 非隔行 PNG，再从四边洪泛 alpha<40 的四邻域连通区域。
清除连通区域内的低 alpha 底色，保留紧邻 alpha≥40 主体的八邻域一像素抗锯齿边缘，
以及与边界不连通的元素细节。六张图均采用该规则。

每张图片使用相同完整模板，将 `<subject>` 替换为下表文字：

> Use case: stylized-concept. Create one original mobile face AR sticker asset: <subject>.
> Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette,
> soft cream outline, clean silhouette readable at 160 pixels wide. Front view,
> symmetrical level, isolated centered complete object. No face, no person, no text,
> no logos. True transparent background.

| 文件 | subject（完整替换词） | 组合元素 |
|---|---|---|
| cat-ears.png | paired peach and pink cat ears joined by a delicate peach headband | 猫耳发箍 |
| bunny-ears.png | paired tall white bunny ears with coral pink inner ears and a soft lavender headband | 兔耳发箍 |
| sunglasses.png | chic oversized turquoise sunglasses with dark navy lenses, small coral highlights | 墨镜 |
| crown.png | golden three point crown with coral and turquoise jewels | 皇冠 |
| party-hat.png | coral and turquoise striped party cone hat with golden pompom and short curled ribbons | 帽子彩带 |
| heart-headband.png | rose pink headband with two heart shaped antennae | 爱心发箍 |

生成原图以表中名字保存到 `build/showcase/sticker-source/` 后，统一清理残留底色并重新生成六张 PNG 的命令：

```sh
python3 tools/sw/prepare_showcase_stickers.py build/showcase/sticker-source \
    sw/apps/showcase/assets/stickers
python3 tools/sw/rotate_showcase_stickers.py sw/apps/showcase/assets/stickers \
    build/showcase/sticker-frames
python3 tools/sw/embed_showcase_images.py build/showcase/sticker-frames \
    build/showcase/stickers.c --prefix sticker
```

所有元素的锚点是滤波两眼中点，局部 +x 向右、+y 向下，偏移按连续滤波 θ 旋转。
下表参数为 Q8 的 `offset_x, offset_y, width`（单位 d），集中定义在 `sticker.c`。
160×160 基图包括透明边缘；宽度参数指整个基图，五档旋转均居中到 220×220。

| 套装 | x/d | y/d | 宽/d | 基图尺寸 | 五帧 ARGB 字节 |
|---|---:|---:|---:|---|---:|
| 桃桃猫耳 | 0 | -256/256 | 640/256 | 160×160 | 968000 |
| 软糖兔耳 | 0 | -320/256 | 640/256 | 160×160 | 968000 |
| 海盐墨镜 | 0 | 0 | 640/256 | 160×160 | 968000 |
| 宝石皇冠 | 0 | -300/256 | 563/256 | 160×160 | 968000 |
| 彩带派对 | 0 | -384/256 | 563/256 | 160×160 | 968000 |
| 心动发箍 | 0 | -307/256 | 614/256 | 160×160 | 968000 |

旋转角度 −24/−12/0/12/24°，正角在屏幕坐标系中顺时针；运行时 RND 只缩放和混合。
30 帧合计 5,808,000 字节（不含 LVGL 描述符），不超过 6 MB。

## R3 分部位素材（2026-11-16）

新增 11 张均为内置 imagegen 原创透明 PNG，每张的完整提示词如下。
后处理沿用上述 alpha 裁切、双线性缩放和边缘清理；prepare 脚本第三参数
指定基础方形边长，rotate 将各基础图居中到边长 `pixels*11/8` 的方形。
仍为 −24/−12/0/12/24° 五帧；头饰/墨镜保持原图和原尺寸。

### heart-glasses.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: paired coral pink heart-shaped eyeglasses with open transparent lenses, connected by a tiny gold bridge. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 120 pixels wide. Front view, symmetrical level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### star-eyes.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: paired sparkling gold and turquoise five-point star eyeglasses with dark navy inset lenses, connected by a tiny coral bridge. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 112 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### cartoon-eyes.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: paired funny oversized white cartoon eyeballs with navy pupils and coral upper rims, connected as novelty eyeglasses. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 112 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### cat-nose.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: one small peach cat nose with tiny pink triangular tip and a short curved mouth below. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 48 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### clown-nose.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: one glossy round coral red clown nose with soft gold highlight. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 48 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### dog-nose.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: one rounded dark navy puppy nose with a soft peach muzzle and tiny nostril highlights. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 48 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### moustache.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: one curled dark navy handlebar moustache, elegant mirrored curls with tiny gold sheen. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 112 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### red-lips.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: one playful glossy coral red kiss lips, closed lip silhouette with pink highlights. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 112 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### tongue.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: one playful smiling coral mouth with a pink tongue sticking down, cream teeth. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 112 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### blush.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: one small soft coral pink cheek blush patch with three tiny glossy cream sparkles. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 64 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

### cat-whiskers.png

> Use case: stylized-concept. Create one original mobile face AR sticker asset: one cheek's three short dark navy curved cat whisker strokes with tiny gold accents, all extending rightward. Consistent polished playful glossy illustration, bright pastel coral turquoise gold palette, soft cream outline, clean silhouette readable at 64 pixels wide. Front view, level, isolated centered complete object. No face, no person, no text, no logos. True transparent background.

R3 的基础图尺寸与五帧 ARGB 字节（每帧方形画布，未计描述符）：

| 部位 | 文件 | 基图 → 画布 | 字节 |
|---|---|---|---:|
| 眼部 | heart-glasses、star-eyes、cartoon-eyes | 112 → 154 | 各 474320 |
| 鼻子 | cat-nose、clown-nose、dog-nose | 48 → 66 | 各 87120 |
| 嘴部 | moustache、red-lips、tongue | 96 → 132 | 各 348480 |
| 脸颊 | blush | 64 → 88 | 154880 |
| 脸颊 | cat-whiskers | 64 → 88 | 309760（含离线镜像左侧） |

新增 3,194,400 B，加原有六图 5,808,000 B，总计 **9,002,400 B**，低于 10 MB。
左右胡须使用同一原图的镜像基图后分别旋转，保持同一个 θ；腮红左右复用。
五点绝对坐标分别滤波：鼻尖取点 2，嘴中心取点 3/4 的中点，嘴宽以嘴角距离缩放；
脸颊取点 0/3、1/4 的中点，其他部位宽度均按眼距 d 缩放。
头饰仍用眼中点和旋转后的局部偏移，全部样式参数见 `sticker.c`。
当前 UI 每个部位循环包含“无”，预设为猫咪、派对、酷、兔子，最多三脸共用选择。

重新处理新增原图（原图在 build 下；第三参数为基础尺寸）：

```sh
for size in 48 64 96 112; do
    python3 tools/sw/prepare_showcase_stickers.py build/showcase/sticker-source/$size \
        sw/apps/showcase/assets/stickers $size
done
```
