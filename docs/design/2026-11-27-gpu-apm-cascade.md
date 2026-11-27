# GPU 宽乘法的原生 APM 移位级联

## 背景和问题

卡 107 的逻辑块装填受 FF 限制。S-5（`2026-11-24-gpu-ff-closure.md`）
把宽乘法分成基数 2^17 部分积，再在 CLM 中寄存逐级求和；乘法器已有硬核，
求和与中间流水仍占 LUT/FF。第八轮的自动级联没有保证中间寄存边界。
本次基线为 `3ff09e27f8927b5891e861814d697f439b00016e`，规格为 gpu-spec v0.6。
实现提交为 `c6eb850d3`（包装、倒数和 plane）及 `30a376f54`（几何和 project II=2）。

PG2L 的 `GTP_APM_E2` 提供 s25×s18 乘法、48 位后加器和带算术右移的 CPI/CPO。
原语依据本机厂商明文模型验证，文件不入库。NPU 链头上板修复表明，链头必须
用 MODEZ=0，不能选择 CPI 后把输入接常数零。

## 约束

- 实现 gpu-spec 2.4、2.12、2.13 第 1–6 条，保持完整积、舍入位置和逐位结果。
- 顶点 II=2、建立三角形 II=8；GPU/SoC 端口和规格不变。
- 固定配置包装，不引入参数；条件编译仅在 tech 原语包装中。
- X/Y、MULT、P、CPO 使用内部寄存器；只有流水确实停顿时才使用使能。
- 数据不复位；PDS 不使用 generate 层次引用或 generate 内数组元素切片。

## 可选方案

| 方案 | 求和位置 | 特点 |
|---|---|---|
| S-5 | CLM 中的分片加法树 | 部分积独立寄存，完整积正确，但求和和结果对齐需要较多 FF |
| 直接宽乘 | PDS 自动推断 | 无法从 RTL 保证级联的中间寄存器，已有第八轮失败证据 |
| 原生移位级联 | APM 48 位后加器 | 显式开启寄存器；只把输入错拍和已完成的低位残数留在 CLM |

采用原生移位级联。X 按 24 位分块（非最高块补零成为 s25），Y 通常按
16 位分块（补零成为 s18）；s18 以内的有符号 Y 直接使用完整原生输入。
最高块按原输入符号扩展，其他块补零。把各项按权位 e 从低到高排序：

```
C0 = x0*y0
Ck = xk*yk + (C{k-1} >>> (ek-e{k-1}))
```

每级保留前级的低 `ek-e{k-1}` 位，延迟到链尾后与最终高位拼接；不在
CLM 中相加。所有当前配置的相邻权位差均为 8、16 或 24，可由专用级联完成。
负中间和采用算术右移，低位残数与最终高位的拼接仍是完整二进制补码乘积。
第 k 项操作数晚 k 个使能时钟送入，N 个 APM 的延迟为 N+2 个使能时钟。

### 乘法清单和延迟

旧部分积数及拍数沿用 S-5。表中的新拍数从原生包装输入到输出计，尚未
计入旁路输入寄存器和为保持原消费拍而加的结果对齐。

| 运算（份数按单模块） | S-5 部分积/拍 | 原生 APM/拍 | 集成处理 |
|---|---:|---:|---|
| transform s32×s16（6） | 2 / 3 | 2 / 4 | X/Y 内部寄存替代原 coefficient/vertex 输入寄存，总拍数不变 |
| transform u24×u8（3） | 2 / 3 | 1 / 3 | 单 APM，结果拍不变 |
| transform u33×u8（3） | 2 / 3 | 2 / 4 | X 内部寄存替代 illumination 求和结果寄存；颜色表提前一拍读 |
| clip s40×s43（2） | 9 / 最多13 | 6 / 8 | 保留原分量等待，包含分子流水的稳定时间 |
| project s40×u35（原3套→2套） | 9 / 11 | 6 / 8 | 第1拍 X/Y、第2拍 Z 复用 X；结果对齐分别3/2拍 |
| project u16×u35（原2套→1套） | 3 / 5 | 2 / 4 | 交换为 u35×u16；第1拍 U、第2拍 V，U 对齐1拍 |
| project s94×u16（原2套→1套） | 6 / 9 | 4 / 6 | 保留低94位；Y 输入晚1拍占相反相位，X/Y 对齐3/2拍 |
| project_recip u31×u30（1） | 4 / 5 | 4 / 6 | 内部 X/Y 寄存吸收 mantissa/seed 的一拍 |
| project_recip u30×u32（1） | 4 / 5 | 4 / 6 | 内部输入寄存吸收 correction 的一拍，seed 同步提前 |
| setup_plane s34×s18（4） | 2 / 3 | 2 / 4 | 内部 X/Y 寄存吸收 difference/context 的一拍 |
| setup_plane s56×u31（2） | 8 / 10 | 6 / 8 | 结果对齐2拍 |
| setup_plane s56×s18（2） | 4 / 7 | 3 / 5 | 结果对齐2拍 |

