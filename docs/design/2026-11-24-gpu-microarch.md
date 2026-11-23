# GPU 微结构设计记录

| 项 | 内容 |
|---|---|
| 日期 | 2026-11-24 |
| 状态 | 已决定，待协调者批准冻结 |
| 依据 | `2026-11-23-gpu-resource-closure.md`（已决定，da4c70345）、`gpu-spec.md` v0.3草案（8f55e23f0，2.4–2.6、2.12–2.13）、`2026-11-24-model-gpu-numeric-v03.md`（B32/P18）、`tools/gpu/model/planes.py`（b3315ccb0）、`gpu-soc-spec.md` v0.2、`rtl/include/regs/gpu.json`、`2026-11-23-gpu-architecture.md`、`2026-11-23-gpu-2d-estimates.md`、`gpu-plan.md` |
| 源码基线 | `8f9272261`（本次文档修订基线），分支 `zc100116/gpu-dev` |
| 数字性质 | 以下 GPU 周期、资源、级数均为结构估算，未经综合、PDS 或上板测量；历史实测另注明出处 |

## 1. 背景和问题

GPU 需要把固定功能几何、三角形/四边形扫描、对象推进、片上纹理和片上读改写连接成一条流水线。R-1–R-4 并行开发前，需要统一状态归属、流的排列、停顿和排空语义，否则局部单元都正确也可能在重叠绘制或命令切换时产生错误。第二版只替换三角形建立之前的几何单元，因此该边界单独定义。

本文按 v0.3 草案 B32/P18 数值定义 Verilog-2001 内部接口；目标115200像素、纹理192KiB及完整/当前组两级调色板沿用资源闭合决定。本文件只记录微结构及估算，不修改规格或寄存器JSON。

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
| R-1 | `unpack`、`list_pack` | 独立装入/拆包适配模块、独立命中/释放列表打包模块；不并入DMA或对象核 |
| R-1 | `resolve` | 读目标颜色、三行缓冲、四路AA、RGB565打包、Surface逐行写出 |
| R-2 | `geometry` | 自成一体的几何外壳：顶点三元组、变换/光照、五平面裁剪、扇形拆分、投影、背面剔除 |
| R-2 | `transform`、`clip`、`project` | 上述三个内部算术阶段；不对R-1/R-3暴露内部状态 |
| R-2 | `setup` | 屏幕空间三角形→包围框、左上偏置边方程、属性平面；在几何替换边界之外 |
| R-3 | `raster`、`quad` | 三角形4像素组扫描、四边形快速扫描及两路有序选择；相同fragment契约 |
| R-3 | `perspective` | 四路18位尾数q倒数、透视u/v与偏导，四边形直通；送纹理单元 |
| R-3 | `object` | 一对象/拍运动/寿命/区域/八框并行碰撞、事件及更新对象、有序四边形输出 |
| R-4 | `texture`、`texture_ram`、`palette` | LOD、请求排程/去重/冲突、192KiB四体RAM、4读口完整调色板和8读口当前组副本、三种过滤、着色 |
| R-4 | `pixel`、`target` | 透明丢弃、模板/深度/混合、目标RAM、同字依赖旁路、CLEAR及RESOLVE访问 |

