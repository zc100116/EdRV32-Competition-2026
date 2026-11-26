# 棱炉地宫（GPU 2D 肉鸽 demo）设计

日期：2026-11-26；状态：协调者已确认，实施中；实际取舍与用量见 README.md。依据：G-4 Task、
`docs/spec/gpu-spec.md` v0.5 §2.1–2.10、§7；共享运行时以 G-3 交付版本为准。
设定图：`outputs/gpu-test-games-20261126/concept-rogue.png`，为 imagegen 概念图，
不是 GPU 截图，不构成已达到的性能或像素精度承诺。

## 玩法与原创设定

玩家是白青配色的方壳检修机器人，进入失控的地下彩晶热炉，关闭“棱炉监工”。
场景是机械地宫，青蓝地砖、铜橙炉门、紫色管线、发光炉晶；不使用现有游戏角色、
关卡、名称或素材，也不引用本仓库另一个肉鸽项目。保持 G-3 现代卡通像素风：
大色块、2～3 阶明暗、深蓝描边、背景压暗，攻击与可拾取物明亮发光。

一局目标 5～10 分钟，单层 9 房：入口、5 战斗、宝箱、祭坛、Boss。
从固定种子 PRNG 生成 9 节点连通树：先长出 6 房主链，再向空邻格接 3 条支路，
Boss 放在距入口最远的叶节点；类型分配避开入口和 Boss。每次选取现存空邻格，
不靠反复重试凑图。每房 18×9 个 32px 地砖，固定外墙和 4 个可能的门，障碍模板
由种子选取且留出门间通道；切房时仅活动房运行。小地图显示已见房、已清房、特殊房。
清房开门、掉金币，并弹出三选一道具；金币在祭坛支付一次可选治疗。无存档、
局外成长、多角色；生命归零显示失败与本局种子，Boss 死亡显示通关，可重开。

## 操作

| 动作 | ETH/PC 完整输入 | 板上四键模式 |
|---|---|---|
| 移动 | 方向键四向 | bit0/bit1 左右转向，角色持续沿朝向走；碰墙停住 |
| 射击/挥砍 | 自动瞄准最近敌人并连续攻击 | 同左 |
| 手动瞄准 | 按住 A（VI_A），方向键控制瞄准，松开恢复移动 | 自动瞄准 |
| 翻滚 | B（VI_B） | bit2 短按 |
| 控制菜单 | Start（VI_START） | bit2 长按 0.5 秒，按下后等释放才执行短按 |
| 返回开机菜单 | Esc（VI_ESC） | bit3 |

完整输入使用已存在的 VI 位，不新增硬件协议；具体 PC 键位在 G-3 完成后按平台
映射确定并写 README。控制菜单用 next/prev/enter 选武器、模式、负载、继续；
选卡界面冻结战斗，左右选择、确认领取（四键此时 bit2 直接确认）。
四键转向行走让两维房间都可到达，入口菜单说明该操作；不依赖 ETH 才能通关。

## 内容和手感

| 内容 | 数量和行为 |
|---|---|
| 主角 | 24×24，待机/走路 4 帧、翻滚 4 帧；100 HP |
| 武器 | 点射枪（每 12 tick）、5 弹霰弹（每 36 tick）、弧刃（每 28 tick） |
| 弧刃 | 挥动 10 tick，旋转约 120°；武器贴图由 2 三角形旋转，刀光 12 三角形弧带，3 份递减 alpha 历史姿态拖尾；每挥同敌只命中一次 |
| 翻滚 | 12 tick，前 8 tick 无敌，冷却 45 tick；残影 3 份 |
| 冲撞敌“铜角” | 预警 24 tick，再直线冲撞，撞墙硬直 |
| 远程敌“棱眼” | 保持距离，三连扇射，攻击前核心亮起 |
| 分裂敌“胶核” | 缓慢追踪，死亡分成两个小核，小核不再分裂 |
| Boss“棱炉监工” | 大型悬浮炉心与分离钳臂；一阶段扇形/环形弹幕；50% HP 后交替旋转弹幕和召唤铜角/棱眼，有预警安全空隙 |
| 道具 | 穿透、多弹、吸血、护盾四类；清房抽 3 个不同选项，只作用本局 |
| 场景 | 蓝紫冷炉、铜橙热炉两主题，共用瓦片以调色板换色；4 帧开门、3 帧火把 |

60 Hz 固定 tick，渲染与实际计时分开。命中停顿普通 2 tick、重击 4 tick，
停顿期间仅特效计时继续；震动 2～4px、白闪 3 tick、击退 6 tick、伤害数字
上飘 30 tick，死亡碎裂 6～12 片及火星。射击含 2 帧枪口火、落地弹壳和短音；
火把亮度以查表闪动，加色光晕不是动态光照或 bloom。

## GPU、纹理与内存预算（设计估算）

原生 640×360，2 条 640×180；所有条带绘制相同世界 tick，只有首条可推进对象。
地砖、角色、门、粒子走 1:1 DRAW_QUAD；旋转武器/弧带走 DRAW_TRI，
不把不支持旋转缩放的四边形通道当作通用精灵。CPU 负责 AI、房间、拾取与敌人
碰撞；GPU OBJ_STEP 用于敌弹运动、寿命和对玩家一个目标框的碰撞。玩家子弹
对多敌人用 CPU 房间格网，避免把硬件 8 目标误写成任意敌人数。
三角形使用正交 MVP、16B 顶点；加色火光和 alpha 残影按状态批次绘制。

