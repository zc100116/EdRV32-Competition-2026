# GPU 微结构设计记录

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-24 |
| 状态 | 讨论中，待协调者评审；资源方案采用已决定的闭合方案；接口待S-1数值和协调者评审冻结 |
| 依据 | `2026-11-23-gpu-resource-closure.md`（已决定，da4c70345）、`gpu-spec.md` v0.1 全文、`gpu-soc-spec.md` v0.1、`rtl/include/regs/gpu.json`、`2026-11-23-gpu-architecture.md`、`2026-11-23-gpu-2d-estimates.md`、`gpu-plan.md` |
| 源码基线 | `7af750469fe447178c1d04297e9eede01ded0c39`（本次修订基线；原稿7ed45f8e9），分支 `zc100116/gpu` |
| 数字性质 | 以下 GPU 周期、资源、级数均为结构估算，未经综合、PDS 或上板测量；历史实测另注明出处 |

## 1. 背景和问题

GPU 需要把固定功能几何、三角形/四边形扫描、对象推进、片上纹理和片上读改写连接成一条流水线。R-1–R-4 并行开发前，需要统一状态归属、流的排列、停顿和排空语义，否则局部单元都正确也可能在重叠绘制或命令切换时产生错误。第二版只替换三角形建立之前的几何单元，因此该边界单独定义。

本文提出可直接转成 Verilog-2001 端口的候选契约。它不是修改规格的依据；数值研究 G-N1–G-N3 完成后，协调者须把获准接口及数值定稿同步到规格，再冻结并行任务。本次依用户已决定的资源闭合记录，将目标减半、纹理定为192KiB，并采用完整/当前组两级调色板；对应规格变更由S-1承接，本文件不修改规格。

## 2. 约束

- 全 GPU 只有 `clk_gpu`，按200 MHz、5ns周期设计，预期全SoC约180 MHz（G-T1开发初值），150 MHz为保底，频率待PDS定稿。内部无 CDC。GPU 外的 X9/X10/X3 分别只用已有 `axi256_async_bridge`、`apb_async_bridge`、`cdc_sync_bit`；区域复位由顶层一级 `edrv32_reset_copy` 分发，不在各模块自行同步。
- 一个渲染单元，4 条水平相邻像素通道；目标为640×180或1280×90，均为115200像素；640×360分2条、1280×720分8条。颜色 RGB565、深度 u16、模板 u8 不缩减。
- DDR 地址/命令/记录布局逐位取 `gpu.json`；操作码及枚举取 gpu-spec 2.11。下文原始命令保留256位；已决定的目标/纹理布局/STEP行为及候选TGT_X0对齐由S-1同步，数值†仍待M-1。
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

`geometry` 内部模块及 `texture` 内部模块的端口由其 worker 自行划分，不跨任务。倒数算法同源但不用一个跨worker共享RTL文件：R-2 `project` 和 R-3 `perspective` 各有本地实现，数值规则均由 S-1 统一。tech RAM/APM 包装、公共头、寄存器生成物和文件列表不归这四个 worker 修改。

### 4.2 通用内部协议与排列

以下表中 A→B 表示负载及valid由A输出、B输入，ready反向。展开端口时源端加 `_o`、目的端加 `_i`。每个流 `p` **恰有** `p_valid`（1，A→B）、`p_ready`（1，B→A）及表列负载。均在上升沿 `valid && ready` 时传输；valid不能等待ready，受阻时valid和全部负载保持。无组合跨单元ready链，接收端至少有两项弹性寄存槽；RAM读前预留返回槽。延迟指无背压下接收沿到产生输出valid的沿数，停顿时输出顺序不变，接口不依赖固定延迟。

所有打包数组小下标在低位：`lane k` 对应像素x+k，`vertex j` 对应输入顺序第j个，`component c` 顺序R/G/B。重复字段用 `[k*W +: W]` 展开；表列宽度为整个端口宽度。数值暂定的地方加 †，由 G-N1–G-N3/S-1 一次性修订，不能由worker各自改。

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

