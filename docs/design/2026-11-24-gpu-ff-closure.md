# GPU FF 与时序收敛

## 背景和问题

卡 107 第五轮（`7bb2560e4`）PDS Compile/综合通过，Device Map 报 DRC-0018：
全片 FF 320,874，器件容量 319,600；GPU 286,085，perspective 161,622，
raster 51,448。perspective 的全局流水使能扇出过高；纹理地址组合路径过长。

## 约束

数值和输出顺序保持 `7bb2560e4`，四个 lane、所有位宽和参考模型不变。
深度至少 8 的数据延迟用 RAM；长流水不随出口停顿；新增 DRM 总量不超过 60。
Yosys 数字仅作参考，以 PDS 为准。最终验收还需 Windows 创建新 IP 后重跑 PDS。

## 可选方案

寄存器移位保留原行为，但每项有效/无效数据都占用整条 FF 链，且全局 CE 扇出大。
固定距离环形 RAM 保持每条延迟的拍数，只需要一组地址计数器和同步读出口。
将相同深度跨 lane 合并，能利用 72 位宽度；输入相同的梯度延迟共享一次存储。

## 决策

### perspective

固定 512 项地址环，每拍写地址加一，深度 D 的读地址为写地址减 (D−1)，
RAM 同步读的一个周期计入 D。控制 valid 在复位/stop 时清零，数据 RAM 不复位。

| 延迟深度 | 合并后的有效位宽 | 512×72 实例 |
|---|---:|---:|
| 8（scale 高位量/方向） | 120 | 2 |
| 9 | 8 | 1 |
| 12 | 40 | 1 |
| 14（含 subtract 指数） | 392 | 6 |
| 25（subtract 旁路） | 464 | 7 |
| 41 | 58 | 1 |
| 51（四路导数共用同一 inverse） | 116 | 2 |
| 53 | 256 | 4 |
| 54 | 116 | 2 |
| 103 | 160 | 3 |
| 105（含 metadata） | 305 | 5 |
| 合计 | | 34 |

subtract 的 25 拍旁路和 14 拍指数，以及 scale 的 8 拍高位移位量/方向，
通过新增的 RAM 数据端口合并到同深度全局 bank，不改变辅助单元的算术或拍数。
scale 低 7 位移位量仍按各算术级使用，最长延迟七拍；控制有效位仍为寄存器。

结果负载 849 位，分为 12 个 RAM bank。FIFO 使用 512 项物理地址环，
以 128 个 credit 限制已接收、尚未输出的总项数（包括入口两项），容量大于 105+2。
入口有两项队列；外部输入握手时预留 credit，无 credit 时不接收新输入。出口 RAM 同步预读
队首，等待下游时保持读输出，消费后推进读地址。stop 清空控制状态并丢弃在途 valid。
长算术流水的使能固定为 1，数据每拍推进。

### raster

扫描流水的 advance 固定为 1，16 个 credit 从 scan 握手到结果消费或 mask=0
丢弃期间保留；每拍最多释放一个消费项和一个剔除项。只在 credit 用完时停止
发出新的 scan，已发出的十级算术/覆盖流水继续推进。结果 FIFO 为 64 项，
有效负载 2253 位，复用九个 `edrv32_ram_gpu_read_pool`（64×256 LUTRAM）包装，
不新增 DRM；入口总在途数限制为 16。深 metadata 延迟合并为 280 位×10 拍
（四个 delay IP）和 7 位×9 拍（一个 delay IP）。

### 队列写入点

第 5 轮 `flow-excerpts.log` 的 GPU multi-write 清单仅列出以下三项。

| 数组 | 处理 |
|---|---|
| pixel `old_r` | 将 target 返回与前项转发合并为一个地址/数据/使能写口；返回优先，冲突拍推迟转发 dispatch |
| read DMA `first_keep_r` | 七个客户端各自保留一个 32 位寄存器，使用请求/AR 消费选择器，只写整个寄存器一次 |
| write DMA `first_keep_r` | 四个客户端各自保留一个 32 位寄存器，使用请求/突发装入完成选择器，只写整个寄存器一次 |
| pixel `result_r` | 现有代码已经是 `pipe_valid_r[14]` 下唯一整元素写入点，第 5 轮没有该数组的 multi-write 警告，保持原写法 |
| pixel `addr_r`、`mask_r`、`depth_r`、`color_r`、`alpha_r` | 32 项输入字段，原有 accept 单一整元素写口，保持 |
| pixel `return_slot_r` | 32 项返回顺序队列，原有单写口，保持 |
| texture `x_r`、`y_r`、`mask_r`、`depth_r`、`color_r`、`alpha_r`、`quad_r`、`palette_r` | 32 项输入字段，原有 accept 单一整元素写口，保持 |
| texture 每 lane 的 `u_r`、`v_r` | 32 项输入坐标，原有 accept 单写口，保持 |
| texture 每 lane 的 `lod_r` | 32 项 LOD 数据，原有 LOD 完成单写口，保持 |
| texture 每 lane 的 `result_color_r`、`result_alpha_r`、`result_mask_r` | 32 项结果字段，原有过滤完成单写口，保持；第 5 轮没有以上 texture 数组的 multi-write 警告 |
| texture completion/LOD-ready | 现有每 context 一个四位寄存器，非 RAM 数组；保留单写寄存器 |

