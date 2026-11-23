# GPU 微结构设计记录

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-24 |
| 状态 | 讨论中，待协调者评审；本文接口是冻结候选，尚不授权 R-1–R-4 开工 |
| 依据 | `gpu-spec.md` v0.1 全文、`gpu-soc-spec.md` v0.1、`rtl/include/regs/gpu.json`、`2026-11-23-gpu-architecture.md`、`2026-11-23-gpu-2d-estimates.md`、`gpu-plan.md` |
| 源码基线 | `7ad024c9db840c12522a79a80094495eeff71153`，分支 `zc100116/gpu` |
| 数字性质 | 以下 GPU 周期、资源、级数均为结构估算，未经综合、PDS 或上板测量；历史实测另注明出处 |

## 1. 背景和问题

GPU 需要把固定功能几何、三角形/四边形扫描、对象推进、片上纹理和片上读改写连接成一条流水线。R-1–R-4 并行开发前，需要统一状态归属、流的排列、停顿和排空语义，否则局部单元都正确也可能在重叠绘制或命令切换时产生错误。第二版只替换三角形建立之前的几何单元，因此该边界单独定义。

本文提出可直接转成 Verilog-2001 端口的候选契约。它不是修改规格的依据；数值研究 G-N1–G-N3 完成后，协调者须把获准接口及数值定稿同步到规格，再冻结并行任务。发现的资源闭合及性能测量条件问题见第 6 节；没有通过减小渲染目标、纹理容量或吞吐掩盖它们。

## 2. 约束

- 全 GPU 只有 `clk_gpu`，开发初值 150 MHz，周期 6.667 ns。内部无 CDC。GPU 外的 X9/X10/X3 分别只用已有 `axi256_async_bridge`、`apb_async_bridge`、`cdc_sync_bit`；区域复位由顶层一级 `edrv32_reset_copy` 分发，不在各模块自行同步。
- 一个渲染单元，4 条水平相邻像素通道；目标为 640×360 或 1280×180，均为 230400 像素。颜色 RGB565、深度 u16、模板 u8 不缩减。
- DDR 地址/命令/记录布局逐位取 `gpu.json`；操作码及枚举取 gpu-spec 2.11。下文的原始命令负载保留全部 256 位，不引入另一套外存 ABI。
- 按命令及表内顺序提交。只有 RESOLVE 写出颜色到 DDR；对象/列表写回仍按规格进行。可见完成须等最后 B 响应。
- 只做规格第 6 节的四种错误和规定的列表溢出、PERF0–8；无超时、非法内部输入检查、额外统计、自动降级或恢复路径。验证断言留在 testbench。
- 数据寄存器和 RAM 不复位，仅控制状态复位；业务 RTL 无条件编译。RAM/APM 由固定 tech 包装承接，IP 说明与生成由协调者安排。

## 3. 可选方案

| 取舍 | 方案 A | 方案 B | 选择及理由 |
|---|---|---|---|
| 命令并行 | 每条命令排空后才执行下一条；预取命令可继续 | 多条命令带状态标签并行，维护 RAM/纹理依赖 | A。四边形在同一 DRAW 内连续流动，不在每个四边形间排空；避免把约 15 拍像素延迟重复计入每个小精灵 |
| 渲染目标 RAM | 颜色/深度/模板分开：原生 2048×18 组织，4×29+4×29+2×29=290 块 | 合并 160 位四像素字：9 个 18 位切片，29 段，共 261 块 | B。每个像素操作都读完整字，禁写字段沿用旧值，减少宽度取整浪费；逻辑上仍分别有颜色64、深度64、模板32 |
| 纹理读口 | 复制四份全纹理，独立读口 | 一份纹理按2×2字块奇偶分4体，每体双读；仅nearest任意4lane可能冲突 | B。A 仅纹理就约256块，预算不可接受；B 保留完整请求，停顿影响性能，不改变颜色 |
| 调色板 | 两份双读，合计4读口 | 四份双读，合计8读口 | B。双线性2像素/拍、三线性1像素/拍均需8纹素/拍；任意索引不能依靠分组避免冲突 |
| TEX_LOAD布局 | DMA按当前描述符重排 | 工具离线按字块交织，DMA仍拷贝 | 离线方案。TEX_LOAD命令没有格式/尺寸字段，当前SET_TEX也未必描述待加载纹理；在线重排需新增描述符约束或端口，离线仅需定稿存储ABI |
| 几何边界 | 几何输出边方程和属性平面 | 几何输出屏幕空间三角形，独立建立单元输出平面 | B。第二版替换时无需理解扫描器；建立单元留在原位置 |
| 算术映射 | 全部乘法映射 APM | 宽数值乘法用 APM，8位颜色乘法用 LUT 流水 | B。全 APM 仅四通道混合就要24个8×8乘积，另有过滤/着色，难守120预算；LUT代价列入估算 |
| AA 写出 | 一个像素/拍，230400拍=1.536ms | 四像素/拍、三行缓冲，57600拍=0.384ms | B。A 在不计 DDR 等待时已不达标 |