PERF只在regs累加：各单元给本地周期事件，`perf_vertex:1`、`perf_triangle:1`、`perf_quad:1`为对应输入顶点/非退化建立三角形/开始扫描四边形的握手脉冲，`perf_pixel_count:3`为该拍实际颜色写入像素数0–4，`perf_texture_stall:1`为纹理bank冲突周期，`perf_read_wait:1`为读DMA等待周期，`perf_resolve_busy:1`、`perf_object_busy:1`为占用电平；总忙由busy。多个同类事件同拍的设计只有pixel允许大于1；未用PERF读0。事件都是源输出、regs输入，无反压、不跨域。

### 4.3 几何单元的完整替换边界

几何单元只消费 `geometry_cfg`、`draw`、`vertex`、`finish` 和 `stop`，输出 `screen_triangle`、`unit_done`及顶点事件。`setup` 是独立消费者，第二版4路SIMD替换整个geometry后仍按此屏幕三角形格式输出；没有程序存储、指令口、SIMD占位参数或第二版专用逻辑。

| 流 | A→B | 信号名:位宽 | 格式和含义 |
|---|---|---|---|
| `vertex` | read_dma→geometry | `vertex_data:128` | gpu.json VERTEX的16B原样；先v0/v1/v2，再下一三角形；三角形数量来自draw；每2拍可收1顶点，无额外last端口 |
| `screen_triangle` | geometry→setup | `screen_triangle_x:48`、`screen_triangle_y:48` | 各3×s12.4（16bit），屏幕像素坐标 |
| 同一流 | 同上 | `screen_triangle_depth:48` | 3×u16，投影/映射后的深度 |
| 同一流 | 同上 | `screen_triangle_q:96`† | 3×u6.26，1/W |
| 同一流 | 同上 | `screen_triangle_uq:96`†、`screen_triangle_vq:96`† | 各3×u14.18，u*q、v*q，以纹素为单位 |
| 同一流 | 同上 | `screen_triangle_color:72` | 3×RGB888，低字节R、其次G、再B；光照后饱和 |

输出是完成五平面裁剪、投影和剔除的三角形，裁剪多边形按扇形顺序输出。完全裁掉、退化或剔除的输入不输出；setup仍独立拒绝零面积，不产生像素。几何输出done在最后一个screen_triangle握手后成立；setup自己的done另行排空。状态在接受draw前握手，直到本DRAW完成保持。无隐含顶点缓存地址、内部裁剪缓冲地址或矩阵RAM读口跨过此边界。

开发初值：矩阵32bit s15.16、输入位置s16，点乘积保留48bit，四项求和50bit后转s23.8（32bit）†；近平面W_NEAR=1/16、保护带G=4†。裁剪边距与交点比例用加宽中间值，逐面属性插值，最多8个多边形顶点（原3点加5平面各最多1点），双8项工作集放寄存器。协调者在本次D-1问答中给出的视口工作假设为：SET_TARGET空闲字承载VP_X0/VP_Y0/VP_W/VP_H；sx=VP_X0+(X/W+1)*VP_W/2，sy=VP_Y0+(1−Y/W)*VP_H/2；Z/W饱和到[0,1]后映射u16。几何按此设计，SET_TARGET原始256bit配置流包含这些状态，具体编码待S-1修订gpu.json，不在本稿另指定偏移。屏幕坐标舍入、插值截断和倒数误差由M-1/S-1逐位确认；本文不把截断方式另定为与模型竞争的规格。内部candidate格式先保证接口范围，G-N定稿若需变宽须同时重算APM/DRM。

### 4.4 建立、扫描、纹理与像素接口