非 GPU 的 CPU regfile、mem_xbar 警告不在本任务归属内。

### TEX 配置流水

SET_TEX 接收后，mip 尺寸每级寄存，尺寸乘积和基址前缀分别寄存，最后一级
在第 19 拍稳定；第 20 拍后允许接收 sample。九位环绕掩码、行跨度的二进制
移位量同样在配置时寄存。固定配置各级只含九位尺寸选择、9×9 乘积或十七位
加法，结构级数预算均不超过 8；此处是估算，仍需 PDS 验证。

取样时用已存掩码直接环绕，行乘法改为按预存指数移位。布局保证列号占据行偏移
的零低位，二者用 OR 合并；mip 基址按四个半字对齐，bank 两位单独拼接，保留
全部有效位及原 17 位回绕行为。取样/分配器剩余路径的实际时序尚待测量。
在最终 Yosys LUT6 网表中，从 `log2_w_r` 各位开始、只沿组合 `$lut`
的 A→Y 边追踪，在 FF 边界停止：到下一 FF 的最长路径为 7 级，
到 `texture_read_addr_o` 没有直达组合路径。此数字不含布线、硬核或 PDS 专用映射。

### 其余纯数据延迟线

texture 将九拍的 136 位过滤权重和八位 LOD 分数合并为 144 位，两块 delay IP；
数据每拍推进，原九拍 valid/slot/mode/lane 控制保持原关系。

setup_plane 将 h 的首拍单独寄存，随后和 33 位 first 系数合并为 43 位×13 拍；
h 读出后再寄存一拍，使 normal 使用第 14 拍的 h，plane_h 仍为第 15 拍。
offset 先寄存一拍，再与六位 reciprocal exponent 合并为 42 位×9 拍，
保持 offset 总十拍、exponent 总九拍。此 bank 再并入 project_recip 的六位指数，
该指数在 setup 首拍寄存后经过九拍 RAM，总十拍，bank 有效宽度增至 48 位。
两个 bank 共用 enabled 时钟计数器，
与原 enable_i 停顿严格同步；tag/valid 控制仍为寄存器。

project 将原 11 拍、224 位有效顶点负载改为首拍字段寄存加十拍 RAM；
同一深度并入 project_recip 的六位指数，共四块 RAM。W 不进入负载 RAM，
因为只供倒数计算，原来的 W 延迟输出没有使用者。project_recip 的指数存储
由调用者的 RAM 提供，算术结果和 valid 延迟不变。

object 将 24 位对象下标的十二拍延迟替换为一块 RAM，仍随原 advance 停顿。

### 参考资源测量

改前输入为 `7bb2560e4`，改后输入为 `980d03182`。Yosys 版本为
0.70+219（git 5053d0e26）；RAM/ROM 包装设为 blackbox，保留模块层次，
使用 `synth -noabc`，再用 ABC 的 `strash; if -K 6` 映射到 LUT6。
FF 数为层次展开后的所有 DFF 位单元之和；LUT 数为 `$lut` 位单元之和；
DRM 数按固定配置 RAM/ROM 包装实例计数。blackbox 内的输出寄存器和 LUTRAM
读寄存器没有计入 FF；raster 新增九个 256 位 LUTRAM 包装的读寄存器也没有计入。
LUT6 列只计包装外逻辑，不含 LUTRAM IP 内部 LUT；两版 LUTRAM 包装实例数为
11 → 20，其中九个新增实例全部属于 raster 结果 FIFO。
保留层次未按实例常量输入裁剪，通用乘法也未映射 Pango DSP，因此这些数字
不能与 PDS 的数字直接相减。**以下 Yosys 估算仅作参考，以 PDS 为准。**

