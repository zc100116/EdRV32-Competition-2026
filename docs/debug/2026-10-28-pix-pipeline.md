# PIX 125 MHz 流水化（V-R6）

## 1. 现象

Windows PDS 在 PG2L200H-6、clk_mem 8 ns 下的 PIX 最差路径为 −7.667 ns：
行 RAM → 窗口选择 → 灰度乘法 → 加法 → 饱和 → point2 乘法输入。
原始证据见 `docs/reports/2026-10-28-timing-media-top.md` 和该报告引用的 Windows 产物。
原核为组合逻辑，均值还包含组合除 9。

## 2. 复现

基线：`b6e17ef`；实现和验证提交：`d9d525810b1b90814a3c4f4ab2722afe1ab73999`。
工具：Verilator 5.020，Yosys 0.70+219（5053d0e26），Linux。
仿真使用各测试自身固定模式、随机种子；PX-14 使用独立模块测试定义的 1–10 种子。
全部命令从仓库根目录、执行 `. ~/.local/opt/edrv32/env.sh` 后运行。

```sh
python3 tools/check/verilog_style.py rtl/media/pix
verilator --lint-only -Wall -DSIM_MODE -Irtl/include \
    --top-module edrv32_pix -f rtl/filelists/pix.f
for tier in smoke full; do
    for unit in pix_point pix_filter pix_control pix_kernel; do
        python3 tools/regress.py "$tier" -j 1 --path "verif/unit/$unit"
    done
done
python3 tools/regress.py smoke -j 1 --path verif/block/pix
python3 tools/regress.py full -j 1 --path verif/block/pix
python3 tools/regress.py smoke -j 1 --path verif/block/vin/pix_integration
mkdir -p build/pix_synth
yosys -Q -T -l build/pix_synth/pix.log -s verif/unit/pix_control/resource.ys
```

`tools/regress.py` 的 `--path` 为单值选项，重复传入时仅最后一个生效；因此按目录分别运行，
仍使用 `-j 1`，不使用 `--parallel`。

## 3. 观察

已完成的单元结果：point1、point2 各 31,061 次比对；filter 192 帧，全部 OP、
2–1280 宽、补零边界、间隙、冻结；kernel 10,488 个窗口，全部 OP。
核测试另外穷举 2,304 个倒数乘法输入和 2,296 个可达均值和。
启用的 filter 实测首像素延迟为一行 + 11 拍。

控制单元首轮在 `tb.sv` 的 EOF 检查报 `cycles=48 limit=40`。
其 `frame(8,2)` 设置 40 拍上限，随后直接 `prepare(16,3)` 没有更新该变量，
沿用了 8 像素行宽的上限；16 像素的正确规格上限为 48 拍。
修改 `prepare()` 按当前宽度更新 `w+32` 后，控制单元 smoke/full 全部通过。

## 4. 根因

空间核缺少寄存器边界，把 RAM tco、窗口选择、乘法、加法、比较连接成一条路径。
point1 把中心化、乘法、两次偏置加法、饱和和 Gamma 查表放在同一拍；point2 同拍执行
灰度乘法与求和、阈值及反色。输入间隙和输出反压要求所有新增数据、标志和 valid
与现有 `advance` 同步推进，不能只给算术加延迟。

## 5. 修复

### 流水划分

点运算始终各为 5 拍（原先各 1 拍，增加各 4 拍），包括旁路配置。
每个启用的 3×3 级为一行 + 11 拍（原先一行 + 3 拍，增加 8 拍）；
OP 0/7 保持一拍旁路，不经过行 RAM。

| 模块 / 级 | 该拍运算 |
|---|---|
| filter R1 | 行 RAM 读请求和请求元数据；原有延迟写与同址前递保持 |
| filter R2 | 原始 DRM 输出直接寄存，前递元数据同步延迟 |
| filter R3 | 前递、行 bank 选择、补零和横向历史寄存 |
| kernel K1 | 两个完整 3×3 窗口寄存；灰度乘法的输入寄存器 |
| kernel K2 | 灰度三路乘法的输出；RGB 均值/高斯第一层两两加法及尾项舍入；锐化中心 ×5（移位加）和邻点两两加法 |
| kernel K3 | 灰度 R+G、B+128 并行；RGB 第二层加法；锐化邻点合并 |
| kernel K4 | 灰度最终加法；RGB 八点和；锐化中心减邻点和 |
| kernel K5 | Sobel 四个正权瓣的角点和、中心点延迟；min/max 第一层；RGB 第九点合并；锐化饱和 |
| kernel K6 | Sobel 正权瓣加两倍中点；min/max 第二层；均值倒数常量乘法输出（K5 为输入寄存）；高斯移位 |
| kernel K7 | Sobel 两方向绝对差：正反相减与比较并行，选择输出；min/max 第三层；RGB 运算选择 |
| kernel K8 | Sobel 幅值和、饱和；min/max 第四层；最终核输出选择并寄存 |
| point1 P1 | RGB565 展开、中心化（翻转最高位）、对比度输入寄存；BRIGHTNESS+128 预加 |
| point1 P2 | 有符号对比度乘法输出寄存 |
| point1 P3 | 算术右移后的乘积与预加偏置相加 |
| point1 P4 | 饱和及 BC 旁路选择 |
| point1 P5 | Gamma 查表及旁路选择，输出寄存 |
| point2 P1 | RGB888 和控制输入寄存 |
| point2 P2 | 灰度三路乘法输出寄存 |
| point2 P3 | R+G、B+128 并行加法 |
| point2 P4 | 灰度最终加法 |
| point2 P5 | 灰度/阈值选择、反色、RGB565 截断及输出寄存 |