| 流 | A→B | 负载信号:位宽 | 时序与语义 |
|---|---|---|---|
| `triangle_setup` | setup→raster | `triangle_setup_bounds:64` | x0/y0/x1/y1各s16，含左上不含右下；x0按4向下取整，覆盖还受边/目标裁剪；y为整数行 |
| 同一流 | 同上 | `triangle_setup_edge:480`† | 3边×4值×s40：E在首组lane0中心的值、一步x增量、一步y增量、左上偏置；同一边4值依次从低位排列；建立时统一内部方向为E>=0，左上边偏置0，其他边偏置-1，覆盖测试E+bias>=0 |
| 同一流 | 同上 | `triangle_setup_plane:1008`† | 7属性×3值×s48：首lane0中心值、每1像素dx、每1行dy；属性顺序q/uq/vq/z/R/G/B；小数位分别26/18/18/16/24/24/24。边偏置只影响覆盖，不偏移插值 |
| `quad_record` | read_dma→quad | `quad_record_data:128` | gpu.json QUAD；表顺序，无逐项命令排空 |
| `object_record` | read_dma→object | `object_record_data:256`、`object_record_idx:24` | gpu.json OBJ及对象编号，从0递增；空槽也传入以保持索引 |
| `object_quad` | object→quad | `object_quad_data:128`、`object_quad_x:17`、`object_quad_y:17` | 存活且draw=1；data承载QUAD非位置字段，其x/y位不使用；位置独立s17，p取整−半宽高，不截成外部QUAD的s12造成屏外回绕；顺序与对象表相同，不会与DRAW_QUAD源同时活动 |
| `fragment` | raster/quad有序选择→perspective | `fragment_x:16`、`fragment_y:16`、`fragment_mask:4`、`fragment_quad:1` | x/y为s16屏幕整数坐标，x是4倍数；lane位置x+k；mask为覆盖且在scissor/target内，0组不发 |
| 同一流 | 同上 | `fragment_q:128`†、`fragment_uq:128`†、`fragment_vq:128`†、`fragment_depth:64`、`fragment_color:96` | 各4lane，q/uq/vq格式同几何输出；depth4×16、color4×24；quad的q=1，uq/vq直接表示纹素坐标，color为白色 |
| 同一流 | 同上 | `fragment_gradient:192`†、`fragment_palette:4`、`fragment_alpha:8` | 梯度顺序duq/dx、duq/dy、dvq/dx、dvq/dy、dq/dx、dq/dy各s32；quad梯度不用。palette为quad项覆盖值，tri使用SET_TEX；alpha为quad全局alpha，tri=255 |
| `sample` | perspective→texture | `sample_x:16`、`sample_y:16`、`sample_mask:4`、`sample_quad:1`、`sample_u:128`†、`sample_v:128`† | 4×s16.16纹素坐标；quad绕过倒数，保留翻转方向产生的坐标；texture按尺寸取模 |
| 同一流 | 同上 | `sample_span:128`†、`sample_depth:64`、`sample_color:96`、`sample_palette:4`、`sample_alpha:8` | span每lane u16.16，为max(abs(du/dx),abs(du/dy),abs(dv/dx),abs(dv/dy))；梯度由商导数(uq'−u*q')/q得到；LOD由texture计算 |
| `shaded` | texture→pixel | `shaded_x:16`、`shaded_y:16`、`shaded_mask:4`、`shaded_depth:64`、`shaded_color:96`、`shaded_alpha:32` | 过滤/着色后4lane RGB888及A8；透明lane清mask，目标坐标/深度保持原lane；每输入组严格对应一个输出组，允许mask全0 |
| `target_read` | pixel→target | `target_read_addr:16` | 地址为目标四像素字，范围0–28799；无mask，读全160bit |
| `target_old` | target→pixel | `target_old_data:160` | 顺序响应；每lane40bit={stencil8,depth16,color16}；读请求到输出5拍：地址预译码1、DRM阵列/输出寄存2、两级选择树2；已包含同拍写回旁路 |
| `target_write` | pixel→target | `target_write_addr:16`、`target_write_data:160` | 已合并保留字段的完整字；握手沿提交逻辑结果/写寄存，下一沿完成物理RAM写；不再对未改lane做物理掩码；最终结果旁路见4.7 |
| `resolve_read` | resolve→target | `resolve_read_addr:16` | 仅RESOLVE期间允许，独占target读端；同字映射 |
| `resolve_color` | target→resolve | `resolve_color_data:64` | 5拍有序响应，每lane16bit RGB565；不读改写，不更新目标 |

四边形和三角形同一命令不混排；raster/quad只允许当前draw源输出。quad_record的s12位置先符号扩展到s17，object_quad使用独立s17位置，两路归一为同一内部扫描格式；减半宽高采用整数floor，最终按模型确认。quad不能为了隐藏开销调换精灵顺序。过滤吞吐较低时，texture持有一个4lane组并分拍发lane0/1、lane2/3（bilinear）或逐lane（trilinear），组装回原4lane，pixel看到的lane/address不变。

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