| Module | FF before | FF after | LUT6 before | LUT6 after | DRM before | DRM after |
|---|---:|---:|---:|---:|---:|---:|
| GPU | 394093 | 285962 | 349520 | 341868 | 194 | 254 |
| u_command | 1915 | 1915 | 1153 | 1155 | 0 | 0 |
| u_geometry | 24677 | 22386 | 76237 | 76262 | 1 | 5 |
| u_list_pack | 2227 | 2227 | 1693 | 1692 | 0 | 0 |
| u_object | 4946 | 4667 | 2482 | 2501 | 0 | 1 |
| u_palette | 197 | 197 | 168 | 168 | 8 | 8 |
| u_perspective | 174085 | 77400 | 79009 | 78095 | 4 | 50 |
| u_pixel | 23499 | 23499 | 30010 | 24827 | 0 | 0 |
| u_quad | 1898 | 1898 | 2078 | 2078 | 0 | 0 |
| u_raster | 64585 | 57262 | 34739 | 30472 | 0 | 5 |
| u_read_dma | 1893 | 1897 | 3392 | 3498 | 0 | 0 |
| u_regs | 1895 | 1895 | 2404 | 2404 | 0 | 0 |
| u_resolve | 2843 | 2843 | 4335 | 4339 | 3 | 3 |
| u_setup | 49796 | 48856 | 62856 | 62975 | 1 | 3 |
| u_target | 7311 | 7311 | 5451 | 5451 | 129 | 129 |
| u_texture | 26442 | 25825 | 35542 | 37915 | 0 | 2 |
| u_texture_ram | 1027 | 1027 | 798 | 798 | 48 | 48 |
| u_unpack | 2553 | 2553 | 2011 | 2011 | 0 | 0 |
| u_write_dma | 2261 | 2261 | 2866 | 2931 | 0 | 0 |
| reset_copy（18 个） | 18 | 18 | 0 | 0 | 0 | 0 |

初始中间检查采用 Yosys 默认 `abc -lut 6`，只测 perspective：保留层次
174085 → 92200 FF、74665 → 73987 LUT6；扁平化后 164254 → 83105 FF。
该阶段先于辅助单元延迟合并，已按任务要求向协调者提出中间结果及算术重定时建议。
默认 ABC 中间数字与上表快速映射结果分开记录，不作为同一阶段结果。

同一保留层次方法的最大 CE 扇出为 86836 → 3702；改后最大网络位于 setup。
geometry 由 4127 降至 1836，object 3660 → 3381；perspective 最大为 1877，
raster 最大为 1977。早期独立扁平化检查的 perspective CE 为 158688 → 1877，
raster 为 35911 → 1977。CE ≤4000 目标在当前参考网表中已满足。

FF 目标仍未满足：GPU 285962 >120000，perspective 77400 >30000，
raster 57262 >20000。仅做延迟存储搬迁不能闭合这些差额；辅助算术本身还有大量
逐位移位/分片进位流水寄存器。层次估算中 perspective 的 normal 占 31280 FF、
scale 14376、subtract 本体 11632、multiply 6768、其余 13344；raster 的
分片 add 占 26483、模块本体 24066、plane 本体 5740、prepare 本体 973。
这些是当前网表的贡献值，不是修改算术级数后的预测值。已经提出不改变数值、位宽和 lane 的算术重定时建议，
当前尚未收到答复，没有擅自调整这些算术流水级。

复现资源测量时，从对应 commit 导出 `rtl/` 到独立目录，按 `gpu.f` 展开源文件：

```python
from pathlib import Path
root = Path('.')
Path('build').mkdir(exist_ok=True)
files = [(root/'rtl/filelists'/line).resolve()
         for line in (root/'rtl/filelists/gpu.f').read_text().splitlines()
         if line.strip() and not line.startswith('+')]
Path('build/lut6.abc').write_text('strash\nif -K 6\n')
Path('build/gpu.ys').write_text(
    'read_verilog -D SIM_MODE -Irtl/include ' + ' '.join(map(str, files)) + '\n'
    'blackbox edrv32_ram_gpu_* edrv32_rom_gpu_*\n'
    'synth -top edrv32_gpu -noabc\n'
    'abc -lut 6 -script build/lut6.abc\n'
    'stat\nwrite_json build/gpu.json\n')
```

运行 `yosys -Q -T -s build/gpu.ys`。每模块递归展开 cells 的类型统计，
名称含 DFF 的单元计 FF，`$lut` 计 LUT；RAM/ROM 按上述固定配置计 DRM。
CE 扇出通过逐实例绑定模块端口至父层 net，累加各 DFF 的 E 端点；常量使能不计。
原始测量脚本、网表和日志留在 `build/gpu-ff-closure/`。

## 影响

新增 `edrv32_ram_gpu_delay` / `ip_ram_gpu_delay`，固定 512×72、简单双口，
同步读延迟一拍，一个实例一块 DRM36K；当前 perspective 延迟线 34 块、结果队列 12 块，raster 延迟线 5 块，
texture 过滤元数据 2 块、setup_plane 元数据 2 块、project 元数据 4 块、object 下标 1 块，
共新增 60 块。以第五轮全片 296 块为基准，估算为 356/415。
IP 创建说明见 `fpga/ip/ip_ram_gpu_delay.md`，GPU 文件列表加入包装，
perspective 单元测试仅增加新包装的编译依赖，激励和期望值不变。

