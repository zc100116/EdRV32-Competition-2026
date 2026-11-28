# GPU v2 验证方案

| 项 | 内容 |
|---|---|
| 版本 / 日期 | v0.1 / 2026-11-27 |
| 状态 | 草案；仅为验证工作设计，未声称已运行或通过 |
| 对应规格 | docs/spec/gpu-v2-spec.md v0.1 |
| 依据 | GPU v2 架构 M-5/M-6/M-8 数值语料、M-9 流量模型；gpu-spec v0.6 §2.13；ES 1.1.12 |

## 1. 验证对象和范围

必须验证 GPU v2 的全部原生命令、状态、FP32 顶点/SFU、裁剪、bin、source48 setup、双lane覆盖、纹理cache、双纹理env、雾、像素、tile load/store、双槽、APB/AXI、驱动和已公布的桌面兼容入口。RTL必须与 Python v2 逐位比较；公开 API 必须与 Mesa 软件渲染和定向解析结果比较。

GPU模块验证负责命令至DDR目标的可见结果与事务；SoC层负责APB/AXI异步桥、P3竞争、PLIC13、BSP cache维护、DISP读目标和上板帧时间。不得以单元无背压吞吐替代SoC性能。桌面兼容只按最终公布函数集合验证；可选功能仅在开启构建中验证，默认关闭行为必须覆盖。

本方案覆盖规格§1–8的行为与数值条款；§9是待定记录、§10是历史，不构成硬件测试行为。待定项定稿后，协调者必须把最终编码/量化数据填入对应测试项；验证worker不得自行补充另一套硬件行为。

## 2. 验证环境

| 层级 | 环境/结构 | 参考与观测 |
|---|---|---|
| 单元 | Verilator5 --timing，SV自检TB；必要四态/复位用Icarus | 顶点指令/结果、SFU请求/返回、setup行、覆盖mask、cache返回、像素写入逐项记分 |
| GPU模块 | 命令DDR镜像+APB BFM+AXI256存储模型，可控合法背压 | Python v2执行相同列表，逐位比目标、顶点/bin与物化输出；事务计数 |
| PC软件 | 同一API fixture在PC模拟器v2与Mesa EGL ES1上下文执行 | ReadPixels图像、API错误/查询、GL状态、driver命令跟踪 |
| SoC | CPU软件+BSP+存储/显示模型，独立验证worker | SIM_EXIT、UART、IRQ、DDR最终字节和DISP读取 |
| Windows | PDS小探针/全GPU/整片，用户GUI+Windows Codex | 时序/层次资源/IP行为；上板串口与显示/读回 |

所有新增测试必须进入tools/regress.py统一入口，每目录提供test.yaml/files.f；输出PASS/FAIL与退出码。worker必须-j 1，同一时刻只跑一个仿真；超过60秒的单项进入full。生成物放build/，必须记录输入commit、工具版本、参数、种子、命令及原始日志位置，不计算文件哈希。