`geometry` 内部模块及 `texture` 内部模块的端口由其 worker 自行划分，不跨任务。倒数不使用跨worker共享RTL文件：R-2 `project`、`setup` 和 R-3 `perspective` 各有本地实现，project及setup面积倒数取2.12，perspective像素倒数取2.13；不共用跨单元算术池。tech RAM/APM 包装、公共头、寄存器生成物和文件列表不归这四个 worker 修改。

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
| `resolve` | command→resolve | `resolve_command:256`、`resolve_target:256`、`resolve_wide:1` | 先排空所有像素；target为最近SET_TARGET原命令快照，执行期间不变；写出区域按命令，颜色读接口见后表 |
| `unit_done` | geometry/setup/raster/quad/perspective/object/texture/pixel/target/resolve→command | 每单元 `unit_done:1`（电平，无valid/ready） | finish由1变0时清0，finish已到达且所有本命令输出已握手、内部无有效项后置1并保持到下次启动；无输出的空DRAW也完成；pixel/target完成须包括RAM提交；resolve/object须再由command合并DMA B排空；object_result是完成后的发布口，不计入object的unit_done排空条件 |
| `finish` | command→各处理单元 | `finish:1`（每单元独立电平） | 表示该单元本命令不会再有输入；仅在其全部上游done后拉高，保持到下次启动；1→0表示新命令开始，各单元清unit_done，command在发配置前至少保持一拍finish=0。不清除或丢弃已接收工作 |
| `stop` | command→所有业务单元 | `stop:1`（电平） | ABORT或ERROR后保持至本次排空完成；停止生成新工作，丢弃尚未发出的业务负载；DMA已经接收的请求继续服务。stop期间各返回消费者继续ready并丢弃返回内容，已握手写区间的数据仍从已缓存突发供完。无额外取消标签 |
| `dma_idle`、`dma_error` | DMA→command | 各方向 `dma_idle:1`、`dma_error:1`（电平） | idle表示队列、在途及返回负载全空；error是本次运行非OKAY的粘滞位，映射ERR_CODE2 |

finish按依赖逐级推进：输入DMA完成→geometry或quad/object；geometry完成→setup；setup完成→raster；raster/quad完成→perspective；perspective完成→texture；texture完成→pixel；pixel完成→target。对象的quad输出先入quad再走同一像素链，object自身完成不等绘制链；CLEAR/RESOLVE在区间数据源终止后finish。每单元以finish的1→0开始新命令，随后接收配置/draw；finish/stop由command复原，不能靠瞬时FIFO空提前宣告完成。

`regs` 与 `command` 的控制线：`start:1`、`abort:1`、`soft_rst:1` 为regs→command一拍脉冲；`enable:1`、`desc_base:32`、`desc_count:16`、`wide:1`为regs→command电平，start沿快照。command→regs为 `busy:1`、`done:1`一拍、`error:1`一拍、`err_code:32`（error同拍），DONE_COUNT由regs在done递增。CTRL/START/DOORBELL/SOFT_RST按SoC7.1执行，不另定义软件行为。

对象结果流 `object_result`：object→regs，`object_result_valid/ready`及 `object_result_hit_count:24`、`object_result_free_count:24`、`object_result_alive_count:24`、`object_result_overflow:2`，仅在对象输出及相关B全部结束后由command允许握手，随后寄存器整体生效。command给object的 `object_publish:1` 为此条件电平；object不提前发布。下一OBJ_STEP开始清溢出。

PERF只在regs累加：各单元给本地周期事件，`perf_vertex:1`、`perf_triangle:1`、`perf_quad:1`为对应输入顶点/非退化建立三角形/开始扫描四边形的握手脉冲，`perf_pixel_count:3`为该拍通过全部测试像素数0–4，与写入开关无关，CLEAR/RESOLVE不计，`perf_texture_stall:1`为纹理bank冲突周期，`perf_read_wait:1`为读DMA等待周期，`perf_resolve_busy:1`、`perf_object_busy:1`为占用电平；总忙由busy。多个同类事件同拍的设计只有pixel允许大于1；未用PERF读0。事件都是源输出、regs输入，无反压、不跨域。

### 4.3 几何单元的完整替换边界

几何单元只消费 `geometry_cfg`、`draw`、`vertex`、`finish` 和 `stop`，输出 `screen_triangle`、`unit_done`及顶点事件。`setup` 是独立消费者，第二版4路SIMD替换整个geometry后仍按此屏幕三角形格式输出；没有程序存储、指令口、SIMD占位参数或第二版专用逻辑。