### 实现提交

| 提交 | 内容 |
|---|---|
| `4a84be516` | gpu: move perspective delay lines to RAM |
| `ed2fb190e` | gpu: credit-based perspective pipeline |
| `8f39122e7` | gpu: coalesce perspective helper delays in RAM |
| `1209e5eea` | gpu: credit-based raster pipeline with RAM delays |
| `a4b3bf617` | gpu: give queued old values and DMA masks one write point |
| `ec1f71b4b` | gpu: precompute texture mip addressing at TEX configuration |
| `980d03182` | gpu: move remaining metadata delays into shared RAM |

### 验证方法与结果

仿真只在指定仿真环境执行，工具为 Verilator 5.051 devel、Icarus Verilog
14.0 devel（s20260301-328-geda9fdcd1）。
未修改参考模型、输入向量或比较规则。GPU 的 18 个 unit 目录全部通过；
pixel、texture、raster 在各自最后一次修改后再次通过；最终 RAM 合并之后
perspective、geometry、setup、object 再次通过。单测重跑命令为：

```sh
for path in verif/unit/gpu_*; do
    python3 tools/regress.py full --path "$path" -j 1
done
```

perspective 两组各 1800 项全部逐位相同，无反压 first=123、last=1922、
cycles=1924，有反压 first=123、last=3368、cycles=3370，stop/finish 通过。
raster 四组 fragment 数为 32813、32813、32487、32487，总计 130600，
周期为 50930、74590、50547、73925。geometry 63 draws / 615 vertices /
179 triangles；setup 264 inputs / 262 outputs；object 15 cases / 1569 inputs /
1037 updates / 1557 events / 836 quads，均通过。

GPU 顶层 lint 命令在 `rtl/filelists/` 下执行：
`sh ../../tools/check/lint.sh -DSIM_MODE -f gpu.f --top-module edrv32_gpu`，0 告警。
风格检查 `python3 tools/check/verilog_style.py rtl/gpu rtl/tech/edrv32_ram_gpu_delay.v`
检查 37 个文件，0 告警。

完整模块回归命令：

```sh
python3 verif/block/gpu/run.py rtl \
    gt01 gt02 gt03 gt04 gt05 gt06 gt07 gt08 gt09 gt10 gt11 gt12 gt13 \
    gt14 gt15 gt16 gt17 gt18 gt19 gt20 gt21 gt22 gt23 gt24 gt25
python3 verif/block/gpu/gt25/performance.py compare
```

实际运行中各文件列表相同，只构建一次仿真程序，
依次使用 `run.generate` 生成数据、按每项 `sim_args.json` 和元数据 seed 运行，
用 `run.compare` 逐项比较。编译保留原来的 `--binary --timing -Wall -j 1`，
另外指定 `--output-groups 0 -MAKEFLAGS OPT_FAST=-O1`，避免工具默认把全部 C++
合为一个大文件；构建优化选项不改变 RTL 周期。最终一次重跑复用已经生成的参考数据。
GT-25 另外执行 `verif/block/gpu/gt25/performance.py` 的 compare/measure 流程。

最终 RTL 的 GT-01～GT-25（含所有子场景）全部通过；GT-25 十个性能场景
全部通过模型比较及性能检查。原始最终日志为 `build/gpu-ff-closure/latest-gt01-25.log`，
两版完整周期报告为同目录的 `GT25-before.txt`、`GT25-after.txt`。
完成后已经清理自己的临时仿真目录和进程。

### GT-25 全部命令周期

基线为独立导出的 `7bb2560e4`，两版采用同一 DDR 延迟、180 MHz 周期换算，
周期含 APB 观察开销。AA RESOLVE 640×360 两版均为 79031 周期（0.439061 ms），
低于 90000 周期上限。下表列全十个场景、124 条命令，允许变化的周期逐项列出。