| 纹理 | 格式/尺寸 | 字节 |
|---|---|---:|
| 角色/三敌/小核/Boss 分件/武器 | I8 256×256，无 mip | 65536 |
| 32px 地砖/墙/门/火把/祭坛/宝箱 | I8 256×256，无 mip | 65536 |
| 爆裂/弧光/弹体/光晕 | I8 128×128，无 mip | 16384 |
| HUD/中文字体/道具图标 | I8 256×128，无 mip | 32768 |
| 合计 | 每项 OFFSET 32B 对齐 | **180224 / 196608** |

余量 16384B；16 组调色板独立于纹理 RAM。进入 demo 一次 TEX_LOAD/PAL_LOAD，
之后每帧装入 0B。中文用共享 Fusion Pixel 子集；新增字由 BDF 管线生成。
新角色/瓦片 imagegen 源图保存在本 demo assets，许可/提示词/处理方法记入
`assets/SOURCES.md`；G-3 STYLE.md 出现后沿用其量化、描边、缩放规则。
不直接把概念图裁成未经预算的游戏贴图。

正常目标：同屏 24 敌、256 弹、128 碎片、32 飘字，约 1100 四边形、
最多 180 三角形（每条提交，含武器/拖尾）；压测档敌/弹分别
32/512、64/2048、128/8192，效果粒子最多 512。该上限是 demo 内容预算。
顶档含场景/HUD 小于 10000 对象/四边形，需协调共享 TEST_QUAD_MAX=8192 的
容量或分批；优先让弹体用独立对象表，不扩大共用 quad 表。
额外 CPU 状态/格网目标 <256KiB，最大弹体表 8192×32=256KiB，
命中/释放各 8192×4=32KiB；复用公共 Surface/命令/顶点缓冲。

帧估算（不是实测）：以 GPU 180MHz、CPU 100MHz 作为估算输入。
正常对象/quad 等效 1100×2×80/180M = 0.98ms（16×16 I4 的规格参考，
实际 I8/32px 和光晕另估）；按 1.2M 混合片元、2像素/周期保守计 3.33ms，
三角形建立 180×2×8/180M = 0.016ms，加写出 ≤0.5ms、DDR/状态约 2ms，
GPU 设计目标 <8ms。CPU AI/碰撞/构命令先按 0.6M cycles=6ms，
总串行估算 <14ms，目标 60fps；I4 的单项指标不能证明 I8 或板端帧率。
压测顶档允许跌帧，显示实测且不自动减量；不以参考模拟器 FPS 冒充板端结果。
HUD 左下复用对象数、FPS、CPU ms/GPU µs 口径；另外显示敌/弹数、种子和负载档。

## 验收与集成

G-3 交付或协调后才改共用运行时、菜单/Makefile，增加第 3 个入口。
先完成此 demo，编译 board/linux/windows 并逐个捕获独立状态：
`rogue-combat.png`、`rogue-slash.png`、`rogue-boss.png`、`rogue-choice.png`、
`rogue-minimap.png`、`rogue-stress.png`；`rogue-3s.zip` 为 180 个连续 tick。
截图走 PC 参考 GPU，受击/挥砍/菜单须真在对应状态；README 记录种子、命令、
按键、实际纹理用量和测量。无需 RTL/SoC 仿真，编译/headless 前检查可用内存 ≥2GiB。

## imagegen 提示词

内置 imagegen；生成 concept-rogue.png，以下为完整提示词：

> Use case: stylized-concept. Asset type: approval gameplay mockup for an ORIGINAL 640x360 GPU dungeon demo titled 棱炉地宫. Create a 16:9 landscape top-down room-based dungeon combat screen. Modern cartoon pixel art, visible crisp square pixels, large clean color clusters, 2-3 shades per material, dark navy outlines. Dark blue-violet mechanical furnace dungeon with tiled square floor, chunky low walls, copper-orange animated doorway at top, violet pipes, cyan and orange wall torches with small additive-looking halos. White-and-turquoise small box-shell maintenance robot at lower middle, no human face, swinging a separate oversized angular cyan energy cleaver, a readable sweeping curved blade-light arc and three fading weapon trails, sparks and floating damage number 24. Three original enemy silhouettes: coral copper horned charging cube, violet floating prism-eye turret, gold round split-gel core with two small pieces. Upper middle a larger mechanical floating furnace core boss with detached clamp arms, orange glowing center. Organized sparse orange/magenta bullet fans with readable empty paths, coins and one broken enemy scattering chunks. Keep background darker than actors, no visual clutter. Compact thin bordered dark navy Chinese HUD panels: top left title 棱炉地宫 and heart health icons, top center boss title 棱炉监工 and magenta health bar, top right a tiny 9-room minimap. Bottom left small diagnostics 对象 420  FPS 60  CPU 6ms  GPU 8ms. Bottom right three small weapon icons pistol shotgun cleaver. Achievable logical 640x360 pixel-grid game screenshot mockup enlarged cleanly, not painterly, no photorealism, no logos, no watermark, no characters or art copied from existing games. The diagnostic numbers are illustrative concept labels only.