以下延迟/周期均为结构估算（200MHz），每个寄存器到寄存器路径≤3级LUT；所有DRM/APM均有输入及输出寄存。宽加/减分18–24bit片段传carry，多相交错反馈保持II；数据和valid/指数同步。II按输入输出无背压计，端到端另含DDR、预装及裁剪开销。

| 阶段 | 分级/无背压延迟估算 | II/吞吐 |
|---|---|---|
| 变换/光照 | 展开1、16矩阵积分2拍发射、APM输入/乘/输出3、四项加法树每层分2拍共4、缩位2，约12拍；光照点积/截负/环境加/颜色乘分别流水并对齐 | 顶点II=2；8乘/拍完成16项/2拍；限全在保护带内、不触发裁剪 |
| 裁剪 | 边距加减2、分类1；交点比例倒数按归一化入口后段12拍、属性APM3、加/缩位各2，共约22拍/被求交边（可流水）；双8顶点工作集 | 全内快速分类约4拍；跨五平面按边序列，膨胀会反压，完整命令另报 |
| 顶点投影 | 前导位/归一化3、种子DRM输入/读/输出3、牛顿乘各3共6、减法2、指数还原2、投影APM3、视口/深度4、剔除3，约26拍 | 倒数核II=1，顶点II=2；裁剪与投影共用数值规则，工作集有序 |
| 三角形建立 | 坐标差/面积/倒数/属性差积/初值分别切级，约36拍；宽乘/减间均寄存 | 8拍发射时隙、至少5个在途上下文，II=8；不能以36拍延迟充当II |
| 三角形扫描 | 40bit边/48bit属性加法分两级，两相交错组号0/2/4与1/3/5，反馈+8dx；组内四lane并行常数增量，比较/mask2级，约5拍 | II=1，4像素/拍；每行两相起点独立+dy，行尾不插泡，输出仍按组序 |
| 四边形扫描 | 建立2、位置/UV/翻转2、mask1，约5拍；当前/下一记录预建 | 连续16×16为64组（对齐）或80组（不齐），稳态≤80拍/个，建立/换行不额外插泡 |
| 像素透视 | 四份18bit尾数倒数：归一化3+种子3+牛顿乘6+减2+还原2=16；UV乘3、缩位2；偏导两乘各3、差2、取最大2，约31拍并对齐 | 4lane、II=1；每lane2个牛顿APM+4个UV APM+8个偏导APM† |
| 纹理过滤 | LOD4、地址3、纹理RAM/树5、palette4；横lerp差2+乘3+加2、纵同7；三线性同样再7；着色乘3+d2；nearest约21、bilinear约35、trilinear约42拍 | nearest4（无冲突）、bilinear2、trilinear1像素/拍；后两者任意UV。RGBA乘积保留全精度 |
| 像素运算 | mask1、目标读5、模板/深度比较2、模板更新2、因子/展开2、APM3、d2、op2、饱和/P565/合并2、提交1，共22拍 | II=1、4像素/拍，无同字未决依赖；d不是简单右移 |
| 对象STEP=1 | 读取alive1、v加2、p/寿命2、存活区2、八框并行比较2、hit/free/count2、输出1，共12拍 | II=1，不含绘制/DDR；8命中mask一次输出，列表拥堵反压 |
| 对象STEP=0 | 原alive判定1、quad位置2、输出1，共4拍 | II=1，只绘制原存活项；无区域/碰撞/列表/写回路径 |
| AA | 亮度2、min/max树2、绝对差2、阈值/方向2、加权和2、P565/打包2，共12拍 | 四像素/拍，独立于像素RMW，不改目标 |

矩阵、裁剪空间、比例、面积倒数、q/uq/vq、48bit平面、18bit尾数/指数和LOD偏导格式均为†，须随G-N1–G-N3误差研究定稿；DDR格式、s12.4屏幕坐标、u16深度、u8.8外部UV不变。宽乘先扩展，缩位/舍入由模型统一；每一级不得自行丢精度。顶点投影完整倒数16拍，裁剪交点比例共享算法可将已归一化边距入口后段约12拍作为估算，不能跳过数学步骤。