| 场景 | 命令序号 | 7bb2560e4 周期 | 改后周期 | 差值 |
|---|---:|---:|---:|---:|
| quad | 1 | 28 | 28 | +0 |
| quad | 2 | 28840 | 28840 | +0 |
| quad | 3 | 22 | 22 | +0 |
| quad | 4 | 88 | 88 | +0 |
| quad | 5 | 22 | 22 | +0 |
| quad | 6 | 46 | 46 | +0 |
| quad | 7 | 22 | 22 | +0 |
| quad | 8 | 415 | 415 | +0 |
| quad | 9 | 85 | 85 | +0 |
| quad | 10 | 22 | 22 | +0 |
| quad | 11 | 25 | 25 | +0 |
| quad | 12 | 43 | 43 | +0 |
| quad | 13 | 16699 | 16702 | +3 |
| quad | 14 | 39349 | 39346 | -3 |
| nearest | 1 | 28 | 28 | +0 |
| nearest | 2 | 28840 | 28840 | +0 |
| nearest | 3 | 22 | 22 | +0 |
| nearest | 4 | 88 | 88 | +0 |
| nearest | 5 | 22 | 22 | +0 |
| nearest | 6 | 46 | 46 | +0 |
| nearest | 7 | 22 | 22 | +0 |
| nearest | 8 | 268 | 268 | +0 |
| nearest | 9 | 28 | 28 | +0 |
| nearest | 10 | 22 | 22 | +0 |
| nearest | 11 | 49 | 49 | +0 |
| nearest | 12 | 4510 | 4513 | +3 |
| nearest | 13 | 39469 | 39466 | -3 |
| bilinear | 1 | 28 | 28 | +0 |
| bilinear | 2 | 28840 | 28840 | +0 |
| bilinear | 3 | 22 | 22 | +0 |
| bilinear | 4 | 88 | 88 | +0 |
| bilinear | 5 | 22 | 22 | +0 |
| bilinear | 6 | 46 | 46 | +0 |
| bilinear | 7 | 22 | 22 | +0 |
| bilinear | 8 | 268 | 268 | +0 |
| bilinear | 9 | 28 | 28 | +0 |
| bilinear | 10 | 43 | 43 | +0 |
| bilinear | 11 | 37891 | 36574 | -1317 |
| bilinear | 12 | 39460 | 39631 | +171 |
| trilinear | 1 | 28 | 28 | +0 |
| trilinear | 2 | 28840 | 28840 | +0 |
| trilinear | 3 | 22 | 22 | +0 |
| trilinear | 4 | 88 | 88 | +0 |
| trilinear | 5 | 22 | 22 | +0 |
| trilinear | 6 | 46 | 46 | +0 |
| trilinear | 7 | 22 | 22 | +0 |
| trilinear | 8 | 268 | 268 | +0 |
| trilinear | 9 | 28 | 28 | +0 |
| trilinear | 10 | 43 | 43 | +0 |
| trilinear | 11 | 62038 | 62035 | -3 |
| trilinear | 12 | 39559 | 39562 | +3 |
| palette_i4 | 1 | 28 | 28 | +0 |
| palette_i4 | 2 | 28840 | 28840 | +0 |
| palette_i4 | 3 | 22 | 22 | +0 |
| palette_i4 | 4 | 88 | 88 | +0 |
| palette_i4 | 5 | 22 | 22 | +0 |
| palette_i4 | 6 | 46 | 46 | +0 |
| palette_i4 | 7 | 22 | 22 | +0 |
| palette_i4 | 8 | 415 | 415 | +0 |
| palette_i4 | 9 | 85 | 85 | +0 |
| palette_i4 | 10 | 22 | 22 | +0 |
| palette_i4 | 11 | 307 | 307 | +0 |
| palette_i4 | 12 | 38155 | 36841 | -1314 |
| palette_i4 | 13 | 39529 | 39469 | -60 |
| palette_i8 | 1 | 28 | 28 | +0 |
| palette_i8 | 2 | 28840 | 28840 | +0 |
| palette_i8 | 3 | 22 | 22 | +0 |
| palette_i8 | 4 | 88 | 88 | +0 |
| palette_i8 | 5 | 22 | 22 | +0 |
| palette_i8 | 6 | 46 | 46 | +0 |
| palette_i8 | 7 | 22 | 22 | +0 |
| palette_i8 | 8 | 415 | 415 | +0 |
| palette_i8 | 9 | 133 | 133 | +0 |
| palette_i8 | 10 | 22 | 22 | +0 |
| palette_i8 | 11 | 301 | 301 | +0 |
| palette_i8 | 12 | 38152 | 36835 | -1317 |
| palette_i8 | 13 | 39490 | 39433 | -57 |
| vertex | 1 | 28 | 28 | +0 |
| vertex | 2 | 28840 | 28840 | +0 |
| vertex | 3 | 22 | 22 | +0 |
| vertex | 4 | 88 | 88 | +0 |
| vertex | 5 | 22 | 22 | +0 |
| vertex | 6 | 46 | 46 | +0 |
| vertex | 7 | 22 | 22 | +0 |
| vertex | 8 | 22 | 22 | +0 |
| vertex | 9 | 25 | 25 | +0 |
| vertex | 10 | 43 | 43 | +0 |
| vertex | 11 | 3001 | 3001 | +0 |
| vertex | 12 | 39430 | 39430 | +0 |
| setup | 1 | 28 | 28 | +0 |
| setup | 2 | 28840 | 28840 | +0 |
| setup | 3 | 22 | 22 | +0 |
| setup | 4 | 88 | 88 | +0 |
| setup | 5 | 22 | 22 | +0 |
| setup | 6 | 46 | 46 | +0 |
| setup | 7 | 22 | 22 | +0 |
| setup | 8 | 22 | 22 | +0 |
| setup | 9 | 25 | 25 | +0 |
| setup | 10 | 43 | 43 | +0 |
| setup | 11 | 374515 | 374515 | +0 |
| setup | 12 | 39544 | 39544 | +0 |
| objects | 1 | 19 | 19 | +0 |
| objects | 2 | 28837 | 28837 | +0 |
| objects | 3 | 25 | 25 | +0 |
| objects | 4 | 85 | 85 | +0 |
| objects | 5 | 22 | 22 | +0 |
| objects | 6 | 46 | 46 | +0 |
| objects | 7 | 25 | 25 | +0 |
| objects | 8 | 40 | 40 | +0 |
| objects | 9 | 66607 | 66607 | +0 |
| objects | 10 | 39454 | 39454 | +0 |
| resolve | 1 | 28 | 28 | +0 |
| resolve | 2 | 28840 | 28840 | +0 |
| resolve | 3 | 22 | 22 | +0 |
| resolve | 4 | 88 | 88 | +0 |
| resolve | 5 | 22 | 22 | +0 |
| resolve | 6 | 46 | 46 | +0 |
| resolve | 7 | 22 | 22 | +0 |
| resolve | 8 | 22 | 22 | +0 |
| resolve | 9 | 28837 | 28837 | +0 |
| resolve | 10 | 39535 | 39535 | +0 |
| resolve | 11 | 22 | 22 | +0 |
| resolve | 12 | 28834 | 28834 | +0 |
| resolve | 13 | 39496 | 39496 | +0 |