| 流 | A→B | 信号名:位宽 | 格式和含义 |
|---|---|---|---|
| `vertex` | unpack→geometry | `vertex_data:128` | gpu.json VERTEX的16B原样；先v0/v1/v2，再下一三角形；三角形数量来自draw；每2拍可收1顶点，无额外last端口 |
| `screen_triangle` | geometry→setup | `screen_triangle_x:51`、`screen_triangle_y:51` | 各3×s12.4（17bit），屏幕像素坐标 |
| 同一流 | 同上 | `screen_triangle_depth:48` | 3×u16，投影/映射后的原始深度，f=0 |
| 同一流 | 同上 | `screen_triangle_q:105` | 3×u35 Q30，原始1/W，f=30，W≥1/16故q≤16 |
| 同一流 | 同上 | `screen_triangle_uq:153`、`screen_triangle_vq:153` | 各3×u51 Q38，原始16位Q8 UV乘35位Q30 q的完整积，f=38 |
| 同一流 | 同上 | `screen_triangle_color:216` | 3顶点×3通道×u24 Q16；裁剪/光照后的原始颜色，f=16；低通道R、其次G、再B |

输出是完成五平面裁剪、投影和剔除的三角形，裁剪多边形按扇形顺序输出；剔除后顶点连同属性排为正面积，再交setup。完全裁掉、退化或剔除的输入不输出；setup仍独立拒绝零面积，不产生像素。几何输出done在最后一个screen_triangle握手后成立；setup自己的done另行排空。状态在接受draw前握手，直到本DRAW完成保持。无隐含顶点缓存地址、内部裁剪缓冲地址或矩阵RAM读口跨过此边界。

矩阵为32位s15.16、输入位置s16，32×16积48位，四项累加50位，一次舍入/饱和为40位s23.16。W_NEAR=1/16，G=4；五平面顺序及对称交点公式取2.4，距离用s43（40位坐标、乘4及加减），距离差s44，坐标交点分子s84（40+43+1），除后按规格舍入。裁剪UV为u16 Q8、颜色u24 Q16，各分量同样完整扩展。双8顶点寄存工作集保留全部属性。

投影X/Y/Z×q为75位Q46（40+35）；视口乘法再扩16位，1与坐标积先同Q46对齐。sx/sy仅在规格给定的一次舍入后饱和到17位；深度按round(65535·Z·q)后夹到u16。背面面积以17位屏幕坐标计算。

SET_TARGET原始256位的字节0x10低/高16位为VP_X0/VP_Y0（命令bits[143:128]/[159:144]，s16）；0x14低/高16位为VP_W/VP_H（bits[175:160]/[191:176]，u16），与gpu.json一致。所有target配置流原样保留这些位。

倒数严格采用归一化Q30尾数（u31）、10位中点种子索引、一次牛顿迭代及指数还原舍入；乘法保留31×31完整62位，种子r₀为u30，t及2−t的减法用32位。几何输出q用u35 Q30；setup对面积使用同一Q30算法并保留面积指数k，不先将1/A舍入为Q30。像素倒数另按2.13的P18规则。种子ROM保存Q30种子的高18位，读取后左移12位并拼接由常数组合逻辑给出的低12位；低位必须补全，不能截成18位尾数。

### 4.4 建立、扫描、纹理与像素接口

