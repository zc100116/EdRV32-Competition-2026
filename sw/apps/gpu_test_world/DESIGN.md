# 云脊漫游（GPU 3D 开放世界 demo）设计

日期：2026-11-26；状态：设计待协调者确认，未实现。依据：G-4 Task、
`docs/spec/gpu-spec.md` v0.5 §2.1–2.10、§7；运行时复用 G-3 交付版本。
设定图：`outputs/gpu-test-games-20261126/concept-world.png`，为 imagegen 概念图，
不是 GPU 渲染截图。纹理、帧预算均为设计估算，等待真实构建与板端测量。

## 玩法与原创设定

玩家操纵白青色单人悬浮勘测器，在“云脊岛”自由探索，收集散落的 24 枚光种，
寻找三个原创地标：风页塔、折光庭、云轮风车。第三人称跟随镜头，靠近地标
弹出“发现：风页塔”等中文提示和简短合成音效。5～10 分钟可发现三地标并收集
12 枚光种，出现探索完成面板后允许继续逛；不做战斗、任务树、存档或成长。
不引用现有开放世界游戏或本仓库另一个肉鸽项目的设定、名字和素材。

沿用 G-3 大色块、2～3 阶明暗、深蓝细描边、饱和橙/青/紫、低多边形配像素纹理；
此场景增加青绿草坡、金色沙滩、紫灰岩脊和雪顶。小飞行器悬于地面/海面上约 3m，
沿坡平滑升降，可跨水，不要求步行角色骨骼、攀爬或物理载具。世界边缘为可见的
海上边界浮标，达到边界停止平移，避免无目标无限地图。

## 操作与内容

| 动作 | ETH/PC 完整输入 | 板上四键模式 |
|---|---|---|
| 移动 | 上下前进/后退，左右转向 | bit0/bit1 转向，默认持续前进 |
| 停驻/继续 | A（VI_A） | bit2 短按 |
| 控制菜单 | Start（VI_START） | bit2 长按 0.5 秒；释放后判定短按 |
| 返回开机菜单 | Esc（VI_ESC） | bit3 |

控制菜单 next/prev/enter：正常/压测、负载档、LOD 着色、昼夜时刻、继续；
按键期间暂停移动，昼夜时刻可选白天/黄昏，正常状态自动昼夜循环。
复用现有 VI 位与平台映射，G-3 交付后再确定 README 的 PC 键位。
移动约 18m/s，转向限制避免镜头急转；相机后方 12m、上方 7m，贴近高坡时
按高度图抬高相机。没有复杂物理和碰撞网格，地标以圆柱边界阻挡勘测器。

内容固定：24 光种、3 地标、3 树形网格、2 岩石网格、1 小屋、1 勘测器。
树与岩石按区块种子放置，近处实体低多边形，远处减少数量；复用网格但仍逐实例
提交矩阵与 DRAW_TRI，GPU 没有硬件 instancing。风车叶片旋转，光种上下浮动，
拾取产生加色星芒与计数。右上罗盘/小地图显示北向、三个地标和玩家；左上显示
光种数和已发现地标；左下显示三角形数、可见块、FPS、CPU/GPU 耗时。

## 地形、分块与 LOD

2048×2048m，32×32 个 64m 区块。种子确定的整数值噪声叠加岛屿径向衰减，
高度 0～240m，海平面 16m。高度采样使用绝对世界网格坐标，邻块共边取样相同。
世界位置 Q16.16、角度 256 相位查表、矩阵 s15.16；GPU 顶点为块内整数米，
每块独立平移 MVP，保持 s16 顶点与 RV32IM 精度范围。

| 地形级别 | 距相机块中心 | 每块网格 | 主体三角形 |
|---|---|---|---:|
| LOD0 | <128m | 16×16 格，步长 4m | 512 |
| LOD1 | 128～320m | 8×8 格，步长 8m | 128 |
| LOD2 | 320m～视距 | 4×4 格，步长 16m | 32 |

边缘加向下 8m 的裙边隐藏不同 LOD 裂隙；每块裙边三角形数分别
128/64/32；这是明确的地形接缝方案。CPU 先距离，再 5 个视锥平面与块 AABB
测试；GPU 仍处理近平面和保护带裁剪。共 1024 个块描述（种子、坐标、高度范围），
相机附近 9×9=81 块缓存完整 17×17 高度样本，每帧最多生成 2 个新区块。
移动前方优先生成，正常 18m/s 远低于 2块/tick 的生成速率；首次进入加载完初始
窗口再开始游戏。远块使用粗采样数据，按距离重建缓存，不做文件系统流媒体。

地表按高度和坡度为每个地形小格选择草/沙/岩/雪材质，不宣称 GPU 多纹理混合；
边缘用顶点色缓和，批次按材质组织。可见地形批次复用同一个相机 MVP，CPU 把
块局部坐标转换为相机附近原点坐标，避免每块×每材质的状态批次过多。
透明海面在不透明地形后画，LEQUAL、关闭深度写，按远到近提交水块；岸边浅水
带由高度阈值生成浅青面片，少量加色泡沫，无反射/refraction 或水下物理。
雾不是 GPU 独立指令：CPU 按顶点视距混合基色与雾色，GPU 再做纹理和顶点光照；
远景减少方向光，令最远处近似天空色，掩盖视距截断。

天空用不测深度的渐变屏幕条加简单 alpha 云片；昼夜周期 180秒，查表插值
天空色、雾色、环境光、方向光方向。黄昏橙紫，夜间压暗地形并突出光种；
没有实时阴影、体积云或后处理 bloom。灯光 SET_LIGHT 是物体空间方向，
相机原点变换仅平移时可共用世界方向；旋转物件需转入其本地空间。