project_recip 的外部延迟仍为24拍，setup_plane 仍为85拍；setup 的对齐计数
和 setup.v 不需要修改。transform 仍为19拍，project 含倒数和 FIFO 写入仍为75拍。
project 的入口每两个使能时钟开放一次；valid 标签选择共享乘法器的第一项，
第二项在随后一拍发射。停顿同时冻结发射相位、标签、算术和 RAM 地址。
共享结果的2/3拍对齐使用同一条延迟链，不重复保存相同深度的数据。

### clip 突发与 project II=2 的对接

首轮 geometry 回归在稳态第29个输入报 vertex II=4：clip 全内旁路先检查3拍，
再连续输出3个顶点，直接连接 II=2 的 project 会把这3拍输出拉长到5拍。
协调者批准在 clip 内部出口加入两项弹性 FIFO；满时允许同拍取出和写入，
既不丢掉突发的第三项，也不改变 project 的严格两拍接收节奏。

新增寄存为 `2×(264数据+3索引+1末项)+2占用+1读指针+1写指针=540 FF`。
数据按九个字段分开保存，无数据复位；仅实际入队时写队列元素，没有额外延迟 bank。
stop 清空队列控制，idle 同时等待状态机和队列排空。geometry 的既有数值、
反压、stop/restart 和稳态 II 检查在加入该队列后恢复通过。

### 原语固定配置表

四种原生单元分别为 `edrv32_apm_gpu_head`、`shift8`、`shift16`、`shift24`。
固定宽乘法包装的名字直接写明两输入的符号和位宽，配置见上表；它们只连接原生
单元、输入错拍和低位残数，不含额外求和器。所有包装均位于 `rtl/tech/`。

| 参数 | 全部原生单元 |
|---|---|
| GRS_EN | `"FALSE"` |
| USE_POSTADD / USE_PREADD / USE_SIMD | 1 / 0 / 0 |
| X_REG / Y_REG / MULT_REG / P_REG / CPO_REG | 全为1 |
| ASYNC_RST | 0；各数据复位端口接0 |
| 其余参数 | 厂商默认值；未使用的预加、Z 和模式寄存不启用 |

| 端口 | 连接 |
|---|---|
| X / Y | `{5'b0, x_i[24:0]}` / `y_i[17:0]` |
| MODEY / MODEIN | `3'b001` / `5'b00010` |
| MODEZ（head / shift8 / shift16 / shift24） | `4'd0` / `4'd7` / `4'd6` / `4'd5` |
| CPI | 后级接前级 CPO；head 不选择 CPI，外部闲置输入接0 |
| CPO | 只连接下一 APM 的专用 CPI，不接逻辑残数寄存 |
| P | 同拍的寄存后加结果，连接 CLM 低位残数寄存及链尾结果 |
| COUT / CXO / CXBO | 不使用 |
| CXI / CXBI / XB / Z / CIN | 全接0 |
| 全部 CE | `enable_i`；clip 接1，其他单元按真实流水停顿使能 |
| 全部 RST | 接0，只有业务 valid/计数状态复位 |

### 固定宽乘法包装的级联次序

下表模块名统一加前缀 `edrv32_apm_gpu_`；均无参数，端口为 clk、enable、
a、b、p。输入为模块名给出的原始位宽，p 除 s94×u16 保留低94位外均为两输入
位宽之和。e 为各 APM 项的权位，按表中顺序连接 CPO→CPI；第一项用 head，
随后按相邻 e 的差选择 shift8/16/24。操作数块从原输入的对应24/16位位置取，
最高块按输入符号扩展；s16/s18 的 Y 用完整有符号块。延迟从 X/Y 输入采样计。

| 包装后缀 | e 次序 | APM数 / 延迟 |
|---|---|---:|
| s32xs16 | 0,24 | 2 / 4 |
| u24xu8 | 0 | 1 / 3 |
| u33xu8 | 0,24 | 2 / 4 |
| s40xs43 | 0,16,24,32,40,56 | 6 / 8 |
| s40xu35 | 0,16,24,32,40,56 | 6 / 8 |
| u35xu16 | 0,24 | 2 / 4 |
| s94xu16 | 0,24,48,72 | 4 / 6 |
| u31xu30 | 0,16,24,40 | 4 / 6 |
| u30xu32 | 0,16,24,40 | 4 / 6 |
| s34xs18 | 0,24 | 2 / 4 |
| s56xu31 | 0,16,24,40,48,64 | 6 / 8 |
| s56xs18 | 0,24,48 | 3 / 5 |