## 4. 决策（候选）

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
| R-4 | `texture`、`texture_ram`、`palette` | LOD、请求排程/去重/冲突、256KiB分体RAM、8端口调色板、三种过滤、着色 |
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

几何单元只消费 `geometry_cfg`、`draw`、`vertex` 和 `stop`，输出 `screen_triangle`、`unit_done`及顶点事件。`setup` 是独立消费者，第二版4路SIMD替换整个geometry后仍按此屏幕三角形格式输出；没有程序存储、指令口、SIMD占位参数或第二版专用逻辑。

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
| `target_read` | pixel→target | `target_read_addr:16` | 地址为目标四像素字，范围0–57599；无mask，读全160bit |
| `target_old` | target→pixel | `target_old_data:160` | 顺序响应；每lane40bit={stencil8,depth16,color16}；读请求到输出3拍：分段地址寄存、DRM读、局部选择寄存；已包含同拍写回旁路 |
| `target_write` | pixel→target | `target_write_addr:16`、`target_write_data:160` | 已合并保留字段的完整字；一次握手在该沿提交RAM；不再对未改lane做物理掩码；最终结果旁路见4.7 |
| `resolve_read` | resolve→target | `resolve_read_addr:16` | 仅RESOLVE期间允许，独占target读端；同字映射 |
| `resolve_color` | target→resolve | `resolve_color_data:64` | 3拍有序响应，每lane16bit RGB565；不读改写，不更新目标 |

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
| `palette_load` | read_dma装入适配→palette | `palette_load_idx:12`、`palette_load_data:20` | group*256+entry；每beat拆8个PAL_ENTRY逐项广播写四份；高12位DDR填充忽略 |
| `object_update` | object→写回适配 | `object_update_idx:24`、`object_update_data:256` | 仅step=1，保持原记录未定义位及非运动字段；更新alive/p/v/life；地址基址+32*idx |
| `object_event` | object→列表打包适配（R-1） | `object_event_idx:24`、`object_event_hit:8`、`object_event_free:1` | 每对象一次，hit位k对应目标k；先按对象顺序，再按目标编号递增压缩列表；free是本次由活变死；空槽不计free。命中/释放是否同时产生严格依2.9及模型的顺序 |

对象result计数由object统计未截断事件总数，hit每拍popcount8、free/alive各0/1。R-1打包器只对容量内条目写DDR，full后停止追加；对象单元得到同一配置快照，以实际计数和MAX比较形成规定的overflow。两边不重复统计可见寄存器，也不添加第二套溢出行为。尾部用WSTRB保留容量外及相邻数据。

### 4.6 流水线、数值与吞吐

以下II为可连续接收的发起间隔，延迟为估算；有限FIFO满时反压是协议行为。性能要分别测算术核稳态和带DDR命令总周期，不用前者代替后者。

| 阶段 | 流水拆分与估算延迟 | II/吞吐及成立条件 |
|---|---|---|
| 变换/光照 | 输入展开1；8个宽乘法器分2拍做16项；乘法2；两层加法各1；坐标缩位1。光照并行点积、max、环境/方向色、颜色乘积，约8拍 | 输入II=2，16项矩阵乘/2拍=8项/拍；无裁剪/下游停顿时1顶点/2拍 |
| 裁剪 | 五平面依次处理，边距、t倒数、属性插值分级；两个8点工作集 | 普通全内三角形快速分类后通过，跨平面走边序列；输出膨胀及裁剪耗时须单独报告，不能承诺任意裁剪仍每2拍一个原始顶点 |
| 顶点投影 | 归一化/前导位2，10bit索引ROM1，牛顿两次乘法各2，中间减法1，指数还原1，投影乘法2，视口/深度1，剔除2，约14拍 | 倒数流水II=1，几何输入II=2；W_NEAR=1/16和G=4均为† |
| 三角形建立 | 坐标差/边系数、面积、面积倒数、属性差积、平面初值分级；约24拍 | 多上下文流水，面积倒数II≤8，7组属性共享宽乘法按8拍时隙发射；每8拍可收一个三角形，非24拍才收下一个 |
| 三角形扫描 | 行起点寄存；三边各4lane比较；7属性4lane增量；mask；约3拍 | 一个4像素组/拍；边步进为E+dx、+2dx、+3dx，下一组+4dx，行末用独立行起点+dy，避免累积漂移 |
| 四边形扫描 | 当前/下一记录双上下文；建立1拍；每行4/5组；行尾下一行预计算，无气泡 | 16×16对齐64组、不对齐80组；在同DRAW内重叠建立，稳态≤80拍/个。平均76只是2D估算，验收使用最坏横向余数 |
| 像素透视 | 四份18bit规格化尾数倒数核†，LZ/ROM/两次乘法/减法/还原约9拍，uq*w和vq*w各2拍，梯度差/乘分开，约16拍 | 4lane并行II=1；归一化指数单独携带。宽乘法按32×18拆两APM，禁止一个组合路径串倒数和透视乘法 |
| 纹理过滤 | LOD前导1/4bit小数表/偏置与clamp3拍；地址2；RAM2；调色板1；横lerp乘/加各1；纵lerp乘/加各1；三线性再乘/加各1；着色乘/d各1 | nearest4像素/拍（无bank冲突）；bilinear2、trilinear1像素/拍对任意UV；每拍8个tap及8个palette读口 |
| 像素运算 | 透明mask1；目标读3；模板/深度比较1；模板操作1；展开/因子选择1；8×8乘法2；d和op1；饱和/P565/合并1；提交1 | 无同字未决依赖时4像素/拍；颜色d严格用RND定义，不用简单右移近似 |
| 对象核 | 存活/步进1；速度相加1；位置/寿命1；存活区判定1；八框并行重叠1；hit/free/count1；输出寄存1 | II=1，不含绘制；8命中用mask并行输出。写回和列表带宽不足时反压，不丢事件 |

