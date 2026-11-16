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
