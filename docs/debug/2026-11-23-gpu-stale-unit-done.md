# GPU 旧完成状态导致 DRAW 提前退休

## 1. 现象

GT-01 的三角形没有出现在 RESOLVE 图像中，四边形/对象计数正常。
首个差异 DDR 地址为 `0x800010be`，期望 `ff`、实际 `00`。
PERF1/2/3 为期望的 3/1/3；PERF4 期望 4160、实际 2112，恰少 2048 个三角形像素。

## 2. 复现

基线 `ab8e9265a`；固定 seed `202601`；修复 `99f089d2f`。
环境：用户提供的仿真主机（环境不记录）；仿真器 Verilator，版本按本批要求不记录。
命令：`python3 verif/block/gpu/run.py rtl gt01`。

## 3. 观察

在 `build/` 临时绑定接口观察模块，没有修改 DUT 或独立测试的判据。
观测时刻为首次 `quad_draw_valid && quad_draw_ready` 的上升沿，即下一绘制已经启动：

| 前一 DRAW_TRI 的接口 | 已握手次数 |
|---|---:|
| vertex | 3 |
| screen_triangle / triangle_setup | 0 / 0 |
| raster fragment / 选择后 fragment | 0 / 0 |
| perspective sample / shaded / target_write | 0 / 0 / 0 |

下一命令在 geometry 尚未输出三角形前已经开始；最终 PERF2=1 说明建立事件后来仍然发生。

## 4. 根因

基线 `rtl/gpu/edrv32_gpu_target.v:174–178` 仅在目标访问或 CLEAR 启动时清 done，
未在 finish 下降时清除上一命令留下的 `unit_done=1`，违反微结构 4.2。
新 DRAW 等待几何/建立/纹理流水线时没有目标访问，因此旧完成电平一直保留。
`edrv32_gpu_command.v:332` 的 `draw_complete_w` 采用 target 的完成电平，
其 `S_EXEC` DRAW 分支遂提前进入 `S_RETIRE`，随后改变 fragment 来源及绘制状态。
pixel 同样只在配置/输入握手时清 done，空命令切换也不符合该公共契约。

## 5. 修复

`99f089d2f` 在 pixel、target 中让 finish=0 清 unit_done；finish 到达且内部排空后才置位。
修正完成状态的生命周期，已接收的数据继续按握手排空。
修复后的 GT-01 图像和 12 项寄存器比较 PASS，PERF4 恢复为 4160。

## 6. 防回归

pixel/target 单测新增：空命令完成后拉低 finish，在没有输入或新配置时等待 8 拍，检查 done 已清零。
两项 full 回归均 PASS；原有像素运算、RMW、RAM 旁路和 CLEAR 检查继续通过；顶层 lint 0 告警。
复现：`python3 tools/regress.py full --path verif/unit/gpu_pixel -j 1`，以及对应的 `gpu_target`。

## 7. 同类排查

geometry、setup、raster、quad、perspective、texture、texture_ram、palette 均在 finish 低时清 done。
resolve 用登记的 finish 下降沿清 done；pixel/target 已按上述规则修复。
object 当前只在 object_cfg 握手时清 done；已通过 ask `msg_d36ff8122340` 报告公共契约与 stop 优先行为的处理问题，待裁定。
unpack/list_pack 是由 unpack/pack 启动握手重启的适配器，不在 4.2 的处理单元完成表中。
DMA 输出的是队列/在途排空的 idle 电平，没有 finish/unit_done 接口；不作同类更改。