| 流 | A→B | 负载信号:位宽 | 时序与语义 |
|---|---|---|---|
| `triangle_setup` | setup→raster | `triangle_setup_bounds:64` | x0/y0/x1/y1各s16，含左上不含右下；x0按4向下取整，覆盖还受边/目标裁剪；y为整数行 |
| 同一流 | 同上 | `triangle_setup_edge:480` | 3边×4值×s40：E在首组lane0中心的值、一步x增量、一步y增量、左上偏置；同一边4值依次从低位排列；建立时统一内部方向为E>=0，左上边偏置0，其他边偏置-1，覆盖测试E+bias>=0 |
| 同一流 | 同上 | `triangle_setup_origin:32`、`triangle_setup_start:490`、`triangle_setup_gradient:784`、`triangle_setup_h:70` | origin低16位xr、高16位yr，均s16；7×s70规范起点s；7×2×s56增量gx/gy，属性内先gx；7×s10指数h；属性顺序固定depth/q/uq/vq/R/G/B |
| 同一流 | 同上 | `triangle_setup_normal_gradient:174` | 6×29位归一化数，顺序Gq,x/Guq,x/Gvq,x/Gq,y/Guq,y/Gvq,y；各为N(g,h−f)，详下文 |
| `quad_record` | unpack→quad | `quad_record_data:128` | gpu.json QUAD；表顺序，无逐项命令排空 |
| `object_record` | unpack→object | `object_record_data:256`、`object_record_idx:24` | gpu.json OBJ及对象编号，从0递增；空槽也传入以保持索引 |
| `object_quad` | object→quad | `object_quad_data:128`、`object_quad_x:17`、`object_quad_y:17` | 存活且draw=1；data承载QUAD非位置字段，其x/y位不使用；位置独立s17，p取整−半宽高，不截成外部QUAD的s12造成屏外回绕；顺序与对象表相同，不会与DRAW_QUAD源同时活动 |
| `fragment` | raster/quad有序选择→perspective | `fragment_x:16`、`fragment_y:16`、`fragment_mask:4`、`fragment_quad:1` | x/y为s16屏幕整数坐标，x是4倍数；lane位置x+k；mask为覆盖且在scissor/target内，0组不发 |
| 同一流 | 同上 | `fragment_plane:1960`、`fragment_h:70` | 4lane×7属性×s70的T，lane内属性顺序depth/q/uq/vq/R/G/B；每属性物理单位2^(h−f)，h同setup，四lane共用一份；不先舍入回几何格式 |
| 同一流 | 同上 | `fragment_gradient:174`、`fragment_palette:4`、`fragment_alpha:8` | 六个归一化梯度原样传递；palette为quad覆盖值，tri使用SET_TEX；alpha为quad全局alpha，tri=255 |
| `sample` | perspective→texture | `sample_x:16`、`sample_y:16`、`sample_mask:4`、`sample_quad:1`、`sample_u:128`、`sample_v:128` | 4×s32 Q8纹素坐标；quad绕过倒数，保留翻转方向产生的坐标；texture按尺寸取模 |
| 同一流 | 同上 | `sample_span:384`、`sample_depth:64`、`sample_color:96`、`sample_palette:4`、`sample_alpha:8` | span每lane u96 Q16，为max(abs(du/dx),abs(du/dy),abs(dv/dx),abs(dv/dy))；四偏导按2.13第13–14条的归一化乘减生成，各自舍入Q16再取最大；LOD由texture计算 |
| `shaded` | texture→pixel | `shaded_x:16`、`shaded_y:16`、`shaded_mask:4`、`shaded_depth:64`、`shaded_color:96`、`shaded_alpha:32` | 过滤/着色后4lane RGB888及A8；透明lane清mask，目标坐标/深度保持原lane；每输入组严格对应一个输出组，允许mask全0 |
| `target_read` | pixel→target | `target_read_addr:16` | 地址为目标四像素字，范围0–28799；无mask，读全160bit |
| `target_old` | target→pixel | `target_old_data:160` | 顺序响应；每lane40bit={stencil8,depth16,color16}；读请求到输出5拍：地址预译码1、DRM阵列/输出寄存2、两级选择树2；已包含同拍写回旁路 |
| `target_write` | pixel→target | `target_write_addr:16`、`target_write_data:160` | 已合并保留字段的完整字；握手沿提交逻辑结果/写寄存，下一沿完成物理RAM写；不再对未改lane做物理掩码；最终结果旁路见4.7 |
| `resolve_read` | resolve→target | `resolve_read_addr:16` | 仅RESOLVE期间允许，独占target读端；同字映射 |
| `resolve_color` | target→resolve | `resolve_color_data:64` | 5拍有序响应，每lane16bit RGB565；不读改写，不更新目标 |

位宽推导：顶点差s18、面积叉积s37；组对齐扩展的边函数统一s40，左上偏置只用于覆盖，不进入属性平面。setup以规范xr=floor(min sx/16)、yr=floor(min sy/16)建立，不以条带或scissor起点建立。属性f=[0,30,38,38,16,16,16]；q/uq/vq各h=bit_length(max原始幅值)−32（全零bit_length=0），深度h=−16、颜色h=−8；s10能容纳全部h。