矩阵格式、裁剪空间/比例、面积倒数、q及uq/vq、48bit平面、18bit倒数尾数、LOD与偏导格式都属于†开发初值，须由G-N1–G-N3误差研究一起定稿；DDR格式、s12.4屏幕坐标、u16深度、u8.8外部UV不随本记录改变。所有乘法先显式扩宽、再按模型指定位置缩位。颜色滤波过程中保留乘积和至少权重小数位，最后按模型统一舍入；不能每一级自行减少精度以省资源。

**RESOLVE估算**：目标读每拍4pixel，AA也4pixel；3行循环缓冲，每行最大1280pixel，输出时上/中/下各取一个64bit字，水平邻居由上一字/本字/下一字寄存拼接。先准备两行再输出第一行，区域外邻居复制区域边界像素，不能使用区域外目标数据。亮度加法、min/max树、方向绝对差、阈值/方向比较、逐通道(2C+邻居和)>>2、P565分别寄存，约8拍。流水同时填下一行，目标RAM每字只读一次；最后一行使用复制邻居。

640×360核心57600拍，预读两行上界320拍、启动/尾部及打包预算256拍，剩余至75000拍约16824拍给DDR背压和B排空。输出460800B=14400 AXI beat；0.5ms要求有效写带宽至少0.9216GB/s，流水平均每4个GPU拍1beat，需1.2GB/s；不能把4.8GB/s的clk_gpu端口峰值当DDR保证。若默认模型及P3仲裁无法把额外等待限制在上述余量内，指标不成立，须交协调者处理。1280×180也为57600核心拍，行预读640拍，需另测。

### 4.7 同字读改写与命令串行等效

目标逻辑字地址 `a = (y−TGT_Y0)*(width/4) + ((x−TGT_X0)>>2)`；由于TGT_X0不保证4对齐，**在扫描输出到目标读之前**，pixel将屏幕4lane按目标相对x重新对齐，必要时拆成相邻两个目标字，mask、颜色、深度、alpha一起转移。不可直接用屏幕x/4作目标地址。无偏移对齐时一组一字；对不对齐偏移，先在pixel入口以相邻屏幕组拼接完整目标字、只对目标行首尾输出部分字，不能让每个屏幕组都永久拆成两笔而将吞吐减半。拼接保持图元顺序且在图元结束刷新尾字；第7节4pixel/拍指标按连续目标字测，任意偏移边界开销另测。

每个未完成RMW保留地址/新160bit/结果ready。读请求进入pixel前查所有未提交项，按程序顺序选最近前驱：

1. 无同址前驱：发target_read；RAM读响应可与更早写回同址，target用提交字做优先旁路，禁止依赖IP同址read-during-write的未定行为。
2. 最近前驱的最终合并字已就绪：直接转发该完整字，不发RAM读。
3. 最近前驱尚在比较/混合流水：该后继保留在入口，暂停发射直到结果就绪；不读取陈旧RAM字，也不把多个Alpha混合当可交换运算。

这是地址依赖记分而非额外输入检查，最多覆盖pixel流水有效项（按12项环，满则反压）。结果提交后保留一个最近写字旁路寄存，覆盖RAM读延迟窗口；pixel按有序读请求分配内部返回槽号并按有序响应回收，不跨worker传tag。同址连续RMW在结果产生前必须停顿，不能虚称任意反复写一个字仍4pixel/拍。普通16×16扫描的同址距离至少64拍，足以隐藏流水依赖，保证四边形目标。