## 状态

讨论中：RAM/credit/单写口/纹理配置预计算已经实现；当前参考网表的新增 DRM 与
CE 扇出满足限额，FF 总量及 perspective/raster 子模块限额尚未满足。
算术重定时的中间提问等待答复；Windows 新 IP 创建与 PDS 时序/资源复测尚未执行。
本记录不把功能回归通过等同于 FF 或 180 MHz 时序闭合。

## S-3：算术流水、G 精度与 2×2 LOD（2026-11-25）

实现提交：S-3.1 `0725ffa10`；模型 S-3.2 `f985fe992`；RTL S-3.3 `f4b9bf8be`。基线 `8807e6580`；S/G按d=[8,4,4,4,12,12,12]舍入，累加W=[62,66,66,66,58,58,58]，移除归一化梯度，成对八lane计算2×2差分LOD，Q=0输出U=V=0、负Q保留倒数符号；本节更新上文 S-2 的固定精度及“算术重定时尚未实现”状态。
沿用上文 Yosys 0.70+219（5053d0e26）、RAM/ROM blackbox、`synth -noabc`、ABC `strash; if -K 6`、递归计数 DFF/`$lut` 的方法，逐个以 `edrv32_gpu_<模块>` 为顶层，未全 GPU 扁平化；复现用上文 `gpu.ys` 生成代码替换 `synth -top`，运行 `yosys -Q -T -s build/gpu.ys`。top 行另将 `edrv32_gpu_*` blackbox，只计 24 位对象序号、源选择及18个reset copy；总计是独立模块之和，缺少调用方常量裁剪，故不等于上文整 GPU 层次综合。blackbox 内寄存器及 LUTRAM LUT 不计入。
APM 未映射，以第7轮PDS为准；perspective 的18×18乘法实例 **48 / 48 / 16**，其余模块动态乘法数量和位宽未变。没有新增IP。

