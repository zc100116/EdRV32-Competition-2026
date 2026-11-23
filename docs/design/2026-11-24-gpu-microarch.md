# GPU 微结构设计记录

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-24 |
| 状态 | 已决定，待协调者批准冻结 |
| 依据 | `2026-11-23-gpu-resource-closure.md`（已决定，da4c70345）、`gpu-spec.md` v0.2（2.4–2.6、2.12、第7节）、`gpu-soc-spec.md` v0.2、`rtl/include/regs/gpu.json`、`2026-11-23-gpu-architecture.md`、`2026-11-23-gpu-2d-estimates.md`、`gpu-plan.md` |
| 源码基线 | `b2ac0bb8b`（本次修订基线），分支 `zc100116/gpu-dev` |
| 数字性质 | 以下 GPU 周期、资源、级数均为结构估算，未经综合、PDS 或上板测量；历史实测另注明出处 |

## 1. 背景和问题

GPU 需要把固定功能几何、三角形/四边形扫描、对象推进、片上纹理和片上读改写连接成一条流水线。R-1–R-4 并行开发前，需要统一状态归属、流的排列、停顿和排空语义，否则局部单元都正确也可能在重叠绘制或命令切换时产生错误。第二版只替换三角形建立之前的几何单元，因此该边界单独定义。

本文按 v0.2 定稿数值定义 Verilog-2001 内部接口；目标115200像素、纹理192KiB及完整/当前组两级调色板沿用资源闭合决定。本文件只记录微结构及估算，不修改规格或寄存器JSON。

## 2. 约束

- 全 GPU 只有 `clk_gpu`，按200 MHz、5ns周期设计，预期全SoC约180 MHz（G-T1开发初值），150 MHz为保底，频率待PDS定稿。内部无 CDC。GPU 外的 X9/X10/X3 分别只用已有 `axi256_async_bridge`、`apb_async_bridge`、`cdc_sync_bit`；区域复位由顶层一级 `edrv32_reset_copy` 分发，不在各模块自行同步。
- 一个渲染单元，4 条水平相邻像素通道；目标为640×180或1280×90，均为115200像素；640×360分2条、1280×720分8条。颜色 RGB565、深度 u16、模板 u8 不缩减。
- DDR 地址/命令/记录布局逐位取 `gpu.json`；操作码及枚举取 gpu-spec 2.11。下文原始命令保留256位；目标/纹理布局/STEP行为及TGT_X0按4对齐均遵循v0.2。
- 按命令及表内顺序提交。只有 RESOLVE 写出颜色到 DDR；对象/列表写回仍按规格进行。可见完成须等最后 B 响应。
- 只做规格第 6 节的四种错误和规定的列表溢出、PERF0–8；无超时、非法内部输入检查、额外统计、自动降级或恢复路径。验证断言留在 testbench。
- 数据寄存器和 RAM 不复位，仅控制状态复位；业务 RTL 无条件编译。RAM/APM 由固定 tech 包装承接，IP 说明与生成由协调者安排。

## 3. 可选方案

| 取舍 | 未采用方案 | 已决定方案及理由 |
|---|---|---|
| 命令并行 | 多命令带标签和依赖调度 | 每命令排空，同DRAW的四边形连续流水；保持顺序和低控制成本 |
| 目标容量/映射 | 原目标230400像素，160bit字需261块 | 115200像素、160bit合并字、末段异构，129块；每屏多遍变换/读表，像素及输出总量不重复 |
| 纹理容量/读口 | 256KiB需64块；复制纹理更多 | 192KiB、4体奇偶分块双口48块，保证任意UV双线性2/三线性1像素每拍 |
| 调色板 | 四份完整表16块；小副本用DRM需确认半块独立双口 | 两份完整表8块；当前组8份单读LUTRAM，0额外DRM，约1600 LUT；三角形过滤前预装 |
| TEX_LOAD布局 | 在线重排但命令没有待装格式/尺寸 | 离线交织及小mip padding，DMA按字拷贝，越界按物理尺寸 |
| 几何边界 | 输出边/平面耦合扫描器 | 输出屏幕三角形；独立setup便于第二版替换 |
| 算术映射 | 小乘法占LUT且布线多 | 混合/过滤/着色移APM，保守按一乘积一APM；双8×8打包仅作待Windows确认的潜在节省 |
| DMA池 | 深度取整的两套512×256各4块 | 读64×256、写32×256用LUTRAM，仍保留4读/2写在途和16beat突发 |
| 时钟/AA | 单像素AA；原150MHz宽组合级 | 200MHz每级≤3 LUT；四路AA三行缓冲；预期整片180MHz、保底150MHz |

## 4. 决策

### 4.1 单元划分和文件归属

所有业务文件放 `rtl/gpu/`，一个文件一个同名模块。下表省略文件名共同前缀 `edrv32_gpu_` 和后缀 `.v`，例如 `command` 即 `edrv32_gpu_command.v`。集成顶层 `edrv32_gpu.v` 由 I-1 负责。

| worker | 文件功能名 | 职责 |
|---|---|---|
| R-1 | `regs` | APB本地setup寄存、公共/私有寄存器、IRQ、规格PERF；快照对象配置 |
| R-1 | `command` | 命令预取/解码、状态所有者、错误1/3/4、命令启动及排空、DONE/ABORT |
| R-1 | `read_dma`、`write_dma` | 内部读写客户仲裁、32B对齐/4KiB切分、AXI返回分派、错误2、在途排空 |
| R-1 | `resolve` | 读目标颜色、三行缓冲、四路AA、RGB565打包、Surface逐行写出 |
| R-2 | `geometry` | 自成一体的几何外壳：顶点三元组、变换/光照、五平面裁剪、扇形拆分、投影、背面剔除 |
| R-2 | `transform`、`clip`、`project` | 上述三个内部算术阶段；不对R-1/R-3暴露内部状态 |
| R-2 | `setup` | 屏幕空间三角形→包围框、左上偏置边方程、属性平面；在几何替换边界之外 |
| R-3 | `raster`、`quad` | 三角形4像素组扫描、四边形快速扫描及两路有序选择；相同fragment契约 |
| R-3 | `perspective` | 四路q倒数、透视u/v与偏导，四边形直通；送纹理单元 |
| R-3 | `object` | 一对象/拍运动/寿命/区域/八框并行碰撞、事件及更新对象、有序四边形输出 |
| R-4 | `texture`、`texture_ram`、`palette` | LOD、请求排程/去重/冲突、192KiB四体RAM、4读口完整调色板和8读口当前组副本、三种过滤、着色 |
| R-4 | `pixel`、`target` | 透明丢弃、模板/深度/混合、目标RAM、同字依赖旁路、CLEAR及RESOLVE访问 |

`geometry` 内部模块及 `texture` 内部模块的端口由其 worker 自行划分，不跨任务。倒数算法同源但不用一个跨worker共享RTL文件：R-2 `project` 和 R-3 `perspective` 各有本地实现，数值规则均取规格2.12。tech RAM/APM 包装、公共头、寄存器生成物和文件列表不归这四个 worker 修改。

### 4.2 通用内部协议与排列