**RESOLVE估算**：三行缓冲各最多1280像素，每拍各读64bit，用上一/当前/下一字拼水平邻居；先填两行，流水同时装入下一行，边界复制写出区域端点。每目标字仅读一次；每条115200像素核心28800拍。640×180预读≤320拍，1280×90预读≤640拍，各另留256拍启动/尾包/B响应基础配额。

640×360按两次640×180 RESOLVE合计核心57600拍，启动预算2*(320+256)=1152拍，合计58752拍；0.5ms在200/180/150MHz允许100000/90000/75000拍，额外DDR等待余量分别41248/31248/16248拍。两条共460800B、14400beat，0.5ms需≥0.9216GB/s；稳态每4GPU拍一beat，在200/180/150MHz分别1.6/1.44/1.2GB/s。DDR仍125MHz，不能按GPU峰值保证B返回；上述余量必须perf实测，且不含两条之间的重新绘制。1280×720八条总核心230400拍，另测全屏总周期。

### 4.7 同字读改写与命令串行等效

采用协调者候选 `TGT_X0[1:0]=0`（S-1待用户确认），TGT_Y0任意；软件保证，不在RTL新增对齐检查。屏幕x为4倍数，因此目标字地址 `a=(y−TGT_Y0)*(width/4)+((x−TGT_X0)>>2)`，范围0–28799，lane直接对应目标像素，不需要重新对齐、拼接或拆字。地址口保留唯一16bit，高位自然为0；width/4分别160/320。

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

**纹理布局（已决定，待S-1同步）**：4体×48KiB，每体24576×16，12段2048×18，共**48块**；两半各96KiB，以物理字节地址<98304/≥98304区分（不再使用byte[17]划分）。请求地址/段预译码寄存1、DRM读/输出寄存2、12段按3组4选1及最终3选1各1，共5拍；两读端树独立，段号/valid同步。

16bit字覆盖的纹素块为I4的2×2、I8的2×1、RGB565的1×1；体号=(块x&1)|((块y&1)<<1)。最近邻任意4lane可以集中一个体的4个不同字，此时按lane顺序用双口分两拍、同址合并，PERF5计冲突停顿；已取得的结果保留，不重复取样。四边形连续4像素在I4中最多跨3个相邻字块，无此最坏集中冲突。

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

离线工具输出上述交织字流，TEX_LOAD按字线性复制，体号仅取目标半字地址低2位；32B装入beat拆4拍，每拍4体各写一个16bit字，ready反压。在线重排需知道每个待装纹理的尺寸/格式/mip及源起始，TEX_LOAD现有字段没有这些信息，不能借当前SET_TEX推断，故不推荐为此新增硬件状态/端口。离线方案需在gpu-spec2.6和gpu.json相关说明中明确新布局、padding及物理大小计算，由工具/参考模型/RTL统一；本稿不修改已确认规格。

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
| R-2 顶点倒数种子† | 1份1024×18 | 1 |
| R-3 像素倒数种子† | 4lane各1024×18 | 4 |
| R-1 DMA池 | 读64×256，写32×256 LUTRAM | 0 |
| **GPU DRM总计** | **129+48+8+3+1+4** | **193** |

DMA读池4个16beat区=64×256，写池2个16beat区=32×256，共24576bit；按32bit/LUT为768 LUT容量代理，含读树/指针/寄存预留约1500 LUT、600 FF，仍支持4读/2写在途和16beat突发。命令FIFO32×256、顶点16×128、quad4×128、对象输入/更新各16×256、对象事件16×33、列表各两个256bit尾包、setup至少5项上下文（36拍延迟/8拍II）、fragment/sample/shaded各两项槽均用LUTRAM/FF，计入4.11；不整表缓存。

矩阵16×32及状态、裁剪双8顶点、32项未决RMW存寄存器；LOD16项小数表用组合常数分级，不占DRM。相对闭合记录约195块，本选择193少2块：当前组采用LUTRAM而非理想独立18Kb双口的2块；全芯片加保留63为**256/415=61.69%**，低于65%共3.31个百分点，按floor(415*0.65)=269块尚余13块。保留模块63已按任务提供的全芯片代理口径，IP实际占用仍由PDS确认。

### 4.9 单AXI256内部DMA仲裁