R为最近舍入、半值远离零；未列舍入点的中间乘加完整保留。按2.13先求ai=R(rawi/2^h)（最多33位幅值）；Dx/Dy为对边坐标差乘16，分子ΣD·ai保留s56，与Q30面积倒数r完整相乘为s87，再R(/2^(30+k))得s56的gx/gy。s=aa+R(((16xr+8−ax)gx+(16yr+8−ay)gy)/16)，中间完整扩展，s保存s70。像素T=s+(x−xr)gx+(y−yr)gy保存s70；行、lane、组分别加gy/gx/4gx，不舍入、不截断。条带首组由同一s/g直接求值，起点不重新舍入；因此与planes.py逐位一致。

归一化负载固定29位：低18位为幅值M，bit18为符号，bits[28:19]为s10指数E，物理值为(−1)^sign·M·2^E；零固定(+,0,0)。N、乘积36位、带3保护位的s23对齐减法和舍入进位全部按2.13第8–9条。每lane先N(Tq,hq−30)，以F=17、中点种子、两次18×18完整积及规定舍入得w=N(r1,−34−E)；U=N(N(Tuq,huq−38)×w)，V同理。sample输出R(U×256)、R(V×256)为s32 Q8，不饱和；LOD偏导使用归一化U/V，不能改用已舍入的sample_u/v。深度由Q16舍入夹u16、RGB由Q24舍入夹u8后送sample。

quad使用同一fragment契约：h固定为[−16,0,0,0,−8,−8,−8]，Tdepth=z<<16、Tq=2^30、Tuq=u_Q8<<30、Tvq=v_Q8<<30、RGB=255<<24；故q=1，uq/vq的物理值直接为纹素坐标。fragment_quad=1时透视旁路恢复Q8坐标，不作P18归一化；梯度及span置0（quad强制nearest），深度/颜色仍按同一输出舍入。
四边形和三角形同一命令不混排；raster/quad只允许当前draw源输出。quad_record的s12位置先符号扩展到s17，object_quad使用独立s17位置，两路归一为同一内部扫描格式；减半宽高采用整数floor，取整规则依2.9。quad不能为了隐藏开销调换精灵顺序。过滤吞吐较低时，texture持有一个4lane组并分拍发lane0/1、lane2/3（bilinear）或逐lane（trilinear），组装回原4lane，pixel看到的lane/address不变。

### 4.5 装入、DMA及对象写回接口

内部DMA采用字节区间请求，客户不自行切AXI突发。读客户编号固定：0命令、1矩阵、2顶点、3四边形、4对象、5纹理、6调色板；写客户编号固定：0对象表、1命中列表、2释放列表、3RESOLVE。每客户至多一条逻辑区间未完成，客户有独立流，不把编号做成业务单元端口。矩阵DMA读回2个256位beat后command组成512位matrix；命令beat直达command；顶点/quad由独立unpack每beat拆成两项，纹理/调色板装入适配也归unpack；列表压缩及尾包由独立list_pack负责。