以下表中 A→B 表示负载及valid由A输出、B输入，ready反向。展开端口时源端加 `_o`、目的端加 `_i`。每个流 `p` **恰有** `p_valid`（1，A→B）、`p_ready`（1，B→A）及表列负载。均在上升沿 `valid && ready` 时传输；valid不能等待ready，受阻时valid和全部负载保持。无组合跨单元ready链，接收端至少有两项弹性寄存槽；RAM读前预留返回槽。延迟指无背压下接收沿到产生输出valid的沿数，停顿时输出顺序不变，接口不依赖固定延迟。

所有打包数组小下标在低位：`lane k` 对应像素x+k，`vertex j` 对应输入顺序第j个，`component c` 顺序R/G/B。重复字段用 `[k*W +: W]` 展开；表列宽度为整个端口宽度。Qn表示n位小数；s格式包含符号位，位宽均显式列出；扩展乘加不在规格舍入点之外截断。

**命令/配置及完成接口**：

| 流/信号 | A→B | 负载（信号名:位宽） | 时序及语义 |
|---|---|---|---|
| `geometry_cfg` | command→geometry | `geometry_cfg_matrix:512`、`geometry_cfg_light:96`、`geometry_cfg_target:256`、`geometry_cfg_pixel:256`、`geometry_cfg_wide:1` | 仅几何空闲时接收；matrix为16×32行优先；light低48为lx/ly/lz，下24方向色，再24环境色；target/pixel为原命令；每次DRAW_TRI前给一次完整快照 |
| `draw` | command→geometry、raster、quad、object（各独立同名实例前缀） | `draw_command:256` | 只向当前命令涉及的单元各发送一次；四边形/对象还使用下面state快照；DRAW_TRI的geometry按COUNT收3N顶点 |
| `render_state` | command→raster、texture、pixel（各独立流） | `render_state_tex:256`、`render_state_pixel:256`、`render_state_target:256`、`render_state_wide:1` | DRAW开始前各接收一次；分别为最近SET_TEX/PIXEL/TARGET原命令，执行期间不变；quad每项覆盖palette并强制nearest |
| `palette_prepare` | command→palette | `palette_prepare_group:4` | 仅DRAW_TRI且I4/I8、SAMPLE非nearest时，在启动几何前发一次；装载当前组副本 |
| `palette_prepared` | palette→command | 无负载，仅valid/ready | 256项全部预装完成后响应一次；握手后才开始DRAW_TRI。每次符合条件的DRAW都重新预装，不加命中标签 |
| `object_cfg` | regs→object（command调度） | `object_cfg_live:64`、`object_cfg_targets:512`、`object_cfg_hit_base:32`、`object_cfg_hit_max:24`、`object_cfg_free_base:32`、`object_cfg_free_max:24` | OBJ_STEP前快照；矩形依次x0/y0/x1/y1，每项s16；targets低64为目标0；寄存器后续写不影响在执行命令 |
| `clear` | command→target | `clear_command:256`、`clear_target:256`、`clear_wide:1` | CLEAR独占目标；清除区域与目标和SCISSOR求交，未清字段保留 |
| `resolve` | command→resolve | `resolve_command:256`、`resolve_wide:1` | 先排空所有像素；写出区域按命令，颜色读接口见后表 |
| `unit_done` | geometry/setup/raster/quad/perspective/object/texture/pixel/target/resolve→command | 每单元 `unit_done:1`（电平，无valid/ready） | 接受本命令前置0，finish已到达且所有本命令输出已握手、内部无有效项后置1并保持到下次启动；无输出的空DRAW也完成；pixel/target完成须包括RAM提交；resolve/object须再由command合并DMA B排空；object_result是完成后的发布口，不计入object的unit_done排空条件 |
| `finish` | command→各处理单元 | `finish:1`（每单元独立电平） | 表示该单元本命令不会再有输入；仅在其全部上游done后拉高，保持到下次启动。不清除或丢弃已接收工作 |
| `stop` | command→所有业务单元 | `stop:1`（电平） | ABORT或ERROR后保持至本次排空完成；停止生成新工作，丢弃尚未发出的业务负载；DMA已经接收的请求继续服务。stop期间各返回消费者继续ready并丢弃返回内容，已握手写区间的数据仍从已缓存突发供完。无额外取消标签 |
| `dma_idle`、`dma_error` | DMA→command | 各方向 `dma_idle:1`、`dma_error:1`（电平） | idle表示队列、在途及返回负载全空；error是本次运行非OKAY的粘滞位，映射ERR_CODE2 |

finish按依赖逐级推进：输入DMA完成→geometry或quad/object；geometry完成→setup；setup完成→raster；raster/quad完成→perspective；perspective完成→texture；texture完成→pixel；pixel完成→target。对象的quad输出先入quad再走同一像素链，object自身完成不等绘制链；CLEAR/RESOLVE在区间数据源终止后finish。每单元接受新draw或状态快照开始本命令，finish/stop由command复原，不能靠瞬时FIFO空提前宣告完成。

`regs` 与 `command` 的控制线：`start:1`、`abort:1`、`soft_rst:1` 为regs→command一拍脉冲；`enable:1`、`desc_base:32`、`desc_count:16`、`wide:1`为regs→command电平，start沿快照。command→regs为 `busy:1`、`done:1`一拍、`error:1`一拍、`err_code:32`（error同拍），DONE_COUNT由regs在done递增。CTRL/START/DOORBELL/SOFT_RST按SoC7.1执行，不另定义软件行为。

对象结果流 `object_result`：object→regs，`object_result_valid/ready`及 `object_result_hit_count:24`、`object_result_free_count:24`、`object_result_alive_count:24`、`object_result_overflow:2`，仅在对象输出及相关B全部结束后由command允许握手，随后寄存器整体生效。command给object的 `object_publish:1` 为此条件电平；object不提前发布。下一OBJ_STEP开始清溢出。

PERF只在regs累加：各单元给本地周期事件，`perf_vertex:1`、`perf_triangle:1`、`perf_quad:1`为对应输入顶点/非退化建立三角形/开始扫描四边形的握手脉冲，`perf_pixel_count:3`为该拍通过全部测试像素数0–4，与写入开关无关，CLEAR/RESOLVE不计，`perf_texture_stall:1`为纹理bank冲突周期，`perf_read_wait:1`为读DMA等待周期，`perf_resolve_busy:1`、`perf_object_busy:1`为占用电平；总忙由busy。多个同类事件同拍的设计只有pixel允许大于1；未用PERF读0。事件都是源输出、regs输入，无反压、不跨域。

### 4.3 几何单元的完整替换边界

几何单元只消费 `geometry_cfg`、`draw`、`vertex`、`finish` 和 `stop`，输出 `screen_triangle`、`unit_done`及顶点事件。`setup` 是独立消费者，第二版4路SIMD替换整个geometry后仍按此屏幕三角形格式输出；没有程序存储、指令口、SIMD占位参数或第二版专用逻辑。