command对DRAW发送结束后，等geometry/setup/raster/object/texture/pixel/target相关done及DMA完成，再改变状态或启动下一命令。命令预取只读命令，不发下一命令的数据DMA。SET_MATRIX等状态更新发生在排空后；TEX_LOAD/PAL_LOAD等所有写入RAM握手完才允许后续绘制。RESOLVE独占target，CLEAR也独占读写，部分清除同样按整字保留字段。最后DONE再等read/write DMA全idle；OBJ_STEP结果等对象表、命中、释放三类最后B返回才发布。ABORT停止业务生成，已经接收的DMA区间及AXI事务全部排完，AXI无未完成事务后IDLE；不保证目标内容。

### 4.8 片上RAM物理组织及DRM账本

**区分容量下限与可用端口映射。** 36Kb=36864bit=4608B；仅以总bit除36864会得颜色100、深度100、模板50、纹理57等容量下限，无法说明原生宽度空位、bank及端口复制。下表按36Kb块等效的原生2048×18、1024×36、512×72配置估算；实际IP支持的双口宽深/输出寄存仍须Windows确认，不能视为PDS结果。

目标160bit按4lane×40bit排列，切成9份18bit（最高2bit不用），地址低11bit为段内字，高5bit选择29段，最后只用256字。逻辑一字中color64/depth64/stencil32完整覆盖两种形状；同一逻辑字的9切片读写同拍。宽深分段与输出树局部寄存，禁止261块RAM输出接一个大组合mux。每段预译码、读端保留段号两拍，再分组树选输出。每个物理段仅一个读口和一个写口；写全160bit，避免按颜色/深度/模板写使能导致另一种RAM布局。

**纹理布局候选（协调者要求评估，待S-1定稿）**：4体×64KiB，每体32768×16有效bit，16段2048×18，合计64块。16bit字覆盖的纹素块为I4的2×2、I8的2×1、RGB565的1×1；体号=(块x&1)|((块y&1)<<1)。最近邻任意4lane可以集中一个体的4个不同字，此时按lane顺序用双口分两拍、同址合并，PERF5计冲突停顿；已取得的结果保留，不重复取样。四边形连续4像素在I4中最多跨3个相邻字块，无此最坏集中冲突。

对任意一个双线性2×2纹素足迹，跨越的字块在x和y方向各不超过2个，故每体最多一个不同16bit字；一个字可提供多个所需纹素，读取后按块内位置拆tap。两个任意双线性足迹最多每体两字，使用双口，不需要冲突重放；三线性两级各一个足迹亦最多每体两字，故保证任意UV下2像素/拍双线性、1像素/拍三线性。尺寸为2的幂，环绕从末字块到首字块保持奇偶差；块网格只剩一列/一行时重复地址合并，小mip见下面padding规则。两半是线性物理byte[17]，各128KiB，不复制纹理。

唯一候选地址公式：格式块宽高(bw,bh)依次(2,2)/(2,1)/(1,1)，第k级Wk=max(1,W>>k)、Hk=max(1,H>>k)，块网格Bx=ceil(Wk/bw)、By=ceil(Hk/bh)，每级占字节 `Lk=8*ceil(Bx/2)*ceil(By/2)`。Pk=SET_TEX.OFFSET+sum(Lj,j<k)。纹素u/v先按Wk/Hk环绕，块坐标bx=floor(u/bw)、by=floor(v/bh)，物理半字地址：

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

原始总量以每级ceil(Wk*Hk*bits/8)相加，I4若按不取整的纯bit数为43690.5B（87381个纹素×0.5），对应增加13.5B、膨胀约0.030899%；其余格式无半字节差异。256×256 RGB565的全mip物理占用超过单半区128KiB，软件只能安排其完整256KiB空间中的合法区间，不能宣称任何格式全mip都可在半区双缓冲。