读写方向分别轮转仲裁，以最多16beat一个突发作为非抢占单位；读侧7客户，写侧4客户。每客户区间可拆为多突发，不等整区间才让别人运行。读最多4笔、写最多2笔在途，对应gpu-soc P3初值；全部本地ID取0保持顺序，ID宽仍为1，不增加ID空间。每个AR/AW握手入客户/长度/逻辑末尾队列，R按AR顺序、B按AW顺序回收；不把单ID误解成只能一笔在途。W严格跟随AW顺序，先凑齐该突发数据再发AW，AW受阻保持，禁止W串客户。

拆分算法：当前物理地址A向下32B对齐，剩余覆盖beat为ceil((A原始低5位+字节数)/32)。`n=min(剩余beat,16,(4096−(A&4095))/32)`，ARLEN/AWLEN=n−1（4bit），后续A+=32n。所有实际AXI地址32B对齐，INCR，不带SIZE/BURST端口。写首尾WSTRB与请求keep相交；读首尾keep交给拆包器。命令DESC_BASE按64B软件约束使用，不加额外检查；matrix/顶点/quad/对象/TEX_LOAD地址由json低位隐含0；列表基址32B对齐，尾部不足8项仍只写所需字节。RESOLVE按每行 `BASE + y*STRIDE + 2*x` 独立区间生成，行之间不跨stride填充，行首不32B对齐也用首尾WSTRB。

读池4区各16beat，AR发出前预留n个返回位置；即使业务反压仍有已发R的存放位置，不靠取消AXI腾空间。写池为已打包突发服务，write_data不具备空间时ready拉低。command/矩阵/顶点/quad/对象/texture/palette均走同一个读仲裁器；对象更新、命中、释放、RESOLVE均走同一个写仲裁器。TEX_LOAD/PAL_LOAD的DDR结束还不算命令结束，需等待最后RAM写握手。texture descriptor越界检查只在SET_TEX比较OFFSET+sum(Lk)与196608B容量；TEX_LOAD越界只比较dst+bytes与196608B；其他软件合法性信任内部契约。

STEP=1的OBJ_STEP中可同时对象读、对象写、列表写；推进核1对象/拍不等于单端DDR持续1对象/拍。每对象读32B、更新写32B，最坏再写8×4B命中和4B释放，DDR流量可达100B/对象；200MHz下1对象/拍要求20GB/s，超过AXI256/125MHz端口峰值4GB/s。对象性能的核吞吐和命令端到端吞吐必须分开验收；核II=1已获协调者认可为无背压测量条件；STEP=0只剩对象读和绘制流，完整命令仍另报。

### 4.10 200MHz时序预算和扇出

周期5ns，局部目标逻辑≤1.5ns、布线≤2ns，余1.5ns留setup、时钟不确定性/偏斜及SoC拥塞；独立模块目标WNS≥+0.5ns@200MHz，整片预期180MHz（5.556ns），150MHz（6.667ns）保底。均为设计目标，不是测量承诺。所有路径每级≤3级LUT，APM/DRM输入、输出均寄存；不能把长carry或桶移位藏在一个“加法”名称内。

| 长路径 | 每级预算/分割（估算，均≤3级LUT） |
|---|---|
| 倒数/牛顿 | 前导位/归一化3拍；ROM输入/阵列/输出3；两个乘法各APM3；2−乘积减法分2；指数还原2。禁止串两个乘法 |
| 透视/偏导 | UV宽乘APM3，缩位2；每导数两次APM各3，中间差2、指数对齐2；跨度比较树2；属性/指数延迟对齐 |
| 双线性/三线性 | 每方向lerp的差值2、乘APM3、加法/取位2，共7；三线性多一级同构核，不能提前计算尚未返回的颜色差 |
| 混合/着色 | 因子选择/展开2；APM3；d两级；ADD/SUB/MIN/MAX各2；饱和/P565/合并2；24混合乘与16着色乘分开流水 |
| 边函数/属性 | 40/48bit加分20/24bit两拍，两相交错反馈保持每拍一组；符号/左上覆盖/mask2；面积乘积APM3后积差分2 |
| 矩阵/光照 | 32×16乘输入/乘/输出3；加法树每层2；坐标缩位2；点积、max、环境加和颜色乘分别寄存 |
| 目标/纹理返回 | 地址/段CE寄存1，DRM阵列/输出2，4选1局部1、最终4/3选1再1，共5拍；每个mux独立一层，不合并树 |
| 调色板/LUTRAM | 完整表4段选择单级；小副本分页读树分级并保持4拍；DMA宽口同样本地分页、输出寄存 |
| AA | 亮度、min/max、差、方向比较、加权和、P565各2拍，合计12；跨字邻居选择先寄存 |