| 流 | A→B | 信号名:位宽 | 格式和含义 |
|---|---|---|---|
| `vertex` | read_dma→geometry | `vertex_data:128` | gpu.json VERTEX的16B原样；先v0/v1/v2，再下一三角形；三角形数量来自draw；每2拍可收1顶点，无额外last端口 |
| `screen_triangle` | geometry→setup | `screen_triangle_x:51`、`screen_triangle_y:51` | 各3×s12.4（17bit），屏幕像素坐标 |
| 同一流 | 同上 | `screen_triangle_depth:48` | 3×u16，投影/映射后的深度 |
| 同一流 | 同上 | `screen_triangle_q:105` | 3×u35 Q30，1/W，W≥1/16故q≤16 |
| 同一流 | 同上 | `screen_triangle_uq:153`、`screen_triangle_vq:153` | 各3×u51 Q38，16位Q8 UV乘35位Q30 q的完整积 |
| 同一流 | 同上 | `screen_triangle_color:216` | 3顶点×3通道×u24 Q16；光照后u8左移16位，低通道R、其次G、再B |

输出是完成五平面裁剪、投影和剔除的三角形，裁剪多边形按扇形顺序输出。完全裁掉、退化或剔除的输入不输出；setup仍独立拒绝零面积，不产生像素。几何输出done在最后一个screen_triangle握手后成立；setup自己的done另行排空。状态在接受draw前握手，直到本DRAW完成保持。无隐含顶点缓存地址、内部裁剪缓冲地址或矩阵RAM读口跨过此边界。

矩阵为32位s15.16、输入位置s16，32×16积48位，四项累加50位，一次舍入/饱和为40位s23.16。W_NEAR=1/16，G=4；五平面顺序及对称交点公式取2.4，距离用s43（40位坐标、乘4及加减），距离差s44，坐标交点分子s84（40+43+1），除后按规格舍入。裁剪UV为u16 Q8、颜色u24 Q16，各分量同样完整扩展。双8顶点寄存工作集保留全部属性。

投影X/Y/Z×q为75位Q46（40+35）；视口乘法再扩16位，1与坐标积先同Q46对齐。sx/sy仅在规格给定的一次舍入后饱和到17位；深度按round(65535·Z·q)后夹到u16。背面面积以17位屏幕坐标计算。

SET_TARGET原始256位的字节0x10低/高16位为VP_X0/VP_Y0（命令bits[143:128]/[159:144]，s16）；0x14低/高16位为VP_W/VP_H（bits[175:160]/[191:176]，u16），与gpu.json一致。所有target配置流原样保留这些位。

倒数严格采用归一化Q30尾数（u31）、10位中点种子索引、一次牛顿迭代及指数还原舍入；乘法保留31×31完整62位，种子r₀为u30，t及2−t的减法用32位。输出按调用方量级保存：q用u35 Q30，像素w用u54 Q30（q最小可为128个Q30单位，w最大2²³）。种子ROM保存Q30种子的高18位，读取后左移12位并拼接由常数组合逻辑给出的低12位；低位必须补全，不能截成18位尾数。

### 4.4 建立、扫描、纹理与像素接口

| 流 | A→B | 负载信号:位宽 | 时序与语义 |
|---|---|---|---|
| `triangle_setup` | setup→raster | `triangle_setup_bounds:64` | x0/y0/x1/y1各s16，含左上不含右下；x0按4向下取整，覆盖还受边/目标裁剪；y为整数行 |
| 同一流 | 同上 | `triangle_setup_edge:480` | 3边×4值×s40：E在首组lane0中心的值、一步x增量、一步y增量、左上偏置；同一边4值依次从低位排列；建立时统一内部方向为E>=0，左上边偏置0，其他边偏置-1，覆盖测试E+bias>=0 |
| 同一流 | 同上 | `triangle_setup_plane:2016`、`triangle_setup_area:40` | 7属性×3个s96整数分子：首中心N、每像素ΔxN、每行ΔyN；属性顺序q/uq/vq/z/R/G/B，小数位30/38/38/0/16/16/16；公共正面积u40作分母。保留有理平面，不能先舍入斜率再累加 |
| `quad_record` | read_dma→quad | `quad_record_data:128` | gpu.json QUAD；表顺序，无逐项命令排空 |
| `object_record` | read_dma→object | `object_record_data:256`、`object_record_idx:24` | gpu.json OBJ及对象编号，从0递增；空槽也传入以保持索引 |
| `object_quad` | object→quad | `object_quad_data:128`、`object_quad_x:17`、`object_quad_y:17` | 存活且draw=1；data承载QUAD非位置字段，其x/y位不使用；位置独立s17，p取整−半宽高，不截成外部QUAD的s12造成屏外回绕；顺序与对象表相同，不会与DRAW_QUAD源同时活动 |
| `fragment` | raster/quad有序选择→perspective | `fragment_x:16`、`fragment_y:16`、`fragment_mask:4`、`fragment_quad:1` | x/y为s16屏幕整数坐标，x是4倍数；lane位置x+k；mask为覆盖且在scissor/target内，0组不发 |
| 同一流 | 同上 | `fragment_q:140`、`fragment_uq:204`、`fragment_vq:204`、`fragment_depth:64`、`fragment_color:96` | 各4lane，q/uq/vq格式同几何输出；depth4×16、color4×24；quad的q=1，uq/vq直接表示纹素坐标，color为白色 |
| 同一流 | 同上 | `fragment_gradient:576`、`fragment_area:40`、`fragment_palette:4`、`fragment_alpha:8` | 梯度顺序duq/dx、duq/dy、dvq/dx、dvq/dy、dq/dx、dq/dy各s96分子，共用u40面积；uq/vq梯度Q38、q梯度Q30；quad梯度不用。palette为quad项覆盖值，tri使用SET_TEX；alpha为quad全局alpha，tri=255 |
| `sample` | perspective→texture | `sample_x:16`、`sample_y:16`、`sample_mask:4`、`sample_quad:1`、`sample_u:128`、`sample_v:128` | 4×s32 Q8纹素坐标；quad绕过倒数，保留翻转方向产生的坐标；texture按尺寸取模 |
| 同一流 | 同上 | `sample_span:384`、`sample_depth:64`、`sample_color:96`、`sample_palette:4`、`sample_alpha:8` | span每lane u96 Q16，为max(abs(du/dx),abs(du/dy),abs(dv/dx),abs(dv/dy))；梯度由商导数(uq'−u*q')/q得到；LOD由texture计算 |
| `shaded` | texture→pixel | `shaded_x:16`、`shaded_y:16`、`shaded_mask:4`、`shaded_depth:64`、`shaded_color:96`、`shaded_alpha:32` | 过滤/着色后4lane RGB888及A8；透明lane清mask，目标坐标/深度保持原lane；每输入组严格对应一个输出组，允许mask全0 |
| `target_read` | pixel→target | `target_read_addr:16` | 地址为目标四像素字，范围0–28799；无mask，读全160bit |
| `target_old` | target→pixel | `target_old_data:160` | 顺序响应；每lane40bit={stencil8,depth16,color16}；读请求到输出5拍：地址预译码1、DRM阵列/输出寄存2、两级选择树2；已包含同拍写回旁路 |
| `target_write` | pixel→target | `target_write_addr:16`、`target_write_data:160` | 已合并保留字段的完整字；握手沿提交逻辑结果/写寄存，下一沿完成物理RAM写；不再对未改lane做物理掩码；最终结果旁路见4.7 |
| `resolve_read` | resolve→target | `resolve_read_addr:16` | 仅RESOLVE期间允许，独占target读端；同字映射 |
| `resolve_color` | target→resolve | `resolve_color_data:64` | 5拍有序响应，每lane16bit RGB565；不读改写，不更新目标 |

