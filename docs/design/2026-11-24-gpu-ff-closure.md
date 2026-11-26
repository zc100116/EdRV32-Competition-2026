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

## S-4：半宽三角形、四边形旁路、切拍与控制复制

依据 gpu-spec v0.5、微结构4.13/4.14（d5d44d9cb）；周期基线为0018e27f2。四边形直接生成sample，与三角形重组后的sample在texture之前按命令来源有序选择；quad平面、fragment_quad和perspective的quad旁路全部删除。三角形按同一4×2块的左上、左下、右上、右下四个2像素半行发射，perspective保留两行结果，先合并上行、再合并下行；数值、覆盖掩码和组顺序不变。texture/pixel/target仍为4 lane，SoC端口及IP类型不变。

提交顺序：183cae592（旁路）、5297e4538（2 lane）、dabf447ff（宽算术切拍）、9fda023d4（区域控制复制）、ba3310ea6（补全texture、DMA、队列与控制路径）、04170a381（clip字段索引/计数复制）。前四个提交按协调者确认先提交后集中回归；最终回归覆盖这些提交的合成结果。

### 资源与宽总线

下表各格为 **FF / LUT6 / DRM实例**，递归包含模块子单元；top只计顶层本体。FF/LUT6使用相同通用Yosys映射（`synth -noabc; abc -lut 6 -script`，脚本`strash; if -K 6`），乘法没有替换成Pango APM；DRM按实际包装模块实例计数，含两种倒数ROM，不含read_pool/write_pool/palette_current分布式RAM。数字用于同口径比较，不能当作PDS器件资源预测。最终perspective与raster的FF、LUT6均低于0018e27f2；geometry/setup/texture增加数据寄存和地址上下文，最终独立模块合计FF增加64677、LUT6减少1712，需在第8轮PDS确认实际资源与布线。

| 模块 | d5前 | 旁路后183cae592 | 半宽后5297e4538 | 切拍后dabf447ff | 复制后9fda023d4 | 最终04170a381 |
|---|---:|---:|---:|---:|---:|---:|
| command | 1915 / 1143 / 0 | 1915 / 1143 / 0 | 1915 / 1143 / 0 | 1915 / 1143 / 0 | 1915 / 1143 / 0 | 2043 / 1221 / 0 |
| geometry | 22386 / 75515 / 5 | 22386 / 75515 / 5 | 22386 / 75515 / 5 | 45882 / 79180 / 5 | 46722 / 82939 / 5 | 46792 / 77460 / 5 |
| list_pack | 2227 / 1719 / 0 | 2227 / 1719 / 0 | 2227 / 1719 / 0 | 2227 / 1719 / 0 | 2227 / 1719 / 0 | 2227 / 1719 / 0 |
| object | 4667 / 2512 / 1 | 4667 / 2512 / 1 | 4667 / 2512 / 1 | 4667 / 2512 / 1 | 4908 / 3235 / 1 | 4908 / 3235 / 1 |
| palette | 197 / 168 / 8 | 197 / 168 / 8 | 197 / 168 / 8 | 197 / 168 / 8 | 197 / 168 / 8 | 197 / 168 / 8 |
| perspective | 27407 / 41068 / 43 | 27405 / 40618 / 39 | 14903 / 20941 / 26 | 14903 / 20941 / 26 | 14903 / 20941 / 26 | 15003 / 21775 / 26 |
| pixel | 23499 / 19316 / 0 | 23499 / 19316 / 0 | 23499 / 19316 / 0 | 23499 / 19316 / 0 | 23499 / 19316 / 0 | 24228 / 17782 / 0 |
| quad | 1910 / 2018 / 0 | 1910 / 2027 / 0 | 1910 / 2027 / 0 | 1910 / 2027 / 0 | 1910 / 2027 / 0 | 1950 / 2176 / 0 |
| raster | 28966 / 22870 / 3 | 28966 / 22870 / 3 | 22910 / 19890 / 3 | 22910 / 19890 / 3 | 22910 / 19890 / 3 | 22913 / 19940 / 3 |
| read_dma | 1897 / 3461 / 0 | 1897 / 3461 / 0 | 1897 / 3461 / 0 | 1897 / 3461 / 0 | 1897 / 3461 / 0 | 2091 / 4592 / 0 |
| regs | 1895 / 2435 / 0 | 1895 / 2435 / 0 | 1895 / 2435 / 0 | 1895 / 2435 / 0 | 1895 / 2435 / 0 | 1940 / 2115 / 0 |
| resolve | 2843 / 4161 / 3 | 2843 / 4161 / 3 | 2843 / 4161 / 3 | 2843 / 4161 / 3 | 3283 / 4359 / 3 | 3373 / 4118 / 3 |
| setup | 42944 / 44943 / 3 | 42944 / 44943 / 3 | 42944 / 44943 / 3 | 64640 / 44916 / 1 | 68368 / 48843 / 1 | 68370 / 49378 / 1 |
| target | 7311 / 4896 / 129 | 7311 / 4896 / 129 | 7311 / 4896 / 129 | 7311 / 4896 / 129 | 7311 / 4896 / 129 | 7311 / 4872 / 129 |
| texture | 25347 / 34398 / 2 | 25347 / 34398 / 2 | 25347 / 34398 / 2 | 25347 / 34398 / 2 | 25347 / 34398 / 2 | 56740 / 49393 / 2 |
| texture_ram | 1027 / 799 / 48 | 1027 / 799 / 48 | 1027 / 799 / 48 | 1027 / 799 / 48 | 1027 / 799 / 48 | 1027 / 799 / 48 |
| unpack | 2553 / 2028 / 0 | 2553 / 2028 / 0 | 2553 / 2028 / 0 | 2553 / 2028 / 0 | 2553 / 2028 / 0 | 2511 / 1932 / 0 |
| write_dma | 2261 / 3412 / 0 | 2261 / 3412 / 0 | 2261 / 3412 / 0 | 2261 / 3412 / 0 | 2261 / 3412 / 0 | 2305 / 3481 / 0 |
| top | 43 / 1898 / 0 | 43 / 892 / 0 | 43 / 892 / 0 | 43 / 892 / 0 | 43 / 892 / 0 | 43 / 892 / 0 |
| 合计 | 201295 / 268760 / 245 | 201293 / 267313 / 241 | 182735 / 244656 / 228 | 227927 / 248294 / 226 | 233176 / 256901 / 226 | 265972 / 267048 / 226 |

RAM物理配置沿用已有IP。perspective输出逻辑队列由128组缩为32组，outstanding由128个4 lane输入降为64个2 lane输入；结果记录849→657位，只存每两像素共用的LOD span，出队复制恢复4 lane字段。结果RAM由12→10个72位bank，延迟与结果RAM共39→35→24个；recip_p18 ROM由4→4→2个。raster延迟RAM仍3个，64×256的read_pool由8→4个，扫描credit仍16，避免半行重组产生气泡。setup_plane的两块长延迟元数据RAM删除，短字段改为与消费位置一致的寄存器链。

| 模块间通道 | d5d44d9cb前 | 第1步后 | 第2步及最终 |
|---|---:|---:|---:|
| raster→perspective平面 | 1736 | 1736 | 868 |
| quad→共享fragment平面 | 1736（常量/旁路字段） | 删除 | 删除 |
| fragment覆盖 / quad标记 | 4 / 1 | 4 / 删除 | 2 / 删除 |
| triangle fragment完整记录 | 1855 | 1854 | 984 |
| perspective算术U/V、颜色、深度 | 128/128、96、64 | 相同 | 64/64、48、32 |
| 重组后→texture sample完整记录 | 849 | 849 | 849 |
| texture→pixel / pixel→target | 4 lane / 4 lane | 相同 | 相同 |

### 切拍清单

拍数均为相关运算从已寄存操作数到结果可消费的延迟；分段加减每拍最多35个有效数位及1个进位位，不改变中间值的完整精度。变量移位按两位选择量分成4选1，每组一拍；乘法先寄存操作数，再保留完整乘积三级寄存。APM/DRM边界均保留输入、输出寄存；setup属性RAM输出先单独寄存，再做属性选择，消除第7轮DRM读出直达APM的长路径。