历史依据：`2026-11-08-rnd-fmax-eval.md` 引卡68R2源 `49448d0c89ccecda82aa7bf23a5b9c82fdf98791`、回传 `a5d08903812061a894dd8cdfff970fc77eefbb0d`，PDS2022.2-SP6.1/PG2L200H-6，125MHz内部最差+0.153ns；9级地址链为逻辑1.779ns/走线5.446ns，另一个0级command→APM路径走线5.830ns。原始文件 `tasks/win/20261108-68-soc-v021-full/artifacts/R2/native_reports/edrv32_fpga_board_full_top.rtr.gz`、`timing_setup_top200.txt`。这说明低逻辑级数仍可被跨区域布线拖垮，不能直接据旧RND数据宣称GPU的200/180MHz可达。

`2026-11-13-resource-slim-media.md` 的卡70ADS/高扇出原文来自 `7153d605cc6c66fa7f415b22bbe8d5b40da7ff08`，源码 `ce2b4fd42edc526fa702fd08071e14b4c2a0353a`：cancel约680、state582、blend_valid/tag519负载。GPU的stop/valid/状态不广播到整个宽数据通路：command按单元寄存控制副本；texture按4bank、pixel按4lane、target按15段分层复制CE/写控制，局部目标每份≤32–64负载，再以PDS扇出/布线检查调整。仅控制复制，不复制全部256bit数据。

`2026-11-14-fanout-rnd.md`（接续b8c5e211）是Yosys0.70+219参考测量，不是PDS：位列offset负载197–226→60–62、选择256→每份32；`2026-11-14-fanout-npu.md`（09290bda基线）控制按8份/64份切片后每份32或8–9。此处只借鉴局部复制组织，不能把该负载数换算GPU实际WNS。物理副本按需要keep/syn_preserve，避免综合重新合并；数据寄存不加复位，控制reset来自区域副本。

### 4.11 每单元与全芯片资源估算

采用一乘积一APM保守口径，32×16/32×18宽乘各2个18×18等效APM；偏导†为18bit尾数+指数，每lane4导数各两乘=8APM。颜色小乘移APM：过滤两bilinear核各3次lerp×RGBA4通道=24，加三线性末级4，共28（差值9×权重8，不假设能双打包）；四像素RGB着色12+全局alpha4=16；混合4lane×RGB3×源/目标2=24。总小乘68APM，不复用不同流水级去损失II。

若一个APM能独立打包两个8×8乘法且输入/输出无串扰，着色和混合40乘或可20APM实现，省20；**待Windows确认的假设，不计基线**，9×8 lerp不列入双打包。顶点光照的小乘已计transform/light，不重复算。实际APM模式与标准乘法推导由tech/PDS确认；不在业务RTL手写门级乘法。

| 单元 | LUT估算 | FF估算 | DRM | APM估算/公式 |
|---|---:|---:|---:|---|
| R-1 regs/command | 3000 | 2300 | 0 | 0 |
| R-1 DMA/打包 | 5500 | 4400 | 0 | 2，地址配额 |
| R-1 resolve/AA | 3500 | 3400 | 3 | 0 |
| R-2 transform/light | 4800 | 5000 | 0 | 22=8*2+6 |
| R-2 clip/project | 5500 | 5800 | 1 | 12，共享比例/坐标 |
| R-2 setup | 4500 | 4800 | 0 | 12，共享梯度/面积 |
| R-3 raster/quad | 4500 | 5600 | 0 | 0 |
| R-3 perspective | 5500 | 7200 | 4 | 56=4*(2+4+8)† |
| R-3 object | 2800 | 3000 | 0 | 0 |
| R-4 texture/filter/palette | 8400 | 8500 | 56 | 44=28过滤+16着色 |
| R-4 pixel/target | 6300 | 8000 | 129 | 24混合 |
| **GPU业务总计** | **54300** | **58000** | **193** | **172** |
| GPU边界桥/区域reset配额 | 500 | 500 | 0 | 0 |
| **GPU合计** | **54800** | **58500** | **193** | **172** |
| 保留模块（任务给定代理） | 40000 | 未提供 | 63 | 10 |
| **全芯片估算** | **94800 LUT** | GPU58500+保留FF待实测 | **256 DRM** | **182 APM** |

