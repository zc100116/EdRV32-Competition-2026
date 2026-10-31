# RND v2 实施方案

| 项 | 内容 |
|---|---|
| 版本 / 日期 | v0.1 / 2026-10-31 |
| 状态 | [~] 阶段一已批准；独立REF/VERIFY由协调者直接派发，本人顺序实施RTL |
| 依据 | rnd-spec v0.3、rnd-testplan v0.2、设计记录2026-10-31-rnd-v2的D1–D8 |
| 工作包 / 分支 | T-RND2 / zc100116/task-rnd-v2（基线7732a05b，zc100116/b3） |

## 1. 目标和完成标准

实现G1两lane 4×4采样、G2目标遮罩/圆角裁切/阴影挖空、G3+G4逆仿射与单lane双线性；只实现v0.3。
RN-01–29对应smoke/full/perf、RN-17主机原阈值、新增旋转/弧/widgets帧及profile认领通过；旧命令perf周期不增加。
RND/技术包装/board top风格和lint零告警，board_render smoke通过；Yosys记录资源和最长逻辑级数，对比D8预算。
clk_mem 125MHz、RND≤32K LUT/130APM/66DRM、G4≤40APM、AFFINE窗口/填充≤4DRM；PDS实测及上板单独进行，不进卡21。
汇总报告docs/reports/2026-10-31-rnd-v2.md不超过80行，只写结论、数字、条件、复现命令。

## 2. 前置条件

- 本人完成三个文档并提交，通过Orca ask交协调者审核；批准前禁止派开发任务。
- 已有RND、dma2d、LVGL主机RN-17及profile可用；旧RN-18以基线和最终版在同一台机器比较。
- 协调者因Orca深度上限改为：独立REF/VERIFY直派，本人MASK→GEO→AFF顺序实施RTL，再INTEG合入验证提交；参考和模块验证独立于RTL。
- MASK完成后由项目经理冻结共享命令/参数读客户端、coverage/像素valid-ready握手、背压冻结和ABORT排空、源采样/混合接口及文件归属；记录具体端口、位宽、时序，交协调者确认规格未覆盖的选择，再派并行任务。
- rtl/filelists、fpga/scripts等未授权共享文件仍由协调者处理；新增RAM仅限RND技术包装与已授权fpga/ip说明/索引。

## 3. 待办清单

原计划子任务使用独立worktree、gpt-6.1-sol medium；实际Orca拒绝depth2/max1且effectsApplied=false，协调者授权本人当前分支顺序完成RTL及单元测试，独立REF/VERIFY由协调者另派。
每份派发正文展开范围、改动、约束、归属、验收五项，禁止跨归属修改和规格外检查/兜底；项目经理评审并串行集成提交。

| 编号 | 内容 | 执行者（角色/模型） | 依赖 | 验收 | 分支/任务卡 | 状态 |
|---|---|---|---|---|---|---|
| V2-DOC | v0.3规格、验证方案和本计划；提交后ask审核 | 项目经理本人/Codex | D1–D8 | 三文档diff无空白错误；协调者批准 | task-rnd-v2 | [x] |
| V2-REF | 扩展独立整数oracle、命令/参数编码、手算/算术自测 | 协调者直派独立验证员工/gpt-6.1-sol medium | DOC批准 | rnd_ref.py --selftest及自身参考自测通过；不读RTL、不跑整体回归 | task-rnd2-ref | [ ] |
| V2-MASK | G2 RTL、参数读取、MASK直写/阴影挖空/BLIT圆角；自写单元测试、技术RAM说明（需要时）；列出共享接口 | 项目经理本人/Codex | DOC批准，REF由独立员工并行准备 | 自身单元检查/风格/lint零告警；旧字段保留；接口评审冻结 | task-rnd-v2 | [x] |
| V2-VERIFY | 按RN-21–29及RN-14/15/17/19扩展模块/SoC激励、向量和计数检查 | 协调者直派独立验证员工/gpt-6.1-sol medium | MASK及接口冻结、REF | 不读被测RTL；自测向量/模型和harness；不跑被测RTL整体回归；提交可执行测试 | task-rnd2-verify | [ ] |
| V2-GEO | G1发生器/译码接入、AA/渐变、差分/并集；自写单元测试 | 项目经理本人/Codex | MASK、接口冻结、REF | RN-21–23对应单元检查，背压冻结，62.5Mpx/s计算峰值；风格/lint零告警 | task-rnd-v2 | [~] |
| V2-AFF | G3+G4同时交付，32×16遍历、32源块、NN与单lane双线性、技术RAM及说明；自写单元测试 | 项目经理本人/Codex | MASK、接口冻结、REF | NN/四tap边界和Q还原单元检查；窗口≤4DRM、G4≤40APM估算；风格/lint零告警 | task-rnd-v2 | [ ] |
| V2-INTEG | 驱动编码/参数clean、LVGL supported与翻译、RN-17新增帧/coverage，统一联调和测量 | 项目经理本人/Codex | VERIFY、GEO、AFF合并 | 下列统一验收全部完成，失败归类后修复，不放宽判据；提交及≤80行报告 | task-rnd-v2 | [ ] |
| V2-REVIEW | 审核提交、预算对比及汇总；最终worker_done交协调者 | 项目经理本人/Codex | INTEG | 验收证据齐全，最后一项通过立即提交/worker_done；PDS项明确待单独上板 | task-rnd-v2 | [ ] |