### FF/LUT 估算方法

以下为结构估算，不是 PDS 测量。移位级联去掉原 `(部分积数−1)` 个逻辑
求和节点；按每节点完整结果宽 W 的加法上界估算，最多减少
`(部分积数−1)×W` 个进位 LUT，实际节点的恒零和符号复制会减少该数。
新求和 LUT 为0；project 三组共享选择器合计最多约
`(40+35)+(35+16)+(94+16)=236` 个二选一 LUT（未扣常数和共享）。

新 CLM FF 按各固定包装的输入块错拍和残数延迟计数：第 k 项仅寄存真实
`wxk+wyk` 个源位、共 k 拍；前级低位残数 dk 延迟 `N−1−k` 拍。
公式为 `Σ k×(wxk+wyk) + Σ dk×(N−1−k)`，另加上表列出的结果对齐。
乘积和后加的内部寄存均落 APM；不能把 SIM 行为模型中的这些 FF 算作物理 CLM。
替代的 coefficient、vertex、illumination、difference/context 寄存不再单独保存。

### 逐项寄存与进位 LUT 估算

下表逐份列出 S-5 求和树的显式寄存位数（不计第一级部分积寄存），以及
新包装的 CLM 输入错拍＋残数寄存位数；未扣综合合并，未计上文外部输入吸收和
结果对齐。这是 RTL 结构估算，不能当成器件 FF 实测。LUT 列按上述
`(旧部分积数−1)×W` 给出移除进位 LUT 的上界；不包含乘法器本体。

| 运算 | 旧树 FF | 新错拍＋残数 FF | 移除进位 LUT 上界/份 |
|---|---:|---:|---:|
| transform matrix | 110 | 48 | 48 |
| transform illumination | 64 | 0 | 32 |
| transform color | 89 | 41 | 41 |
| clip | 469 | 640 | 664 |
| project position | 1177 | 576 | 600 |
| project UV（交换输入） | 274 | 51 | 102 |
| project viewport | 1067 | 378 | 470 |
| reciprocal Newton 第一次 | 360 | 227 | 183 |
| reciprocal Newton 第二次 | 372 | 230 | 186 |
| setup difference×delta | 122 | 52 | 52 |
| setup numerator×reciprocal | 2324 | 639 | 609 |
| setup gradient×offset | 801 | 166 | 222 |

clip 的新错拍/残数寄存比旧求和树增加171位/份，其收益是移除逻辑求和及减少
3个 APM/份；FF 收敛主要来自 project 的复用和 setup 的宽树搬迁。
例如 setup inverse 每份增加结果对齐174位后仍估算减少
`2324−639−174=1511` 位逻辑寄存。project 的坐标共享结果只保留一条225位
延迟链，另一个坐标链为225位；UV 对齐51位，视口对齐282位。
另外只保存深度符号的两拍寄存、35位还原延迟和31位倒数规格化结果，删除
这些路径不再使用的高位；乘法树消失后删除未使用的 credit 区域副本。

## 决策

采用上述全寄存移位级联和 project 两拍复用方案。没有改变数值格式、
舍入点、饱和点或规格；没有加入额外保护、兜底和多周期时序例外。

## 影响

修改 transform、clip、project、project_recip、setup_plane；新增固定原语和
宽乘法包装、GPU 文件列表行及 geometry/setup 单元的编译依赖。
setup.v 不需要对齐修改，交接后本任务不再修改该文件。
IP 说明由协调者依据本记录配置表维护。

### 验证和资源证据

本机厂商模型等价性：

```sh
. ~/.local/opt/edrv32/env.sh
EDRV32_PANGO_SIM_DIR="$HOME/.local/share/edrv32/pango" \
    python3 verif/unit/gpu_project_apm/run.py
```

12 种固定配置同时与精确乘积和厂商模型逐拍比较，12,000 轮随机、全零、
全一、符号边界及随机停顿全部 PASS。初步 s40×s36 原理验证同样为
6 APM、8 拍，12,000 轮 PASS；入库可复现入口以上述实际 s40×u35 和 s40×s43
配置覆盖相同的6级链。

SIM_MODE 顶层 lint 在共享工作树的 R-6b 端口对齐后通过，0 告警：

```sh
cd rtl/filelists
sh ../../tools/check/lint.sh -DSIM_MODE -f gpu.f --top-module edrv32_gpu
```