位宽推导：17位顶点坐标差用s18，面积叉积18+18+1=37位；像素组按4对齐时p−a保留s19，边函数18+19+1=38位，统一s40包含偏置和步进，正面积用u40。只扫描三角形包围框及其组对齐扩展，不把整段s16屏幕空间外推到边寄存。最大属性uq/vq为u51，三项E·attr累加需40+51+2=93位，统一s96分子；乘前扩展，符号和舍入均取2.12。对N/A一次舍入到q35/uq51/vq51/z16/颜色24 Q16，颜色再按规格舍入/饱和到u8，避免把已舍入dx/dy当精确平面。

透视完整uq51×w54=105位Q68，右移60位舍入得到Q8，sample容器s32。偏导保留有理梯度：以u的Q8整数U计算(Duq−U·Dq)·w/A，32+96+1=129位差，乘54位w为183位Q68，转Q16需除A并右移52位；跨度用u96：实际Dq分子位界35+18+1+4=58，乘U32后差最多91位，再乘w54并移52位最多93位，96位足够。quad的uq/vq先将Q8坐标左移30位、q=2³⁰；送sample时恢复Q8，跨度不用。上述是唯一精确接口；下文B/C只比较尚未获准的规格改动，不构成另一个端口定义。

四边形和三角形同一命令不混排；raster/quad只允许当前draw源输出。quad_record的s12位置先符号扩展到s17，object_quad使用独立s17位置，两路归一为同一内部扫描格式；减半宽高采用整数floor，取整规则依2.9。quad不能为了隐藏开销调换精灵顺序。过滤吞吐较低时，texture持有一个4lane组并分拍发lane0/1、lane2/3（bilinear）或逐lane（trilinear），组装回原4lane，pixel看到的lane/address不变。

### 4.5 装入、DMA及对象写回接口

内部DMA采用字节区间请求，客户不自行切AXI突发。读客户编号固定：0命令、1矩阵、2顶点、3四边形、4对象、5纹理、6调色板；写客户编号固定：0对象表、1命中列表、2释放列表、3RESOLVE。每客户至多一条逻辑区间未完成，客户有独立流，不把编号做成业务单元端口。矩阵DMA读回2个256位beat后command组成512位matrix；命令beat直达command；顶点/quad每beat拆成两项。

| 流 | A→B | 负载信号:位宽 | 协议及语义 |
|---|---|---|---|
| `read_req`（每读客户） | 客户→read_dma | `read_req_addr:32`、`read_req_bytes:32` | 精确字节区间；仅bytes>0时发请求；源地址可由Surface行偏移等形成，DMA向下32B对齐读取并在拆包时去掉首尾无关字节 |
| `read_data`（每读客户） | read_dma→客户 | `read_data_data:256`、`read_data_keep:32`、`read_data_last:1` | 对齐DDR beat的原始数据；keep标记属于请求区间的字节，低位为低地址，last为逻辑请求末beat；每客户顺序返回 |
| `read_done`（每读客户） | read_dma→客户 | `read_done:1`，无握手一拍 | 最后read_data已握手后脉冲；错误请求也等全部已发R消耗后结束，错误另经dma_error通知 |
| `write_req`（每写客户） | 客户→write_dma | `write_req_addr:32`、`write_req_bytes:32` | 精确连续有效字节区间；此流握手后才消费该客户write_data |
| `write_data`（每写客户） | 客户→write_dma | `write_data_data:256`、`write_data_keep:32`、`write_data_last:1` | 已按DDR对齐beat排列；keep是该请求中实际写字节位置，last标记逻辑末拍；列表项32bit、resolve像素16bit按地址排列 |
| `write_done`（每写客户） | write_dma→客户 | `write_done:1`，无握手一拍 | 该请求所有突发B返回后脉冲；对象/列表计数发布依赖这些完成 |
| `texture_load` | read_dma装入适配→texture_ram | `texture_load_addr:18`、`texture_load_data:256`、`texture_load_keep:32` | 18bit纹理字节地址（32B对齐），32B一组；按离线字流线性地址写4体，拆成四次8B内部写；RAM返回ready反压 |
| `palette_load` | read_dma装入适配→palette | `palette_load_idx:12`、`palette_load_data:20` | group*256+entry；每beat拆8个PAL_ENTRY逐项广播写两份完整表；高12位DDR填充忽略 |
| `object_update` | object→写回适配 | `object_update_idx:24`、`object_update_data:256` | 仅step=1，保持原记录未定义位及非运动字段；更新alive/p/v/life；地址基址+32*idx |
| `object_event` | object→列表打包适配（R-1） | `object_event_idx:24`、`object_event_hit:8`、`object_event_free:1` | 仅step=1时每个已处理对象一次，step=0不发事件、不写列表；hit位k对应目标k；先按对象顺序，再按目标编号递增压缩列表；free是本次由活变死；空槽不计free。命中/释放是否同时产生严格依2.9及模型的顺序 |

STEP=0只检查原记录alive并按draw开关输出四边形；不推进、不做存活区判定/碰撞、不写回/列表，hit/free/overflow结果为0，alive_count统计原存活对象。STEP=1才走运动/判定/碰撞/写回路径；对象result计数由object统计未截断事件总数，hit每拍popcount8、free/alive各0/1。R-1打包器只对容量内条目写DDR，full后停止追加；对象单元得到同一配置快照，以实际计数和MAX比较形成规定的overflow。两边不重复统计可见寄存器，也不添加第二套溢出行为。尾部用WSTRB保留容量外及相邻数据。

### 4.6 200MHz流水线、数值与吞吐

以下均为结构估算，不是综合结果。每级≤3级LUT，宽加减按每20位两拍切分；全精度分块乘用APM三拍、部分积压缩/进位每层两拍。整数位移只在规格舍入点取位。II按无背压计。

| 阶段 | 分级/延迟估算 | II/吞吐与限制 |
|---|---|---|
| 变换/光照 | 16矩阵积两拍发射、APM3、50位加法树两层各3、饱和2，约14拍；光照分级对齐 | 顶点II=2，全内三角形 |
| 裁剪 | s43距离加减3、分类1；对称交点分子84位，6块乘积压缩/加减约9、精确除法另计 | 全内约4拍；跨平面按边序列反压，不把倒数近似代替规定交点除法 |
| 顶点投影 | 归一化3、种子3、两次牛顿宽乘各5、减2、还原3=21；40×35的6块积3+压缩/加减6；视口乘/舍入8、剔除4，共约42拍 | 顶点II=2；三坐标各6块，不能再按32×18的2块计 |
| 建立 | s18差2、面积积/差5、属性分子乘/压缩9、首中心求值与符号对齐8，约24拍；面积不预舍入成斜率 | 目标II=8；至少ceil(24/8)=3上下文，保留5项配额；需实现调度验证 |
| 扫描/插值 | s40边加2、s96分子加5、覆盖2；N/A逐属性精确除法采用下述保守展开基线：96步×2拍=192拍，再舍入2，合计约201拍 | 四lane并行、各步寄存，II=1；长延迟和资源不能隐去 |
| 四边形扫描 | 建立2、位置/UV/翻转2、mask1，共5拍；当前/下一预建 | 对齐16×16为64组，不齐最多80组，稳态≤80拍 |
| 像素倒数/UV | 倒数21；51×54的9块乘3+压缩/进位6、舍入2，共32拍 | 4lane II=1；精确全乘基线104 APM，详4.11 |
| 每像素精确偏导A | u×Dq、差、乘w共约22拍；183/40精确除法183步×2=366拍，取Q16/最大4，共约392拍 | 与UV并行，结果按原4lane组对齐；资源尚未闭合 |
| 纹理 | 96位跨度前导位/移位5、256项log2表2、偏置/夹取2、地址3、RAM5、palette4；RGBA过滤乘加独立分级 | nearest4（无冲突）、bilinear2、trilinear1像素/拍；双线性横向保留Q8积，纵向保留Q16积再一次舍入 |
| 像素运算 | mask1、目标读5、比较2、模板2、因子2、APM3、d2、op2、合并2、提交1，共22拍 | 4像素/拍；同字依赖另停顿 |
| 对象 | STEP=1共12拍，STEP=0共4拍 | 单元II=1，不含绘制/DDR；STEP=0不走推进/碰撞/列表/写回 |
| AA | 亮度/minmax/差/方向/和/打包各2拍，共12 | 四像素/拍 |