数据寄存器和帧标志不复位；valid 和原有控制状态按复位/clear 清除。
所有数据、valid、标志在 `advance=0` 时冻结；Gamma 写入仍独立于推进与清除。
point1 的配置随每拍输入延迟，保持输入 SOF 同拍快照配置的原有语义。
未新增 RTL 文件或 filelist 条目，未保留旧组合核备用路径。

### 精确除 9

令 `x=sum+4`，改为 `floor(x*3641 / 32768)`，即乘法后取 `[22:15]`。
对于 `0 <= x <= 2303`，写成 `x=9q+r`，有 `0<=q<=255`、`0<=r<=8`。
由于 `9*3641=32768+1`，乘积为 `32768q+q+3641r`，而
`q+3641r <= 255+3641*8=29383 < 32768`，因此商逐位相同。
RTL 可达的 `sum+4` 为 4–2299；单元测试覆盖全部可达均值和，并额外穷举要求的完整范围。

### 资源参考

Yosys 通用 LUT6 综合，行 RAM 黑盒：**21,163 LUT6**、13,177 个触发器位、4 个 RAM 包装实例。
原始记录：`build/pix_synth/pix.log`、`build/pix_synth/pix.json`。
映射前 `proc; flatten; opt; wreduce; opt; stat` 得到 **132 个 `$mul`**，
记录为 `build/pix_synth/arithmetic.log`；不是器件 APM 占用数。
复现该统计：保留 `resource.ys` 中 `synth -top` 之前的 read/hierarchy 命令，随后执行
`proc; flatten; opt; wreduce; opt; stat`；本次脚本位于 `build/pix_synth/arithmetic.ys`。
协调者已在 V-R6 问答中确认该报告口径：通用 LUT6 与 `$mul` 仅作参考，真实 LUT/APM 以
Windows PDS 为准，不另外寻找 Pango 映射。
该 Yosys 没有 Pango 综合后端，不能提供真实 APM 数，125 MHz 是否收敛仍需 Windows PDS
在 PG2L200H-6、8 ns 下测量；本次不把 Linux 结构划分当成器件时序实测。

## 6. 防回归

`pix_point` 使用输入期望队列，验证流水延迟后的逐位结果，增加随机配置、间隙及冻结。
`pix_filter` 检查启用级的首像素延迟不超过一行 + 16 拍，并保留原有冲刷上限检查。
`pix_control` 只修正当前帧行宽对应的上限变量，判据仍为规格 `W+32`。
新增 `pix_kernel` 对独立整数公式逐位比对，穷举除 9，并在全局冻结时保持管线。
独立模块测试 `verif/block/pix/`、`verif/block/vin/` 未改动。

| 检查 | 结果 | 原始日志 |
|---|---|---|
| RTL 风格 | 6 文件，0 告警 | 上述命令标准输出 |
| Verilator RTL lint | 0 告警 | 上述命令标准输出；独立模块和 VI-18 编译也启用 `-Wall` |
| point/filter/control/kernel smoke | 4 PASS / 0 FAIL | `build/regress/smoke/unit/pix_*/verilator/{compile,run}.log` |
| point/filter/control/kernel full | 4 PASS / 0 FAIL | `build/regress/full/unit/pix_*/verilator/{compile,run}.log` |
| PIX smoke | 2 PASS / 0 FAIL（参考模型 selftest + 12 个 RTL 场景） | `build/regress/smoke/block/pix/verilator/run.log`、`selftest/verilator/run.log` |
| PIX full | 3 PASS / 0 FAIL（25 个 full 场景、selftest、12 个 smoke 场景） | `build/regress/full/block/pix/full/verilator/run.log`、同目录下 selftest/顶层日志 |
| PX-10 | 连续输入 256 拍 / 256 双像素拍，2 像素/拍；随机流控通过 | `build/pix/dut/PX-10/run.log` |
| PX-11 | 两帧分别 **1312 / 1312 拍**，上限均为 **1312 拍**；下一 SOF 等待通过 | `build/pix/dut/PX-11/run.log` |
| VI-18 | 摄像头、内存源、ABORT、恢复全部 PASS | `build/vin_pix/run.log` |

完整 1280×720 全链路 PX-07 三帧、49 种级联 PX-05、PX-14 十个随机种子全部通过。
`pix_filter` 对连续流首像素之后的每拍输出增加无空拍检查，smoke/full 均通过。
PX-11 的 1312 拍正好是 `2*640 + 5 + 11 + 11 + 5`；本实现保留规格上限，未调整判据。

修改文件：

- `rtl/media/pix/edrv32_pix_filter.v`
- `rtl/media/pix/edrv32_pix_kernel.v`
- `rtl/media/pix/edrv32_pix_point1.v`
- `rtl/media/pix/edrv32_pix_point2.v`
- `verif/unit/pix_point/tb.sv`
- `verif/unit/pix_filter/tb.sv`
- `verif/unit/pix_control/tb.sv`
- `verif/unit/pix_kernel/{files.f,test.yaml,tb.sv}`
- 本调试记录


## 7. 同类排查

两个空间级共用同一 filter/kernel 实现，因此同时修复；point1 的乘法及 Gamma、point2
的灰度乘法也拆开。每条算术路径保留明确输入/输出寄存器；均值、高斯为平衡加法树，
腐蚀/膨胀为四层比较树。Sobel 用非负正权瓣分别求和，再并行相减和比较选择绝对值，
避免“有符号求和再取负”的串联进位链。