| 流 | A→B | 负载信号:位宽 | 协议及语义 |
|---|---|---|---|
| `read_req`（每读客户） | 客户→read_dma | `read_req_addr:32`、`read_req_bytes:32` | 精确字节区间；仅bytes>0时发请求；源地址可由Surface行偏移等形成，DMA向下32B对齐读取并在拆包时去掉首尾无关字节 |
| `read_data`（每读客户） | read_dma→客户 | `read_data_data:256`、`read_data_keep:32`、`read_data_last:1` | 对齐DDR beat的原始数据；keep标记属于请求区间的字节，低位为低地址，last为逻辑请求末beat；每客户顺序返回 |
| `read_done`（每读客户） | read_dma→客户 | `read_done:1`，无握手一拍 | 最后read_data已握手后脉冲；错误请求也等全部已发R消耗后结束，错误另经dma_error通知 |
| `write_req`（每写客户） | 客户→write_dma | `write_req_addr:32`、`write_req_bytes:32` | 精确连续有效字节区间；此流握手后才消费该客户write_data |
| `write_data`（每写客户） | 客户→write_dma | `write_data_data:256`、`write_data_keep:32`、`write_data_last:1` | 已按DDR对齐beat排列；keep是该请求中实际写字节位置，last标记逻辑末拍；列表项32bit、resolve像素16bit按地址排列 |
| `write_done`（每写客户） | write_dma→客户 | `write_done:1`，无握手一拍 | 该请求所有突发B返回后脉冲；对象/列表计数发布依赖这些完成 |
| `texture_load` | unpack→texture_ram | `texture_load_addr:18`、`texture_load_data:256`、`texture_load_keep:32` | 18bit纹理字节地址（32B对齐），32B一组；按离线字流线性地址写4体，拆成四次8B内部写；RAM返回ready反压 |
| `palette_load` | unpack→palette | `palette_load_idx:12`、`palette_load_data:20` | group*256+entry；每beat拆8个PAL_ENTRY逐项广播写两份完整表；高12位DDR填充忽略 |
| `object_update` | object→写回适配 | `object_update_idx:24`、`object_update_data:256` | 仅step=1，保持原记录未定义位及非运动字段；更新alive/p/v/life；地址基址+32*idx |
| `object_event` | object→list_pack（R-1） | `object_event_idx:24`、`object_event_hit:8`、`object_event_free:1` | 仅step=1时每个已处理对象一次，step=0不发事件、不写列表；hit位k对应目标k；先按对象顺序，再按目标编号递增压缩列表；free是本次由活变死；空槽也发一次hit=0、free=0事件，但不发update、不绘制、不计ALIVE。命中/释放是否同时产生严格依2.9及模型的顺序 |

STEP=0时所有对象都不发event和update；只检查原记录alive并按draw开关输出四边形；不推进、不做存活区判定/碰撞、不写回/列表，hit/free/overflow结果为0，alive_count统计原存活对象。STEP=1仅非空槽走运动/判定/碰撞/写回路径；对象result计数由object统计未截断事件总数，hit每拍popcount8、free/alive各0/1。R-1打包器只对容量内条目写DDR，full后停止追加；对象单元得到同一配置快照，以实际计数和MAX比较形成规定的overflow。两边不重复统计可见寄存器，也不添加第二套溢出行为。尾部用WSTRB保留容量外及相邻数据。

### 4.6 200MHz流水线、数值与吞吐

以下均为结构估算，不是综合结果。目标每级≤3级LUT，宽加减按每20位一拍切分（含选择的复杂级再拆拍）；全精度分块乘用APM三拍、部分积压缩/进位每层两拍。整数位移只在规格舍入点取位。II按无背压计。