| 模块 / 原S-3记录中的运算 | 原拍数→新拍数 |
|---|---|
| transform：50位matrix_sum，两个并行乘积对之和再合并 | 单拍宽和→2+2；整个顶点6→19 |
| transform：42位lighting除255 / 截断 | 单拍长除法→定界整数恒等式及寄存；包含在19拍内 |
| clip：43位接收距离 / 边距离，44位denominator | 1→2 / 1→输入1+加减2；1→2 |
| clip：84位numerator及绝对值 | 乘积3、分段差3、绝对值4；原各1拍 |
| clip：45位恢复除法比较/减法 | 每商位1→3（两段进位、选择/提交） |
| clip：85位舍入 / 40位恢复符号 | 保留可观察低40位，舍入2、符号恢复3；S_ROUND等待8拍 |
| project_recip：40位normalize | 1→并行前导编码3、选择量1、分组移位3、选择1 |
| project_recip：62/63位舍入乘积 | 1→乘积3后取高位与guard，再用32/31位加法各1；整单元10→20 |
| project：40位恢复倒数 | 1→偏移/舍入量寄存、40位加法2、分组移位3、选择1 |
| project：94位viewport调整与乘法 | 单拍调整→加减3；乘法3；常量左移1 |
| project：94位绝对值、95位舍入/符号/offset | 1→绝对值4；舍入等价49位2、符号3、offset2，精度不变 |
| project：94位深度舍入 | 1→取高49位和guard后加法2；总后处理4→36 |
| setup_plane：51位maximum/h前导编码 | 单拍串行→两轮比较/选择各2，前导编码3、h1 |
| setup_plane：52位scale/舍入 | 单拍变量移位→每组选择2位、各3拍；舍入加法2 |
| setup_plane：56位numerator | 1→2（两段进位） |
| setup_plane：87位绝对值、88位舍入/56位符号 | 各1→4、3、3；88位移位按7位量分4拍 |
| setup_plane：75位origin_sum及舍入 | 各1→3；绝对值/符号各4 |
| setup_plane：70位start | 1→2（两段进位） |
| setup_plane：G丢位56位绝对值/52位舍入 | 各1→3/2，丢位4位量分2拍、符号3 |
| setup_plane：S丢位70位绝对值/66位舍入 | 各1→3/2，丢位分2拍、符号3；整单元15→74 |
| setup：面积 / 三条edge，属性RAM→APM | 宽减单拍→乘法输入1、乘积3、37位差2；属性读出后增加1拍 |
| geometry：扇形剔除 | 单拍差/乘积/面积→差1、乘积3、比较/keep1，双屏幕bank保持II=6 |
| texture：LOD后地址、bank分配、系数/颜色乘积 | 地址6拍；分配2拍；权重/颜色/alpha乘法输入及结果寄存；NN/双线性/三线性II不变 |
| read_dma / write_dma：轮转选择、边界和更新 | 一拍串行链→选择、请求字段、burst建立3阶段；AR/AW握手后使用预计算地址与剩余量 |
| command：SET_TEX mip容量检查 | 每mip1→5（块尺寸、字节量、累计、基址、比较/提交） |
| pixel：32项前驱搜索、旧值读出→stencil | 组合扫描→4拍接收侧依赖搜索、奇偶预取；旧值及各lane负载增加1拍，15→16；稳态II=1组 |
| resolve：输出地址 / pack选择 | 行乘积、基址、x偏移各1拍；变量宽切片改为4个常量切片；请求增加3拍 |
| regs / unpack / quad / target | APB读预译码与平衡OR；palette末字预计算；quad边界提前预测；target写回/完成条件化简，无数据格式变化 |

| 模块 | 最长参考级数 | 超6级路径说明 |
|---|---:|---|
| command | 8 | 状态/错误与取命令控制优先链 |
| geometry | 7 | polygon完成与fan控制 |
| list_pack | 6 | — |
| object | 6 | — |
| palette | 4 | — |
| perspective | 7 | N最高有效块编码→窗口选择 |
| pixel | 9 | 返回握手→dispatch→old_valid位图写译码 |
| quad | 7 | 组边界/最后一组预测控制 |
| raster | 8 | credit/换行→plane load使能 |
| read_dma | 6 | — |
| regs | 6 | — |
| resolve | 7 | 行填充/发送完成状态控制 |
| setup | 6 | — |
| target | 8 | 空闲/clear接受→clear坐标更新控制 |
| texture | 9 | retire索引→completed位图选择→shaded_valid/retire握手 |
| texture_ram | 3 | — |
| unpack | 6 | — |
| write_dma | 7 | burst准备/接受与槽更新控制 |

全部模块未发现未寄存输入/输出的乘法，亦无超过36位的加减、比较或取负算术单元。pixel与texture的9级控制路径已分别确认保留，其余7～9级控制/选择路径同样记录交PDS；本次不再增加控制流水。

参考最长级数按协调者确认的方法计量：先保存粗网表，已寄存输入/输出的乘法按APM边界计0；≤36位加减、比较、取负及常数两项shift-add按一段进位计1，纯常数移位计0，其余逻辑映射LUT6。资源和深度使用Yosys 0.70+219（5053d0e26）；复制前整GPU网表使用仿真环境已有Yosys 0.67+94。时序参考映射采用协调者确认的`balance; rewrite; refactor; balance; if -K 6`。剩余7～9级控制/选择路径按协调者收尾决定交第8轮PDS核验，不声称已经满足所有模块≤6或180MHz时序。

### 高扇出

复制前取第3步早期修订9d090a955的Yosys GPU扁平网表（随后功能修正合入dabf447ff）；该次整GPU分析在空闲内存满足要求时执行，其后按各模块独立网表及顶层端口绑定统计，不再综合整GPU。下表计DFF使能/复位实际位负载、mux选择位负载及IP输入引脚，不计时钟与常量。现有reset_copy的PDS preserve注释在Yosys分析脚本中等效为keep，RTL/common不改，不增加复位周期；新增区域寄存器同时用keep与`syn_preserve=1`。

| 控制网（层次） | 复制前扇出 | 最终原主干 / 最大局部副本扇出 |
|---|---:|---:|
| u_setup.enable_w | 25794 | 848 / 1317（plane使能1197，area使能1317） |
| u_geometry.u_project.enable_w | 16688 | 1640 / 1175，16个数据区域 |
| u_geometry.u_transform.enable_w | 6514 | 23 / 1166，6个数据区域 |
| quad_rst_n_w（Yosys误合并18区域） | 3626 | quad 21 / 18区域最大1168 |
| u_object.advance_w | 3399 | 538 / 711，15个字段区域 |
| u_resolve.advance_w | 2217 | 57 / 696，4个AA通道 |
| u_geometry.u_clip.bank_r | 2154 | 原网消除 / 410，9个字段区域 |
| u_geometry.u_clip.state_r | 2134 | 原网消除 / 343，9个字段区域 |
| u_geometry.u_clip.push_w | 2122 | 330 / 330，9个字段区域 |
| u_geometry.u_clip.vertex_index_r（补全选择器后） | 2114 | 2 / 323，9个字段索引副本 |
| u_geometry.u_clip.last_index_w（补全选择器后） | 2112 | 原网消除 / 320，9个字段计数副本 |

最终所有控制网≤2000；全GPU最大为`u_setup.push_w` **1759**。setup的27个plane区域、project的16区域和transform的6区域各自保留输出credit计数与本地enable；object按字段复制待发标志，resolve按AA通道复制输出计数，clip按9个字段复制状态、bank、顶点索引及输入顶点数。后两条2114/2112是补全选择器后的新增审计发现，已在04170a381消除。

### 回归与GT-25

最终04170a381：18项GPU unit全部通过，GT-01～GT-25全部通过，逐位DDR、寄存器和组序比较沿用现有模型。GT-18/19的生成器需dict union，使用环境中已有Python 3.9重跑通过；不改参考模型或期望值。风格36文件0告警，GPU顶层lint 0告警。texture单元13248组通过，各格式连续512组的最近邻/双线性/三线性严格为4/2/1像素/周期，预装261周期；三角形raster/perspective的2 lane与重组组序由现有单元比分模型验证。GT-25四边形净工作量平均64.757812周期/16×16对象，满足≤80；AA RESOLVE共80048周期（0.444711ms），低于90000。下表含APB观察开销，默认DDR、180MHz，列全所有命令。

| 场景 | 0018e27f2逐命令周期 | 04170a381逐命令周期 |
|---|---|---|
| quad | 28, 28840, 22, 88, 22, 46, 22, 415, 85, 22, 25, 43, 16633, 39415 | 28, 28840, 22, 88, 31, 55, 28, 412, 82, 31, 25, 40, 16618, 40009 |
| nearest | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 22, 49, 4396, 39502 | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 28, 43, 8656, 39937 |
| bilinear | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 43, 36577, 39628 | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 49, 58060, 40096 |
| trilinear | 28, 28840, 22, 88, 22, 46, 22, 268, 28, 43, 62209, 39475 | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 49, 75517, 39901 |
| palette_i4 | 28, 28840, 22, 88, 22, 46, 22, 415, 85, 22, 307, 36844, 39466 | 28, 28840, 22, 88, 31, 55, 28, 412, 82, 31, 307, 58321, 40081 |
| palette_i8 | 28, 28840, 22, 88, 22, 46, 22, 415, 133, 22, 301, 36838, 39430 | 28, 28840, 22, 88, 31, 55, 28, 412, 133, 31, 307, 58327, 40195 |
| vertex | 28, 28840, 22, 88, 22, 46, 22, 22, 25, 43, 3001, 39430 | 28, 28840, 22, 88, 31, 55, 28, 25, 28, 43, 3034, 40003 |
| setup | 28, 28840, 22, 88, 22, 46, 22, 22, 25, 43, 281581, 39364 | 28, 28840, 22, 88, 31, 55, 28, 25, 28, 43, 543871, 40165 |
| objects | 19, 28837, 25, 85, 22, 46, 25, 40, 66607, 39454 | 25, 28840, 25, 82, 31, 55, 28, 46, 74695, 40297 |
| resolve | 28, 28840, 22, 88, 22, 46, 22, 22, 28837, 39535, 22, 28834, 39496 | 28, 28840, 22, 88, 31, 55, 28, 25, 28840, 40015, 22, 28837, 40033 |