Mesa应使用明确启用gles1的构建、EGL_OPENGL_ES_API、client version1、与待测目标相同的RGB565/D16/S8配置及无MSAA上下文；环境必须明确选择软件驱动并记录GL_VENDOR/RENDERER/VERSION，不能把硬件结果作为软件参考。[Mesa EGL文档](https://docs.mesa3d.org/egl.html)说明gles1构建选项及libGLESv1_CM，[LLVMpipe文档](https://docs.mesa3d.org/drivers/llvmpipe.html)给出软件光栅器背景。最终Mesa commit/构建及EGL平台 **[待定 V2-01]**，推荐llvmpipe、surfaceless pbuffer；若运行环境未提供ES1上下文，必须明确失败并补齐环境。

### 2.1 piglit实际源码枚举

2026-11-27通过上游[GitLab API](https://gitlab.freedesktop.org/api/v4/projects/mesa%2Fpiglit/repository/archive.tar.gz?sha=fb2884b0835a25a1bd53f1163858c653d8b1c06d)取得完整源码归档，在内存枚举所有CMakeLists.gles1.txt。上游commit为`fb2884b0835a25a1bd53f1163858c653d8b1c06d`；下表是源码提供的GLES1构建目标，不代表本仓库已经编译/运行。源码树没有独立tests/gles1.py测试全集；不能凭空列出“全部GLES1 piglit均已覆盖”。

| 编号 | 实际构建目标 | 上游目录（tests/spec/下） | 本任务处理 |
|---|---|---|---|
| PG01 | arb_point_sprite-checkerboard_gles1 | arb_point_sprite | 必跑，GLES路径使用GL_OES_point_sprite |
| PG02 | oes_compressed_paletted_texture-api | oes_compressed_paletted_texture | 必跑，覆盖必须提供的上传扩展 |
| PG03 | oes_fixed_point-attribute-arrays | oes_fixed_point | 核心fixed数组必须测；上游扩展名检查见下文 |
| PG04 | oes_matrix_get-api | oes_matrix_get | matrix-get属于ES1.1核心增加项，必须测；上游扩展名检查见下文 |
| PG05 | oes_compressed_etc1_rgb8_texture-basic | oes_compressed_etc1_rgb8_texture | ETC1不在本轮目标，未公布时不适用 |
| PG06 | oes_packed_depth_stencil-depth-stencil-texture_gles1 | ext_packed_depth_stencil | depth texture/FBO扩展不在目标；不能用它代替内部D24S8测试 |
| PG07 | oes_draw_texture | oes_draw_texture | OES_draw_texture不在目标，未公布时不适用 |
| PG08 | ext_image_dma_buf_import-invalid_hints | ext_image_dma_buf_import | EGL/DRM扩展不在目标，不适用 |
| PG09 | ext_image_dma_buf_import-invalid_attributes | 同上 | 同上 |
| PG10 | ext_image_dma_buf_import-missing_attributes | 同上 | 同上 |
| PG11 | ext_image_dma_buf_import-ownership_transfer | 同上 | 同上 |
| PG12 | ext_image_dma_buf_import-unsupported_format | 同上 | 同上 |
| PG13 | ext_image_dma_buf_import-intel_external_sampler_only | 同上 | 同上 |

另有tests/util/CMakeLists.gles1.txt，仅构建piglitutil_gles1库，不是测试。PG08–13受PIGLIT_BUILD_DMA_BUF_TESTS条件控制。源码出处：[point sprite](https://gitlab.freedesktop.org/mesa/piglit/-/blob/fb2884b0835a25a1bd53f1163858c653d8b1c06d/tests/spec/arb_point_sprite/CMakeLists.gles1.txt)、[paletted](https://gitlab.freedesktop.org/mesa/piglit/-/blob/fb2884b0835a25a1bd53f1163858c653d8b1c06d/tests/spec/oes_compressed_paletted_texture/CMakeLists.gles1.txt)、[fixed](https://gitlab.freedesktop.org/mesa/piglit/-/blob/fb2884b0835a25a1bd53f1163858c653d8b1c06d/tests/spec/oes_fixed_point/CMakeLists.gles1.txt)。

复现枚举应使用同commit源码的`rg --files | rg 'CMakeLists.gles1.txt$'`，再读取各文件的piglit_add_executable行及对应C源码的supports_gl_es_version/require_extension。未来构建命令初值`cmake -S <piglit> -B build/piglit -DPIGLIT_BUILD_GLES1_TESTS=ON`，执行PG01–04时使用各目标的`-auto`；参数以锁定commit源码为准。PG03/PG04源码分别要求GL_OES_fixed_point/GL_OES_matrix_get字符串；ES1.1将其子集纳入核心，扩展名不是必报。若原用例因别名未公布而SKIP，必须单列原结果，并以自有核心入口fixture验证相同行为；不得为通过测试虚报扩展。PG04的matrix-as-int-bits查询必须按ES1.1 §6.1.2覆盖。完整GLES1 API、8灯、COMBINE、ReadPixels等缺口必须由下表自有ES fixture覆盖，不能把GL桌面测试直接算作GLES1结果。

## 3. 测试项清单

每项必须细分至字段/枚举/边界组合，不得只检查“图像非黑”。表内“逐位”均指Python v2；M代表Mesa同API流；A代表独立解析结果。s/f/p分别为smoke/full/perf。

| 编号 | 规格条款 | 测试内容 | 激励方法 | 检查方法 | 档位 |
|---|---|---|---|---|---|
| VT01 | §1、§3、§4 | 时钟/复位、APB各寄存器访问/复位/IRQ、ID/CAPS、私有槽状态、PERF一拍统计 | 定向BFM | 逐拍期望；数据RAM不要求复位值 | s/f |
| VT02 | §2.2、§4、§5 | 每opcode和所有头/负载字段；STATE/PROGRAM/CONSTANTS作用范围、默认状态 | 定向+合法随机命令 | 解码模型、最终结果逐位；done不得早于B | s/f |
| VT03 | §2.1 F01/F02、§2.2 | 全数组类型/stride/offset/current、UB/US索引、7图元、flat末顶点、VBO/客户端数组 | API程序、随机小网格 | M/A、驱动命令与Python逐位 | s/f |
| VT04 | §2.4、§2.1 F03/F04 | ISA逐opcode、mask/swizzle/neg/abs、RF边界、2常量读口、FMA/DP舍入 | 定向+M5原14变体128组 | 每指令输出逐位；独立双精度误差 | s/f |
| VT05 | §2.4 | LOOP 1/8灯、CONST_REL stride2/8、展开/循环等价、1024行与12context控制 | 生成合法程序、全部状态 | 物理/SSA/展开输出逐位相等，发射/写回预约无冲突 | f |
| VT06 | §2.4、§2.1 F04/F14 | SFU RCP/RSQ/LOG/EXP小表、两Newton、混合II4、表双读口/与setup并发 | M5/M6原语料+512混合请求 | 逐位与延迟/吞吐；单函数独立解析误差 | s/f/p |
| VT07 | §2.5、§2.1 F05/F06 | 六面+用户面逐面/交线/顶点、共享边反向、完全内外、裁后扇分、平移/viewport/DepthRange/cull | 定向+合法随机 | clip顶点/bin/coverage逐位，M/A；flat裁前颜色 | s/f |
| VT08 | §2.3、§2.5 | 64B逐字段、一般q与双面完整记录、源ID/三索引、bin段头/clear类型/顺序/聚合 | 状态交错、跨64边界、大小图元 | 逐字节期望，实际DDR流量和引用数 | s/f/p |
| VT09 | §2.6 1–7 | source48规格化/倒数/分子抵消/整数重定位、4池9在途/72bank | M5/M6的39三角形、area1/细长/大平移/64边界±1 | 每节点逐位；780原始整数边界恒等式；银行端口预约 | s/f/p |
| VT10 | §2.6 8–10 | 两套projective分母、负/零与近零、Q8输出、四helper、目标/scissor外helper | 原7918探针及一般q/双面新增状态 | UV/Z/RGBA/LOD max/RMS、mip分歧，逐位 | f |
| VT11 | §2.7、§2.1 F02/F06/F07 | top-left共享边/顶点、退化/屏外、lane尾部、diamond-exit、strip/loop端点、smooth点线、sprite | 定向旋转/平移/八象限+API程序 | coverage逐位/A；重复blend/stencil计数；M分类容差 | s/f |
| VT12 | §2.8、§2.1 F08–F12 | 八内部格式/五base format、1/2/4/最大尺寸、所有mip、六MIN/两MAG/两wrap、半纹素、阈值/tie | 定向棋盘/边缘/渐变、随机纹理 | tap地址/权重/输出逐位，M | s/f |
| VT13 | §2.8、§2.5 | cache hit/miss/refill/evict/合并、四bank、跨line、两对象同地址不同版本、更新失效 | 定向冲突流+随机合法背压 | 冷/热cache最终输出相同；miss/字节/顺序逐项检查 | s/f/p |
| VT14 | §2.9、§2.1 F13/F14 | 两stage反馈、disabled stage、base format、所有env/COMBINE合法source/operand/scale、DOT3、三种雾 | 定向真值/边值+API组合 | 各stage逐位，M/A | s/f |
| VT15 | §2.9、§2.1 F15–F17 | alpha/depth/stencil八函数、六操作、全部mask、blend合法因子、16logic、Da=1、alpha0、dither、offset | 全枚举定向+同字连续RMW | 内部事件及最终C/D/S逐位，M/A | s/f |
| VT16 | §2.10、§2.1 F11/F18 | 全/部分clear、保留C/D/S、load/store、masked clear、Read/Copy跨tile、RGBA/565、pack1/2/4/8与行序 | 多物化区间API序列 | DDR与读回逐字节，M；完成必须等B | s/f |
| VT17 | §5、§2.1 F19 | 双槽N/N+1、ready/退休、资源复用、纹理更新/删除、数组快照、Flush/Finish、依赖帧 | 交错序列+随机合法AXI等待 | 与全串行Python相同、槽状态与资源最后引用时刻 | s/f |
| VT18 | §6、§5 | opcode错误、关闭可选opcode、RRESP/BRESP错误、ABORT排空 | 命令边界定向注错 | ERR/IRQ/停止取新命令/已有事务完成；不测规格外错误 | s/f |
| VT19 | §2.1 F19、§2.1限制表 | ES默认状态/Get/Is/对象/API错误/栈限制/查询/无MSAA/OES_read_format | API定向、每个公布入口 | M及ES状态表；必需扩展缺失即失败 | s/f |
| VT20 | §2.1 F20、§2.10 | 驱动对象推进/碰撞；可选quad/AA开关、tile halo/边缘规则 | 同输入CPU参考与可选构建 | 按最终公布功能逐位；AA原图邻域不得递归反馈 | f |
| VT21 | §2.1兼容层、F01–F04/F08/F19 | begin/end、QUADS、display list、TexGen、glOrtho等已公布入口 | 桌面API与对应ES数组流成对 | PC/驱动输出与ES等价，桌面Mesa另比较 | s/f |
| VT22 | §7 | D1顶点/11与16属性setup、点线、单/双纹理、COMBINE最坏服务 | 连续无背压、512三角形，预热后中间256 | 周期计数；5M顶点/次setup每秒；首包另记 | p |
| VT23 | §7、§2.3/2.8、§5 | 1k/5k/10k场景，v/f/λ/miss与共享DDR、首帧/重叠 | M9 fixture及真实索引网格，见4.3 | 周期模拟/RTL/板测同模型逐项对照 | p |
| VT24 | §3–5、§7 | SoC APB/X3/X9/X10、P3竞争、BSP一致性、DISP与目标所有权 | CPU软件+DISP/AUD/CPU并发 | IRQ13/目标内容/事务、PDS/上板报告 | f/p |
| VT25 | F07/F12/F01、§2.1 | piglit PG01/02/03/04 | 锁定源码真实GLES1构建 | PG01/02必须PASS，PG03/04原结果及核心等价fixture按2.1判定；其余按公布扩展归属记录 | f |

## 4. 参考模型

### 4.1 Python v2逐位参考

必须升级tools/gpu/model/，保留旧v0.6入口的可复现性，新增明确v2命令/状态和算术版本。模型必须涵盖FP32逐操作舍入、staged DP、SFU小表、clip交点、完整输出属性、source48重建/60位重定位、top-left/点线、cache可见语义、env/雾/像素、tile与帧槽。RTL和PC模拟器不得以自身执行函数生成期望值。

逐位比较必须包括：每顶点输出/裁后数据、每源锚点S/gx/gy/e、每tile重定位、coverage、helper坐标/LOD、各纹理stage、像素C/D/S、bin与最终DDR/ReadPixels。FP32模型必须显式处理位模式和舍入，不能依赖Python双精度隐式充当FP32。独立双精度解析模型必须保留，用于误差统计；它不替代逐位模型。

必须复用以下原语料，不能删掉超限或underflow样本：

- tools/gpu/study/m5_vertex.py：14变体×128组，种子20261127，G类32组定向可见spot/specular；位置/非整数shininess/双面/两纹理矩阵/雾。
- m6_sfu.py：RCP/RSQ各20000，LOG含近1的20254，EXP20000，pow窄域/广域；广域normal和underflow子集必须分别报告。复合pow约1.03e-5个别误差不得用clamp隐藏。
- m5_setup.py/m6_setup.py/m8_setup.py：39三角形、两分母、7918边界/helper探针、780整数恒等式；area1、近共线、大平移抵消、细长必须保留。相同原始整数边界必须零差异。
- m8_vertex.py：staged/fused抵消例 `(1+2^-23,1,0)·(1−2^-23,−1,0)`；staged为0、fused为−2^-46。v2默认必须匹配staged。

对单操作的约1e-5精度解释必须引用ES §2.1.1，位置/法线至少2^32、颜色/纹理至少2^10；不得把1e-5当整个光照表达式的统一相对阈值。近零抵消必须同时报告绝对误差、非零相对误差与分类，不人为加分母下限。FP32特殊值定稿前结果标未定，不能记为PASS。

### 4.2 Mesa帧比较和容差

同一API命令、状态、输入float/fixed量化、矩阵、纹理、目标格式、viewport/pack参数必须分别送Mesa和PC模拟器。必须关闭MSAA、控制dither状态，并通过ReadPixels比较同一行序。先用固定颜色/无过滤图确认坐标、cull和目标格式，再分组增加功能。

容差初值如下，全部为 **[待定 V2-02]** 的评审建议；它们是互操作回归阈值，不作为Khronos一致性认证结论，也不得放宽RTL/Python零差异要求。

| 分类 | 初值通过规则 |
|---|---|
| API状态/错误、离散模板、pack布局、常量色logic/mask/clear | 必须精确相同；RGB565先转存储整数后比较 |
| 无纹理/nearest且无采样切换边界的内部像素 | 每个目标颜色通道差≤1目标量化单位；默认565为R/B各1个5位码、G1个6位码；RGBA8每通道1 |
| linear/trilinear、光照/雾/blend内部像素 | 量化前RGBA8展开每通道差≤2；须同时报告max/RMS和超限坐标，不用平均值掩盖局部失败 |
| 深度 | 可读内部D16与解析参考差≤1 LSB；比较图只在避开相等测试阈值的fixture应用颜色容差；阈值/offset测试用明确解析期望 |
| 覆盖边界 | 自有精确覆盖模型必须零差异；与Mesa的实现自由差异只在该图元边界0.5像素带单列，记录坐标/计数/原因，不能直接从统计删除；共享边漏画/重复写必须失败 |
| nearest texel/mip或MIN/MAG门限 | 专门fixture精确测门限；与Mesa临界差异须给出原始λ/坐标并按冻结的ES允许范围判定，禁止把任意纹理差异归入边界 |

需要不同容差的fixture必须先由协调者修订本方案；验证worker不得自行增加像素豁免。报告必须同时给出原图、差异图、coverage XOR、max/RMS、最大差像素的状态/属性/tap和分类。

### 4.3 性能模型对照

必须首先复现`python3 -B tools/gpu/study/m9_model.py`；它是现有估算入口，不是v2周期模拟器。未来必须对1k/5k/10k三角形，分别测v≈1索引网格与v=3独立输入；f初值1.634，实际clip放大/大图元f必须另记录。λ必须取真实tile顶点miss/T，v必须取真实输入变换miss/T，不得从原始网格顶点数推定。

必须执行固定片元F=717910和同比过绘F=717910*T/1000两类场景，miss10%/50%（真实trace另列）、GPU带宽1.0/1.5/1.8GB/s、150/200MHz模型点；200MHz板测须以PDS收敛为前提。W256效率初值.55，AXI总读写必须合并统计。ReadPixels/保留D/S/一般q扩展记录/多draw段头必须追加专项负载，不混入普通清帧数字。

必须对照G、P、D的分项周期/字节、lower/planning/serial三种口径，报告首帧延迟和稳定帧间隔。普通tile的setup必须按f次收费，无DDR平面表流量；输入索引表、状态包、段头、扩展记录不得漏计。模型-RTL差异必须按前端、cache、setup银行冲突、像素、总线等待归因；本草稿不设置未经测量的“误差百分比门禁”。精确周期模拟器自身的事件/字节必须与trace一致。

## 5. 覆盖目标

每条规格行为必须至少映射到§3一个测试，枚举集合覆盖必须100%。跨项组合必须覆盖两纹理×一般q×fog×alpha/depth/stencil、clear mask×物化重开、双槽×状态/纹理版本、clip×flat/双面、边界helper×LOD；不得只靠单项开关覆盖宣称完整功能。

| 规格 | 测试闭合 |
|---|---|
| §1时钟/结构 | VT01/08/09/13/17/22/24 |
| §2.1 F01/02/03/04 | VT03/04/05/06/07/21/25 |
| §2.1 F05/06/07 | VT07/10/11/25 |
| §2.1 F08/09/10/11/12 | VT08/12/13/16/25 |
| §2.1 F13/14/15/16/17/18 | VT14/15/16 |
| §2.1 F19/20及限制 | VT01/17/19/20/21 |
| §2.2每条命令/状态/输入字段 | VT02/03/05/08/16/17/18 |
| §2.3全部字段/bin顺序 | VT08/10/17/23 |
| §2.4每ISA/数值规则 | VT04/05/06/22 |
| §2.5每裁剪面/投影/缓存身份 | VT07/08/11/13 |
| §2.6第1–7条、第8–10条及结构 | VT09、VT10、VT09/22 |
| §2.7全部覆盖 | VT11 |
| §2.8格式/过滤/cache | VT12/13 |
| §2.9 env/雾/像素/clear/offset | VT14/15/16 |
| §2.10load/store/读回/可选项 | VT16/17/20 |
| §3每端口/§4每寄存器 | VT01/02/18/24 |
| §5每边界/双槽/ABORT | VT02/16/17/18/24 |
| §6每错误 | VT18 |
| §7每参数组合/性能目标/估算边界 | VT12/20/22/23/24 |
| §8验证要求 | VT01–25及本节映射 |

所有正文待定项必须由G2-01..12登记；关闭项时必须更新测试的具体位编码/期望与本表。各参数值至少一个full构建；默认性能档必须跑全套，可选开关各跑开启和关闭，不要求所有无关参数笛卡尔积。

## 6. 通过判据和回归档位划分

| 档位 | 内容 | 通过判据 |
|---|---|---|
| smoke | 每单元短定向、三角形/纹理/像素/双槽代表流、必要API短用例 | 全部PASS、RTL/Python零位差、无TB协议违例、lint/风格0告警；单项≤约60秒 |
| full | 所有枚举/随机/精度语料、M帧、PG01–04、参数/可选构建、SoC | smoke通过、每项覆盖完整；M按冻结容差通过；必需用例不得以SKIP记通过 |
| perf | 单元无背压、1k/5k/10k、共享DDR/上板 | §7的5M顶点/s和5M setup次/s目标达成；分项模型/测量口径完整；实际帧时间与资源据实报告 |

PDS必须分别给200/150MHz时序、资源向量和CLMA/CLMS占用；只有实际通过的频率可写为实测。目标未达时必须报告失败/瓶颈，不能更换负载后保留原指标名称。方案/规格待定导致尚无期望的测试必须记“待定”，不能作为通过计数。当前文档草稿验收仅检查章节/条款映射/实际piglit枚举；不要求在本Task运行RTL、Mesa、piglit或PDS。

## 7. 待定事项与变更记录

| 编号 | 待定项 | 推荐初值与定稿时机 |
|---|---|---|
| V2-01 | Mesa/piglit执行环境、commit、EGL平台与板端适配 | piglit锁本次枚举commit；Mesa锁driver Task时可构建版本，先确认真实ES1上下文再冻结 |
| V2-02 | Mesa分类容差与允许边界差异规则 | §4.2初值；Python/PC模型与Mesa首轮定向图之后、独立验证Task派发前冻结 |
| V2-03 | 全状态精度/字段/端口等规格待定项的期望数据 | 逐项跟随G2-01..12关闭，不能由验证worker自行填算术语义 |

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-11-27 | v0.1 | 初稿；建立VT01–25映射、M5/M6精度延续、Mesa分类容差建议、实查piglit 13个GLES1构建目标与适用性；未执行实现回归 |