| 阶段 | 分级/延迟估算 | II/吞吐与限制 |
|---|---|---|
| 变换/光照 | 16矩阵积两拍发射、APM3、50位加法树两层各3、饱和2，约14拍；光照分级对齐 | 顶点II=2，全内三角形 |
| 裁剪 | s43距离加减3、分类1；对称交点分子84位，6块乘积压缩/加减约9、精确除法另计 | 全内约4拍；跨平面按边序列反压，不把倒数近似代替规定交点除法 |
| 顶点投影 | 归一化3、种子3、两次牛顿宽乘各5、减2、还原3=21；40×35的6块积3+压缩/加减6；视口乘/舍入8、剔除4，共约42拍 | 顶点II=2；三坐标各6块，不能再按32×18的2块计 |
| 建立 | 面积/归一化/Q30倒数32拍；7属性各40拍预算（缩放3、分子积6/求和6、倒数积7/舍入5、起点积7/相加4，余2拍控制；P18梯度并行），共32+7×40=312拍 | 保守II=312，一上下文串行；调度须RTL验证 |
| 扫描/插值 | 裁剪首值按同一规范s/g求值，17位偏移移位加法17×4加合并4，共72拍预算；稳态边/属性分块加4、lane展开4、覆盖/对齐2，约10拍 | s70反馈按每20位一拍分4相交错，稳态II=1组，行切换含起点装入；各相位跨4组加16gx，行首相位均由同一平面求值；无像素除法 |
| 四边形扫描 | 建立2、位置/UV/翻转2、mask1，共5拍；当前/下一预建 | 对齐16×16为64组，不齐最多80组，稳态≤80拍 |
| 像素透视/UV | 70位归一化前导位/分层移位/舍入8、种子3、牛顿两乘各3与舍入各2、减2、w归一化4、UV乘及归一化7、Q8输出3，共37拍 | 4lane II=1；每lane2牛顿+2UV乘，共16 APM；各舍入点严格按2.13 |
| 每像素LOD偏导 | 与UV之后串联：U/V×Gq乘及N共7、保护位对齐/s23减及N共8、乘w及N共7、Q16/绝对值/max共5，计27拍 | 4lane II=1，每lane8乘，共32 APM；以未转Q8的U/V求每像素四偏导，无除法 |
| 纹理LOD/取样 | u96跨度前导位/移位5、256项log2表2、偏置/夹取2，LOD共9拍、II=1组；地址3、RAM5、palette4，过滤乘加独立分级 | nearest4（无冲突）、bilinear2、trilinear1像素/拍；双线性二维积一次舍入 |
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
| R-2 建立面积倒数种子 | 独立1份1024×18，Q30低12位由LUTROM补全 | 1 |
| R-3 像素倒数种子 | 4lane各1024×18，P18完整种子，无低位补全 | 4 |
| R-1 DMA池 | 读64×256，写32×256 LUTRAM | 0 |
| **GPU DRM总计** | **129+48+8+3+1+1+4** | **194** |

DMA读池4个16beat区=64×256，写池2个16beat区=32×256，共24576bit；按32bit/LUT为768 LUT容量代理，含读树/指针/寄存预留约1500 LUT、600 FF，仍支持4读/2写在途和16beat突发。命令FIFO32×256、顶点16×128、quad4×128、对象输入/更新各16×256、对象事件16×33、列表各两个256bit尾包、setup单项计算上下文及两项输出槽（II=312）、fragment/sample/shaded各两项槽均用LUTRAM/FF，计入4.11；不整表缓存。

矩阵16×32及状态、裁剪双8顶点、32项未决RMW存寄存器；LOD256项×9位小数表（索引8位，含舍入到256的端点）用组合常数分级，不占DRM。DRM为194块：几何投影、建立面积各有独立Q30种子ROM，像素四份为完整P18种子；不跨单元共享端口。全芯片加保留63为**257/415=61.93%**，低于65%；floor(415×0.65)−257=12块余量。相对原193账本新增建立ROM一块，不能把几何种子与建立种子漏算为一份；IP实际占用待PDS。

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
| P18透视/偏导 | 18×18完整36位APM3；每次N及对齐/舍入独立寄存，不串接两乘；符号与s10指数随行 |
| s70平面反馈 | 每20位进位一拍，4拍；4相交错，反馈推进16像素，逐组输出；行首保存4相位起点 |
| 建立宽积 | 56×31用8块APM，s87压缩/加法切段寄存；两池仅在setup内部复用，逐像素不除法 |
| 目标/纹理 | 地址/段CE1、DRM读/输出2、局部及最终选择各1，共5拍 |
| palette/过滤 | 完整及当前组读4拍；横积/纵积均保留精度，只有二维和末端舍入；三线性另一次舍入 |

command按单元寄存控制副本，texture按4bank、pixel按4lane、target按15段分层复制CE/写控制，局部目标每份≤32–64负载。控制不广播到整条宽数据通路，数据寄存不复位。上述预算必须由PDS的最差路径/扇出确认，不能由LUT级数宣称180/200MHz已可达。

### 4.11 每单元与全芯片资源估算

采用B32/P18，删除旧精确插值除法、倒数UV混合软乘和LOD-A展开实现。以下均为结构估算，非综合/时序实测；不宣称整GPU已闭合。沿用原账本其余基础配额（包括raster/quad 6500 LUT），不把数值研究的局部预算误作全GPU预算。