LOD取跨度Q16的前导1位置减16作为整数部分，其后8位查round(256·log2(1+i/256))，输出Q8；跨度0按规格取LOD=0。偏置s3.4左移4位后相加并夹取。256×9位常数表按32bit/LUT容量代理为72 LUT，另留移位/选择流水配额；不是原稿16项表。

RESOLVE估算保持：640×360两条核心2×115200/4=57600拍，启动2×(320+256)=1152拍，共58752拍。180MHz下0.5ms有90000拍，DDR额外等待余量31248拍；两条460800B需0.9216GB/s，稳态每4GPU拍一beat为1.44GB/s。均须perf实测，不含重新绘制。1280×720八条核心230400拍。

### 4.7 同字读改写与命令串行等效

采用v0.2的 `TGT_X0[1:0]=0`，TGT_Y0任意；软件保证，不在RTL新增对齐检查。屏幕x为4倍数，因此目标字地址 `a=(y−TGT_Y0)*(width/4)+((x−TGT_X0)>>2)`，范围0–28799，lane直接对应目标像素，不需要重新对齐、拼接或拆字。地址口保留唯一16bit，高位自然为0；width/4分别160/320。

每个未完成RMW保留地址/新160bit/结果ready。读请求进入pixel前查所有未提交项，按程序顺序选最近前驱：

1. 无同址前驱：发target_read；RAM读响应可与更早写回同址，target用提交字做优先旁路，禁止依赖IP同址read-during-write的未定行为。
2. 最近前驱的最终合并字已就绪：直接转发该完整字，不发RAM读。
3. 最近前驱尚在比较/混合流水：该后继保留在入口，暂停发射直到结果就绪；不读取陈旧RAM字，也不把多个Alpha混合当可交换运算。

这是地址依赖记分而非额外输入检查，覆盖pixel流水有效项（32项环，覆盖22拍RMW及入口/返回槽，满则反压）。target在阵列采样拍对该读地址与待物理提交写寄存/最近已写字比较，匹配结果作为本次读的旁路值随5拍响应流水保存；不能只在响应末端用一个全局最近写字替换此前读值。pixel按有序读请求分配内部返回槽号并按有序响应回收，不跨worker传tag。同址连续RMW在结果产生前必须停顿，不能虚称任意反复写一个字仍4pixel/拍。普通16×16扫描的同址距离至少64拍，足以隐藏流水依赖，保证四边形目标。

command对DRAW发送结束后，等geometry/setup/raster/object/texture/pixel/target相关done及DMA完成，再改变状态或启动下一命令。命令预取只读命令，不发下一命令的数据DMA。SET_MATRIX等状态更新发生在排空后；TEX_LOAD/PAL_LOAD等所有写入RAM握手完才允许后续绘制。RESOLVE独占target，CLEAR也独占读写，部分清除同样按整字保留字段。最后DONE再等read/write DMA全idle；STEP=1的OBJ_STEP结果等对象表、命中、释放三类最后B返回才发布；STEP=0没有这些写事务，按原存活项绘制结束发布。ABORT停止业务生成，已经接收的DMA区间及AXI事务全部排完，AXI无未完成事务后IDLE；不保证目标内容。

### 4.8 片上RAM物理组织及DRM账本

36Kb=36864bit=4608B；计数按原生2048×18、1024×36、512×72宽深取整，不能仅用有效bit总和相除。以下均为估算，IP端口/模式仍待Windows确认。

目标115200像素，28800个160bit四像素字，lane k为bits[40k+:40]={stencil8,depth16,color16}。地址a<28672时：段s=a>>11（0–13），字内r=a[10:0]；每段9片2048×18，最高2bit不用。a≥28672时段s=14，尾r=a−28672（0–127），3片512×72拼216bit后取低160bit，未用位不参与结果。DRM=14*9+3=**129**，无需第二种逻辑像素布局；颜色64/深度64/模板32覆盖两形状。

读树5拍：请求沿预译码段/地址并寄存；阵列同步读1拍；DRM输出寄存1拍；15段分4/4/4/3四组各4选1并寄存；最后4选1并寄存。每级mux≤3LUT，尾段先本地拼接，禁止129块汇入大组合mux。写地址/数据/CE也本地寄存，在target_write握手沿提交的逻辑结果立即进入旁路，物理RAM写在下一沿完成；unit_done包括这一拍，读响应覆盖该写寄存及最近已提交字。

**纹理布局（v0.2）**：4体×48KiB，每体24576×16，12段2048×18，共**48块**；两半各96KiB，以物理字节地址<98304/≥98304区分（不再使用byte[17]划分）。请求地址/段预译码寄存1、DRM读/输出寄存2、12段按3组4选1及最终3选1各1，共5拍；两读端树独立，段号/valid同步。

16bit字覆盖的纹素块为I4的2×2、I8的2×1、RGB565的1×1；体号=(块x&1)|((块y&1)<<1)。最近邻任意4lane可以集中一个体的4个不同字，此时按lane顺序用双口分两拍、同址合并，PERF5计冲突停顿；已取得的结果保留，不重复取样。四边形连续4像素在I4中最多跨3个相邻字块，无此最坏集中冲突。

取样先按级缩放Q8坐标，再u′=u_k−128、v′=v_k−128；以floor(u′/256)、floor(v′/256)为左上纹素，fx/fy取非负模256。RGBA各按四个权重(256−fx)(256−fy)、fx(256−fy)、(256−fx)fy、fx·fy求和后一次round(/65536)；三线性再按LOD低8位f一次round((t_l(256−f)+t_{l+1}f)/256)。横向中间结果不舍入，避免两次lerp舍入改变规格。减半个纹素只移动足迹起点，足迹仍为任意位置2×2。