复现：GPU unit逐目录执行`python3 tools/regress.py full --path verif/unit/gpu_<模块> -j 1`；GT逐目录执行`python3 tools/regress.py full --path verif/block/gpu/gtNN -j 1`。风格`python3 tools/check/verilog_style.py rtl/gpu`；顶层lint在`rtl/filelists/`执行`sh ../../tools/check/lint.sh -DSIM_MODE -f gpu.f --top-module edrv32_gpu`。Yosys逐模块读取`gpu.f`并将`edrv32_ram_gpu_*`/`edrv32_rom_gpu_*`设为blackbox，`synth -top edrv32_gpu_<模块> -noabc`后映射LUT6，递归统计DFF/LUT6与DRM包装实例；粗网表使用`-noalumacc -flatten -run begin:fine`保留算术以追踪参考深度。原始统计、网表及日志存`build/s4/`，仿真摘要和GT25结果复制到同目录。所有RTL仿真均在指定仿真环境执行，结束后清理本任务的进程与目录。

## S-5：宽乘法的 APM 部分积流水

### 背景、约束与决策

基线为 `cefbd28fa`（卡107第8轮输入 `38095a121` 的GPU RTL相同）。第8轮
`artifacts/round8/synthesis-clk_gpu-setup.txt` 的三条最差路径均属于 project 的
`N788_m1→m4`：CPO/CPI级联之间夹有LUT6CARRY，11级、WNS −3.145ns，综合估算
114.9MHz。第8轮报告只有三条综合setup明细，无法据此把每个RTL乘法一一对应到
PDS内部编号；以下区分原RTL操作数/乘积寄存和已经观测到的PDS级联，不虚构其他
乘法的原生拆块数。

保持gpu-spec v0.5、微结构4.13/4.14、舍入位置、完整有效位、输出顺序和吞吐。
采用基数2^17分块：非最高块补零后为s18，最高块按原操作数符号扩展；每个部分积
独立寄存，再由平衡加法树相加。加法每拍最多35个有效位加一个进位位，上段操作数
仅传到实际消费拍，低段只保留结果。原方案把整个宽乘法交给PDS拆分、随后延迟完整
乘积两拍；两拍延迟不能隔开PDS自动生成的级联路径。本次让寄存器落在部分积和
求和级之间，仍需下一轮PDS确认物理映射、频率和器件资源。

协调者补充要求同时收缩数据寄存：稳定的draw配置保留局部上下文；逐项常数按标签
保存，延迟至少8拍且宽度至少36位的纯延迟使用既有delay RAM包装。不新增IP类型，
不改变texture、pixel、target接口或SoC端口。所有数据寄存均不复位，只有控制状态
复位/stop清除；加深流水同时调整valid、标签和负载的相位。

### 宽乘法清单

`s/u`分别表示有符号/无符号，位宽为原RTL实际操作数；括号内另列已知恒零位。
原流水拍数从已寄存操作数开始计，原乘法均为“乘积1拍＋完整乘积延迟2拍”。
project_recip同时被project和setup各实例化一次，下面先按单模块列出，实例统计再
递归计入父模块。乘法的旧阶段用原寄存器名称定位，避免将不同模块的局部拍号混用。

| 模块与旧乘积阶段 | 原宽度、份数 | 原拆块方式 |
|---|---|---|
| transform `matrix_product{0,1}_{0,1,2}` | s32×s16，6份，输入寄存后第1～3拍 | PDS自动拆分，模块共24 APM（含其余乘法） |
| transform `illumination_product{0,1,2}` | u24×u8，3份 | 同上 |
| transform `color_product{0,1,2}` | u33×u8，3份 | 同上 |
| clip `previous_product/current_product` | s40×s43，2份，交点分量乘积第1～3拍 | PDS自动拆分，模块共10 APM |
| project `position_product{0,1,2}` | s40×s36（第二输入为u35补零），3份 | 自动拆分，project不含倒数共24 APM；最差N788为4块级联 |
| project `uv_product{0,1}` | u16×u35，2份 | 自动拆分 |
| project `viewport_product{0,1}` | s94×s17（第二输入为u16补零），2份；乘积保留低94位 | 自动拆分 |
| project_recip `newton_product` | u31×u30，1份 | 自动拆分，两个牛顿乘法共8 APM |
| project_recip `newton_result` | u30×u32，1份；目标62位 | 同上 |
| setup_plane `product{0,1}_{0,1}` | s34×s18，4份；原局部第21～23拍 | 自动拆分，plane全部乘法共26 APM |
| setup_plane `inverse{0,1}` | s56×s32（第二输入为u31补零），2份；分子低4位为零 | 自动拆分 |
| setup_plane `origin_product{0,1}` | s56×s18，2份 | 自动拆分 |

setup前端两份s18×s18、geometry扇形两份s18×s18均保留。texture中配置尺寸最大
u9×u9、权重u9×u9、过滤u8×u17、LOD u8×u9、调制u8×u8；pixel_lane为
u8×u8；resolve为u16×u11，都未超过单块宽度。texture的常量乘256是固定移位。
perspective八份u18×u18虽需注意符号模式，但第8轮层次表恰为8 APM；协调者据此
确认每份已经只用1 APM，保留已寄存输入/输出的原实现。其余GPU RTL未找到需要
拆分的运行时乘法。

### 高扇出区域复制

geometry原`polygon_accept_w`的2,129负载主要来自8顶点×264位保存寄存。
按九个字段分别复制sending状态和counts占用计数，用本字段状态译码accept；
每个字段只驱动自身8顶点数据，控制仍由原握手推进，增加54位控制FF且不增加周期。
主干accept只保留控制和计数写入负载。

集成末发现新增project部分积树共用旧使能区域，两个区域的FF使能负载分别达到
2560和2073。经协调者确认，position_product1和position_product2各自改用独立
credit副本，区域数9→11，新增四位控制FF；该修改无数据或valid相位变化。最终通用映射的11个区域输入引脚负载分别为
899/1280/793/1580/266/1748/692/636/299/1280/1280，最大1748。geometry
资源在此修改后重测，其余模块采用本轮相同RTL已完成的测量。

palette原`rd_en_r`的2,592负载对应八份当前调色板读使能被合并。
经协调者授权扩展归属到`rtl/tech/edrv32_ram_gpu_palette_current.v`，每个page
各保存一份读使能，驱动本page的20位输出寄存；page选择另有原相位的使能寄存。
FPGA/行为模型共用这段流水，IP配置、端口、ifdef结构及四拍读语义不变。
所有区域副本带`(* keep = "true", syn_preserve = 1 *)`；实际PDS扇出仍待下一轮核验。

### 统计口径与复现

FF/LUT6使用同一Yosys 0.67+94（7defa5186）通用映射。分别对geometry、setup、
texture、pixel、palette、perspective、resolve读取`gpu.f`列出的文件，定义
`SIM_MODE`并加入`rtl/include`；将`edrv32_ram_gpu_*`、`edrv32_rom_gpu_*`设为
blackbox，然后执行：

```text
synth -top edrv32_gpu_<模块> -noabc -noalumacc -run begin:fine
write_json <粗网表>
synth -top edrv32_gpu_<模块> -noabc -run fine:check
abc -lut 6 -script <包含 strash 和 if -K 6 两行的ABC脚本>
write_json <映射网表>
```

FF递归计映射网表所有DFF单元位数，LUT6计`$lut`个数，乘法实例计粗网表的`$mul`；
共享子模块递归计入父模块。此处乘法实例数不是PDS APM数；宽乘法拆成多个小乘法后，
该列自然增加。RAM/ROM包装blackbox的内部FF和LUT不计入，外围寄存保留；因此palette
页内使能复制不反映在palette一行。与S-4资源表使用的算术映射流程不同，不直接比较
两节的LUT绝对值；本节前后严格采用相同命令。基线RTL由`git archive cefbd28fa rtl`
提取；最终RTL取本节列出的提交。原始统计、综合日志及回归日志放在`build/s5/`。

### 新的部分积与延迟

