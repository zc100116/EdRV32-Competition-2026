# 云脊漫游素材来源

- `terrain.png`：本任务 2026-11-26 使用 Codex 内置 imagegen 生成的原创草/沙/岩/雪四材质源图，作为项目自制素材使用，不宣称 CC0。
- 草木、岩石、勘测器、三地标、海岸、水面由 `world.c` 的原创网格构造；没有从其他游戏导入美术或设定。
- 字体和 HUD 复用 G-4 肉鸽模块，来源与 SIL OFL 1.1 许可位置见 `../../gpu_test_rogue/assets/SOURCES.md`。
- 处理遵循 `../../gpu_test_common/assets/STYLE.md`：面积缩到64×64、共享72色量化，RGB565与7级mipmap、2×2块交织；处理头文件放build。

## terrain.png 完整提示词

Use case: stylized-concept. Asset type: game terrain texture source sheet for original low-poly cartoon GPU island. Exactly 2 columns by 2 rows of square texture swatches, no margins, no text, no objects, no grid border. Top left: teal-green short grass in large irregular pixel clusters, top right: warm golden beach sand with a few ochre pixel flecks, bottom left: muted violet-gray stone with broad chunky crack clusters, bottom right: pale icy snow with lavender-blue pixel shadow patches. Each square should look like a seamless 32x32 pixel material tile enlarged sharply, 2-3 shades per material, simple large clean blocks, saturated modern cartoon colors, no fine noise, no photorealism, no painterly gradients, no landscape or perspective.


## terrain-v2.png（G-5，2026-11-26）

Codex 内置 imagegen 生成的原创细节材质源图；作为项目自制素材使用，不宣称 CC0。
仍走公共72色量化、RGB565、七级 mip 和2×2块交织管线，第五张物件皮肤由草地源图亮度形成中性像素纹理。
云、海浪和光晕为工具构造的 I8 alpha 图，均无第三方素材。

完整提示词：

Use case: stylized-concept. Production texture sheet for low poly island exploration videogame. Exactly 2 columns x 2 rows equal square tiles, no borders or margins, no text no labels. Flat orthographic seamless surface textures not landscape. Top left grassy meadow: medium teal-green base with short lime grass blade clusters, irregular moss patches, dark green small shadow clusters, visible crisp pixel detailing evenly across entire tile. Top right golden sand: warm pale golden base, wind ripples, scattered small orange and cream pebbles, small pixel clusters. Bottom left fractured violet gray rock: broad gray-purple facets with dark indigo cracks, small angular mineral flecks, highlighted edges. Bottom right snow: pale icy blue-white base, subtle lavender crevices, small blue pixel clusters, mostly white. Modern cartoon pixel art large clean clusters and 2-3 tone shades, no realism no smooth gradients. Each tile should read clearly when downsampled to64x64. Coherent navy/violet teal gold palette, grass medium bright and calm.