归属：REF仅verif/block/rnd/rnd_ref.py及其参考自测；VERIFY仅verif/block/rnd其他文件；board_render只运行现有smoke，需修改先向协调者确认。
MASK负责当前共享descriptor/engine/draw接入和G2单元；GEO/AFF的具体RTL文件及单元目录在MASK后划分，禁止同时改同一文件，公共接入修改由项目经理串行应用。
AFF拥有RND仿射源窗口/插值模块及对应rtl/tech和fpga/ip文件，README行由项目经理串行集成。
INTEG拥有sw/drivers/rnd.c、include/rnd.h、sw/apps/s3/lvgl/draw_rnd.c、tools/s3的RN-17内容及指定汇总报告；其他LVGL主机文件若需修改先ask协调者。
文档和共享文件由项目经理维护授权范围；跨本包归属需求先ask，不修改mem_xbar、DISP或其他模块RTL/规格。

统一验收（仅V2-INTEG执行整体回归；本机Verilator/Yosys/regress均flock /tmp/edrv32-sim.lock，-j 1，不用--parallel）：

- `flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/rnd -j 1`。
- `flock /tmp/edrv32-sim.lock python3 tools/regress.py full --path verif/block/rnd -j 1`，完整模块回归一次；修复失败后只重跑失败/受影响项。
- `flock /tmp/edrv32-sim.lock python3 tools/regress.py perf --path verif/block/rnd -j 1`，RN-18各场景与同机基线比较，RN-29新命令测量。
- `python3 tools/s3/rn17.py`（使用已锁定LVGL；新增旋转/弧/widgets帧，原阈值不变）和`python3 sw/apps/s3/host/rnd_profile.py`。
- `flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/soc/board_render -j 1`。
- 现有tools/check风格检查及Verilator -Wall lint覆盖rtl/media/rnd、RND技术包装、edrv32_fpga_board_render_top；具体filelist命令在集成报告记录。
- 现有Yosys流程测量最长逻辑级数/资源参考，具体输入、脚本、数字与基线同机对比并入报告；不将Yosys值冒充PDS站点数或125MHz收敛结论。

仿真主机只由Codex使用；运行前按空闲核/可用内存留余量，各任务独立构建目录，结束清理；只回传自行总结结果，不回传环境或文件原文。
报告环境写“用户提供的仿真主机（环境不记录）”；不可用则本机flock，不另改验收条件；改前改后比较保持同机。

## 4. 规格定稿项

| 项 | 时间 | 依据 |
|---|---|---|
| v0.3草案、编码/逐位语义 | 开工前 | 协调者审阅三个文档并答复ask |
| 新命令周期、读放大及画质 | INTEG结束 | RN-17/18/29及profile数据；不虚构板上收益 |
| 资源和125MHz | 单独PDS/上板后由协调者回填 | slow角WNS≥0/TNS=0、原生LUT/APM/DRM及RN-17板测 |
| 既有性能待定项、批量大小 | 板测后 | 对照v0.3第9节；未取得项明确保留待定 |

## 5. 风险和阻塞

- 阶段一已获协调者批准（35abfa9f及EDGE_INCL修订），可按依赖派发。
- G1与LVGL AA不同、G4相位/预乘可能无法通过RN-17；出现失败明确上报，不静默回软件或放宽阈值。
- 源读放大依赖变换局部性；32块不能保证带宽上限，按实际beat报告。
- APM/DRM端口组织与旧blend关键路径风险：只做已规定流水与资源；任何估算超D8先ask，不自行裁减。
- 本机仅3核；本包不发心跳/进度给协调者，只在决策时ask、完成时worker_done；各检查点收取follow-up。

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-31 | v0.1 | 依据D1–D8，制定REF→MASK→GEO/AFF→INTEG及独立验证分工；协调者审核批准 |
| 2026-10-31 | v0.1 | 协调者批准35abfa9f，要求TRIANGLE改为FLAGS[3:1] EDGE_INCL精确比较；改完直接开工，无需复审 |
| 2026-10-31 | v0.1 | Orca拒绝depth2/max1；协调者决定直派独立REF/VERIFY，本人顺序MASK→GEO→AFF及单元测试，最后合入验证提交再INTEG；未创建子员工 |
| 2026-10-31 | v0.1 | G2 draw单元10用例通过（Da=0/1/128/255、负形状、半径截断、KEEP、RGB565/ARGB及背压）；RND风格/lint零告警；新增filelist/RN-17相关文件修改获协调者授权 |