| 乘法 | 每份新部分积数 | 原3拍→新拍数 |
|---|---:|---:|
| transform matrix / illumination / color | 各2 | 3→3 |
| clip previous / current | 各9 | 3→最多13 |
| project position | 各9 | 3→11 |
| project uv | 各3 | 3→5 |
| project viewport | 各6 | 3→9 |
| project_recip 两个Newton乘法 | 各4 | 3→5 |
| setup_plane difference×delta | 各2 | 3→3 |
| setup_plane numerator×reciprocal | 各8 | 3→10 |
| setup_plane gradient×offset | 各4 | 3→7 |

transform完整流水仍为19拍、顶点II=2；clip未裁剪旁路仍为3拍，一个交点的9个
分量合计增加90拍。clip在已有S_MULTIPLY等待期间保持操作数稳定，所有新部分积和
加法均有真实寄存，不使用多周期路径例外。project_recip为20→24拍，project含
倒数和FIFO写入为57→75拍。setup_plane为74→85拍，setup接收到output-valid为
109→124个使能边沿间隔，含面积倒数多出的4拍；三角形II仍为8。停顿期间各局部
credit副本、RAM地址与负载保持同一个使能周期计数。

transform把RGB565和UV分别存在16项标签表，共768位数据，只传4位顶点标签；
稳定的draw光照配置仅保留48位局部值。四路坐标的8拍纯延迟合并成三个72位delay
bank。project视口快照按使能周期标签存入64项既有read_pool，长坐标/颜色延迟增加四块delay，
视口与结果对齐共增加七个read_pool。setup_plane的倒数31位、指数6位、delta72位、
offset36位共145位常数每三角形只存一次，16项表按原四位三角形标签读出；新增十块
delay。setup的原始属性值只活跃到面积倒数返回和七属性读出，最长小于64个使能周期，
因此16项缩为8项；按序返回的每属性起点/梯度/h只保留一项组装寄存，出口仍保留两项。

完整GPU层次统计：delay包装实例34→51，新增17块；DRM/ROM包装实例总数226→243，
与S-4相同口径，排除read_pool、write_pool和palette_current分布式RAM。
read_pool为5→12，其余DRM/ROM包装数不变。第8轮PDS的GPU层次值为269.5 DRM，
整片为332/415；按既有512×72 delay IP每实例占1 DRM估算，新增17块后分别为
286.5和349/415（约84.1%）。这些估算只计显式delay增量，不含推断存储重映射，最终物理占用须由PDS确认，
不能把243个包装实例等同为243个器件DRM。

实现提交：`a43b6de00`（区域复制）、`aa61a0d08`（transform/clip分块）、
`3283aa900`（transform/clip存储收缩）、`477cf77d8`（setup/plane）、
`a1a6225ff`（project/reciprocal）、`587fb7f2d`（geometry单元文件列表连接
read_pool依赖）、`d6aabe62f`（新增部分积树的使能区域复制）。最终RTL版本为`d6aabe62f`；其后的本节记录不改变RTL。
GPU风格检查37文件0告警，完整顶层lint 0告警；命令与S-4相同，另包含授权修改的
palette_current包装。geometry首次编译缺少read_pool源文件，补全文件列表后重跑通过；
没有修改测试激励、参考模型或数值期望。

最终粗网表中geometry递归100个乘法、setup递归42个乘法，所有乘法的两个输入
宽度都不超过18位（检查`$mul`的A_WIDTH/B_WIDTH，含符号位）；原先的宽乘法已消失。
该结构检查不把LUT乘法或APM数当作物理映射结果。

### 同口径资源结果

各格按 **FF / LUT6 / 乘法实例** 列出；父模块包含子模块，父子行不能再次相加。

| 模块 | cefbd28fa | d6aabe62f |
|---|---:|---:|
| geometry | 46792 / 62495 / 28 | 43130 / 66392 / 100 |
| transform | 6617 / 11782 / 15 | 4980 / 12870 / 27 |
| clip | 12770 / 19466 / 2 | 13711 / 19874 / 18 |
| project | 16360 / 23208 / 9 | 13340 / 25500 / 53 |
| project_recip | 1163 / 4272 / 2 | 1734 / 4602 / 8 |
| setup | 68370 / 43514 / 12 | 38623 / 38868 / 42 |
| setup_plane | 26937 / 22866 / 8 | 19643 / 25222 / 32 |
| texture | 56744 / 38874 / 73 | 56744 / 38860 / 73 |
| pixel | 24228 / 14512 / 24 | 24228 / 14512 / 24 |
| pixel_lane | 1444 / 1302 / 6 | 1444 / 1302 / 6 |
| palette | 197 / 138 / 0 | 197 / 138 / 0 |
| perspective | 15003 / 20487 / 8 | 15003 / 20487 / 8 |
| perspective_multiply | 141 / 674 / 1 | 141 / 674 / 1 |
| resolve | 3373 / 3897 / 1 | 3373 / 3897 / 1 |

geometry/setup合计FF 115162→81753，减少33409（约29.0%）；LUT6 106009→105260，
减少749。clip和reciprocal的部分积树增加了局部寄存，其余延迟/上下文收缩抵消了增加。
texture RTL未改，FF/乘法实例相同，通用映射LUT仍有14个差异；如实列出，不将其
解释为纹理逻辑变化。上述数字均为通用综合对比，不替代PDS器件资源。

### GT-25逐命令周期

180MHz、默认DDR延迟，含APB观察开销；每格按命令1…N列全。基线取cefbd28fa
中已记录的S-4最终实测；本次使用相同场景和模型。

| 场景 | cefbd28fa | d6aabe62f |
|---|---|---|
| quad | 28, 28840, 22, 88, 31, 55, 28, 412, 82, 31, 25, 40, 16618, 40009 | 28, 28840, 22, 88, 31, 55, 28, 412, 82, 31, 25, 40, 16618, 40009 |
| nearest | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 28, 43, 8656, 39937 | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 28, 43, 8689, 39904 |
| bilinear | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 49, 58060, 40096 | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 49, 58093, 40063 |
| trilinear | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 49, 75517, 39901 | 28, 28840, 22, 88, 31, 55, 28, 265, 49, 49, 75550, 39868 |
| palette_i4 | 28, 28840, 22, 88, 31, 55, 28, 412, 82, 31, 307, 58321, 40081 | 28, 28840, 22, 88, 31, 55, 28, 412, 82, 31, 307, 58354, 40048 |
| palette_i8 | 28, 28840, 22, 88, 31, 55, 28, 412, 133, 31, 307, 58327, 40195 | 28, 28840, 22, 88, 31, 55, 28, 412, 133, 31, 307, 58360, 40162 |
| vertex | 28, 28840, 22, 88, 31, 55, 28, 25, 28, 43, 3034, 40003 | 28, 28840, 22, 88, 31, 55, 28, 25, 28, 43, 3052, 39985 |
| setup | 28, 28840, 22, 88, 31, 55, 28, 25, 28, 43, 543871, 40165 | 28, 28840, 22, 88, 31, 55, 28, 25, 28, 43, 543904, 40132 |
| objects | 25, 28840, 25, 82, 31, 55, 28, 46, 74695, 40297 | 25, 28840, 25, 82, 31, 55, 28, 46, 74695, 40297 |
| resolve | 28, 28840, 22, 88, 31, 55, 28, 25, 28840, 40015, 22, 28837, 40033 | 28, 28840, 22, 88, 31, 55, 28, 25, 28840, 40015, 22, 28837, 40033 |

AA RESOLVE仍为80048周期（0.444711ms），低于90000周期上限。四边形净周期/对象
保持基线；三角形命令差来自新增算术流水的建立/排空，稳态顶点II=2和三角形II=8
由geometry/setup单元的原有吞吐检查验证，texture/pixel流水未改。

### 回归与状态

首轮18个GPU单元测试、GT-01～GT-25全部通过，DDR/寄存器/输出组序继续由
原模型逐位比较。geometry文件列表修复后单独重跑通过。最后的使能区域复制仅改变
project，按协调者确认重跑geometry和GT全套，其余17个单元RTL未变，沿用本轮通过
结果；无RTL仿真失败。GT-12覆盖57子场景，GT-13的16组宽度/翻转/边界场景全部通过。
texture仍通过13248组及最近邻/双线性/三线性稳态吞吐检查；geometry和setup的原有
II检查通过。GT-25四边形净周期为64.757812/对象，AA RESOLVE为80048周期；相比
cefbd28fa，三角形DRAW多33周期、vertex场景多18周期，其后RESOLVE分别少33/18周期，
其他逐命令周期见上表。