| 模块 | FF：8807 / S-3.1 / S-3.3 | LUT6：8807 / S-3.1 / S-3.3 | APM（三阶段） |
|---|---:|---:|---|
| command | 1915 / 1915 / 1915 | 1143 / 1143 / 1143 | 未映射，以PDS7为准 |
| geometry | 22386 / 22386 / 22386 | 75515 / 75515 / 75515 | 未映射，以PDS7为准 |
| list_pack | 2227 / 2227 / 2227 | 1719 / 1719 / 1719 | 未映射，以PDS7为准 |
| object | 4667 / 4667 / 4667 | 2512 / 2512 / 2512 | 未映射，以PDS7为准 |
| palette | 197 / 197 / 197 | 168 / 168 / 168 | 未映射，以PDS7为准 |
| perspective | 77400 / 38512 / 27407 | 77203 / 87639 / 41068 | 未映射，以PDS7为准 |
| pixel | 23499 / 23499 / 23499 | 19316 / 19316 / 19316 | 未映射，以PDS7为准 |
| quad | 1910 / 1910 / 1910 | 2018 / 2018 / 2018 | 未映射，以PDS7为准 |
| raster | 57262 / 35335 / 28966 | 30364 / 27683 / 22870 | 未映射，以PDS7为准 |
| read_dma | 1897 / 1897 / 1897 | 3461 / 3461 / 3461 | 未映射，以PDS7为准 |
| regs | 1895 / 1895 / 1895 | 2435 / 2435 / 2435 | 未映射，以PDS7为准 |
| resolve | 2843 / 2843 / 2843 | 4161 / 4161 / 4161 | 未映射，以PDS7为准 |
| setup | 49180 / 49180 / 42944 | 47382 / 47382 / 44943 | 未映射，以PDS7为准 |
| target | 7311 / 7311 / 7311 | 4896 / 4896 / 4896 | 未映射，以PDS7为准 |
| texture | 25825 / 25347 / 25347 | 34106 / 34398 / 34398 | 未映射，以PDS7为准 |
| texture_ram | 1027 / 1027 / 1027 | 799 / 799 / 799 | 未映射，以PDS7为准 |
| unpack | 2553 / 2553 / 2553 | 2028 / 2028 / 2028 | 未映射，以PDS7为准 |
| write_dma | 2261 / 2261 / 2261 | 3412 / 3412 / 3412 | 未映射，以PDS7为准 |
| top | 43 / 43 / 43 | 2296 / 2296 / 1898 | 未映射，以PDS7为准 |
| GPU（独立模块之和） | 286298 / 225005 / 201295 | 314934 / 322981 / 268760 | 未映射，以PDS7为准 |

GPU FF 比120000目标多 **81295**，raster 比20000多 **8966**；perspective **27407 ≤ 30000**。perspective LUT6 降低 **46.8%**，距至少50%尚差 **2467 LUT6**。perspective/raster 之外仍有144922 FF，setup本体上下文/系数占39407、raster本体占16037；perspective LUT6 中差分（含N）10848、未映射通用乘法10640。这些存储和运算成本超出三类冗余流水消除的收益，功能通过不代表资源闭合。
S-3.1 的 perspective LUT6 增加10436，其中68个N（52个直接实例加16个subtract内部实例）各增加150，共10200；scale增加504、subtract本体减少768、其余增加500。旧九拍移位分摊为小mux，新三拍的变量移位与串行优先计数放大组合网络；同法实测旧N为329 LUT，microarch中的560是先前估算。S-3.3 改为并行4位编码/分组选择，66位输入首拍仅捕获最高有效16位块（顶块18位）及其下18位组成的36位窗口，后三组显式平衡4选1完成移位、最后舍入；36/23位输入直接用36位窗口。scale/subtract 同样显式4选1，去掉隐式长变量移位链；N单实例数据如下（subtract含内部N，raster最终取最宽66位，均由所属模块网表递归计数）。

| 单元 | 8807 FF/LUT6 | S-3.1 FF/LUT6 | S-3.3 FF/LUT6 |
|---|---:|---:|---|
| normal | 460/329 | 140/479 | W66 113/296；W36 114/222；W23 101/181 |
| scale | 599/226 | 311/247 | W96 311/245；W32 182/170 |
| subtract | 1187/856 | 521/958 | 482/678 |
| raster_add | 373/170 | 176/184 | W66 164/172；W62 152/160；W58 140/148；W40 86/103 |