令M(a,b)=ceil(a/18)·ceil(b/18)、B=32、P=18、W=B+38=70。两个setup乘法池各max(M(56,31),M(31,32))=8 APM，共16；像素四lane×(2牛顿+2UV+8偏导)×M(18,18)=48 APM。无软乘或像素展开除法。
建立LUT=8(B+55)+1200+384=2280；像素LUT=28W×2+12W×4+16(6P+48)+4×256+72+1000+128max(P−18,0)=11872。合计14152 LUT/64 APM，1000覆盖及72 log表已含，不重复追加。该公式与数值报告一致。

| 单元 | LUT估算 | FF估算 | DRM估算 | APM估算 |
|---|---:|---:|---:|---:|
| regs/command | 3000 | 2300 | 0 | 0 |
| DMA/unpack/list_pack | 5500 | 4400 | 0 | 2 |
| resolve/AA | 3500 | 3400 | 3 | 0 |
| transform/light | 5000 | 5400 | 0 | 22=8×2+6 |
| clip/project | 7884 | 8000 | 1 | 26=3×6+2×4 |
| setup（B32） | 2280 | 8000 | 1 | 16=2×8 |
| raster/quad基础队列及扫描 | 6500 | 10000 | 0 | 0 |
| 像素平面累加/归一化/透视/LOD（P18） | 11872 | 24936 | 4 | 48=4×12 |
| object | 2800 | 3000 | 0 | 0 |
| texture/filter/palette | 9000 | 10000 | 56 | 44=28+16 |
| pixel/target | 6300 | 8000 | 129 | 24 |
| 桥/区域reset | 500 | 500 | 0 | 0 |
| **GPU合计** | **64136** | **87936** | **194** | **182** |
| 保留模块代理 | 40000 | F_reserved（未提供） | 63 | 10 |
| **全芯片合计** | **104136** | **87936+F_reserved** | **257** | **192** |

LUT合计=未替换基础49984+2280+11872=64136；APM=未替换基础118+16+48=182。全芯片APM=192/740=25.95%，距floor(740×30%)余30；DRM=257/415=61.93%，距floor(415×65%)余12。GPU仍比60K LUT目标多4136，须后续实现/综合收敛，不能以局部14152<15000宣称全GPU闭合。

FF为独立寄存配额：未替换基础55000；setup沿用8000（上下文、两乘法池完整积和控制）；像素估算28×70×5（平面相位/结果）+12×70×4（输入归一化）+48×36×3（乘积流水）+48×29×4（归一化/对齐）+4×256（控制）=24936。总FF=55000+8000+24936=87936；基础raster队列保守保留，宽负载停顿槽及扇出复制可能继续改变结果。保留模块未提供FF，故全芯片仅给显式公式，不虚构合计。LUTRAM位不重复算FF；几何和setup两份Q30低位ROM各384 LUT，像素P18种子无低位ROM。

## 5. 影响

- 本次只修改本设计记录；不改RTL、规格、gpu.json、文件列表或测试。纯文档不运行RTL lint/仿真；`git diff --check` 通过，4.8的纹理枚举实跑结果为 `PASS 783363 192KiB bounds; palette 8-read preload`。
- R-1–R-4接口以4.2–4.4为唯一定义，算术依据v0.3草案2.13和planes.py（b3315ccb0）；几何/建立Q30及像素P18种子包装需分别落实；R-1有独立unpack/list_pack。
- 复现以文档基线8f9272261加本次文档提交为准；纹理公式命令见4.8，资源公式见4.11。数值研究结果引用既有报告，本次没有重跑数值研究或新增测量报告。

## 6. 状态

**已决定，待协调者批准冻结。** 采用B32/P18唯一路径：规范平面起点、s56系数、s70无损步进、P18透视及逐像素LOD。GPU估算194 DRM、182 APM、64136 LUT、87936 FF；全芯片估算257 DRM、192 APM、104136 LUT、87936+F_reserved FF（保留模块FF未提供）。GPU LUT尚超60K目标4136；建立II=312及200MHz分级均为结构估算，实际时序、吞吐和资源待RTL与PDS验证。