复现：GPU单元逐目录执行`python3 tools/regress.py full --path verif/unit/gpu_<模块> -j 1`；
GT使用`verif/block/gpu/run.py`的原generate/compare流程，按RTL版本编译完整GPU bench后，
用相同binary逐GT运行全部子场景，GT-25再执行原`performance.measure`统计和判定。
最后一轮GT复用同一组已生成的激励和期望，逐场景全部重新仿真和比较。
GT-18/19模型使用已有Python 3.9；未安装工具，未改变模型或期望值。原始摘要在
`build/s5/regression/`和最终`build/s5/recheck/`，GT-25逐命令统计在`build/s5/gt25-performance-final.txt`，资源在
`build/s5/{baseline,final}-counts.json`及对应综合日志。全部仿真及本节同口径资源测量在指定仿真环境执行，
本机未运行RTL仿真；仿真目录在结果归档后已清理。

状态：S-5 RTL和本卡仿真验收完成；原N788类宽乘法已被寄存的原生宽度部分积替代。
物理APM使用、区域副本保留、实际扇出和clk_gpu时序交下一轮PDS确认，本节不声称
已经达到150/180MHz。


## S-6：GPU 片上存储归类（2026-11-26）

### 背景、约束与决策

第8轮层次表基线为 `origin/win/20261124-107-gpu-board` 的
`tasks/win/20261124-107-gpu-board/artifacts/round8/resource_hier.txt`：
GPU 269.5 DRM，整片332 DRM；S-5新增17个delay实例后估算分别286.5、349。
本节只改变小存储的物理归类，不改变规格、接口、算术、使能、停顿或有效位时序。

协调者在 `6e91f70f2` 更新微结构4.15并替换包装：使用既有
`edrv32_ram_gpu_table`（64×72，同步写、组合读）；原 `delay64` 名称不再使用。
单读口同步表在原读位置保留输出寄存器，组合读保持组合读；多读口复制表、并联写口。
深度≤4或总位数<256的结构保留寄存器。比较器并行读取的地址记分牌、并行组包、
多写/复位控制状态和带中途修改/多抽头的运算流水仍是原寄存器电路，不作为RAM重推断。
没有新增IP，没有数据复位或额外保护。

### 显式delay清点

下表“深度”是有效时钟距离，包含原RAM末级寄存读，不是原IP的512项物理容量；
原类型全部为512×72 DRM。每个列出的旧实例均已移除，未留下深度>64的delay。
`d72`、`d84`是所在流水级编号，实际存储距离只有53、24拍，不能按名字判断容量。
同深度字段在能减少片数时合并；每片最多72位，不整体搬运超过256位记录。
project的8拍三片（152位）和setup_plane的24拍两片（104位）已经达到
ceil(总宽/72)的最少片数，保持原字段分片；34拍双88位则由4片合并成3片。

| 模块 | 旧实例（范围列出全部后缀） | 深度×有效宽度 / 用途 | 改后 |
|---|---|---|---|
| project | `u_input_delay_0,1,2,3` | 24×224，倒数对齐的顶点负载 | 4 table+原输出寄存 |
| project | `u_payload_delay0` | 49×72，颜色对齐 | 1 table+原输出寄存 |
| project | `u_payload_delay1,2,3` | 8×(72+40+40)，坐标/UV | 3 table+原输出寄存 |
| transform | `g_coordinate_ram[0,1,2].u_delay` | 8×160，四坐标 | 3 table+原输出寄存 |
| object | `u_index` | 12×24，对象索引 | 1 table+原输出寄存 |
| raster | `u_metadata_9_0` | 5×5，边包含/裁剪位 | 25位移位寄存器 |
| raster | `u_metadata_10_0,1` | 6×106，坐标/h/palette | 2 table+原输出寄存 |
| perspective | `u_output_0,1,2,3,4,5,6,7,8,9` | 32×657，样本输出队列 | 10 table+原输出寄存 |
| perspective | `u_delay_sign_0` | 4×4，符号 | 16位使能移位寄存器 |
| perspective | `u_delay_q_0` | 12×24，q | 1 table+原输出寄存 |
| perspective | `u_delay_uvq_0,1` | 14×116，uq/vq | 2 table+原输出寄存 |
| perspective | `u_delay_coordinate_0,1` | 13×128，坐标 | 2 table+原输出寄存 |
| perspective | `u_delay_shade_0,1` | 41×80，着色输入 | 2 table+原输出寄存 |
| perspective | `u_delay_metadata_0` | 43×49，样本元数据 | 1 table+原输出寄存 |
| perspective | `u_delay_scale_0` | 3×60，缩放因子 | 180位使能移位寄存器 |
| perspective | `u_delay_bypass_0,1,2,3` | 10×232，旁路负载 | 4 table+原输出寄存 |
| setup_plane | `u_v52_0_w_d9_r_bank0, u_v52_1_w_d9_r_bank0, u_v52_2_w_d9_r_bank0` | 9×156，三顶点 | 合并3 table+原输出寄存 |
| setup_plane | `u_gradient_bias0_3_r_d40_r_bank0,1; u_gradient_bias1_3_r_d40_r_bank0,1` | 34×176，两个梯度偏置 | 合并3 table+原输出寄存（原4片） |
| setup_plane | `u_start_base_w_d72_r_bank0` | 53×70，平面起点基值 | 1 table+原输出寄存 |
| setup_plane | `u_stored_signed1_w_d84_r_bank0, u_stored_signed0_w_d84_r_bank0` | 24×(52+52)，两梯度 | 2 table+原输出寄存 |
| texture | `g_delay[0,1].u_metadata` | 6×144，过滤权重/分数（外部另有原流水） | 2 table+原输出寄存 |

合计51个旧delay→47个table和3组短寄存器；少1片来自两个88位梯度偏置的共同分片。
原RAM指针由9位收为6位，地址差、使能和所有末级寄存器保持相同，回绕不改变有效数据。

### 小数组重映射

| 模块 | 旧数组 / 深度×宽度 | 改前→改后 / 用途 |
|---|---|---|
| setup | 七属性 `value_r`：8×153，含常零位 | 推断存储→12 table；按16/35/51/51/24/24/24位顶点字段存储并补回51位，保留原同步读 |
| setup | `delta_r, offset_r`：16×(72+36) | 推断存储→2 table，共用属性标签读口 |
| setup | `origin_r, bounds_r`：16×(32+64) | 推断存储→2 table，共用完成标签读口 |
| setup | 三边 `value_r`：16×40；`dx_r,dy_r,bias_r`：16×(40+40+40) | 推断存储→每边1+2 table，保留原输出槽寄存器 |
| setup_plane | `reciprocal_context_r`：16×31；`delta_context0..3_r, offset_context0..1_r`：16×18 | 推断存储→7 table，各保留原同步读；`exponent_context_r`仅96位，保留寄存器 |
| transform | `vertex_color_r,vertex_uv_r`：16×16/32 | 推断存储→各1 table，分别按原标签组合读 |
| geometry | 七字段 `screen_r`：16×17/17/16/35/51/51/72 | 推断三读口存储→每字段3 table（共21），扇形顶点三读口写口并联 |
| pixel | `depth_r,color_r,alpha_r`：32×(64+96+32) | 推断同步表→3 table；mask仅128位保留寄存器 |
| pixel | `old_r`：32×160；`result_r`：32×160 | 推断表→3 table及双读口6 table，保留旧字同步读与结果组合读 |
| texture | `x_r,y_r,depth_r`：32×(16+16+64) | 推断表→2 table，退队组合读 |
| texture | `color_r,alpha_r`：32×(96+8) | 推断表→2 table，着色组合读 |
| texture | 四lane `u_r,v_r`：32×(32+32)；`lod_r`：32×12 | 推断表→各lane 1 table及双读口2 table；原偶/奇缓存寄存器不变 |
| texture | 四lane `result_color_r,result_alpha_r`：32×(24+8) | 推断表→每lane 1 table；result_mask仅32位保留寄存器 |
| texture | `g_nearest_compare`及44个`g_address_pool_*`的even/odd：各16×22/21/16 | 原推断LUTRAM→90显式table，原缓存读拍不变；不是纹理数据bank |
| write_dma | `strobe_r`：32×32 | 推断表→1 table，保留原同步读 |

setup第8轮的32.5 DRM推断量只能由父模块剩余量核对，层次表没有给数组逐项归属；
因此不伪造单数组DRM分摊。texture的6 DRM、pixel的5.5 DRM和write_dma的0.5 DRM
也按模块剩余量记录。原read_pool/write_pool仍使用既有显式LUTRAM包装。

### DRM与LUT估算

单位为第8轮的36K等效DRM；S-5后的“改前”只在对应模块加入实际新增delay数。
ROM和范围外功能存储全部保留，不能把table实例数当成DRM减少量。