对公式做了独立Python枚举：三种格式、W/H各取1/2/4/8/16/32/64/128/256，覆盖783363个足迹起点，均满足单足迹每体最多一个不同字。两个足迹因此每体最多两字；同一证明适用于三线性跨级（Pk总是4字对齐）。可复现命令如下，纯文档公式检查，不替代RTL验证：

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
print('PASS', count)
PY
```

离线工具输出上述交织字流，TEX_LOAD按字线性复制，体号仅取目标半字地址低2位；32B装入beat拆4拍，每拍4体各写一个16bit字，ready反压。在线重排需知道每个待装纹理的尺寸/格式/mip及源起始，TEX_LOAD现有字段没有这些信息，不能借当前SET_TEX推断，故不推荐为此新增硬件状态/端口。离线方案需在gpu-spec2.6和gpu.json相关说明中明确新布局、padding及物理大小计算，由工具/参考模型/RTL统一；本稿不修改已确认规格。

TEX_LOAD和DRAW按命令顺序执行，因此本版没有同时读一半/写另一半的命令重排；两半的软件资源管理保留，不加第二装入端口。装入及取样互斥由command保证，不在RAM加重复软件合法性检查。

调色板四份相同4096×20，true-dual-port各提供两个独立读地址，共8读口；每份4段1024×36，故16块而非旧容量估算6块。PAL_LOAD每拍一项同时广播四份，加载期间无取样。I4只用组内低16项，RGB565直接色不读palette、alpha按不透明处理。

| 所有者/用途 | 有效组织、物理映射公式 | DRM块数（估算） |
|---|---|---:|
| R-4 target | 57600×160；ceil(57600/2048)×ceil(160/18)=29×9 | 261 |
| R-4 texture | 4体×32768×16；4×16段×1块 | 64 |
| R-4 palette | 4副本×4段1024×36 | 16 |
| R-1 AA | 3行×1280×16；每行320×64有效字，映射一块512×72（四像素一读/写） | 3 |
| R-2 顶点倒数种子 | 1024×18，一份双口表，常数内容由数值方案生成 | 1 |
| R-3 像素倒数种子 | 4lane各1024×18，4份独立表 | 4 |
| R-1 DMA共享读beat池 | 512×256，ceil(256/72)=4；分成4个128项返回区，供4笔在途 | 4 |
| R-1 DMA共享写beat池 | 512×256，同上4块；两个在途各最多16beat，其余为空闲容量 | 4 |
| 命令/顶点/quad/对象浅队列、setup上下文、事件与列表尾包 | 使用LUTRAM/FF，容量见下文，不占DRM | 0 |
| **GPU DRM总计** | **261+64+16+3+1+4+4+4** | **357** |

command FIFO32×256；vertex FIFO16×128；quad FIFO4×128；object输入/更新各16×256；object事件FIFO16×33；命中/释放各两个256bit尾包寄存；setup4项上下文（输入screen triangle及中间平面约2Kbit/项）；fragment/sample/shaded各两项弹性槽。命中mask在R-1序列压缩，最坏每对象8项会占一个完整DDR beat，不能靠FIFO无限隐藏带宽差。上述浅存储用LUTRAM/FF计入LUT/FF估算；不整表缓存对象，不把全部命中放片上，表长不受FIFO限制。

矩阵16×32与光照/纹理/像素状态放寄存器；LOD4bit小数表16项组合常数，不占DRM；裁剪双8顶点、边函数/平面、待提交目标字使用寄存器。4KiB边界切分元数据和AXI目的客户队列用FF，无额外DRM。

357较gpu-soc9.3的约320高37；加原保留模块约62为 **419/415**，尚未计AUD及可能新增板级IP，资源未闭合。旧估算250目标+57纹理+6palette=313，而本映射261+64+16=341，仅三者已多28；其余差来自明确计入读写池/倒数表。不能把36Kb容量下限当作实现数量，也不能把独立36Kb块空余位相加当作可自动共享。可研究把共享beat池改成LUTRAM节约8块（会增LUT/FF及布线），但本稿没有将未验证优化计成已达预算，更没有改小目标或纹理。


**压缩选项（比较，不在本稿暗中实施）**：基数为上表357块，选项中节省可叠加的前提是存储用途不同；改变G-R1/GS-3须协调者及用户按规格流程定稿。

| 选项 | 精确DRM估算/节省 | LUT、性能或实现代价（估算） | 对规格影响 |
|---|---|---|---|
| 目标末段混合宽深 | 28段×9块2048×18 + 尾256字×160bit用3块512×72 = **255块，省6** | 末段输出先拼接216bit再取160bit，段号控制本地寄存；增加约100–200 LUT，读延迟/吞吐保持 | 容量/行为不变，需两种IP配置；推荐优先 |
| 全palette改LUTRAM | **省16** | 8个独立异步读需8份单读4096×20；按32/64bit每LUT分别20480/10240 LUT，另加深层读mux；双读硬核的4份不能直接当4份单读LUTRAM | 行为不变但60K LUT预算无法闭合，不推荐 |
| palette减少副本/分体 | 两份双读**8块，省8**；一份双读4块省12 | 任意8个调色板索引可落同一组/同一子体；纹素2×2规律不约束索引奇偶。2份最坏需2拍、1份需4拍，无法保证8tap查色/拍 | 违反当前过滤核吞吐目标，不能当无损优化；不推荐 |
| 纹理224KiB | 每体28672×16 =14段；4×14=**56块，省8** | 总容量减少32KiB，无端口/取样速率变化；SET_TEX/TEX_LOAD越界比较使用新容量，两半各112KiB | G-R1初值变更，须定稿确认；候选第二顺序 |
| 纹理192KiB | 每体24576×16=12段；4×12=**48块，省16** | 减64KiB，两半各96KiB，软件素材驻留容量下降 | 同上，不自行采用 |
| 倒数种子改LUTRAM/组合ROM | 五表改分布式，**省5**；若只改顶点表省1 | 5×1024×18，按32/64bit每LUT为2880/1440 LUT容量代理，另加读mux/逻辑；对10bit索引用组合常数综合可能更小但未经测量 | 算法/精度不变；需保留寄存读延迟，候选但不先计节省 |
| DMA池改浅LUTRAM | 读4笔×16beat=64×256，写2笔×16beat=32×256，**省8** | 保持4读/2写在途及16beat突发，只取消物理深度取整闲置；共24576bit，按32/64bit每LUT为768/384 LUT容量代理，连读mux/信用/暂存保守预留1000–1500 LUT、约600 FF；需同步读接口保持 | 不改变规定的并发和突发；不是减小规范队列，内部池容量由本设计选择；推荐 |
| 命令/对象/列表缓冲 | 已用浅LUTRAM/FF，**省0** | 不把本已为0的DRM再次列为节省 | 无 |
| GS-3条带减半目标 | 28800个160bit字：14×9 + 尾128字3块512×72 =**129块**；相对261省132，相对混合255省126 | 每屏几何/命令遍历次数加倍；640×180分2条、1280×90分8条；总像素算术/写出不减，重新裁剪/建立及软件提交增加 | 目标形状/TGT_CFG需改规格及软件，不是v0.1已有两形状；仅GS-3批准后使用 |

推荐先采用末段混合和浅DMA池，357−6−8=**343 DRM**，加历史保留62为405/415，LUT约56800+200+1500=**58500**，但AUD/板级配额仍需确认。若还要向约320收敛，224KiB纹理及分布式倒数表可降到330块，再到192KiB可降到322块；后两种组合的LUT余量偏紧，不宣称已闭合。选择小纹理必须以M-1素材和软件需求及PDS为依据，不能在RTL里同时保留多个容量分支。条带减半收益最大但改变已确认形状，放在最后；全palette改LUTRAM或牺牲取样率不推荐。协调者已同意保留全部行为、在本草案明确超预算和未决闭合，不代表批准上述任一变更。

### 4.9 单AXI256内部DMA仲裁

读写方向分别轮转仲裁，以最多16beat一个突发作为非抢占单位；读侧7客户，写侧4客户。每客户区间可拆为多突发，不等整区间才让别人运行。读最多4笔、写最多2笔在途，对应gpu-soc P3初值；全部本地ID取0保持顺序，ID宽仍为1，不增加ID空间。每个AR/AW握手入客户/长度/逻辑末尾队列，R按AR顺序、B按AW顺序回收；不把单ID误解成只能一笔在途。W严格跟随AW顺序，先凑齐该突发数据再发AW，AW受阻保持，禁止W串客户。

拆分算法：当前物理地址A向下32B对齐，剩余覆盖beat为ceil((A原始低5位+字节数)/32)。`n=min(剩余beat,16,(4096−(A&4095))/32)`，ARLEN/AWLEN=n−1（4bit），后续A+=32n。所有实际AXI地址32B对齐，INCR，不带SIZE/BURST端口。写首尾WSTRB与请求keep相交；读首尾keep交给拆包器。命令DESC_BASE按64B软件约束使用，不加额外检查；matrix/顶点/quad/对象/TEX_LOAD地址由json低位隐含0；列表基址32B对齐，尾部不足8项仍只写所需字节。RESOLVE按每行 `BASE + y*STRIDE + 2*x` 独立区间生成，行之间不跨stride填充，行首不32B对齐也用首尾WSTRB。

读池4区各128beat，AR发出前预留n个返回位置；即使业务反压仍有已发R的存放位置，不靠取消AXI腾空间。写池为已打包突发服务，write_data不具备空间时ready拉低。command/矩阵/顶点/quad/对象/texture/palette均走同一个读仲裁器；对象更新、命中、释放、RESOLVE均走同一个写仲裁器。TEX_LOAD/PAL_LOAD的DDR结束还不算命令结束，需等待最后RAM写握手。texture descriptor越界检查只在SET_TEX计算所有mip总字节并比较容量；TEX_LOAD越界只比较dst+bytes；其他软件合法性信任内部契约。

OBJ_STEP中可同时对象读、对象写、列表写；推进核1对象/拍不等于单端DDR持续1对象/拍。每对象读32B、更新写32B，最坏再写8×4B命中和4B释放，DDR流量可达100B/对象；150MHz下1对象/拍要求15GB/s，超过AXI256/125MHz端口峰值4GB/s。对象性能的核吞吐和命令端到端吞吐必须分开验收；未获澄清前不把此算术核指标表述为全流量保证。

### 4.10 150MHz时序预算和扇出

局部设计目标为寄存到寄存逻辑≤2.5ns、布线≤2.5ns，其余1.667ns留给时钟不确定性/偏斜、setup及全SoC拥塞；独立模块PDS目标WNS≥+1ns@150MHz，最终以全SoCsetup/hold为准。这是设计余量目标而非器件延迟保证。一般每级≤4 LUT级，带宽加法/比较允许≤6等效级但须实测；APM/DRM输入输出必须寄存，禁止两个乘法串在一个周期。

| 长路径 | 每级工作及逻辑预算（估算） |
|---|---|
| 倒数/牛顿 | 32bit前导位分两级各≤3；ROM1级；归一化乘m*r0用2级APM；2−m*r0单独一级≤4；r0*修正用2级APM；移位还原分两级各≤3；指数与valid同延迟 |
| 透视校正 | uq/vq×w拆2级APM，取位/移位一级≤3；偏导的乘、减、再乘分开，不并入倒数末级 |
| 双线性/三线性 | 横向乘法2级、加法1级≤4；纵向同样；LOD级间混合再独立乘/加；RGBA同步流水 |
| 混合 | 因子选择一级≤3；源/目标乘法两级LUT；d归一化一级≤4；加减/MIN/MAX一级≤4；饱和和P565一级≤3 |
| 边函数 | setup的坐标减、乘积、积差各独立；扫描40bit加法一级≤4，符号/边偏置判定下一拍≤3；行起点与当前组分开 |
| 矩阵乘 | 32×16乘积拆2级APM；四项树两级各≤4；坐标缩位一级≤3；不把光照点积和颜色乘法串接 |
| 目标/纹理返回 | 段选择分局部组和最终组，至少两级；地址预译码先寄存，RAM输出到APM之间有本地寄存；ready只返回本地弹性队列 |
| AA | 亮度加法、min/max两层、差值、比较、加权和、P565独立；四通道邻居跨字选择在算术前寄存 |

历史依据：`2026-11-08-rnd-fmax-eval.md` 引卡68R2源 `49448d0c89ccecda82aa7bf23a5b9c82fdf98791`、回传 `a5d08903812061a894dd8cdfff970fc77eefbb0d`，PDS2022.2-SP6.1/PG2L200H-6，125MHz内部最差+0.153ns；9级地址链为逻辑1.779ns/走线5.446ns，另一个0级command→APM路径走线5.830ns。原始文件 `tasks/win/20261108-68-soc-v021-full/artifacts/R2/native_reports/edrv32_fpga_board_full_top.rtr.gz`、`timing_setup_top200.txt`。这说明低逻辑级数仍可被跨区域布线拖垮，不能直接把RND改时钟宣称150MHz可达。

`2026-11-13-resource-slim-media.md` 的卡70ADS/高扇出原文来自 `7153d605cc6c66fa7f415b22bbe8d5b40da7ff08`，源码 `ce2b4fd42edc526fa702fd08071e14b4c2a0353a`：cancel约680、state582、blend_valid/tag519负载。GPU的stop/valid/状态不广播到整个宽数据通路：command按单元寄存控制副本；texture按4bank、pixel按4lane、target按29段分层复制CE/写控制，局部目标每份≤32–64负载，再以PDS扇出/布线检查调整。仅控制复制，不复制全部256bit数据。

`2026-11-14-fanout-rnd.md`（接续b8c5e211）是Yosys0.70+219参考测量，不是PDS：位列offset负载197–226→60–62、选择256→每份32；`2026-11-14-fanout-npu.md`（09290bda基线）控制按8份/64份切片后每份32或8–9。此处只借鉴局部复制组织，不能把该负载数换算GPU实际WNS。物理副本按需要keep/syn_preserve，避免综合重新合并；数据寄存不加复位，控制reset来自区域副本。

### 4.11 每单元资源估算

LUT公式采用控制/地址/比较器的结构配额，加小乘法配额：8×8流水乘法约40 LUT/个、加法/选择约10–30 LUT/通道，数值均为估算；宽乘法按18×18 APM等效拆分，32×16为2，32×18为2；不是RTL综合结果。偏导为LOD近似路径，候选采用18bit规格化尾数加独立指数：每lane的4个导数各两次18×18乘，共8个APM；UV输出的32×18乘各用2个APM。18bit近似精度属于G-N3，未经模型认可不得据此宣称104APM可实现；若偏导需全32bit，须重算超预算。FF按有效流水位数+队列位数估算，不把LUTRAM位数又全记为FF。APM实际小乘法打包能力不能先当节省；过滤/颜色小乘优先LUT，实际映射偏离时由PDS重算。

| 单元 | LUT估算 | FF估算 | DRM | APM估算及输入 |
|---|---:|---:|---:|---|
| R-1 regs/command | 3000 | 2200 | 0 | 0 |
| R-1 read/write DMA及打包 | 4500 | 3800 | 8 | 2（Surface/对象地址流水乘法配额） |
| R-1 resolve/AA | 3500 | 2600 | 3 | 0，四路加法/比较 |
| R-2 transform/light | 5000 | 4200 | 0 | 22：8个32×16乘=16，加6个光照乘 |
| R-2 clip/project | 5500 | 4600 | 1 | 12：比例/坐标属性共享，串行裁剪 |
| R-2 setup | 4500 | 3600 | 0 | 12：属性乘法共享及面积倒数 |
| R-3 raster/quad | 4500 | 4000 | 0 | 0，增量加法/覆盖比较 |
| R-3 perspective | 5500 | 5000 | 4 | 56：4lane×(牛顿2+UV乘4+偏导8)的18×18等效配额† |
| R-3 object | 2800 | 2200 | 0 | 0，八框比较/加法 |
| R-4 texture/filter/palette | 9000 | 6500 | 80 | 0：LOD前导位/小数表及过滤8bit权重乘LUT；偏导宽乘已计R-3 |
| R-4 pixel/target | 8500 | 6000 | 261 | 0，约24个混合乘+12个着色小乘的LUT预算分别归此处/texture |
| **总计** | **56300 LUT** | **44700 FF** | **357 DRM** | **104 APM** |

LUT总计=3000+4500+3500+5000+5500+4500+4500+5500+2800+9000+8500=56300，距60K约3700；APM距120约16。不是能同时保证的上限，尤其†位宽、LUT小乘映射及target大bank选择都可能增加面积/拥塞。外部X9/X10/X3桥、reset_copy等SoC边界配额不在上述业务单元内，估算另约0.5K LUT/0.5K FF（参照视觉项目同型桥），计入GPU边界约56800 LUT/45200 FF，DRM仍357。保留模块约62 DRM仅为历史配置代理，AUD/实际5口xbar及DDR IP最终独立核算。

## 5. 影响

- 本次只新增设计记录，无RTL、规格、寄存器JSON、文件列表或测试修改。RTL lint和仿真不适用于这次纯文档提交；执行 `git diff --cached --check` 及表格/算术人工检查，纹理公式枚举输出 `PASS 783363`。
- 协调者评审后须在规格明确内部接口及性能条件，再以S-1数值方案替换†初值。R-1–R-4只按同一次冻结版本编码，接口位宽调整不能在某个worker内单独完成。
- 后续已有验证任务覆盖命令串行、透明/模板/混合次序、同字连续RMW、TGT_X0非4对齐、双形状、五平面裁剪、bank冲突、4KiB/尾包、列表溢出、B完成后发布及ABORT排空；此处不新增测试方案或RTL检查。perf需分别记录无冲突核吞吐、对齐开销、DDR等待、命令总周期，以验证gpu-spec7，不能只报理想像素核速率。
- GPU IP说明需覆盖160bit目标分段、四体纹理双读、四副本palette、三行AA、倒数ROM、DMA共享池；每种读延迟/双口碰撞要和包装模型一致。PDS须同时给实际DRM/APM/总LUT和全SoC最差路径/扇出，不能从Yosys映射直接宣称150MHz。
- 本文历史证据复现：`git show a5d08903812061a894dd8cdfff970fc77eefbb0d:tasks/win/20261108-68-soc-v021-full/artifacts/R2/timing_setup_top200.txt`，同提交读取native_reports及high_fanout；`git show 7153d605cc6c66fa7f415b22bbe8d5b40da7ff08:tasks/win/20261108-70-soc-npu-post/artifacts/resource_hier.txt`。本文估算可由4.6/4.8/4.11所列整数和公式复算，无新增测量产物。

## 6. 状态

**讨论中，待协调者评审。** 候选接口完整列出，但尚未冻结；G-N1–G-N3未定稿，资源与以下性能条件尚待协调者决策。

1. 物理DRM估算357，高于约320目标，全SoC代理419/415且尚缺AUD配额；需要批准具体资源收敛方案或调整预算，不能未经确认削减规格容量。
2. 按协调者问答要求，改为4体字块奇偶布局，双线性2/三线性1像素每拍按任意UV验收；离线交织、每级至少2×2字块及按物理大小越界检查已获协调者问答同意；布局、离线转换及padding须由S-1写入2.6，当前仍为候选。nearest允许规格所述bank冲突停顿，不把此条件扩展到过滤。
3. 协调者已同意对象核II=1不含绘制/DDR，顶点II=2限普通全内、不触发裁剪的三角形，均在输入输出无背压下验收；待S-1写入测量条件，同时报告完整命令含DDR总周期。
4. RESOLVE的57600拍核心满足预算，但0.5ms还须默认DDR模型及P3仲裁实测证明额外等待≤约16824拍；没有测量不能记为已达标。
5. 接口†格式和算术截断由M-1/S-1定稿；本文不替代数值模型。冻结前删去所有讨论性替代描述，保留唯一位宽和映射。