`python3 tools/check/verilog_style.py` 检查本任务5个业务 RTL和16个 tech 包装，
21文件0告警；`git diff --check` 通过。单测在独立同步目录串行/最多两项并行执行：

```sh
python3 tools/regress.py full --path verif/unit/gpu_geometry -j 1
python3 tools/regress.py full --path verif/unit/gpu_setup -j 1
```

Python 参考模型取 `git archive fd13f647d tools/gpu/model` 的快照，测试源码和
数值期望未改；没有读取 R-6b 工作中的 P-A 模型。
geometry：63 draws、615 vertices、179 triangles，vertex II=2；
setup：264 inputs、262 outputs，triangle II=8，两项全部 PASS。setup 使用 `c6eb850d3` 的
接口和测试快照，验证后已通知协调者交接 setup.v，后续其 P-A 修改由 R-6b 验证。
GT 全套由 R-6b 在集成后执行，本任务不重复跑。

### Yosys 同口径参考

Yosys 0.70+219（5053d0e26），ABC LUT6 通用映射。基线为前述 `3ff09e27f`，
改后为上述两个实现提交；每个模块分别作为顶层，子模块递归计数。RAM/ROM 包装
blackbox；两版均映射 SIM 乘法行为模型，不对 APM 做器件专用映射。
因此下表的改后总 FF/LUT **包含实际应落在硬核中的完整25×18乘法及流水**，
不能直接当成物理 CLM 数字；特别是共享的固定原语模块没有按每实例常数输入裁剪。
它只满足同口径的逻辑参考要求，物理资源仍待 PDS。

| 模块 | 旧FF → 新FF | 旧LUT6 → 新LUT6 | 旧`$mul` → 新`$mul` | 显式APM |
|---|---:|---:|---:|---:|
| transform | 4361 → 5604 | 12971 → 24277 | 27 → 24 | 21 |
| clip | 4894 → 6496 | 16960 → 19017 | 18 → 12 | 12 |
| project_recip | 1734 → 2405 | 4749 → 9190 | 8 → 8 | 8 |
| project | 13791 → 12423 | 31867 → 31759 | 53 → 26 | 26 |
| setup_plane | 17942 → 18058 | 32161 → 37817 | 32 → 26 | 26 |

另外将改后原生 head/shift 单元的 FF/LUT 从层次计数中剔除，可得下表的
CLM 代理；基线没有显式原语边界，不能用这一列直接计算物理前后差值。

| 改后模块 | CLM代理FF | CLM代理LUT6 |
|---|---:|---:|
| transform | 2886 | 2617 |
| clip | 4938 | 6109 |
| project_recip | 1367 | 658 |
| project | 9049 | 3999 |
| setup_plane | 14686 | 10293 |

`$mul` 粗网表宽度只有25×18，以及 transform 保留的8×16光照乘法；不存在
需要工具再拆分的宽 `$mul`。project 行包含其倒数子模块，不能与 reciprocal 行
重复相加。显式包装计数只数 head/shift 原生单元，不把外层固定宽乘法重复计数。

复现时分别用 `git archive` 导出两版 `rtl/`，读取各自 gpu.f 的所有源文件，
定义 SIM_MODE、加入 `rtl/include`，每个模块执行以下脚本（ABC脚本两行为
`strash` 和 `if -K 6`）：

```text
read_verilog -D SIM_MODE -Irtl/include <gpu.f 展开的源文件>
blackbox edrv32_ram_gpu_* edrv32_rom_gpu_*
synth -top edrv32_gpu_<模块> -noabc -noalumacc -run begin:fine
write_json <模块>-coarse.json
synth -top edrv32_gpu_<模块> -noabc -run fine:check
abc -lut 6 -script <上述ABC脚本>
write_json <模块>.json
```

递归遍历顶层模块 cells：type 含 DFF 的单元计1 FF，`$lut` 计1 LUT6，
粗网表 `$mul` 计1乘法；type 为已定义且非 blackbox 的模块时展开子模块，
每个实例都计入。transform 的3个8×16光照乘法仍由工具推断，未计入显式 APM 列。
head/shift8/shift16/shift24 实例各计1 APM，CLM代理剔除
这四种模块内部的全部 DFF/`$lut`。原始脚本、JSON、日志留在
`build/r6a/resources/`；Icarus 输出在 `build/r6a/equivalence.log`，
回归日志回收到 `build/r6a/`，生成物不入库。

## 状态

已决定并实现；原生包装本机等价性、geometry/setup 单测和 II 检查通过。
PDS 布局布线及最终物理 FF/LUT/APM 数由后续任务确认。