对任意一个双线性2×2纹素足迹，跨越的字块在x和y方向各不超过2个，故每体最多一个不同16bit字；一个字可提供多个所需纹素，读取后按块内位置拆tap。两个任意双线性足迹最多每体两字，使用双口，不需要冲突重放；三线性两级各一个足迹亦最多每体两字，故保证任意UV下2像素/拍双线性、1像素/拍三线性。尺寸为2的幂，环绕从末字块到首字块保持奇偶差；块网格只剩一列/一行时重复地址合并，小mip见下面padding规则。两半各96KiB，不复制纹理，软件负责使用/装入区域互不覆盖。

唯一地址公式：格式块宽高(bw,bh)依次(2,2)/(2,1)/(1,1)，第k级Wk=max(1,W>>k)、Hk=max(1,H>>k)，块网格Bx=ceil(Wk/bw)、By=ceil(Hk/bh)，每级占字节 `Lk=8*ceil(Bx/2)*ceil(By/2)`。Pk=SET_TEX.OFFSET+sum(Lj,j<k)。纹素u/v先按Wk/Hk环绕，块坐标bx=floor(u/bw)、by=floor(v/bh)，物理半字地址：

`h = Pk/2 + 4*((by>>1)*ceil(Bx/2)+(bx>>1)) + (bx&1) + 2*(by&1)`。

物理bank=h[1:0]，row=h>>2。I4字内nibble序号=(u&1)+2*(v&1)，I8字内byte序号=u&1；RGB565整字。每个2×2字块组完整保留4个16bit槽，小mip缺失槽填充但永不被取样。Pk初始32B对齐，Lk为8B倍数，级间连续且每级bank起点相同。例I4的2×64一级，Bx=1、By=32，原始4bit/texel需64B，但奇偶布局实际128B；1×1一级占8B。SET_TEX越界按sum(Lk)物理占用，而不是原始纹素bit数。该padding是为了真实保住所有长宽组合的奇偶映射，不能把稀疏体的洞当作纹理容量免费空间。

256×256完整9级的物理尺寸/偏移如下，偏移均相对SET_TEX.OFFSET，单位B：

| 级k/尺寸 | I4占用/偏移 | I8占用/偏移 | RGB565占用/偏移 |
|---|---|---|---|
| 0 / 256×256 | 32768 / 0 | 65536 / 0 | 131072 / 0 |
| 1 / 128×128 | 8192 / 32768 | 16384 / 65536 | 32768 / 131072 |
| 2 / 64×64 | 2048 / 40960 | 4096 / 81920 | 8192 / 163840 |
| 3 / 32×32 | 512 / 43008 | 1024 / 86016 | 2048 / 172032 |
| 4 / 16×16 | 128 / 43520 | 256 / 87040 | 512 / 174080 |
| 5 / 8×8 | 32 / 43648 | 64 / 87296 | 128 / 174592 |
| 6 / 4×4 | 8 / 43680 | 16 / 87360 | 32 / 174720 |
| 7 / 2×2 | 8 / 43688 | 8 / 87376 | 8 / 174752 |
| 8 / 1×1 | 8 / 43696 | 8 / 87384 | 8 / 174760 |
| **物理总量** | **43704** | **87392** | **174768** |
| 原始逐级字节上取整总量 | 43691 | 87381 | 174762 |
| 增加字节/膨胀百分比 | 13 / 0.029754% | 11 / 0.012589% | 6 / 0.003433% |

原始总量以每级ceil(Wk*Hk*bits/8)相加，I4若按不取整的纯bit数为43690.5B（87381个纹素×0.5），对应增加13.5B、膨胀约0.030899%；其余格式无半字节差异。256×256 RGB565的全mip物理占用超过单半区96KiB，软件只能安排其完整192KiB空间中的合法区间，不能宣称任何格式全mip都可在半区双缓冲。

对公式做了独立Python枚举，并检查192KiB末端装入及8副本当前组广播：三种格式、W/H各取1/2/4/8/16/32/64/128/256，覆盖783363个足迹起点，均满足单足迹每体最多一个不同字。两个足迹因此每体最多两字；同一证明适用于三线性跨级（Pk总是4字对齐）。可复现命令如下，纯文档公式检查，不替代RTL验证：

```sh
python3 - <<'PY'
count = 0
for bw, bh in [(2, 2), (2, 1), (1, 1)]:
    for w in [1, 2, 4, 8, 16, 32, 64, 128, 256]:
        for height in [1, 2, 4, 8, 16, 32, 64, 128, 256]:
            stride = (((w + bw - 1) // bw) + 1) // 2
            for v in range(height):
                for u in range(w):
                    banks = {}
                    for dy in [0, 1]:
                        for dx in [0, 1]:
                            x = ((u + dx) % w) // bw
                            y = ((v + dy) % height) // bh
                            a = 4*((y//2)*stride+x//2)+(x%2)+2*(y%2)
                            banks.setdefault(a % 4, set()).add(a)
                    assert max(map(len, banks.values())) <= 1
                    count += 1
capacity = 192 * 1024
for bw, bh in [(2, 2), (2, 1), (1, 1)]:
    sizes = []
    for k in range(9):
        n = max(1, 256 >> k)
        sizes.append(8*((((n+bw-1)//bw)+1)//2)*((((n+bh-1)//bh)+1)//2))
    total = sum(sizes)
    base = ((capacity-total)//32)*32
    assert base + total <= capacity < base + 32 + total
    assert (capacity//2) % 8 == 0
full = [[(group << 8) | index for index in range(256)] for group in range(16)]
for group in range(16):
    copies = [list(full[group]) for port in range(8)]
    for index in range(256):
        assert all(copies[port][index] == (group << 8) | index for port in range(8))
print('PASS', count, '192KiB bounds; palette 8-read preload')
PY
```

离线工具输出上述交织字流，TEX_LOAD按字线性复制，体号仅取目标半字地址低2位；32B装入beat拆4拍，每拍4体各写一个16bit字，ready反压。在线重排需知道每个待装纹理的尺寸/格式/mip及源起始，TEX_LOAD现有字段没有这些信息，不能借当前SET_TEX推断，故不推荐为此新增硬件状态/端口。离线布局、padding及物理大小计算取gpu-spec2.6，由工具/参考模型/RTL统一。

TEX_LOAD和DRAW按命令顺序执行，因此本版没有同时读一半/写另一半的命令重排；两半的软件资源管理保留，不加第二装入端口。装入及取样互斥由command保证，不在RAM加重复软件合法性检查。

**调色板**：两份完整4096×20，每份4段1024×36，共8块，true-dual-port提供4次任意组读取/拍；nearest三角形和四边形均走完整表。PAL_LOAD每拍一项广播写两份，装入时不取样。三角形I4/I8且非nearest时，command先发palette_prepare(group)，从完整表按0–255每拍读一项，广播写当前组的8份单读256×20副本；每副本一独立索引/拍，查色无bank冲突。绘制期间副本不更新。RGB565及nearest不预装；每个符合条件的DRAW_TRI都预装，不增加缓存一致性标签。

| 当前组实现比较 | DRM增量（36Kb等效） | LUT估算/预装周期 | 选择 |
|---|---:|---|---|
| 4份双读256×20 DRM | 保守4块；若36Kb可拆两个独立双口18Kb，则2块 | 少量选择约100 LUT；写一项广播4份，约264拍 | 18Kb半块独立双口及20bit宽配置尚无仓库内确认证据，待Windows确认；本版不依赖此假设 |
| **8份单读256×20 LUTRAM** | **0块** | 容量8*256*20=40960bit；按32bit/LUT为1280 LUT，加分页读树/控制约320，配额**1600 LUT**；约264拍 | **采用**；8个读口，无需假设分布式RAM支持双读 |