| 模块（父子不重复相加） | 第8轮 | S-5后改前估算 | S-6后估算 | S-6 table实例 |
|---|---:|---:|---:|---:|
| geometry（含transform/project） | 5 | 12 | 1 | 34 |
| setup（含setup_plane/area_reciprocal） | 33.5 | 43.5 | 1 | 41 |
| perspective | 25 | 25 | 1 | 22 |
| raster | 3 | 3 | 0 | 2 |
| texture（不含独立texture_ram） | 8 | 8 | 0 | 112 |
| pixel | 5.5 | 5.5 | 0 | 12 |
| object | 1 | 1 | 0 | 1 |
| write_dma | 0.5 | 0.5 | 0 | 1 |
| target / texture_ram / palette / resolve | 129 / 48 / 8 / 3 | 同第8轮 | 同第8轮 | 0 |
| 其他GPU模块 | 0 | 0 | 0 | 0 |
| GPU合计 | 269.5 | 286.5 | 191 | 225 |
| 整片（GPU外62.5不变） | 332 | 349 | 253.5/415（61.1%） | — |

估算减少95.5 DRM，其中显式delay 51、setup推断32.5、texture推断6、pixel推断5.5、
write_dma推断0.5。物理映射、ROM打包和小表常量裁剪最终由PDS确认。
225个64×72 table的未裁剪容量为1,036,800位；按既有64×256 read_pool的256 LUTRAM/LUT
口径，每table至多72 LUTRAM/LUT，未裁剪上界16,200 LUT。按有效字段宽度相加为8193 LUT（geometry 1433 + setup 2004 + perspective 1286 +
raster 106 + texture 2636 + pixel 672 + object 24 + write_dma 32），
其中texture原偶奇地址表已占原推断LUTRAM，不能全部计为增量；大量常零/无用字段可继续裁剪。
此估算不包含地址译码与输出寄存器，不能声称净增只有微结构早期预估的3～4千LUT。
LUT/FF净变化及分布式RAM占用等待PDS实测，不用通用网表冒充器件映射结果。

### 寄存器数组完整复核

以下从S-6输入版本 `6e91f70f2` 逐声明清点，宽度为Verilog常量表达式，深度为元素数；
重复同名项按声明数合并，generate的复制倍数在上方重映射表中注明。
“原寄存器”包括组合运算的临时数组以及带复位/多写口/并行读取的控制或运算寄存器，
不是新增的RAM推断。target/texture_ram/palette/resolve保持任务边界。