新拍数：add **4→2**（低35位结果/进位及未消费高位），absolute **4→2**，N **10→3**（计数及窗口/三级4选1移位/舍入），scale **9→4**，subtract **25→10**，sign **2→1**，maximum **2→1**（并行32位比较后选择），prepare **5→3**；multiply仍3拍。raster由4相位变2相位：S-3.1为x、x+4两相、步进8gx，S-3.3为同x偶/奇两行、步进4gx，换排加2gy。FIFO先存首行，第二行覆盖结果到达后成对提交；两行mask全0则回退写指针并回收2个credit，任一覆盖则完整提交两行及全部8个helper，避免空块占用纹理过滤周期，队列首组可见时间增加1拍。扫描/覆盖 **10→6**，透视 **105→53→43**，texture LOD **9→4**；quad仍3拍，setup仍15拍、II=8。
按协调者确认，本次只重写三类冗余流水；以下原单拍宽组合路径保留相位，供第7轮PDS核对（文件均在 `rtl/gpu/edrv32_gpu_*.v`）：transform `g_sum.matrix_sum_w` 50、`g_light.rounded_w` 42；clip `unused_distance_w/edge_distance_w`43、`denominator_w`44、`numerator_w`/绝对值84、`remainder_next_w`比较/减法45、`unused_rounded_w`85、结果符号恢复40；project_recip `unused_normalized_w`40、`unused_rounded_product_w`62/`unused_rounded_result_w`63。
project `unused_restored_w`40、`g_viewport.next_w`94、`g_screen.magnitude_w`94及`rounded_w/signed_w/offset_w`95、`depth_rounded_w`94；setup_plane `maximum_01_w/maximum_w`及h前导位51、`g_scale.unused_shifted_w`52、`g_axis.numerator_4_r`56、`magnitude_w`87、`unused_rounded_w`88/符号恢复56、`origin_sum_w`及舍入75、`start_13_r`加法70、G丢位绝对值56/舍入52、S丢位绝对值70/舍入66。旧 `g_axis.normal_magnitude_w`56/`rounded_normal_w`57 在S-3.1保留，S-3.3随梯度删除；通用LUT6映射不代表Pango进位链深度或PDS时序。
模型13项自测通过，G2完整研究786556样本完成且原数值不变；18个GPU unit、GT-01～25在S-3.1和S-3.3全部通过；最终空块省略补丁重跑raster/perspective及GT01–07、12、14–15、21–25，未受影响项沿用本阶段已通过结果。GT-12为57子场景，新增1/2/3像素覆盖、跨边、奇数目标起始行、目标/裁剪外上下行、未覆盖Q=0/Q<0，期望均来自模型；N额外以2454项覆盖23/36/66位全部二进制边界、符号、零、舍入进位及enable停顿。perspective连续1800组，raster最长连续28480组，texture最近邻/双线性/三线性为4/2/1像素每周期、预装261周期；风格36文件0告警，顶层lint 0告警。
复现：`python3 tools/gpu/model/selftest.py`；`python3 tools/gpu/model/study_plane_width.py --case G2 --output build/G2.json`；各 `verif/unit/gpu_*` 执行 `python3 tools/regress.py full --path <目录> -j 1`，GT执行 `python3 tools/regress.py full --path verif/block/gpu -j 1`；风格 `python3 tools/check/verilog_style.py rtl/gpu`；lint在 `rtl/filelists/` 执行 `sh ../../tools/check/lint.sh -DSIM_MODE -f gpu.f --top-module edrv32_gpu`。全部RTL仿真在指定仿真环境执行，本机只做Python自测、lint、风格和逐模块综合；原始数据保留 `build/gpu-s3/`。
GT-25下表各格按命令 **1…N** 顺序列全周期；基线为S-2实测（8807与980d的RTL相同），180MHz/默认DDR延迟，含APB观察开销。AA RESOLVE两版均79031周期（0.439061ms），低于90000周期上限；主要DRAW命令差为quad −69、nearest −117、bilinear +3、trilinear +174、I4/I8各+3、setup −92934周期，vertex/object不变。

| 场景 | 8807逐命令周期 | S-3.3逐命令周期 |
|---|---|---|
| quad | 28, 28840, 22, 88, 22, 46, 22, 415, 85, 22, 25, 43, 16702, 39346 | 28, 28840, 22, 88, 22, 46, 22, 415, 85, 22, 25, 43, 16633, 39415 |
| nearest | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 22, 49, 4513, 39466 | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 22, 49, 4396, 39502 |
| bilinear | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 43, 36574, 39631 | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 43, 36577, 39628 |
| trilinear | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 43, 62035, 39562 | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 43, 62209, 39475 |
| palette_i4 | 28, 28840, 22, 88, 22, 46, 22, 415, 85, 22, 307, 36841, 39469 | 28, 28840, 22, 88, 22, 46, 22, 415, 85, 22, 307, 36844, 39466 |
| palette_i8 | 28, 28840, 22, 88, 22, 46, 22, 415, 133, 22, 301, 36835, 39433 | 28, 28840, 22, 88, 22, 46, 22, 415, 133, 22, 301, 36838, 39430 |
| vertex | 28, 28840, 22, 88, 22, 46, 22, 22, 25, 43, 3001, 39430 | 28, 28840, 22, 88, 22, 46, 22, 22, 25, 43, 3001, 39430 |
| setup | 28, 28840, 22, 88, 22, 46, 22, 22, 25, 43, 374515, 39544 | 28, 28840, 22, 88, 22, 46, 22, 22, 25, 43, 281581, 39364 |
| objects | 19, 28837, 25, 85, 22, 46, 25, 40, 66607, 39454 | 19, 28837, 25, 85, 22, 46, 25, 40, 66607, 39454 |
| resolve | 28, 28840, 22, 88, 22, 46, 22, 22, 28837, 39535, 22, 28834, 39496 | 28, 28840, 22, 88, 22, 46, 22, 22, 28837, 39535, 22, 28834, 39496 |
