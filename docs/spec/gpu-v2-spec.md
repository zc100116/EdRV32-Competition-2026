# GPU v2 规格

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-11-27 |
| 状态 | 草案；供协调者审核，不替代正在上板的 gpu-spec v0.6 |
| 范围 | GPU v2 IP、原生命令、ES 1.1 驱动及桌面 GL 1.x 兼容层的边界 |
| 关联文档 | docs/testplan/gpu-v2-testplan.md、docs/plan/gpu-v2-plan.md；docs/design/2026-11-27-gpu-v2-architecture.md（M-9 为架构准则，算术/单元采用 M-8/M-6）；gpu-soc-spec.md；edrv32-soc-spec.md §4、§7 |

## 1. 概述

GPU 必须实现面向 OpenGL ES 1.1 Common profile 的固定功能渲染路径。CPU 驱动必须把 API 状态和数组转换为原生命令；桌面 GL 1.x 兼容层必须在驱动内转换为同一路径。GPU 必须连接媒体 APB 槽 6、mem_xbar P3 和 PLIC 源 13。

GPU 必须采用 64×64 tile、256 位外部流、原生 vec4 FP32 顶点引擎、12 上下文、共享四乘法池 setup、双光栅 lane 和一个分时执行两逻辑纹理单元的采样器。变换后顶点必须写 DDR；不得存储 DDR 平面表；每个 tile 引用必须重建相同源锚点的 setup，再整数重定位。跨帧必须采用两个独立帧槽，片上 tile 目标不得复制为整帧目标。

clk_gpu 必须按 200 MHz 设计，150 MHz 为保底目标 **[待定 G2-01]**。APB/AXI 与 mem 域的跨域必须沿用 X10/X9，irq 必须沿用 X3。复位必须来自 reset_ctrl 并在本域同步释放。

## 2. 功能描述

### 2.1 API 功能映射与最小限制