## 纹理与三角形预算（估算）

每次进入时单独 TEX_LOAD/PAL_LOAD，离开后其他 demo 重装自己的图集。
本版地形程序生成，全部纹理常驻，每帧纹理装入 **0B**；不需要区域纹理流式。
纹理转换使用 G-3 标准库 PNG/BDF、调色板和块交织/mipmap 管线，STYLE.md
交付后统一。新纹理源与许可/提示词记入本 demo `assets/SOURCES.md`。

| 纹理 | 格式/尺寸 | 字节 |
|---|---|---:|
| HUD/字体/光种/云/星芒图集 | I8 256×256，无 mip | 65536 |
| 草、沙、岩、雪、物件表面五张 | 各 RGB565 64×64，7级 mip，含每链对齐 | 5×10944=54720 |
| 水/树冠透明图集 | I8 128×128，无 mip | 16384 |
| 合计 | 全部 OFFSET 32B 对齐 | **136640 / 196608** |

余量 59968B，调色板 RAM 另计。每条 RGB565 mip 链有效 10928B，
按 gpu-spec §2.6 补齐 2×2 块并向下一 OFFSET 留 16B 对齐。
物体轮廓靠深色网格边缘材质/像素纹理，不增加全屏边缘检测。

正常视距 512m，预估视锥可见块 L0/L1/L2 约 8/24/48，
含裙边地形 8×640+24×192+48×64=12800 三角形；
近景树岩/地标/机体约 3500，水岸/光效约 700，合计目标 **17000**。
压测档视距/密度为 384m/0.5、512m/1、768m/1.5，
目标约 10000/17000/30000 三角形，显示实际提交数；密度数是生成物件的
显式档位而非运行时降级。LOD 可视化 L0青/L1金/L2紫，裙边跟随本块颜色，
其他物件保持原色，HUD 给颜色图例。最高档目标小于共享 60000 TRI 容量，
实际数量以输出 CSV 定稿，不隐藏截断。

高度缓存约 81×17×17×2=46818B，区块描述约 32KiB；
额外实例、采样与状态预算 <256KiB，复用公共顶点缓冲与双 Surface。
顶点无索引：30000×3×16=1.44MB/帧构造数据，条带重复提交同一顶点缓冲。

帧估算（非实测）：GPU 180MHz、CPU 100MHz 为输入。
17000 TRI×2条×(3×2顶点周期+8建立周期)/180M = 2.64ms；
按 1.2M 片元/2像素周期 = 3.33ms，RESOLVE ≤0.5ms，
纹理/DDR/批次预留 2ms，GPU 目标约 8.5ms。CPU 可见性、生成2块、
展开网格/顶点色和命令先按 0.7M cycles=7ms，串行目标约 15.5ms，
目标60fps但很紧；压测顶档允许跌帧，不承诺板端60fps，按实测记录。
硬件顶点吞吐是理想条件，DDR、裁剪、水面混合、三线性开销均需测量。
地形默认双线性+mip，像素物件最近邻；不用模拟器墙钟宣称板端性能。

## 集成和验收

先等肉鸽所有截图完成，再实现开放世界；G-3 交付或协调后才改共用菜单/Makefile，
形成 4 个入口。C11 和 -Wall -Wextra -Werror，使用生成寄存器头和 BSP cache 接口。
内存可用 ≥2GiB 才编译/headless，一次只做一个重任务，不运行 RTL/SoC 仿真。

独立场景截图：`world-day.png`、`world-dusk.png`、`world-coast.png`、
`world-landmark.png`、`world-lod.png`、`world-stress.png`；
`world-3s.zip` 为 180 连续 tick。白天/黄昏同一种子不同时间，海岸/地标不同坐标，
LOD/压测具有真实开关和实际计数，不复用一帧。README 写操作、种子、
地形/纹理预算、每帧 TEX_LOAD=0B、build 与 capture 命令和板端未测项。

## imagegen 提示词

内置 imagegen；生成 concept-world.png，以下为完整提示词：

> Use case: stylized-concept. Asset type: approval gameplay mockup for an ORIGINAL 640x360 low-poly GPU open-world exploration demo titled 云脊漫游. Wide 16:9 third-person game screenshot from just above and behind a small white-and-turquoise single-seat boxy hover survey craft with amber thrusters, hovering 3 meters above rolling terrain. Show a vast explorable island vista: stepped bright teal-green grassy hills in foreground, a curving golden beach and translucent turquoise sea at left, violet-gray rocky ridges with white snow tops far behind, a tall original geometric copper wind-page tower landmark on a hill at right, a four-blade windmill and a tiny angular ruin in mid-distance. Three simple low-poly tree shapes and sparse faceted rocks. A winding scattered trail of small glowing cyan-gold seed crystals invites free exploration, no race rings or corridor. Modern cartoon low-poly meshes with crisp pixel-art surface textures, large clean facets, 2-3 shades, dark indigo outlines on craft and small props, high saturation, coherent orange/turquoise/violet color accents, no realism or painterly details. Broad layered lavender clouds in gradient blue sky, distant terrain fades into blue-violet fog; darker foreground shadows let glowing pickups read. Small thin bordered dark navy Chinese HUD: top left 云脊漫游 and 光种 08/24, a compact discovery toast 发现：风页塔 below it, top right small compass/minimap, bottom left small diagnostics 三角形 17000  区块 80  FPS 60  CPU 7ms  GPU 9ms. Make this visually achievable at logical 640x360, clean silhouettes, restrained effects, original setting unrelated to existing games, no logos or watermark. The diagnostic numbers are illustrative concept labels only.