| 模块 | 数组 | 深度 | 宽度 | 改前→改后；用途 |
|---|---|---:|---|---|
| clip | `output_count_r` | 2 | 4 | 原寄存器→原寄存器；裁剪输出槽 |
| clip | `data_r` | 2 | `WIDTH-1:0` (高位:低位) | 原寄存器→原寄存器；裁剪输出槽 |
| geometry | `counts_r` | 16 | 4 | 原寄存器→原寄存器；几何计数/屏幕表/输出槽 |
| geometry | `screen_counts_r` | 2 | 4 | 原寄存器→原寄存器；几何计数/屏幕表/输出槽 |
| geometry | `fan_dx_w` | 2 | 18 | 原寄存器→原寄存器；几何计数/屏幕表/输出槽 |
| geometry | `fan_dy_w` | 2 | 18 | 原寄存器→原寄存器；几何计数/屏幕表/输出槽 |
| geometry | `data_r` | 2 | `WIDTH-1:0` (高位:低位) | 原寄存器→原寄存器；几何计数/屏幕表/输出槽 |
| geometry | `screen_r` | 16 | `WIDTH-1:0` (高位:低位) | 推断数组→显式table；几何计数/屏幕表/输出槽 |
| geometry | `output_r` | 2 | `WIDTH*3-1:0` (高位:低位) | 原寄存器→原寄存器；几何计数/屏幕表/输出槽 |
| list_pack | `hit_pack_r` | 8 | 32 | 原寄存器→原寄存器；并行列表组包/事件槽 |
| list_pack | `free_pack_r` | 8 | 32 | 原寄存器→原寄存器；并行列表组包/事件槽 |
| list_pack | `event_idx_r` | 2 | 24 | 原寄存器→原寄存器；并行列表组包/事件槽 |
| list_pack | `event_hit_r` | 2 | 8 | 原寄存器→原寄存器；并行列表组包/事件槽 |
| list_pack | `event_free_r` | 2 | 1 | 原寄存器→原寄存器；并行列表组包/事件槽 |
| list_pack | `data_r` | 2 | 256 | 原寄存器→原寄存器；并行列表组包/事件槽 |
| list_pack | `addr_r` | 2 | 32 | 原寄存器→原寄存器；并行列表组包/事件槽 |
| list_pack | `bytes_r` | 2 | 6 | 原寄存器→原寄存器；并行列表组包/事件槽 |
| object | `ingress_idx_r` | 2 | 24 | 原寄存器→原寄存器；对象输入/输出槽 |
| object | `ingress_r` | 2 | 1 | 原寄存器→原寄存器；对象输入/输出槽 |
| object | `ingress_r` | 2 | 15 | 原寄存器→原寄存器；对象输入/输出槽 |
| object | `ingress_r`（6处声明） | 2 | 16 | 原寄存器→原寄存器；对象输入/输出槽 |
| object | `ingress_r`（2处声明） | 2 | 24 | 原寄存器→原寄存器；对象输入/输出槽 |
| object | `ingress_r`（4处声明） | 2 | 8 | 原寄存器→原寄存器；对象输入/输出槽 |
| object | `ingress_r` | 2 | 64 | 原寄存器→原寄存器；对象输入/输出槽 |
| palette | `prepare_idx_r` | 4 | 8 | 原类型→原类型（范围外）；调色板控制（范围外） |
| perspective | `input_x_r` | 2 | 16 | 原寄存器→原寄存器；透视输入槽 |
| perspective | `input_y_r` | 2 | 16 | 原寄存器→原寄存器；透视输入槽 |
| perspective | `input_mask_r` | 2 | 4 | 原寄存器→原寄存器；透视输入槽 |
| perspective | `input_h_r` | 2 | 70 | 原寄存器→原寄存器；透视输入槽 |
| perspective | `input_palette_r` | 2 | 4 | 原寄存器→原寄存器；透视输入槽 |
| perspective | `input_alpha_r` | 2 | 8 | 原寄存器→原寄存器；透视输入槽 |
| perspective | `input_plane_r` | 2 | 70 | 原寄存器→原寄存器；透视输入槽 |
| perspective_multiply | `exponent_r` | 2 | 10 | 原寄存器→原寄存器；透视乘法流水 |
| pixel | `addr_r` | 32 | 16 | 原寄存器→原寄存器；像素记分牌/负载 |
| pixel | `mask_r` | 32 | 4 | 原寄存器→原寄存器；像素记分牌/负载 |
| pixel | `depth_r` | 32 | 64 | 推断数组→显式table；像素记分牌/负载 |
| pixel | `color_r` | 32 | 96 | 推断数组→显式table；像素记分牌/负载 |
| pixel | `alpha_r` | 32 | 32 | 推断数组→显式table；像素记分牌/负载 |
| pixel | `old_r` | 32 | 160 | 推断数组→显式table；像素记分牌/负载 |
| pixel | `result_r` | 32 | 160 | 推断数组→显式table；像素记分牌/负载 |
| pixel | `return_slot_r` | 32 | 5 | 原寄存器→原寄存器；像素记分牌/负载 |
| pixel | `pipe_slot_r` | 16 | 5 | 原寄存器→原寄存器；像素记分牌/负载 |
| pixel | `even_r` | 16 | 12 | 原寄存器→原寄存器；像素记分牌/负载 |
| pixel | `odd_r` | 16 | 12 | 原寄存器→原寄存器；像素记分牌/负载 |
| pixel_lane | `base_r` | 15 | 40 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `source_r` | 6 | 24 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `alpha_r` | 4 | 8 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `depth_r` | 3 | 16 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `operation_r` | 2 | 3 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `destination_r` | 3 | 24 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `factor_source_r` | 2 | 24 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `factor_dest_r` | 2 | 24 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `product_source_r` | 3 | 48 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| pixel_lane | `product_dest_r` | 3 | 48 | 原寄存器→原寄存器；像素运算流水/中途更新字段 |
| project | `output_0_r` | 2 | 17 | 原寄存器→原寄存器；投影输出槽 |
| project | `output_1_r` | 2 | 17 | 原寄存器→原寄存器；投影输出槽 |
| project | `output_2_r` | 2 | 16 | 原寄存器→原寄存器；投影输出槽 |
| project | `output_3_r` | 2 | 35 | 原寄存器→原寄存器；投影输出槽 |
| project | `output_4_r` | 2 | 51 | 原寄存器→原寄存器；投影输出槽 |
| project | `output_5_r` | 2 | 51 | 原寄存器→原寄存器；投影输出槽 |
| project | `output_6_r` | 2 | 72 | 原寄存器→原寄存器；投影输出槽 |
| quad | `input_data_r` | 2 | 128 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `input_x_r` | 2 | 17 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `input_y_r` | 2 | 17 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `output_x_r` | 2 | 16 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `output_y_r` | 2 | 16 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `output_mask_r` | 2 | 4 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `output_depth_r` | 2 | 16 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `output_unused_palette_r` | 2 | 4 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `output_alpha_r` | 2 | 8 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `input_begin_x_r` | 2 | 18 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `input_begin_y_r` | 2 | 18 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `input_end_x_r` | 2 | 18 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `input_end_y_r` | 2 | 18 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `input_width_r` | 2 | 9 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `input_height_r` | 2 | 9 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `output_u_r` | 2 | 32 | 原寄存器→原寄存器；四边形输入/输出槽 |
| quad | `output_v_r` | 2 | 32 | 原寄存器→原寄存器；四边形输入/输出槽 |
| raster | `input_bounds_r` | 2 | 64 | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_origin_r` | 2 | 32 | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_h_r` | 2 | 70 | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_start_r` | 2 | `WIDTH-1:0` (高位:低位) | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_gx_r` | 2 | `GRAD_WIDTH-1:0` (高位:低位) | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_gy_r` | 2 | `GRAD_WIDTH-1:0` (高位:低位) | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_start_r` | 2 | 40 | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_gx_r` | 2 | 40 | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_gy_r` | 2 | 40 | 原寄存器→原寄存器；光栅输入槽 |
| raster | `input_inclusive_r` | 2 | 1 | 原寄存器→原寄存器；光栅输入槽 |
| read_dma | `addr_r` | 7 | 32 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `beats_r` | 7 | 32 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `last_keep_r` | 7 | 32 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `owner_r` | 4 | 3 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `length_r` | 4 | 5 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `head_keep_r` | 4 | 32 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `tail_keep_r` | 4 | 32 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `logical_last_r` | 4 | 1 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `data_r` | 2 | 256 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `keep_r` | 2 | 32 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `client_r` | 2 | 3 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `last_r` | 2 | 1 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `end_r` | 2 | 1 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| read_dma | `slot_r` | 2 | 2 | 原寄存器→原寄存器；DMA描述符/读返回槽 |
| regs | `perf_event_r` | 9 | 3 | 原寄存器→原寄存器；性能计数/寄存器状态 |
| regs | `perf_r` | 9 | 32 | 原寄存器→原寄存器；性能计数/寄存器状态 |
| resolve | `output_r` | 2 | 256 | 原类型→原类型（范围外）；解析流水（范围外） |
| resolve | `output_last_r` | 2 | 1 | 原类型→原类型（范围外）；解析流水（范围外） |
| resolve | `output_keep_r` | 2 | 32 | 原类型→原类型（范围外）；解析流水（范围外） |
| resolve | `aa_group_r` | 6 | 9 | 原类型→原类型（范围外）；解析流水（范围外） |
| resolve | `color_a_r` | 5 | 24 | 原类型→原类型（范围外）；解析流水（范围外） |
| resolve | `color_b_r` | 5 | 24 | 原类型→原类型（范围外）；解析流水（范围外） |
| resolve | `color_c_r` | 5 | 24 | 原类型→原类型（范围外）；解析流水（范围外） |
| resolve | `color_d_r` | 5 | 24 | 原类型→原类型（范围外）；解析流水（范围外） |
| resolve | `light_b_r` | 5 | 8 | 原类型→原类型（范围外）；解析流水（范围外） |
| setup | `delta_r` | 16 | 72 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `offset_r` | 16 | 36 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `origin_r` | 16 | 32 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `bounds_r` | 16 | 64 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `nonzero_r` | 16 | 1 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `multiply_a_w` | 2 | 18 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `multiply_b_w` | 2 | 18 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `x_w` | 3 | 18 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `y_w` | 3 | 18 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `difference_x_w` | 3 | 18 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `difference_y_w` | 3 | 18 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `edge_offset_x_w` | 3 | 18 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `edge_offset_y_w` | 3 | 18 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `output_bounds_r` | 2 | 64 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `output_origin_r` | 2 | 32 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `value_r` | 8 | 153 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `output_start_r` | 2 | `WIDTH-1:0` (高位:低位) | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `output_gradient_r` | 2 | `2*GRAD_WIDTH-1:0` (高位:低位) | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `output_h_r` | 2 | 10 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `value_r` | 16 | 40 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `output_value_r` | 2 | 40 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `dx_r` | 16 | 40 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `output_dx_r` | 2 | 40 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `dy_r` | 16 | 40 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `output_dy_r` | 2 | 40 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup | `bias_r` | 16 | 40 | 推断数组→显式table；建立标签表/边/输出槽 |
| setup | `output_bias_r` | 2 | 40 | 原寄存器→原寄存器；建立标签表/边/输出槽 |
| setup_plane | `reciprocal_context_r` | 16 | 31 | 推断数组→显式table；平面标签常数 |
| setup_plane | `exponent_context_r` | 16 | 6 | 原寄存器→原寄存器；平面标签常数 |
| setup_plane | `delta_context0_r` | 16 | 18 | 推断数组→显式table；平面标签常数 |
| setup_plane | `delta_context1_r` | 16 | 18 | 推断数组→显式table；平面标签常数 |
| setup_plane | `delta_context2_r` | 16 | 18 | 推断数组→显式table；平面标签常数 |
| setup_plane | `delta_context3_r` | 16 | 18 | 推断数组→显式table；平面标签常数 |
| setup_plane | `offset_context0_r` | 16 | 18 | 推断数组→显式table；平面标签常数 |
| setup_plane | `offset_context1_r` | 16 | 18 | 推断数组→显式table；平面标签常数 |
| target_store | `addr_r` | 4 | 16 | 原类型→原类型（范围外）；目标功能存储/写队列（范围外） |
| target_store | `meta_r` | 4 | 6 | 原类型→原类型（范围外）；目标功能存储/写队列（范围外） |
| target_store | `bypass_data_r` | 2 | 160 | 原类型→原类型（范围外）；目标功能存储/写队列（范围外） |
| target_store | `group_data_r` | 4 | 160 | 原类型→原类型（范围外）；目标功能存储/写队列（范围外） |
| target_store | `fifo_data_r` | 16 | 160 | 原类型→原类型（范围外）；目标功能存储/写队列（范围外） |
| target_store | `fifo_addr_r` | 16 | 16 | 原类型→原类型（范围外）；目标功能存储/写队列（范围外） |
| target_store | `fifo_meta_r` | 16 | 6 | 原类型→原类型（范围外）；目标功能存储/写队列（范围外） |
| texture | `x_r` | 32 | 16 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `y_r` | 32 | 16 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `mask_r` | 32 | 4 | 原寄存器→原寄存器；纹理上下文/寻址元数据 |
| texture | `depth_r` | 32 | 64 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `color_r` | 32 | 96 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `alpha_r` | 32 | 8 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `quad_r` | 32 | 1 | 原寄存器→原寄存器；纹理上下文/寻址元数据 |
| texture | `palette_r` | 32 | 4 | 原寄存器→原寄存器；纹理上下文/寻址元数据 |
| texture | `u_r` | 32 | 32 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `v_r` | 32 | 32 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `lod_r` | 32 | 12 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `result_color_r` | 32 | 24 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `result_alpha_r` | 32 | 8 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `result_mask_r` | 32 | 1 | 原寄存器→原寄存器；纹理上下文/寻址元数据 |
| texture | `even_r` | 16 | 22 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `odd_r` | 16 | 22 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `even_r`（36处声明） | 16 | 21 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `odd_r`（36处声明） | 16 | 21 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `even_r`（8处声明） | 16 | 16 | 推断数组→显式table；纹理上下文/寻址元数据 |
| texture | `odd_r`（8处声明） | 16 | 16 | 推断数组→显式table；纹理上下文/寻址元数据 |
| transform | `output_0_r` | 2 | 40 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `output_1_r` | 2 | 40 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `output_2_r` | 2 | 40 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `output_3_r` | 2 | 40 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `output_4_r` | 2 | 16 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `output_5_r` | 2 | 16 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `output_6_r` | 2 | 24 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `output_7_r` | 2 | 24 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `output_8_r` | 2 | 24 | 原寄存器→原寄存器；变换输出槽/顶点标签表 |
| transform | `vertex_color_r` | 16 | 16 | 推断数组→显式table；变换输出槽/顶点标签表 |
| transform | `vertex_uv_r` | 16 | 32 | 推断数组→显式table；变换输出槽/顶点标签表 |
| unpack | `count_r` | 5 | 2 | 原寄存器→原寄存器；解包状态 |
| write_dma | `addr_r` | 4 | 32 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `beats_r` | 4 | 32 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `last_keep_r` | 4 | 32 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `owner_r` | 2 | 2 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `burst_addr_r` | 2 | 32 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `length_r` | 2 | 5 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `logical_last_r` | 2 | 1 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `strobe_r` | 32 | 32 | 推断数组→显式table；DMA描述符/字节使能/输出槽 |
| write_dma | `out_data_r` | 2 | 256 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `out_keep_r` | 2 | 32 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |
| write_dma | `out_last_r` | 2 | 1 | 原寄存器→原寄存器；DMA描述符/字节使能/输出槽 |