完整表读延迟4拍（输入1+阵列/输出2+4段选择1）；小副本读索引寄存、分页读取/分层选择各自寄存，总4拍，与完整表对齐。预装预算=请求/发起2+256读发起+完整表4+广播写1+响应1=264拍，在200/180/150MHz为1.32/1.467/1.76us。I4也装满256项，取样只用前16项。固定小副本布局为8×256×20，行号即索引，复制写入无组tag，不改外存或软件行为。

| 所有者/用途 | 物理映射公式（估算） | DRM |
|---|---|---:|
| R-4 target | 14*9片2048×18 + 尾部3片512×72 | 129 |
| R-4 texture | 4体*12片2048×18 | 48 |
| R-4 完整palette | 2副本*4片1024×36 | 8 |
| R-4 当前组palette | 8副本*256×20 LUTRAM，约1600 LUT | 0 |
| R-1 AA | 3行各320×64有效字，各1片512×72 | 3 |
| R-2 顶点倒数种子 | 1份1024×18，低12位由LUTROM补全 | 1 |
| R-3 像素倒数种子 | 4lane各1024×18，低12位由LUTROM补全 | 4 |
| R-1 DMA池 | 读64×256，写32×256 LUTRAM | 0 |
| **GPU DRM总计** | **129+48+8+3+1+4** | **193** |

DMA读池4个16beat区=64×256，写池2个16beat区=32×256，共24576bit；按32bit/LUT为768 LUT容量代理，含读树/指针/寄存预留约1500 LUT、600 FF，仍支持4读/2写在途和16beat突发。命令FIFO32×256、顶点16×128、quad4×128、对象输入/更新各16×256、对象事件16×33、列表各两个256bit尾包、setup至少5项上下文（建立延迟按下表重估，II=8）、fragment/sample/shaded各两项槽均用LUTRAM/FF，计入4.11；不整表缓存。

矩阵16×32及状态、裁剪双8顶点、32项未决RMW存寄存器；LOD256项×9位小数表（索引8位，含舍入到256的端点）用组合常数分级，不占DRM。相对闭合记录约195块，本选择193少2块：当前组采用LUTRAM而非理想独立18Kb双口的2块；全芯片加保留63为**256/415=61.69%**，低于65%共3.31个百分点，按floor(415*0.65)=269块尚余13块。保留模块63已按任务提供的全芯片代理口径，IP实际占用仍由PDS确认。

### 4.9 单AXI256内部DMA仲裁

读写方向分别轮转仲裁，以最多16beat一个突发作为非抢占单位；读侧7客户，写侧4客户。每客户区间可拆为多突发，不等整区间才让别人运行。读最多4笔、写最多2笔在途，对应gpu-soc P3初值；全部本地ID取0保持顺序，ID宽仍为1，不增加ID空间。每个AR/AW握手入客户/长度/逻辑末尾队列，R按AR顺序、B按AW顺序回收；不把单ID误解成只能一笔在途。W严格跟随AW顺序，先凑齐该突发数据再发AW，AW受阻保持，禁止W串客户。

拆分算法：当前物理地址A向下32B对齐，剩余覆盖beat为ceil((A原始低5位+字节数)/32)。`n=min(剩余beat,16,(4096−(A&4095))/32)`，ARLEN/AWLEN=n−1（4bit），后续A+=32n。所有实际AXI地址32B对齐，INCR，不带SIZE/BURST端口。写首尾WSTRB与请求keep相交；读首尾keep交给拆包器。命令DESC_BASE按64B软件约束使用，不加额外检查；matrix/顶点/quad/对象/TEX_LOAD地址由json低位隐含0；列表基址32B对齐，尾部不足8项仍只写所需字节。RESOLVE按每行 `BASE + y*STRIDE + 2*x` 独立区间生成，行之间不跨stride填充，行首不32B对齐也用首尾WSTRB。

读池4区各16beat，AR发出前预留n个返回位置；即使业务反压仍有已发R的存放位置，不靠取消AXI腾空间。写池为已打包突发服务，write_data不具备空间时ready拉低。command/矩阵/顶点/quad/对象/texture/palette均走同一个读仲裁器；对象更新、命中、释放、RESOLVE均走同一个写仲裁器。TEX_LOAD/PAL_LOAD的DDR结束还不算命令结束，需等待最后RAM写握手。texture descriptor越界检查只在SET_TEX比较OFFSET+sum(Lk)与196608B容量；TEX_LOAD越界只比较dst+bytes与196608B；其他软件合法性信任内部契约。

STEP=1的OBJ_STEP中可同时对象读、对象写、列表写；推进核1对象/拍不等于单端DDR持续1对象/拍。每对象读32B、更新写32B，最坏再写8×4B命中和4B释放，DDR流量可达100B/对象；200MHz下1对象/拍要求20GB/s，超过AXI256/125MHz端口峰值4GB/s。对象性能的核吞吐和命令端到端吞吐必须分开验收；核II=1已获协调者认可为无背压测量条件；STEP=0只剩对象读和绘制流，完整命令仍另报。

### 4.10 200MHz时序预算和扇出

周期5ns，局部逻辑目标≤1.5ns、布线≤2ns，余1.5ns留setup、时钟不确定性/偏斜及拥塞；独立模块目标WNS≥+0.5ns@200MHz，整片预期180MHz、150MHz保底。均为设计目标。APM/DRM输入输出寄存，宽运算按4.6展开；40位坐标变更不能只增加寄存位而沿用旧18位尾数路径级数。

| 长路径 | 分割（结构估算） |
|---|---|
| Q30牛顿 | 31×30及30×32各ceil(31/18)×ceil(32/18)=4块，APM3+部分积/加减2，两个乘法不串级 |
| 40×35坐标 | ceil(40/18)×ceil(35/18)=6块，APM3+两层压缩/进位各2–3，完整75位输出 |
| 51×54透视UV | 3×3=9块，APM3+两层压缩/进位共6，舍入2；上下半部不提前截断 |
| s96分子反馈 | 每20位进位一拍，5拍；采用5相交错，反馈推进20像素，逐组输出；行首保存5个相位起点 |
| 精确除法 | 展开恢复除法，每步40位减/选择分2拍；相邻步寄存，不能用一个组合除号估计200MHz |
| 目标/纹理 | 地址/段CE1、DRM读/输出2、局部及最终选择各1，共5拍 |
| palette/过滤 | 完整及当前组读4拍；横积/纵积均保留精度，只有二维和末端舍入；三线性另一次舍入 |

command按单元寄存控制副本，texture按4bank、pixel按4lane、target按15段分层复制CE/写控制，局部目标每份≤32–64负载。控制不广播到整条宽数据通路，数据寄存不复位。上述预算必须由PDS的最差路径/扇出确认，不能由LUT级数宣称180/200MHz已可达。

### 4.11 每单元与全芯片资源估算及待决比较