下表每行必须由所列层实现完整语义；“硬件”包括驱动加载的顶点微码。规范依据为 [OpenGL ES 1.1.12](https://registry.khronos.org/OpenGL/specs/es/1.1/es_full_spec_1.1.pdf) §2–6、附录 C；本文的内部初值不得改变公开 API 语义。

| 编号 | 功能 | 硬件 | 驱动 | 桌面兼容层 |
|---|---|---|---|---|
| F01 | float/fixed、合法 BYTE/SHORT 等数组类型、当前属性、VBO | FP32 输入/运算 | 转换、stride、enable、offset、对象生命周期 | immediate mode 收集为数组 |
| F02 | DrawArrays/Elements、7 种基本图元 | 三角形、点/线覆盖 | 装配 strips/fans/loops、索引与 provoking vertex | QUADS 转三角形，display list 展开 |
| F03 | MV/P/两套纹理矩阵、法线逆转置 | vec4 微码 | 矩阵乘法、栈、逆转置、调用时状态捕获 | glOrtho 等桌面调用转换 |
| F04 | 8 灯、材质、双面、NORMALIZE/RESCALE_NORMAL | 眼空间微码、RCP/RSQ/幂 | 灯/材质常量、COLOR_MATERIAL | 桌面状态映射 |
| F05 | 六视锥面、一个用户面 | 固定裁剪、扇分、投影 | 用户方程按调用时 MV 变换 | 桌面裁剪接口转换 |
| F06 | viewport、DepthRange、cull、scissor、smooth/flat | 覆盖/深度/颜色插值 | GL 左下坐标转换、flat 原图元末顶点颜色 | 同一语义 |
| F07 | aliased/smooth 点线、点大小数组/衰减/fade、point sprite | 专用线覆盖、覆盖 alpha | 点中心裁剪后展开、每单元 COORD_REPLACE | 桌面点状态转换 |
| F08 | 2 逻辑纹理单元、独立矩阵/坐标/env | 一采样器两遍 | texture 对象与描述符 | TexGen 转输入坐标 |
| F09 | POT 2D、全部 mip、REPEAT/CLAMP_TO_EDGE、6 MIN/2 MAG | 地址、过滤、LOD、cache | 上传、分配、完整性与空图像语义 | 桌面允许的调用转换 |
| F10 | A/L/LA/RGB/RGBA；UB/565/4444/5551 | 内部格式解码 | 上传布局与格式转换 | 同一纹理对象 |
| F11 | Tex(Sub)Image、CopyTex(Sub)Image、GENERATE_MIPMAP | tile 物化 | 拷贝、box mip 生成、更新同步 | 桌面调用转换 |
| F12 | OES_compressed_paletted_texture 的 10 种上传格式 | 解压后纹理采样 | palette4/8 × RGB8/RGBA8/565/4444/5551 解压 | 同驱动 |
| F13 | 六种纹理环境和完整 COMBINE | env0→env1 | 参数保存/查询 | 同驱动 |
| F14 | LINEAR/EXP/EXP2 雾 | 顶点因子、像素 RGB 混合 | 雾状态 | 显式 FogCoord/secondary color 不列为 ES 核心 |
| F15 | alpha/depth/stencil 全部比较、mask、清除 | 像素流水 | 默认状态、API 检查 | 同驱动 |
| F16 | 全部合法 BlendFunc、16 logic op、RGBA mask、dither | 像素流水 | 保存查询 | 同驱动 |
| F17 | PolygonOffset | setup 斜率与 Z 偏移 | factor/units | 同驱动 |
| F18 | ReadPixels、OES_read_format、pack alignment | 目标物化 | RGBA/UB、native565 打包读回 | 桌面读回转换 |
| F19 | SAMPLE_* state/query、Flush/Finish、Get/Is/Gen/Delete/Bind、hint、错误/字符串 | 提交、退休状态 | 全部 API 状态和错误、matrix-as-int-bits 核心查询 | 桌面状态和错误 |
| F20 | 对象运动/碰撞；quad 快通道、后处理 AA | 后二者可选，默认关闭 | 对象单元功能 | 按桌面调用语义提交 |

所有配置必须保留 8 灯、2 逻辑纹理单元、1 用户裁剪面；小配置不得删除必需功能。

| 公开限制 | 必须提供的值 |
|---|---|
| MAX_LIGHTS / MAX_TEXTURE_UNITS / MAX_CLIP_PLANES | 8 / 2 / 1 |
| MODELVIEW/PROJECTION/TEXTURE 栈深度 | 16 / 2 / 每单元 2 |
| MAX_TEXTURE_SIZE | 小配置 64；性能档/满配 256 |
| SUBPIXEL_BITS | 4 |
| 点大小、线宽（aliased 和 smooth）范围 | 初值 [1,1]；point sprite 范围 **[待定 G2-02]** |
| SAMPLE_BUFFERS / SAMPLES | 0 / 0；后处理 AA 不改变这两个值 |
| 目标位数 | 默认 R5/G6/B5/A0/D16/S8；可配 RGBA8/D24S8 |
| 浮点范围 | 位置/法线/其他值至少覆盖幅值 2^32；颜色/纹理至少 2^10 |
| 最大 viewport/目标尺寸 | **[待定 G2-02]**，初值 1280×720，必须覆盖 640×360 展示目标 |

FBO、NPOT、各向异性、matrix palette、stipple 不在本轮目标。桌面兼容层的函数集合和扩展公布范围 **[待定 G2-02]**；初值覆盖 immediate mode、QUADS、display list、TexGen、glOrtho，不得把该集合表述为完整桌面 GL 一致性。

### 2.2 原生命令与状态包

命令必须以小端存于 DDR，列表基址初值 64 B 对齐；每条头部 32 B，负载由地址引用。以下编码/字段布局为 **[待定 G2-03]** 的推荐初值，不与 v0.6 二进制兼容。状态包必须捕获不可变 draw 版本，包含顶点程序/常量、纹理描述符、viewport/scissor、光栅、env、雾、像素和目标状态。GPU 不得在回放时读取已经被 N+1 覆盖的 N 全局状态。

头部初值：word0=[7:0] opcode、[8] slot、其余 0；word1=draw/state ID；word2=payload 地址；word3=payload 字节数；word4..7=下表命令参数。固定头和各负载必须由协调者维护的寄存器/格式描述生成 RTL/C/Python 定义。

| 初值 opcode | 命令 | 必须具有的字段与行为 |
|---|---|---|
| 0x01 | STATE | state ID、状态包地址/长度；发布后只影响后续 draw |
| 0x02 | PROGRAM | 程序地址、行数、入口；装入当前状态对应微码 |
| 0x03 | CONSTANTS | vec4 常量地址、首索引、数量；draw 期间不可变 |
| 0x10 | FRAME_BEGIN | slot、frame_id、目标描述符、顶点/bin 内存区域；建立本槽所有权 |
| 0x11 | CLEAR | C/D/S 值和 enable、scissor、各写 mask；必须按命令顺序 bin |
| 0x20 | DRAW_ARRAYS | primitive、first/count、输入描述符、state ID |
| 0x21 | DRAW_ELEMENTS | primitive、index 地址/type/count、输入描述符、state ID |
| 0x22 | DRAW_QUAD | 可选快通道记录地址/count；仅使能配置可用 |
| 0x30 | BIN_SEAL | slot、各 tile 段头表地址；此前几何和 bin 写响应完成后槽 ready |
| 0x31 | TILE_RENDER | slot、tile 范围；依次读取封存 bin、load、setup、绘制、store |
| 0x40 | MATERIALIZE | 目标、矩形、序列号；此前影响区域的所有 tile 必须物化 |
| 0x41 | FRAME_END | slot、frame_id；最后 tile 读完且目标 B 响应完成后退休 |
| 0x42 | FENCE | 序列号；此前命令所有写响应完成后发布完成 |

状态包各字段组推荐初值如下，块内位偏移/长度属于 **[待定 G2-03]**；每组必须有独立的布局定义，不能只传GL状态指针。

| 字段组 | 必须包含的负载 |
|---|---|
| vertex | 程序地址/行数/入口、常量地址/数量、输出属性布局、flat/双面选择 |
| raster | viewport整数框、DepthRange FP32、front face/cull、scissor、点线/smooth/sprite状态 |
| texture[0..1] | enable、图像/采样描述符、base format、env/COMBINE sources/operands/scales、常量色 |
| fog | enable、fogRGB；因子计算参数必须进入顶点常量 |
| pixel | alpha/depth/stencil enable/函数/ref/读写mask/三操作、blend因子、logic opcode、RGBA/depth mask、dither |
| target | 目标描述符和物化序列关联；clear值必须随CLEAR命令保存 |

目标描述符必须含颜色/D/S 基址、pitch、尺寸、格式、load/store 选择。纹理描述符必须含 base format、内部存储格式、每 mip 地址/尺寸/pitch、MIN/MAG、wrap、env 和对象版本。应用对象名不得直接作为 cache 身份。

输入描述符必须分别给 position4、normal3、color4、tex0/tex1 vec4、point size 的地址/stride/当前值选择。驱动必须把启用数组转换为 FP32；缺失 position.w、texture.q 初值为 1，其余缺失分量按 ES 默认属性补足。DrawElements 的公开索引类型必须支持 UNSIGNED_BYTE/UNSIGNED_SHORT；内部初值 uint16，驱动必须分批保持顺序。64 B 原始顶点仅用于适合其字段的 D1 基准，不得把通用双 vec4 纹理输入强制截成 64 B。

### 2.3 变换后顶点和 bin 格式

DDR 变换后记录必须保留 FP32 属性，不得改为 FP16。常见 11 活跃属性的 64 B 记录推荐初值如下 **[待定 G2-04]**：

| 字节 | 内容 |
|---|---|
| 0–7 | sx、sy，各 signed32 Q4 容器；有效屏幕精度至少 4 小数位 |
| 8–51 | 11×FP32，初值 Z、s0/w、t0/w、s1/w、t1/w、1/w、RGBA、fog |
| 52–55 | 输出顶点 ID |
| 56–59 | draw/state ID |
| 60–63 | 裁后图元/属性布局元数据 |

一般 q0/q1 的两套纹理投影需要 13 属性，双面还需完整前/后颜色（一般q加双面共17标量）；64 B 全状态字段完整性尚未定稿。推荐初值为 64 B 主记录加按状态声明的 32 B 扩展记录，完整保留新增 FP32；这属于 **[待定 G2-04]** 的格式提案，未经确认不得把所有状态按 64 B 计费。源三角形索引表初值为三个 uint32 输出顶点 ID；锚点必须从原裁后顶点重算，不能依赖每 tile 改写顶点。

bin 必须按 tile、draw 段组织；每引用初值 uint32 源三角形 ID，顺序由追加位置表达。段头必须含 state ID、引用地址/count、下一段地址；初值 32 B。clear/点线等必须有带类型的段。所有引用必须保持原 draw/图元顺序；不得按材质重排。段头、索引表和聚合 burst 布局 **[待定 G2-05]**；初值按相邻 64 B 以上聚合，不把 4 B 引用当独立满效率 AXI 事务。

### 2.4 顶点微码 ISA 与算术

每上下文必须有 32 个 vec4 FP32 寄存器；源必须支持 xyzw swizzle、negate、absolute，目的写 mask 必须保留未写分量。每拍必须可读取 3 个 RF 源和至多 2 个不同 draw 常量；常量索引初值 7 位、128 vec4。所有上下文必须按同一静态指令次序轮转，驱动排程必须消除 RAW 和唯一 RF 写回口冲突。

| 指令类 | 必须提供的语义 |
|---|---|
| LOAD_ATTR、STORE_VERTEX、END | 读属性、输出字段、等待本顶点所有输出完成 |
| MOV、ADD、MUL、FMA、MIN、MAX、SELECT | vec4、逐分量 mask；FMA 只在末尾舍入一次 |
| DP3、DP4 | 3/4 个逐级 FP32 乘积，平衡 FP32 加法树；DP3 第四乘积为 0，标量结果写 x，可 swizzle 广播 |
| RCP、RSQ、LOG2、EXP2 | 标量 SFU；pow 必须由 LOG2→MUL→EXP2 组成 |
| LOOP、ENDLOOP、LOAD_CONST_REL | 定次数灯循环、base+lamp_index×stride+field；初值计数 1..8、方向灯 stride2、完整灯 stride8；默认程序应完全展开 |

程序存储必须为 1024 行，每行由 64 位指令体和静态排程控制字段组成。控制编码/宽度 **[待定 G2-06]**：初值每上下文 8 位等待，12 上下文合计每行 160 有效位、5 DRM；行宽必须由 VERTEX_CONTEXTS 派生，不作为独立参数。程序必须按状态加载，不能假设所有变体常驻。

FP32 基本运算推荐 round-to-nearest-even；点积必须逐级舍入，不能以融合点积替代。非正规数、NaN/Inf、signed zero 和 MIN/MAX/SELECT 的确切位语义 **[待定 G2-07]**，初值采用 IEEE 单精度逐级结果，SFU 定义域按公开 GL 表达式处理；不得把研究脚本未覆盖范围声称为已验证。

SFU 必须采用小表：RCP64、RSQ64（均两次 Newton）、LOG49 双表和 EXP64 五阶残差，表存一块 DRM；setup 必须使用独立读口共享倒数种子。SFU 混合请求发射间隔必须按 II4 设计。延迟初值（含顶点同步取数）RCP47/RSQ68/LOG88/EXP78 拍；vec4 算术12、DP13、短操作3拍，均为 **[待定 G2-07]** 结构预算。

顶点程序必须实现 MV/P、逆转置法线、NORMALIZE/RESCALE_NORMAL、方向/位置光、spot、衰减、ambient/diffuse/specular/emission、shininess 0..128、双面材质、两套完整纹理矩阵、用户面距离与雾。驱动可折叠不可变常量，但必须保持对应数值语义。

### 2.5 裁剪、投影、分块

三角形必须依次按 x+w、w−x、y+w、w−y、z+w、w−z 和启用的用户面距离裁剪；距离 ≥0 为内侧。交点每属性必须使用对称式 `(a*d_b−b*d_a)/(d_b−d_a)`；共享边两遍历方向必须得到相同结果。具体交点舍入序列 **[待定 G2-07]**，初值完整中间积后 FP32 舍入。裁剪前必须保存 flat 的原图元 provoking color；裁后多边形按扇形拆分。不得沿用 v0.6 的 W_NEAR/保护带代替标准六面。

透视除法后必须映射 `sx=16*(VPx+VPw*(X/W+1)/2)`，`sy=16*(VPy+VPh*(1−Y/W)/2)`，一次量化到 Q4；深度必须为 `near+(far−near)*(Z/W+1)/2`。驱动必须将 GL 左下坐标转换为内部左上坐标，front face 判定必须保持公开 API 定义。不得用饱和屏幕坐标制造边。

bin 必须覆盖裁后图元 bbox 与目标/scissor 相交的 64×64 tile，边界 tile 必须只写有效像素。索引变换 cache 和 tile 顶点 cache 初值各 64 项×64 B、身份包含 draw 输出状态，命中不得混用不同状态。跨 tile 的 setup 必须读取同一组裁后顶点并使用相同源锚点。

### 2.6 setup 与插值的精度规则

以下 R 表示最近舍入、恰好半数时远离零；它用于整数块浮点，与 FP32 RNE 分开。未写 R 的乘加必须完整扩展，不截断、不饱和、不回绕。N48(m,e) 必须把 `m*2^e` 舍入为 signed48 尾数与 signed10 指数，0 记 (0,0)；舍入进位必须重新规格化一次。

1. 面积必须由 Q4 屏幕坐标的精确整数边函数计算；正面积排序后，以 `anchor=(64*floor(min(sx)/1024),64*floor(min(sy)/1024))` 为规范源锚点。锚点不得随 tile/scissor 改变。
2. 面积倒数必须保留指数：`k=floor(log2(A))`，m 为 [1,2) Q31，64 项共享 RCP 种子转换 Q31，再做两次 `y=R(y*(2*2^31−R(m*y/2^31))/2^31)`；倒数物理值 `y*2^(−31−k)`。不得先把小 1/A 量化为固定 Q31。
3. 每属性顶点必须先 N48，取最大指数对齐，得到 v0/v1/v2，令 d1=v1−v0、d2=v2−v0；dx1/dy1、dx2/dy2 为相对顶点 Q4 差。分子 `nx=d1*dy2−d2*dy1`、`ny=dx1*d2−dx2*d1` 必须保留完整 signed82，再 N48；不得在相减前分别截去乘积低位。
4. gx/gy 必须分别为分子 N48（指数加 4，梯度单位为每像素）乘面积倒数再 N48。两个块浮点数相加必须以 `max(ea,eb)−3` 对齐、R 后相加再 N48；乘法必须先完整积再 N48。
5. 在锚点像素中心求 `S=v0+gx*(16*ax+8−sx0)/16+gy*(16*ay+8−sy0)/16`，必须按先 x/y 局部乘积 N48、相加 N48、再加 v0 N48 的次序。S/gx/gy 必须在源锚点选同一指数 e，最近舍入为 signed48；舍入溢出时 e 加1后重新量化。
6. 每 tile 重建必须得到相同 `(S,gx,gy,e)`；tile 原点 `(tx,ty)` 必须只作整数 `S'=S+(tx−ax)*gx+(ty−ay)*gy`。S' 与像素累加必须保留 signed60；gx/gy/e 不得逐 tile 重量化。平面只在片上在途存储，不得写 DDR 平面表。
7. 像素值必须为 `T=S'+(x−tx)*gx+(y−ty)*gy`，物理值 `T*2^e`。逐行/逐 lane 增量计算必须与直接求值逐位相同。重定位和步进不得再舍入。helper 像素同样求值。
8. 深度、RGBA、fog 必须按屏幕线性规则插值；纹理必须独立处理 `s_j/w,t_j/w,q_j/w`，取 `s_j/q_j,t_j/q_j`。q0=q1=1 时可共用 1/w；必须保留一般两分母能力。
9. 透视后归一化算术初值沿用 v0.6 §2.13 第8–12条的18位幅值、signed10指数、3保护位对齐、倒数和每次 N 舍入位置，输入平面改为上述 T/e；Q8 UV 输出不得饱和。0 分母、负分母必须按冻结后的算术契约处理，不得新增透明丢弃。与 FP32 的完整精度衔接 **[待定 G2-07]**。
10. LOD 必须在屏幕偶数对齐 2×2 组计算；覆盖组内四 helper 均参与，包括目标/scissor 外点。必须取四对相邻像素的 U/V 差绝对值最大值作为跨度，按 v0.6 Q16 差分和 Q8 log2 表定义计算。深度/颜色输出必须在指定输出点量化到目标位宽；D16 必须把归一化 Z 乘65535后最近舍入，RGBA8 必须把归一化通道乘255后最近舍入，再夹至合法区间；D24 对应乘2^24−1。

setup 必须为4乘法池、9三角形在途、每三角形最多4活动属性；3宽+3窄规格化口、3加法口、每拍1输入行/1输出行。scratch 初值72个独立92位 bank；具体字段/地址与捕获时序 **[待定 G2-08]**。能力必须容纳一般纹理投影和双面所需属性；11/16属性仅是性能计费样本，不得删除完整 ES 属性。

### 2.7 光栅、点线和覆盖

像素中心必须为 `(16x+8,16y+8)`；边函数必须为 `(bx−ax)*(py−ay)−(by−ay)*(px−ax)`。正面积三角形三边均 >0，或 =0 且为 top-left 边时覆盖；top-left 必须为 by<ay 或 by=ay 且 bx>ax。面积0必须丢弃。共享边必须恰好覆盖一次。

双 lane 必须只改变服务率，不得改变 primitive 顺序。线必须采用 diamond-exit 和半开终点，strip 共享端点不得重复 blend/stencil；Z 沿屏幕线性、纹理沿线透视。点必须先按中心裁剪再展开，sprite 两单元 COORD_REPLACE 必须独立。smooth 点/线覆盖因子必须乘入 alpha；精确覆盖量化公式 **[待定 G2-09]**，初值专用 width1 覆盖发生器，不能用普通两三角矩形代替 diamond-exit。

### 2.8 纹理、cache 与 LOD

内部纹理格式必须支持 A8、L8、LA88、RGB565、RGBA4444、RGBA5551、RGB8、RGBA8；base format 必须独立保留。A 展开为 (1,1,1,A)，L 为 (L,L,L,1)，LA 为 (L,L,L,A)，RGB 无 alpha 时为1。低位宽颜色必须按位复制展开到8位，过滤必须作用于未预乘 RGBA。

每 mip 必须支持1×1起 POT 图像和完整级链；每级尺寸 max(1,base>>level)，border=0。REPEAT 必须在每一级按尺寸取模，CLAMP_TO_EDGE 必须在过滤 tap 寻址时夹边。MIN 六模式为 NEAREST、LINEAR 及其 NEAREST_MIPMAP_NEAREST、LINEAR_MIPMAP_NEAREST、NEAREST_MIPMAP_LINEAR、LINEAR_MIPMAP_LINEAR；MAG 为 NEAREST/LINEAR。

坐标必须先乘该级尺寸并转换至 Q8 纹素单位。nearest 必须取 floor(u)；linear 必须减半纹素，再按 Q8 小数生成四权重，以 R(sum/65536) 逐 RGBA 过滤。跨 mip linear 必须按 Q8 小数 R((a*(256−f)+b*f)/256)。mip-nearest 必须取最近级而非一律 floor。MIN/MAG 必须先用未夹至非负值的 λ 判定：MAG=LINEAR 且 MIN 为 NEAREST_MIPMAP_NEAREST 或 NEAREST_MIPMAP_LINEAR 时 c=0.5，否则 c=0；λ≤c 必须使用 level0 的 MAG，其余必须使用 MIN。精确 Q8 计算与 mip tie **[待定 G2-10]**，初值 mip-nearest 采用 ceil(λ+0.5)−1 并夹至合法级。两套一般 q 必须分别计算坐标和 LOD。

texture cache 必须只缓存 DDR texture 对象，默认64 KiB，可配128/192 KiB；不得继续使用旧版两半常驻纹理 RAM 语义。一个采样器必须先 texture0/env0，再 texture1/env1，disabled stage 必须跳过；反馈必须保存 PRIMARY/PREVIOUS 和阶段身份。cache refill/eviction 不得改变输出；更新同一纹理前驱动必须等待此前采样者退休，再使旧行失效。line/组相联、四 bank 交织、miss 合并和 RGB8/32位端口布局 **[待定 G2-10]**，初值四 bank、64 B line、4-way。不得因 miss 或合法大纹理改用低质量纹理。

### 2.9 纹理环境、雾和像素运算

每 stage 必须支持 MODULATE/REPLACE/DECAL/BLEND/ADD/COMBINE，并依 base format 保留不参与的颜色/alpha。COMBINE 必须支持独立 RGB/alpha sources TEXTURE/CONSTANT/PRIMARY_COLOR/PREVIOUS、合法 operand 与反相、scale1/2/4；运算必须包括 REPLACE/MODULATE/ADD/ADD_SIGNED/INTERPOLATE/SUBTRACT、RGB DOT3_RGB/DOT3_RGBA。中间与输出夹取、舍入初值为8位 UNORM 与 v0.6 d(a*b)；完整运算表 **[待定 G2-11]**，必须逐项按 ES §3.7.12 冻结。

令 C/A 为前一stage颜色/alpha，T/B 为纹理颜色/alpha，K 为环境常量；PRIMARY 必须为原插值颜色，stage0 的 PREVIOUS 必须为 PRIMARY。传统五种环境必须按base format更新实际通道（L/LA视为含RGB，A-only不含RGB）；COMBINE必须使用格式展开后的完整RGBA。结果必须夹至[0,1]。

| 环境 | RGB | alpha |
|---|---|---|
| REPLACE | 含RGB时T，否则C | 含alpha时B，否则A |
| MODULATE | 含RGB时C*T，否则C | 含alpha时A*B，否则A |
| ADD | 含RGB时C+T，否则C | 含alpha时A*B，否则A |
| BLEND | 含RGB时C*(1−T)+K*T，否则C | 含alpha时A*B，否则A |
| DECAL | RGB纹理为T，RGBA纹理为C*(1−B)+T*B | A；其他base format按ES规定的未定义语义，不额外承诺输出 |
| COMBINE | 按合法RGB source/operand构造a0/a1/a2再运算 | 按合法alpha source/operand构造b0/b1/b2再运算 |

COMBINE 的表达式必须分别为REPLACE=a0、MODULATE=a0*a1、ADD=a0+a1、ADD_SIGNED=a0+a1−0.5、INTERPOLATE=a0*a2+a1*(1−a2)、SUBTRACT=a0−a1；alpha同形。DOT3必须为4*sum((a0.rgb−0.5)*(a1.rgb−0.5))，广播至RGB；DOT3_RGBA还必须广播alpha并忽略独立alpha表达式。合法RGB operand必须支持SRC_COLOR/ONE_MINUS_SRC_COLOR/SRC_ALPHA/ONE_MINUS_SRC_ALPHA，alpha operand只取后两者；相应scale后必须夹取。实际8位整数舍入/tie仍按G2-11定稿。

雾因子必须在顶点按 abs(ze) 计算并夹到[0,1]：LINEAR=(end−d)/(end−start)，EXP=exp(−density*d)，EXP2=exp(−(density*d)^2)。插值后必须在两纹理环境之后执行 `RGB=f*C+(1−f)*fogRGB`，alpha 不变。

像素必须按以下顺序串行等效：

1. coverage/scissor/目标范围；texture0/env0→texture1/env1→fog→smooth coverage alpha。
2. alpha test（NEVER/LESS/EQUAL/LEQUAL/GREATER/NOTEQUAL/GEQUAL/ALWAYS）。alpha=0 不得无条件丢弃。
3. stencil test：`ref&readmask` 与 `stored&readmask` 比较；失败执行 sfail 并结束。
4. depth test（同8函数）；失败执行 zfail，通过执行 zpass。disabled depth 必须视为通过并禁止写深度；enabled 时 depth mask 控制写入。
5. stencil KEEP/ZERO/REPLACE/INCR/DECR/INVERT，INCR/DECR必须饱和；写入必须受 write mask 控制。
6. logic op 关闭时按合法源/目的 BlendFunc 相加、夹取；必须支持 ZERO/ONE、SRC/DST_COLOR及反相、SRC/DST_ALPHA及反相、源 SRC_ALPHA_SATURATE。无目标 alpha 时 Da=1，SATURATE 的 alpha 因子=1；不得沿用 v0.6 的因子集合替代缺失项。
7. 转换至目标表示后执行16种 logic op：CLEAR/AND/AND_REVERSE/COPY/AND_INVERTED/NOOP/XOR/OR/NOR/EQUIV/INVERT/OR_REVERSE/COPY_INVERTED/OR_INVERTED/NAND/SET；logic 开启必须旁路 blend。dither 初值恒等，但 enable 必须保存/查询且默认开启。
8. RGBA 各通道 mask 合并旧存储值。RGB565 的 A mask 无写效果。连续同像素/同目标字的 RMW 必须保持上述顺序。

PolygonOffset 必须在深度比较前加 `max(abs(dz/dx),abs(dz/dy))*factor+r*units`；r 初值 D16 的1/65535、D24 的1/(2^24−1)，精确量化 **[待定 G2-11]**。clear 必须遵守 scissor、RGBA/depth/stencil mask，且必须保留未写通道。

### 2.10 tile load/store、ReadPixels 与可选功能

每个物化区间必须按命令顺序处理 tile；保留目标时必须 load 旧 C/D/S，clear 只可替代其实际覆盖且允许写入的位。store 必须写出后续提交需要的 C/D/S，不能仅写颜色而丢失后续使用的 D/S。RGB565/D16/S8 每像素5 B；完整保留区间读写共10 B/像素。

ReadPixels/CopyTex/Finish 必须先使此前相关 tile 和最后写响应完成。RGBA/UNSIGNED_BYTE 读回 RGB565 必须位复制展开且 alpha=255；pack alignment 必须支持1/2/4/8，按 GL 左下行序输出。驱动必须执行 BSP 一致性操作；Flush 只保证提交，Finish 必须等待此前全部工作退休。

quad 快通道、后处理 AA 可配置，默认必须关闭。对象运动/碰撞必须由驱动执行。quad 初值只服务屏幕1:1 nearest，不得改变 ES 点/线/三角形语义；AA 初值沿用 v0.6 五点规则，但 tile 邻域必须来自同一原始目标，halo/物化次序 **[待定 G2-12]**。AA 不得作为 MSAA 报告。

## 3. 接口

标准 AXI256/APB 协议必须引用 edrv32-soc-spec §4.2/4.3，连接必须引用 gpu-soc-spec §3–6。下列所有总线端口处于 clk_gpu；AXI 地址32位、数据256位、WSTRB32位，ID宽度 **[待定 G2-03]** 初值按 SoC AXI256 原定义。

| 信号 | 方向 | 位宽 | 时钟域 | 说明 |
|---|---|---|---|---|
| clk_gpu_i/rst_gpu_n_i | in/in | 1/1 | gpu | 时钟、同步释放低有效复位 |
| s_apb_paddr_i/pwdata_i/prdata_o | in/in/out | 32/32/32 | gpu | 字节地址、写数据、读数据 |
| s_apb_psel_i/penable_i/pwrite_i | in | 各1 | gpu | APB 请求 |
| s_apb_pready_o/pslverr_o | out | 各1 | gpu | 本地寄存响应；不扩展错误集合 |
| m_axi_araddr_o/awaddr_o | out | 各32 | gpu | 读/写地址，经 X9 到 mem_xbar P3 |
| m_axi_arlen_o/awlen_o | out | 各8 | gpu | INCR 突发长度 |
| m_axi_arsize_o/awsize_o | out | 各3 | gpu | 初值5，即每beat32 B |
| m_axi_arburst_o/awburst_o | out | 各2 | gpu | 必须为 INCR |
| m_axi_arid_o/awid_o/rid_i/bid_i | out/out/in/in | SoC规定 | gpu | 事务身份 |
| m_axi_arvalid_o/arready_i、awvalid_o/awready_i | out/in | 各1 | gpu | 地址握手 |
| m_axi_rdata_i/rresp_i/rlast_i/rvalid_i/rready_o | in/in/in/in/out | 256/2/1/1/1 | gpu | 读响应 |
| m_axi_wdata_o/wstrb_o/wlast_o/wvalid_o/wready_i | out/out/out/out/in | 256/32/1/1/1 | gpu | 写数据 |
| m_axi_bresp_i/bvalid_i/bready_o | in/in/out | 2/1/1 | gpu | 写响应 |
| irq_o | out | 1 | gpu→sys | OR(IRQ_STAT & IRQ_EN)，X3→PLIC13 |

外部256位要求必须在 mem_xbar 边界满足，不能用内部窄打包口的峰值替代。内部按字段 bank 存储和传送，不要求所有记录用整宽流水总线。

## 4. 寄存器

公共寄存器必须沿用 edrv32-soc-spec §7.1；下列私有分配和 VERSION 为 **[待定 G2-03]** 初值。所有 RW 控制复位为0；数据 RAM 不复位。

| 偏移 | 名称 | 访问 | 复位 | 位域/行为 |
|---|---|---|---|---|
| 0x000 | ID | RO | 0x0006_0200（初值） | TYPE=6、VERSION=0x0200 |
| 0x004–0x07C | 公共引擎寄存器 | 按SoC | 按SoC | CTRL/STATUS/IRQ/DESC/DOORBELL/DONE_COUNT/PERF 等按公共表，不重分配 |
| 0x100/104 | SLOT0_DESC/SLOT1_DESC | RW | 0 | 两槽 DDR 描述符地址 |
| 0x108 | SLOT_STATUS | RO | 0 | 初值每槽2位：FREE/BUILD/READY/RENDER；完成回FREE |
| 0x10C | RETIRED_FRAME | RO | 0 | 最近已完成目标写响应的 frame_id |
| 0x110 | MATERIALIZED_SEQ | RO | 0 | 最近完成物化的序列号 |
| 0x114 | CAPS | RO | 参数值 | 初值打包目标格式、MAX_TEXTURE_SIZE、quad/AA能力 |

PERF[0..15] 初值：busy、变换顶点、裁后非退化三角形、tile引用、通过像素、纹理miss、DDR读等待、DDR写等待、顶点周期、setup周期、光栅周期、纹理周期、物化周期、输入cache miss、tile顶点cache miss、0。PERF 必须按 SoC 事件寄存一拍后计数、按位宽回绕；功能完成序号不得以 PERF 替代。

## 5. 行为与时序

槽必须按 FREE→BUILD→READY→RENDER→FREE 工作。BIN_SEAL 必须等待本槽几何/bin 写响应；像素侧必须只读 READY/RENDER 槽。N 像素读槽 A 时，N+1 几何可写槽 B；不得复制顶点/setup/纹理算术 lane。M-9 下 setup 属于 tile 消费侧，必须在像素处理前为每引用重建；不能沿用旧 M-7 把每源 setup 预写 DDR 的时序。

帧完成必须在最后 tile 消费且目标最后 B 响应后发布；槽不得在几何完成时回收。每槽必须持有 bin、顶点、索引和状态版本，容量按实际裁剪扩增和 draw 数分配，平面表容量必须为0。命令和状态更新必须保持串行可见结果。双槽资源调度/同帧 setup 与像素的交叠 **[待定 G2-08]**。

顶点输入可在几何读完后释放；变换后顶点和状态必须保留到本槽消费结束。纹理更新/删除/复用前必须等待最后采样者退休，初值由驱动等待，不要求隐式复制。客户端数组必须在延迟执行期间快照或保持稳定。跨帧像素依赖必须按原 GL 顺序等待。

ABORT 必须停止取新命令，等已发 AXI 事务完成后回 IDLE；目标内容不保证。新列表 DONE 必须等待全部命令及其写响应完成。复位只清控制状态，不定义数据 RAM 初始图像。

## 6. 错误处理

仅下表列出的命令执行边界错误必须上报；驱动必须负责 ES 参数错误，内部单元不得重复检查已保证的契约。错误编码为 **[待定 G2-03]** 初值。

| ERR_CODE | 错误 | 检测边界 | 上报/恢复 |
|---|---|---|---|
| 1 | 未定义 opcode（含配置关闭的可选命令） | 命令解码 | ERROR，停止取命令，排空已发事务；由软件 ABORT/重新提交恢复 |
| 2 | AXI 非 OKAY | 命令 DMA/读写完成边界 | ERROR，停止执行，已发事务必须完成；恢复同上 |

格式长度/程序容量/区域容量等检查尚未获架构定义，初值由合法命令契约保证；本草稿不增加越界、超时、校验和、watchdog 或自动降级路径。v0.6 TEX_LOAD/纹理 RAM 越界错误不适用于 DDR texture cache。

## 7. 性能与资源指标

单元目标必须在150 MHz、输入/输出无背压、12context稳态、D1（1方向灯+NORMALIZE+两套单位纹理）下测量：顶点≥5.0M顶点/s，11属性 setup≥5.0M次/s。setup 必须测每 tile 重建服务率；不得把该值称为源三角形持续5M/s。D8/G8不承诺同速。

| 参数 | 小配置初值 | 性能档（默认） | 满配初值 |
|---|---:|---:|---:|
| TILE_W/H、EXTERNAL_BITS | 64/64、256 | 64/64、256 | 64/64、256 |
| VERTEX_LANES/CONTEXTS | 4/12 | 4/12 | 4/12 |
| SETUP 配置 | 4池/9在途 | 4池/9在途 | 4池/9在途 |
| TEXTURE_CACHE_KIB | 64 | 64 | 192 |
| MAX_TEXTURE_SIZE | 64 | 256 | 256 |
| COLOR_BITS/DEPTH_BITS/STENCIL_BITS | 16/16/8 | 16/16/8 | 32/24/8 |
| QUAD_ENABLE、POST_AA_ENABLE | 0、0 | 0、0 | 初值0、0；各可选1 |
| FRAME_SLOTS、RASTER_LANES | 2、2 | 2、2 | 2、2 |
| 顶点/RF/程序 | FP32、32vec4/context、1024行 | 同左 | 同左 |

可配置项必须限于 TEXTURE_CACHE_KIB={64,128,192}、MAX_TEXTURE_SIZE={64,256}、目标格式组合、QUAD_ENABLE、POST_AA_ENABLE；其余本轮固定。VERTEX_CONTEXTS 是程序存储形状的派生来源，初值固定12；是否保留为综合参数 **[待定 G2-06]**。三档为 **[待定 G2-12]** 推荐初值，不能将 M-7 W2 小档旧吞吐移植到本表。

| 条件/配置 | 资源/吞吐/帧时间（全部为估算） |
|---|---|
| 小/性能档，quad/AA关 | GPU LUT55557/FF55724/APM151/DRM219/LUTRAM6519；小档相同数据通路，未计限制纹理尺寸的节省 |
| 满配，quad/AA关 | LUT55557/FF55724/APM151/DRM254/LR6519；=性能档+32 DRM cache+3 DRM目标，控制/宽目标附加逻辑尚待估算 |
| 单元 D1 顶点/11属性setup @150/200 | 29.75/29.713725拍；5.042/5.048 M/s @150，6.723/6.731 @200；setup 首包199拍，非逐项固定II |
| 16属性setup | 43.070588拍，3.483M/s@150；一般更大属性数必须另测 |
| 单纹理/双纹理双线性 | 初值2/1 pixel/拍；三线性1/.5；复杂双COMBINE可低至约.25，均须测量 |
| 性能档，v=1冷tile读取，1k/5k/10k | 6.934/8.163/10.565ms@150；5.546/6.775/8.960ms@200 |
| 性能档，v=3独立三角形，1k/5k/10k | 7.101/8.996/16.198ms@150；5.712/7.608/13.601ms@200 |
| 小/满配相同fixture | 小档相同纹理都≤64时可沿用性能档估算；满配清帧仅颜色store增加460800B/1.5GB/s=0.3072ms，cache miss固定时；不得据此推定真实miss改善 |

估算输入必须明确：640×360、清帧、11属性、f=R/T=1.634、v=V/T为1或3、GPU可用合计读写带宽1.5GB/s、W256效率η=.55、F=717910片元、纹理miss=.10、16B/片元×miss、颜色写460800B。M-9原式 `b=128v+64λ+8f+i`，冷λ=3f、i=6(mesh)/0(独立)，得460.800/710.800 B/T；实际新增索引表/段头与格式扩展必须另收，不得将其忽略项当测量值。

规划帧模型初值 `G=T*(29.75v+29.713725f+11f)+199`、`P=F+115200`、`D=(T*b+460800+16F*miss)/Be`，`Be=min(B,fclk*32*.55)`；帧时间=max(G,P)/fclk+D，串行首帧=(G+P)/fclk+D，理想下界=max(G/fclk,P/fclk,D)。M-9 中跨帧/阶段交叠尚属模型，须按§5实际调度重算。

性能档冷mesh几何roofline约3.089M源三角形/s@150，独立三角形1.681M/s；不得宣称全帧或任意独立三角形5M/s。满配未选11拍专用setup，不得套用fast-ideal结果。资源估算约±40%，LUTRAM包含于LUT，不能重复相加；GPU基线外的SoC资源、CLMA/CLMS列拥塞、W256仲裁、实际PDS时序 **[待定 G2-01/G2-12]**。

## 8. 验证要点

必须按配套验证方案逐条覆盖 F01–F20、原生命令所有字段、顶点 ISA/SFU、六面+用户面、source48/整数重定位、top-left/diamond-exit、两纹理投影与cache、完整像素顺序、tile load/store、ReadPixels、双槽、APB/AXI及§6错误。RTL/Python必须逐位一致；Mesa帧比较必须使用验证方案规定的逐类容差。性能必须分单元稳态、DDR服务、首帧、跨帧间隔与整帧报告，不能互相替代。

## 9. 待定事项

每个编号为一项定稿包；正文同编号的多个标记合并计数，共12项。初值为开发/评审输入，未经定稿不得宣称完整一致性通过。

| 编号 | 事项与推荐初值 | 定稿数据/时机 |
|---|---|---|
| G2-01 | 200MHz设计/150保底、W256有效η=.55、GPU份额1.5GB/s | PDS小探针→整片P&R→板测 |
| G2-02 | 公开范围：viewport1280×720、point/line[1,1]、桌面函数集合见2.1 | API清单/点线模型完成、驱动Task前 |
| G2-03 | 原生命令/状态包/寄存器/AXI ID/错误编码初值见2.2/3/4/6 | 驱动与模型联合评审，RTL并行前 |
| G2-04 | 64B十一属性主记录；一般q/双面用32B扩展提案，保持FP32 | 全ES状态字段枚举和跨tile逐位模型、bin RTL前 |
| G2-05 | 4B bin源ID、32B段头、三索引表、64B以上聚合 | 格式原型和实际DDR字节计数、bin RTL前 |
| G2-06 | 1024×(64+控制)；控制初值12×8，总160有效位/5DRM | 静态排程编码、所有状态容量验证、顶点RTL前 |
| G2-07 | FP32特殊值/clip/透视精度衔接与SFU时序初值见2.4–2.6 | 数值模型和FP32/SFU探针；算术RTL前 |
| G2-08 | setup72×92bank、4池9在途、tile侧setup与双槽调度 | RAM端口逐拍原型/PDS/周期模拟、setup/bin接口冻结前 |
| G2-09 | width1 diamond-exit、smooth覆盖量化 | 点线参考模型对ES定义/Mesa，光栅RTL前 |
| G2-10 | texture四bank/64B line/4way、MIN/MAG门限 | 纹理模型与cache探针，纹理RTL前 |
| G2-11 | env8位UNORM运算表、偏移r与量化 | 像素逐位模型/定向API图，像素RTL前 |
| G2-12 | 三档/可选quad-AA资源、halo与帧预算 | 主路径完整后测量；可选功能Task前决定启用范围 |

## 10. 变更记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-11-27 | v0.1 | 按M-9推荐起草分块/W256/无平面表，沿用M-8 vec4与4池9在途算术；列出待定字段、验证及实施接口；未修改v0.6。协调者确认12上下文程序行宽按64位指令+待定控制、160有效位初值表述 |