### 验证与状态

RTL提交为 `9a30a7705`（以 `6e91f70f2` 的既有table包装为基础），
`be0af54e9`补全raster/perspective Python构建器的独立源列表连接，
`ca3b28ace`将纹理table切片信号声明前移以兼容Icarus；最终RTL版本为`ca3b28ace`。
首轮perspective编译暴露源列表遗漏，纹理编译暴露Icarus对先用后声明切片的限制；
仅补依赖和移动声明，未修改激励、模型或期望值。

在最终版本`ca3b28ace`上重新从头执行完整一轮：18个GPU单元全部通过，
GT-01～GT-25共128个子场景全部通过；没有拼接不同RTL版本的通过结果。
GT-12为57个子场景，GT-13为16个子场景；texture通过13248组、预加载261拍，
最近邻/双线性/三线性稳态吞吐检查通过。geometry/setup原II检查全部通过。
GT-25十个工作负载的124项逐命令周期，与S-5最终`d6aabe62f`全部相同；
比较基线取`b58b512c7`所记录的S-5最终表，未使用较早的S-4数值。
quad净周期64.757812/对象，AA RESOLVE为80048周期（0.444711ms）。

风格检查37文件0告警，GPU顶层lint 0告警；`git diff --check`通过。
本机只执行风格/lint，运行lint前可用内存大于2GiB，没有在本机执行RTL仿真。
复现命令：

```sh
python3 tools/check/verilog_style.py rtl/gpu/*.v rtl/tech/edrv32_ram_gpu_table.v
(cd rtl/filelists && sh ../../tools/check/lint.sh -DSIM_MODE -f gpu.f --top-module edrv32_gpu)
for path in verif/unit/gpu_*; do python3 tools/regress.py full --path "$path" -j 1; done
python3 verif/block/gpu/run.py rtl gt01 gt02 gt03 gt04 gt05 gt06 gt07 gt08 gt09 gt10 gt11 gt12 gt13 gt14 gt15 gt16 gt17 gt18 gt19 gt20 gt21 gt22 gt23 gt24
python3 verif/block/gpu/gt25/performance.py rtl
```

本次GT实跑将完整bench只编译一次（Verilator 5.051，`--timing -Wall --timescale 1ns/1ps
-j 1 --output-groups 0 -MAKEFLAGS OPT_FAST=-O1`，与S-5相同构建选项），
用`tools.regress.expand_files`展开既有文件列表，再按原`run.generate`、binary+
`CASE_DIR/SEED/sim_args`、`run.compare`流程逐场景运行；最后调用原`performance.measure`。
已有Python 3.9用于模型，没有安装工具。两路并行任务在同一仿真会话中执行，
每路构建均为`-j 1`，全部最终仿真完成后归档并清理独立仿真目录。
原始摘要与GT-25报告在`build/s6/regression/`，逐命令基线比较在
`build/s6/cycle-comparison.log`，风格/lint日志在`build/s6/{style,lint}.log`。

状态：S-6 RTL、存储清点和仿真验收完成；DRM/LUT估算等待PDS验证，
实际FF、分布式RAM用量和clk_gpu时序也交下一轮PDS确认。


## S-7：时序、clip 存储与 LOD 分时（2026-11-26）

### 开工估算

输入为 `4426bf9e5`，Yosys 0.70+219（5053d0e26），沿用 RAM/ROM blackbox、
保留模块层次、`synth -noabc -noalumacc` 与 ABC `strash; if -K 6` 口径。
原始脚本、网表和日志在 `build/s7/`；按模块串行综合，每次先检查可用内存。
基线临时测量副本仅将 geometry 的 `next_index_w` 声明前移，解决 Yosys
前向声明读取失败；未改变电路。

| 基线模块 | FF | LUT6 | table 实例 |
|---|---:|---:|---:|
| clip | 13711 | 29820 | 0 |
| geometry（包含 clip） | 38812 | 79989 | 34 |
| perspective | 16475 | 21725 | 22 |

A3 的基线网表清点：clip 工作集4224 FF、两个多边形输出槽4224 FF、geometry
多边形捕获2112 FF，共10560 FF。`estimate.py` 从 current/last/polygon 输出及
project 输入回溯到时序边界，得到 clip 选择锥7761 LUT6、geometry选择锥1074 LUT6。
这些是可替换逻辑的上界，包含写入选择等共享逻辑，不能当作净收益；计划串行读写
后保守预留2000 FF、4000 LUT6用于端点/输出寄存、装载及控制，估算净省约8560 FF、
4835 LUT6，均超过开工阈值。table容量本身不计入blackbox外LUT6，实际物理资源以PDS为准。

A4 核实为一个2×2组、4条边×2轴，共8个subtract；每两次advance才有一组
有效结果，四边形已绕过本单元。Yosys subtract单实例487 FF、708 LUT6；
8→4个即算术本体省1948 FF、2832 LUT6，另可减少scale和最大值树，
预留选择与对齐约1000 LUT6后仍超过1k LUT，决定实施。

### T1 实现

command 将同一 stop 状态并行写入16份带keep/syn_preserve的寄存器，各直接送一个
使用单元；没有延迟一拍，也没有改变ABORT时序。texture先寄存每lane的96位span，
LOD有效位、slot及地址发起全部顺延一拍。过滤fraction缓存提前计算256−fx/fy，
mode/lane只选择已经寄存的权重，移除mode选择后的进位链，过滤流水长度不变。
geometry输出FIFO改为注册head/tail，移除output_read选择器，输出延迟/吞吐不变；
fan的next index与index一起推进，移除fan_index后的加一器，等待周期仍为5。
project与setup各增加三份同步占用计数副本，分摊原common CE，均无新增流水延迟。

T1 Yosys：geometry 38819 FF / 80769 LUT6 / 34 table；perspective与基线相同；
setup 26009 FF / 42896 LUT6 / 41 table；texture与command见`build/s7/t1b-counts.json`。
前向声明整理也包含setup的edge值、系数和标签声明，语义不变。
仿真主机首次只读检查后连接失效，协调者同意重建一次；重建仍连接超时，
故本步先按协调者指示提交，相关单元仿真留待主机恢复后运行。

### A3 实现与接口

clip输出改为`polygon_valid_o/ready_i/data_o[263:0]/index_o[2:0]/last_o`，
每次握手传一个顶点；index从0递增，last标识本多边形最后一个顶点。停顿保持负载，
顺序仍为裁剪遍历顺序。geometry直接接project输入，不再捕获2112位多边形，
在last握手时将index+1加入原count队列，project结果仍逐顶点写入原16项screen表，
扇形输出和屏幕表的三个读口保持原契约。texture/pixel/target与SoC端口不变。

clip九字段分别使用一个table，低4位地址为bank+vertex，两个工作集共用一个写口；
S_LOAD三拍初始化前三个顶点，交点/内侧端点按原顺序逐项追加。只需一个读口：
S_BEGIN读最后顶点以保存previous及其距离，随后读current；不用同时读取两项。
两个多边形输出槽删除，裁剪结果从工作集串行输出；不裁剪时直接从输入捕获寄存器
输出三个顶点，不访问工作集。无背压时，接收三角形t0，检查完成并发首顶点t3，
余下两个t4/t5，t6可接下一三角形，保持每6拍三顶点；project本来支持II=1，
因此三拍burst不降低每2拍一个源顶点的指标。裁剪路径允许增加装载/串行输出时间。
所有交点算术、舍入点、平面顺序均未修改。

A3后geometry为27827 FF / 66692 LUT6 / 43 table，相比T1省10992 FF、14077 LUT6；
包含clip为4894 FF / 16970 LUT6 / 9 table（独立clip顶层16968 LUT6，ABC上下文差2）。
perspective仍16475 FF / 21725 LUT6 / 22 table。风格与顶层lint均0告警；
本步仿真因指定主机不可用待补，未在本机运行仿真。

### A4 实现

8个subtract/96位scale减为4个。U/V在输入出队后25拍有效：完整2×2组的下行
到达时，4单元计算上下两条水平边的U/V差；紧接的一拍用保存的top和previous
（bottom）计算左右两条竖直边。每拍先求4值最大，再把相邻两拍的最大值合并。
不改变归一化减法/scale的任何算术或舍入；全部八个输入仍参与，mask不控制跨度。
组处理II=2，仍可持续每拍2像素。最大值合并增加一拍，元数据、UV/着色延迟与valid
一同由43拍延至44拍；输出行重组和FIFO协议不变。
旁路延迟从232位降至116位，4个table减为2个；scale短延迟由60位降至40位。

A4后perspective为13058 FF / 17441 LUT6 / 20 table，较基线省3417 FF、4284 LUT6，
超过1k LUT实施阈值。geometry保持A3结果。数值与吞吐的动态验收待仿真主机恢复；
本节的II和拍数为RTL结构推导，不冒充仿真实测。