**本次复算发现原稿资源闭合不适用于v0.2完整精度。** 协调者要求先列A/B/C的成本和图像影响，偏导方案等待用户决定；不修改规格。以下是可复算的结构估算，尤其展开除法是直接展开实现的面积代理，不是最优实现的下界；不能据此宣称规格本身不可实现，也不能把它伪报成已闭合方案。

计数口径：乘法块数M(a,b)=ceil(a/18)·ceil(b/18)，18×18软乘面积代理360 LUT、流水108 FF/块；这是结构配额，需综合校准。完整乘积的压缩/对齐在单元基础配额中计。精确n位分子/u40分母的展开除法D(n)取n步，每步减法/选择2×40=80 LUT，两级余数/控制寄存4×40=160 FF；D(n)=(80n LUT,160n FF)。这些代理不含复位或非法输入检查。

| 共用部分 | LUT估算 | FF估算 | DRM | APM估算/公式 |
|---|---:|---:|---:|---|
| regs/command | 3000 | 2300 | 0 | 0 |
| DMA/打包 | 5500 | 4400 | 0 | 2 |
| resolve/AA | 3500 | 3400 | 3 | 0 |
| transform/light | 5000 | 5400 | 0 | 22=8×2+6 |
| clip/project | 7884 | 8000 | 1 | 26=3×6+2×4；裁剪串行复用该算术池 |
| setup | 6500 | 8000 | 0 | 24=4×6，面积/属性乘共享调度 |
| raster/quad（分子加法/队列） | 6500 | 10000 | 0 | 0 |
| object | 2800 | 3000 | 0 | 0 |
| texture/filter/palette | 9000 | 10000 | 56 | 44=28过滤+16着色 |
| pixel/target | 6300 | 8000 | 129 | 24混合 |
| 精确插值除法（四lane×七属性） | 215040=28×D(96).LUT | 430080=28×D(96).FF | 0 | 0 |
| 桥/区域reset | 500 | 500 | 0 | 0 |
| **共用小计（不含像素倒数/UV/偏导）** | **271524** | **493080** | **189** | **142** |

基础LUT合计55600，另加顶点ROM低位384、插值215040、桥500=271524；FF62500+430080+500=493080。相对旧稿，s96分子加法/相位、完整乘积压缩、光照与log2表均增加基础配额；该插值除法开销是原稿只列48位平面时漏计的部分，三种LOD方案都不能消除，须独立优化实现。

**单独核算每像素倒数和UV**：每lane牛顿2×M(31,32)=8块，UV两次M(51,54)=18块，共26；四lane为104 APM，尚未包括偏导。四份1024×30种子中高18位仍用4 DRM，低12位用LUTROM，容量4×1024×12/32=1536 LUT；顶点另1份384 LUT已计上表。全APM实现的该部分为LUT 5500+1536=7036、FF 7200、DRM4、APM104；加共用142和保留10为256/740=34.59%，**UV及倒数本身也需混合映射**。

为只比较LOD的增量，以下三方案均固定像素倒数/UV为68 APM，余104−68=36等效块用LUT：LUT=7036+36×360=19996，FF=7200+36×108=11088，DRM4。全芯片APM统一为142+68+10=220/740=29.73%，floor(740×30%)−220=2块余量；这只是APM满足约束，不能当作面积/时序闭合。

A的偏导每lane四个：32×96需M=12，129×54需M=24，四lane共16×(12+24)=576软乘等效块；再加16×D(183)。故增量LUT=576×360+16×183×80=441600，FF=576×108+16×183×160=530688。除后按Q16取跨度，不截断中间乘积。

B每组只做一次上述四偏导，选组内lane0，不额外取组中心样本；其偏导面积为A的1/4：110400 LUT、132672 FF。C用于比较的具体假设为每个偏导两次18位尾数乘、指数对齐及归一化，四lane×四偏导×两乘=32软乘块，外加16×128 LUT/FF的归一化配额：13568 LUT、5504 FF；先舍入尾数，输出跨度仍Q16，误差必须M-1重测后才能形成规格。

| 方案（偏导待决，接口当前仅A） | GPU APM / 全芯片APM | GPU LUT / 全芯片LUT | GPU FF估算 | 图像影响与规格 |
|---|---|---|---:|---|
| A 每像素完整精度 | 210 / 220 | 733120 / 773120 | 1034856 | 完全遵循现v0.2；精确除法基线面积明显超预算 |
| B 四像素共用lane0 LOD | 210 / 220 | 401920 / 441920 | 636840 | UV逐像素精确；大透视变化时组内mip选择会变，可能出现4像素阶梯；需改2.6 |
| C 每像素18位尾数偏导 | 210 / 220 | 305088 / 345088 | 509672 | UV逐像素精确；LOD边界可能选相邻mip，过滤结果变化；需改2.6/2.12并复核误差 |

FF使用表列每级配额，不是网表计数；完整负载对齐和时序复制还可能增加，当前数值只用于比较结构成本。表中GPU总量=共用小计+19996 LUT/11088 FF+各方案偏导；全芯片LUT再加任务代理40000，FF只列GPU（保留模块未提供）。三种均DRM193，全芯片193+63=256/415=61.69%，保持不变；APM均220低于30%。三种展开基线均超过GPU60K目标，FF也不满足可实现性承诺，不能冻结资源账本。LUTRAM位不重复算FF；5份种子低位共1920 LUT，log2表另72 LUT容量代理，均保留完整Q30/Q8语义。

**推荐C作为数值研究方向**：保留逐像素LOD，资源显著低于A，避免B的组内阶梯；这不是已批准的数值变更。即使选择C，也必须优化共同的精确属性插值和倒数/UV软乘映射，并用综合替换当前展开基线估算；本次不擅自缩短Q30尾数、不提前舍入平面、不降低四lane吞吐。资源与偏导精度等待用户/协调者决定，4.2–4.4仍只定义现行规格的精确接口。

## 5. 影响

- 本次只修改本设计记录；不改RTL、规格、gpu.json、文件列表或测试。纯文档不运行RTL lint/仿真；执行 `git diff --check` 及4.8的纹理枚举，预期 `PASS 783363 192KiB bounds; palette 8-read preload`。
- R-1–R-4的配置/数据接口采用4.2–4.4唯一定义；数值依据v0.2，错误/停顿/排空语义保持。完整Q30种子ROM高18位/低12位分存，DRM不变，但IP说明需同步完整读出语义。
- 待决A/B/C按协调者本次答复列比较，用户决定前不得按B/C实现；选B/C需先修订规格及参考模型。精确插值/透视资源尚未闭合，需另行实现研究和PDS评估，本记录不把展开基线估算写成实测结果。
- 复现以源码基线b2ac0bb8b加本次文档提交为准；纹理公式命令见4.8，算术/资源公式见4.3/4.4/4.11，无新增报告或测量产物。

## 6. 状态

**已决定，待协调者批准冻结。** v0.2数值及当前精确接口已统一；偏导实现方案A/B/C按协调者要求标为待决，不把B/C写进接口表。DRM估算GPU193、全芯片256；按混合映射APM估算GPU210、全芯片220（29.73%）；A展开基线估算为GPU733120 LUT、全芯片773120 LUT，不能宣称满足60K目标或可实现。推荐研究C，并优化共同的精确插值/UV面积；200/180MHz、实际LUT/FF/APM及物理端口模式均待实现与PDS验证。