LUT业务和=3000+5500+3500+4800+5500+4500+4500+5500+2800+8400+6300=54300；FF为各流水有效位/队列配额之和58000，不把LUTRAM位重复计FF。基于旧稿56300 LUT，移除68个小乘×约40LUT≈2720、DMA浅池约+1000、当前组约+1600、目标少选通约−1000、其他分级/选择归并约−880，得54300，都是结构配额而非综合结果。texture8400包含1600当前组LUTRAM，DMA5500包含约1500池配额。

全芯片DRM=193+63=256（61.69%），APM=172+10=182（24.59%）；65% DRM最多269块，25% APM最多185块，分别余13和3块。GPU相对约195目标低2块；APM余量只有3块，数值†若变宽或PDS拆乘超过估算就需协调者重算，不能宣称已实测闭合。GPU LUT54800距60K为5200，全芯片94800约等于原95K配额；FF及实际CLM打包/布线待PDS，不能由LUT比例保证200MHz。

## 5. 影响

- 本次只修订本设计记录，无RTL、规格、寄存器JSON、文件列表或测试修改。RTL lint和仿真不适用于这次纯文档提交；执行 `git diff --cached --check` 及表格/算术人工检查，纹理/192KiB边界/当前组副本公式检查输出 `PASS 783363 192KiB bounds; palette 8-read preload`。
- 协调者评审后须在规格明确内部接口及性能条件，再以S-1数值方案替换†初值。R-1–R-4只按同一次冻结版本编码，接口位宽调整不能在某个worker内单独完成。
- 后续已有验证任务覆盖命令串行、透明/模板/混合次序、同字连续RMW、TGT_X0按4对齐（候选待确认）、双形状、五平面裁剪、bank冲突、4KiB/尾包、列表溢出、B完成后发布及ABORT排空；此处不新增测试方案或RTL检查。perf需分别记录无冲突核吞吐、对齐开销、DDR等待、命令总周期，以验证gpu-spec7，不能只报理想像素核速率。
- GPU IP说明需覆盖160bit目标分段、四体纹理双读、两份完整palette及八份当前组LUTRAM、三行AA、倒数ROM、DMA分布式共享池；每种读延迟/双口碰撞要和包装模型一致。PDS须同时给实际DRM/APM/总LUT和全SoC最差路径/扇出，不能从Yosys映射直接宣称200MHz。
- 本文历史证据复现：`git show a5d08903812061a894dd8cdfff970fc77eefbb0d:tasks/win/20261108-68-soc-v021-full/artifacts/R2/timing_setup_top200.txt`，同提交读取native_reports及high_fanout；`git show 7153d605cc6c66fa7f415b22bbe8d5b40da7ff08:tasks/win/20261108-70-soc-npu-post/artifacts/resource_hier.txt`。本文估算可由4.6/4.8/4.11所列整数和公式复算，无新增测量产物。

## 6. 状态

**讨论中，待协调者评审。** 目标减半、192KiB纹理、调色板两级组织、200MHz级数预算、STEP=0只绘制及无损RAM优化采用资源闭合决定；对应规格由S-1同步。TGT_X0低2位为0仍是协调者候选，待用户确认；本稿只保留此一套地址逻辑。

数值†待M-1/S-1定稿，内部接口经协调者批准后冻结。顶点II=2限普通全内三角形、对象II=1不含绘制/DDR，均按无背压单元稳态验收；另报完整命令周期。双线性2/三线性1按任意UV验收，不加bank条件。当前组预装264拍计入每条符合条件DRAW_TRI总周期。

DRM预算193、全芯片256/415已在结构估算内满足≤65%，APM全芯片182/740满足≤25%但仅余3块；200/180MHz及RESOLVE等待余量、LUT/FF/物理RAM端口模式均待Windows PDS实测。18Kb半块独立双口和双8×8打包都没有被当作已确认能力；不保留额外备用RTL实现。
