# NPU 离线编译工具（N-M1）

依据 [NPU 规格 v0.2](../../docs/spec/npu-spec.md) 2.1–2.5、4.1–4.3，
将固定 640×384 YOLOv8n 的融合卷积、COCO128 标定结果和一幅图像转换成 DDR 镜像。
`checkpoint_audit.py` 核对 63 个融合卷积及三个尺度的特征/检测输出形状；
`fixed_plan.py` 分配 WORK、OUTPUT 和零拷贝拼接；`quantize.py` 完成标定及 INT8 量化；
`input_pack.py` 输出 INT8_C4；`format.py` 负责字节布局；`gen_case.py` 生成小用例。
所有运行时依赖均来自 `tools/requirements.txt`；工具不读取 `legacy/`。

## 复现整网镜像

先按 [环境安装指南第 6 节](../../docs/guides/env-setup.md) 安装 Python 环境、
下载 `~/.local/share/edrv32/npu/yolov8n.pt` 和 `coco128/`，在仓库根目录执行：

```sh
git submodule update --init third_party/ultralytics
export PYTHONPATH="$PWD/third_party/ultralytics"
~/.local/opt/edrv32-py/bin/python tools/npu/checkpoint_audit.py
~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py \
    --image ~/.local/share/edrv32/npu/coco128/images/train2017/000000000009.jpg \
    --out build/npu/yolo_coco_000009/
~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/npu -p 'test_compile.py'
```

编译器首次运行按路径排序，取 COCO128 `images/train2017/` 前 96 张：
每张图每层分别取极值，再对这些极值取 percentile 95；margin 固定为旧流程的 1.05。
共享残差尺度和每 C16 平面的拼接输入尺度保持原量化流程；线性检测头采用非零输出零点。
图像先按最小比例缩放、四舍五入尺寸、居中补 114，再 RGB / 255，
用 `torch.round(· × 127)` 量化；物理输入为 `{0,B,G,R}`，R 位于最低字节。

量化结果缓存于 `build/npu/quantized/model.bin` 和 `quantization.json`。
后者保存量化尺度、零点和标定参数；其中 `index` 对应含六个逻辑 add 的 74 项量化图，
描述符表则将 add 融入前一条 CONV。后续换图像运行同一编译命令即可复用缓存。
要重新标定，删除这两个生成文件后重跑上述命令；不自动判定缓存版本或审批状态。

标定固定使用 1 个 torch 线程（`quantize.calibrate` 中 `torch.set_num_threads(1)`，2026-10-27 用户确认）：标定结果对线程数敏感，固定后任何环境下重新生成的模型镜像逐字节相同。实测：清空缓存后标定加编译 38 s；在 `OMP_NUM_THREADS=3` 环境下重跑，`model.bin` 和 `mem_model.hex` 与第一次逐字节相同。下文 N-M1 和 TL-04 的记录是固定线程之前的 3 线程结果。

2026-10-27 在开发基线 `8c3cb98` 上的 N-M1 工作树实测，Linux 3 核/8 GB、
Python 3.12、torch 2.14.1+cpu、numpy 2.5.2、OpenCV 5.0.0、
ultralytics 8.4.160（子模块 `9d25f80daa5b3af71c16521eba353cb6e7fb66e2`），
保持 torch 默认线程数，同一时刻只运行一个标定任务：

| 项目 | 结果 |
|---|---:|
| 描述符 | 68 = 63 CONV + 3 POOL + 2 UPSAMPLE |
| 融合残差加 | 6 |
| 模型权重区实际字节数 | 3,148,032 |
| 模型镜像总字节数（含量化记录/LUT） | 3,242,752 |
| WORK 区大小 | 5,867,520 |
| C4 输入字节数 | 983,040 |
| OUTPUT 区大小（六个 box/class 输出） | 725,760 |
| 首次编译（含检查点核对和 96 张标定） | 96.131 s |
| 命中缓存后的编译 | 0.154 s |

时间是 `compile_yolo.py` 的 `elapsed_s`，从进入 main 后计时，不含 Python/torch 导入。
首次日志为 `build/npu/compile_first.log`，缓存日志为 `build/npu/compile_cached.log`；
镜像位于 `build/npu/yolo_coco_000009/`。生成物均不入库。
首层描述符为 `IN_C4=1, HALF_TAIL=1, COUT_BLOCKS=1, K_COUNT=9`，
权重实际 2304 B，不采用非 C4 尾块的归约折叠。

## 公共用例文件格式

N-M1/N-M2/N-V1 共用以下协调者约定；其中 `mem_` 前缀及 `ref_desc_` 命名
采用任务给定格式（验证方案 2.4 的旧简写文件名以本约定为准）。
一个用例放在 `build/npu/<用例名>/`：

| 文件 | 内容 |
|---|---|
| `regs.txt` | 每行 `<寄存器名> <十六进制值>`，无 `0x`；寄存器为 MODEL_BASE、WORK_BASE、INPUT_BASE、OUTPUT_BASE、DESC_BASE、DESC_COUNT |
| `mem_<区名>.hex` | 区名 model/desc/input/work/output；独立参考模型的分割快照还可使用 state；空区可无文件 |
| `check.txt` | 每行 `<名称> <起始字节地址十六进制> <字节数十六进制>`；起点、长度均按 32 B 对齐 |
| `ref_out.hex` | 参考模型执行完全部描述符后的 check 区间；本编译器/生成器不产生 |
| `ref_desc_<n>.hex` | 参考模型可选的逐描述符输出；本工具不产生 |

hex 段以 `@<beat 地址>` 起始，beat 地址 = 绝对 DDR 字节地址 / 32，十六进制。
随后每行 64 个十六进制字符，表示一个 256 位 beat，**最左边是最高字节**。
byte 0 是最低 8 位、对应最低 DDR 地址，与 Verilog `$readmemh` 一致。
例如最低四字节 `01 02 03 00` 出现在行的最右端 `00030201`。
每段可以有自己的 `@` 起点；装载方按绝对地址装入目录中全部 `mem_*.hex`，
不通过区名推断地址归属；从未装载或写入的字节读作 0。
`check.txt` 可以列出包含平面间空隙的完整输出范围，这些未写空隙同样为 0。

默认寄存器如下（DESC_COUNT 由算子数决定）：

```text
MODEL_BASE 00100000
WORK_BASE 01000000
INPUT_BASE 04000000
OUTPUT_BASE 05000000
DESC_BASE 00080000
DESC_COUNT 00000044
```

所有默认基址 4 KiB 对齐，位于 1 GiB DDR 内。描述符 64 B、小端字段位置及派生量
见规格 4.1；量化块 512 B，通道项第 7 字节为 0，零点只在 `OUT_ZP`；
三种权重排列见规格 4.3 和[设计记录 4.7.5](../../docs/design/2026-10-27-npu-datapath.md)。
C16 的行紧凑排列、平面跨距按 32 B 对齐；所有拼接部分以相同跨距连续分配。

## 随机小用例命令

小用例只需 numpy，无需加载 torch 或真实权重。以下命令在仓库根目录执行，
`G` 只表示便于复用的命令字符串：

```sh
G="$HOME/.local/opt/edrv32-py/bin/python tools/npu/gen_case.py"
# OP-01：三个输入 C16 平面、三个输出 C32 块；改 cin/cout 可覆盖 1/2/3 块。
$G --op conv --seed 1 --cin 48 --cout 96 --out build/npu/op01
# OP-02：K3 S1，宽度 12；另取 width 4/8 可覆盖边界宽度。
$G --op conv --seed 2 --kernel 3 --width 12 --height 7 --out build/npu/op02
# OP-03：K3 S2；奇数高度 5 的输出高度向上取整为 3。
$G --op conv --seed 3 --kernel 3 --stride 2 --width 12 --height 5 --out build/npu/op03
# OP-04：C4 首层，分别写两个平面和一个平面。
$G --op conv --seed 4 --in-c4 --kernel 3 --stride 2 --cout 32 --out build/npu/op04_c32
$G --op conv --seed 4 --in-c4 --kernel 3 --stride 2 --cout 16 --out build/npu/op04_c16
# OP-05：随机激活表；省略 --lut 可生成旁路。
$G --op conv --seed 5 --lut --out build/npu/op05
# OP-06：残差源在 WORK、OUTPUT，单独分配、不与输出同址。
$G --op conv --seed 6 --res --res-sel work --out build/npu/op06_work
$G --op conv --seed 6 --res --res-sel output --out build/npu/op06_output
# OP-07：只有一个半块，以及第三块为半块。
$G --op conv --seed 7 --cout 16 --out build/npu/op07_c16
$G --op conv --seed 7 --cout 80 --out build/npu/op07_c80
# OP-08：前四通道含 bias INT32 极值、mult -32768/32767/0/-1、shift 0/47/1/46。
$G --op conv --seed 8 --quant-boundaries --out build/npu/op08
# OP-09：全负 POOL，3 个 C16 平面，20×12 容量边界。
$G --op pool --seed 9 --width 20 --height 12 --cin 48 --negative-input --out build/npu/op09
# OP-10：输入宽度 2；也可改为最大宽度 40。
$G --op upsample --seed 10 --width 2 --height 3 --out build/npu/op10
# OP-11：四种基址、非零偏移、宽松平面跨距；每种基址都用于 IN/OUT/RES。
for r in model work input output; do
    $G --op conv --seed 11 --in-sel "$r" --out-sel "$r" --res-sel "$r" \
        --res --offset 0x120 --plane-pad 64 --out "build/npu/op11_$r"
done
# OP-11：前两条 CONV 写连续平面，第三条 CONV 直接读取拼接视图。
$G --op chain --seed 11 --concat --plane-pad 32 --length 5 --out build/npu/op11_concat
# OP-12：4–8 条随机链，随机算子、尺寸、标志和基址，20 个种子。
for s in $(seq 0 19); do
    $G --op chain --seed "$s" --out "build/npu/op12_$s"
done
```

每层随机量化默认含负 mult，前两个通道的 shift 固定为 0、47，其他通道取 0..47。
`HALF_TAIL` 由 `cout % 32 == 16` 推导；`--cin/--cout` 使用实际 C16 通道数。
C4 的实际输入固定为 RGB 三通道，第四字节为 0。默认宽高为 8×6，默认输入/输出
选择 INPUT/OUTPUT，默认起始偏移为 32 B；`--plane-pad` 给每平面增加 32 B 整数倍空隙。
随机链自动选择满足 CONV、POOL、UPSAMPLE 宽度约束的形状；
`--concat` 的前三条描述符固定组成拼接，其余部分随机。

## JSON 定向图接口

```sh
~/.local/opt/edrv32-py/bin/python tools/npu/gen_case.py \
    --config build/npu/concat.json --seed 29 --out build/npu/config_concat/
```

JSON 顶层为 `{"bases": {...}, "layers": [...]}`，`bases` 可省略，键为上述五个
`*_BASE` 寄存器名；各地址/跨距/偏移接受 JSON 整数或 `"0x..."` 字符串。
每层字段如下；通道数为逻辑通道数，C4 输入 `cin=3`。

| 字段 | 语义/缺省 |
|---|---|
| `op` | 必填：`conv`、`pool`、`upsample` |
| `in_w`, `in_h`, `cin` | 来自生产层时继承；外部输入缺省 8×6、16 通道（C4 为 3） |
| `cout` | CONV 缺省 32；POOL/UPSAMPLE 保持 cin |
| `k`, `s` | CONV 核/步长，缺省 1/1 |
| `lut`, `res`, `in_c4` | 布尔标志，缺省 false |
| `half_tail` | 缺省由 cout 推导，可显式指定与形状对应的标志 |
| `in_from` | `"input"` 表示生成随机初始输入；整数为从 0 开始的生产层号；列表表示按顺序读取这些层的连续平面；首层缺省 input，其余缺省前一层 |
| `in_sel`, `out_sel`, `res_sel` | model/work/input/output；输入和残差默认继承生产层，外部输入默认 input，输出及独立残差默认 work |
| `in_offset`, `out_offset`, `res_offset` | 32 B 对齐偏移；输入/残差继承对应生产层，其他按区顺序分配 |
| `in_plane_stride`, `out_plane_stride` | 32 B 对齐；输入继承生产层，其他缺省紧凑值；C4 输入为 0；残差跨距等于输出跨距 |
| `res_from` | 已完成层的层号；省略则生成独立随机残差初始内容 |
| `quant` | `"random"`（缺省）或对象，键 bias/mult/shift/out_zp；每键可为 random 或整数，bias/mult/shift 还可为长度 cout 的列表 |
| `weights` | random（缺省）、max（有效权重全 127）、min（有效权重全 −128）；补齐部分仍为 0 |

输入宽度、通道、偏移、跨距、容量和残差尺度/零点应按规格给出；
显式图可以描述验证需要的指定布局，工具直接按这些字段编码。
`in_from` 列表只建立视图，写入相邻平面由各生产层的 `out_offset` 明确安排。
`res_from` 指定已有输出时不重新随机初始化该区。
工具先分配全部特征图，再将模型参数排在 MODEL 中特征图的末尾，避免混用 MODEL 基址时
覆盖参数；简写模式则将 MODEL 特征图从偏移 0x800000 起分配，参数从 0 起分配。
`check.txt` 列出最后一层的输出，`mem_*.hex` 可以包含多个不连续段。

下面示例可写入 `build/npu/concat.json`：

```json
{
  "layers": [
    {
      "op": "conv", "in_w": 4, "in_h": 4, "cin": 16, "cout": 16,
      "in_sel": "input", "in_offset": "0x20", "out_sel": "work",
      "out_offset": "0x1000", "out_plane_stride": "0x140",
      "weights": "max", "quant": {"bias": 0, "mult": 1, "shift": 0, "out_zp": 0}
    },
    {
      "op": "conv", "in_from": "input", "in_w": 4, "in_h": 4,
      "cin": 16, "cout": 16, "in_sel": "input", "in_offset": "0x20",
      "out_sel": "work", "out_offset": "0x1140", "out_plane_stride": "0x140",
      "weights": "min", "quant": {"bias": 0, "mult": 1, "shift": 0, "out_zp": 0}
    },
    {
      "op": "conv", "in_from": [0, 1], "cout": 16, "out_sel": "output",
      "out_offset": "0x2000", "out_plane_stride": "0x140", "res": true, "res_from": 0,
      "quant": {"bias": 0, "mult": 1, "shift": 0, "out_zp": 0}
    }
  ]
}
```

## TL-03 与实测检查

`test_compile.py` 的 12 项标准 unittest 检查描述符字/位位置、首层和最大层的派生量、
非卷积字段、六次残差融合、拼接地址、设计记录 4.7.5 的普通/半块/C4 权重字节例子、
Cout80 第三块紧缩、量化符号/shift/第 7 字节、C4 RGB/hex 字节序、C16 平面空隙，
以及 JSON 图的拼接、残差来源、定向参数和自定义基址。
上述小用例形状均已生成，另完成种子 0..19 的随机链生成；
日志为 `build/npu/generator_checks.log`。参考算术和 RTL 比对由 N-M2/N-V1 完成。
本改动没有 RTL，Verilator lint 不适用；`python3 tools/check/verilog_style.py tools/npu`
扫描 0 个 Verilog 文件、0 告警；`git diff --check` 通过。

## 0.611 与旧记录 0.623 的 mAP 差异

结论：**未查明**。没有为了匹配记录数字改变 percentile、margin 或标定集。
[旧工程记录](../../legacy/doc/architecture/2026-09-23-yolo-v8n-exec.md)
给出排序前 96 张标定、余 32 张验证，浮点 mAP50/mAP50-95 = 0.642/0.499，
INT8 = 0.623/0.471。协调者在 Linux `/tmp/npuq` 复制旧脚本运行的结果为：

| 路径 | mAP50 | mAP50-95 |
|---|---:|---:|
| 浮点 | 0.6416486813 | 0.4991306414 |
| 旧流程 INT8（Linux 复现） | 0.6112938378 | 0.4655402422 |

这次 Linux 评估含 32 张图、225 个标注、45 个有标注类别；
NMS confidence=0.001、IoU=0.7，INT8 共 3953 个预测。
结果来自 `/tmp/npuq/out/models/yolov8n_int8_coco96_p95_eval.json`，
本任务没有重新实现或修改参考模型/检测后处理。

已核对的证据与局限：

- Linux 旧流程的标定报告为 96 张、percentile 95、margin 1.05，与旧文字记录一致；
  标定首张 000000000009.jpg、末张 000000000520.jpg，验证从 000000000529.jpg 到
  000000000650.jpg。新工具与 Linux 旧流程的标定文件名及排序完全相同。
- 新工具重新标定后，63 层的输入/输出尺度、零点、权重尺度和乘数误差等量化结果
  与 Linux 旧流程逐项完全相同。将旧物理权重还原成逻辑权重后按新格式打包，
  63 层字节完全一致；旧量化记录清除第 7 字节后也与新记录全部一致。
  因而这次布局迁移、C4 打包、HALF_TAIL 紧缩和零点迁移不能解释**迁移前已经出现**的差异。
  检查输出位于 `build/npu/migration_comparison.log`。
- 检查了旧脚本：预处理是相同的 640×384 居中 letterbox，缩放与量化使用 round；
  评估按排序后第 96..127 张取验证集，NMS 参数为 0.001/0.7。
  Linux 浮点结果与旧记录吻合至记录精度，但这不足以证明旧环境完全相同。
- 当前版本确定为 torch 2.14.1+cpu、numpy 2.5.2、OpenCV 5.0.0、ultralytics 8.4.160；
  旧 Windows 测量的依赖版本、原始逐层标定数值、INT8 镜像和完整 eval JSON
  未保存在当前仓库，无法做版本或逐层二分。
  版本差异、当时实际参数/数据顺序与文字记录有出入仍是未排除项，不能当作已确认根因。

要继续定位，需要旧次测量的原始量化结果、评估明细及环境版本；目前保留实测 0.611，
不将 0.623 写成新工具已达到的结果。

## TL-04：整网逐层、检测结果与 INT8 精度核对（N-M3）

`tl04_compare.py` 默认比较 COCO128 的 `000000000009.jpg`（编译示例图）、
`000000000529.jpg` 和 `000000000650.jpg`（验证集首、末图）。
`--legacy-root` 指向已完成旧流程标定的目录，要求其中有
`out/board/yolo_v8n_fixed_plan.json`、
`out/models/yolov8n_int8_coco96_p95.bin` 及同名 `.json`；本机使用 N-M1 的 `/tmp/npuq`。

```sh
export PYTHONPATH="$PWD/third_party/ultralytics"
mkdir -p build/npu/tl04
OPENBLAS_NUM_THREADS=1 /usr/bin/time -f 'wall=%e s peak=%M KiB' \
    ~/.local/opt/edrv32-py/bin/python tools/npu/tl04_compare.py \
    --legacy-root /tmp/npuq > build/npu/tl04/compare.log 2>&1
```

可用 `--images <图像...>` 指定图像、`--out <build 下目录>` 指定生成物位置。
工具把旧脚本和候选复制到输出目录的 `legacy/`，只在副本增加每命令观察回调、
提取原有 DFL/解码/NMS 代码，不修改旧整数算术。
两条路径使用**同一份旧候选量化结果**：以旧解包函数恢复逻辑权重，再调用新工具的
`pack_weights` 按规格 4.3 打包 C4 首层、普通块和 HALF_TAIL；
旧量化项 byte 7 清零，原零点交给描述符 OUT_ZP（规格 4.2）。
转换结果放在本次输出目录的 `quantized/`，通过重定向 `quantize.CACHE`，在进程内调用
原 `compile_yolo.main()` 生成各图用例；不覆盖编译器默认标定缓存，不重新标定或调整参数。

参考模型保存全部 `ref_desc_<n>.hex`；旧路径保存全部 74 个命令的
`legacy/cmd_<n>.npy`。按层名对应 68 个描述符，六个融合 CONV 取旧残差加之后的张量，
其余取相应旧命令输出。物理平面还原为逻辑 `(通道, 行, 列)`，去掉平面间隙和物理补齐。
逐层打印形状和差异元素数；失败打印首个差异坐标及两边数值，最终退出码为 1。
检测对照将参考模型六个检测头按原尺度/零点反量化，再送入复制的旧 DFL/NMS；
按 NMS 原顺序精确比较类别、四个框坐标和置信度。

2026-10-27 在基线 `602d458` 加本节工具改动上实测；依赖版本同上，
torch 默认 3 线程、参考模型 BLAS 1 线程；同一时刻仅运行一个本任务的重任务：

| 图像 | 逐层比较 | 检测数：conf=0.001 / conf=0.25（前 20） | 检测对照 | 单图耗时 |
|---|---|---:|---|---:|
| 000000000009.jpg | 68/68，全部逐位一致 | 156 / 5 | 两组全部完全相同 | 2.680 s |
| 000000000529.jpg | 68/68，全部逐位一致 | 21 / 2 | 两组全部完全相同 | 2.637 s |
| 000000000650.jpg | 68/68，全部逐位一致 | 21 / 2 | 两组全部完全相同 | 2.135 s |

两组 NMS 的 IoU 均为 0.7；conf=0.001 沿用旧库默认最多 300 个结果。
共 204/204 个描述符输出、6/6 组检测对照通过，工具计时 7.583 s，
含导入的 wall 为 11.11 s，峰值 RSS 455272 KiB。
三图最大累加绝对值分别为 151774、146246、159935，均小于旧 float32 整数精确界限 2^24。
日志为 `build/npu/tl04/compare.log`。另对首层快照翻转一个输出字节，
工具报告恰好 1 个差异并返回 1，未跳过后续层；见 `build/npu/tl04/fault_compare.log`。
`py_compile`、`git diff --check` 通过；Verilog 风格检查扫描 0 个文件、0 告警，
本改动无 RTL，Verilator lint 不适用。

**mAP 进一步定位：0.623 的根因仍未查明。** 发现了两个可复现的环境敏感项，
但本次变体均未复现旧记录的 0.623；没有改变 percentile、margin、标定集或量化算法。

- 相同线程设置各重复标定两次：3 线程组的 63 层记录和模型字节完全相同，
  1 线程组也完全相同；跨组有 61/63 层量化记录不同。
  新的默认 3 线程标定与 `/tmp/npuq` 候选记录完全相同。
  因而当前证据支持**线程设置敏感**，未观察到固定线程数下的重复运行不稳定。
  初版比较器用子进程调用编译器，父进程导入 ultralytics 后设置环境变量
  `OMP_NUM_THREADS=1`，子进程据此初始化 torch 为 1 线程，造成两边重新标定结果不同；
  这不是参考算术或权重布局错误。首图首次输出差异为 desc15/旧 cmd18
  `L6.b0.cv1` 的 11 个元素，该层已有 1 个量化权重及 1 个参数字节不同。
  所以 TL-04 固定使用同一份量化结果，标定确定化策略留给后续决策。
- 当前 ultralytics 的 `non_max_suppression` 根据 `torchvision` 是否已导入，
  分别调用 `torchvision.ops.nms` 或 `TorchNMS.nms`。
  对同一批预测分别执行两条后端，旧候选的 128 次调用中有 49 次结果不同
  （32 图 × 浮点/INT8 × 两个 confidence 阈值）；后端选择确实影响当前评估数字。
  固定原 32 张验证图、225 个标注、45 个有标注类别，结果如下：

| 标定线程数 | NMS 后端 | INT8 预测数 | mAP50 | mAP50-95 |
|---|---|---:|---:|---:|
| 3（原 Linux 候选） | TorchNMS | 3953 | 0.6112938378 | 0.4655402422 |
| 3（同一候选） | torchvision | 3950 | 0.6126612881 | 0.4680217482 |
| 1 | TorchNMS | 3933 | 0.6079594176 | 0.4639375846 |
| 1（同一候选） | torchvision | 3934 | 0.6092105557 | 0.4623116645 |

标定重复实验脚本/日志为 `build/npu/tl04/calibration_study.py` 和同名 `.log`，
后三次标定 wall 合计 80.25 s；第一次默认线程标定另见 `default_compile.log`（75.509 s）。
评估脚本/日志为 `build/npu/tl04/eval_nms.py`、`eval_nms.log`（52.44 s）和
`eval_thread_variant.py`、`eval_thread_variant.log`（56.71 s）。
1 线程候选仅还原成旧物理格式交给旧算术执行，量化数值保持原样。
上述生成脚本均在 `build/`，不入库。

以下命令可独立复现标定线程实验（先完成环境安装；四次标定顺序执行）：

```sh
PYTHONPATH="$PWD/tools/npu:$PWD/third_party/ultralytics" \
    ~/.local/opt/edrv32-py/bin/python - <<'PY'
import json
from pathlib import Path
import torch
import quantize
from fixed_plan import build_plan
results = {}
for threads in (3, 1):
    for repeat in (1, 2):
        torch.set_num_threads(threads)
        quantize.CACHE = Path(f"build/npu/tl04/repeat_t{threads}_{repeat}")
        quantize.calibrate(build_plan())
        results[threads, repeat] = quantize.CACHE
for left, right in (((3, 1), (3, 2)), ((1, 1), (1, 2)), ((3, 1), (1, 1))):
    a, b = (results[key] for key in (left, right))
    rows = [json.loads((p / "quantization.json").read_text())["convolutions"] for p in (a, b)]
    print(left, right, "different rows", sum(x != y for x, y in zip(*rows)),
          "model equal", (a / "model.bin").read_bytes() == (b / "model.bin").read_bytes())
PY
```

完成 TL-04 后，以下命令用其复制的旧评估器复现原候选的两种 NMS 评估：

```sh
PYTHONPATH="$PWD/build/npu/tl04/legacy/scripts:$PWD/third_party/ultralytics" \
    ~/.local/opt/edrv32-py/bin/python - <<'PY'
import sys
from pathlib import Path
import torch
import torchvision
from ultralytics.utils.nms import TorchNMS
import yolo_v8n_eval_quant as evaluation
data = Path.home() / ".local/share/edrv32/npu"
candidate = "build/npu/tl04/legacy/out/models/yolov8n_int8_coco96_p95.bin"
for name, backend in (("torchvision", torchvision.ops.nms), ("torch", TorchNMS.nms)):
    torchvision.ops.nms = backend
    sys.argv = ["yolo_v8n_eval_quant.py", "--candidate", candidate,
                "--weights", str(data / "yolov8n.pt"), "--dataset", str(data / "coco128"),
                "--output", f"build/npu/tl04/eval_{name}.json"]
    evaluation.main()
PY
```

除上节 N-M1 已排除的布局迁移、标定图像排序、percentile/margin、预处理和 NMS 阈值外，
本次另排除了这三幅图的参考算术/旧整数算术差异及当前两种 NMS 后端足以单独解释
0.623 的假设；线程设置和 NMS 后端应随以后精度测量一并记录。
旧 Windows 原始候选、完整 eval JSON、依赖版本和实际线程/NMS 后端仍缺失，
无法将上述环境敏感项认定为旧差异的根因，结论保留“未查明”。

## NPU 后处理方案 (b)

`compile_yolo.py` 为 `D{h}.box.out/cls.out` 的六条描述符写入字 13/14；
普通描述符字 13/14/15 保持零。模型末尾追加三份 2048 B 小端表，
每份先是 256×u32 exp_q20，再是 256×u32 probability_q24；权重、量化参数和地址不变。
缓存 `model.bin` 在装载时也会按当前量化参数写入这三份表。

软件构建可直接使用仓库离线快照，仅需 Python 标准库，无需重新标定：

```sh
python3 tools/npu/compile_yolo.py \
    --model-source tasks/win/20261029-09-b3-software/src/npu \
    --out build/npu/software_model
```

showcase 的模型嵌入规则使用此入口；board_npu 的 `board_cases.py` 继续调用
`--image` 入口并打包完整镜像。demo 的 EDNM 上传使用新编译目录的完整
`mem_desc.hex` 和 `mem_model.hex`，上传格式不变。

`yolo_post_ref.py` 默认两阈值为表推导的 103/105/103 和严格 Q24 >4194304。
指定概率阈值时，未显式指定的 INT8 前筛由相同概率表推导；128 表示全拒绝。
Python API `decode_candidates(output, heads, stats=None, int8_thresholds=None,
probability_threshold=4194304)` 返回 NMS 前全部 `[xyxy_q8, probability_q24,
class_id, anchor]`；`pack_candidates` 生成连续的小端 `<4iIHH` 24 B 记录。
`postprocess_candidates` 执行 CPU 排序/NMS/映射且保留调用者的原始候选。

```sh
python3 tools/npu/yolo_post_ref.py build/npu/post_tools/output.bin \
    --candidates-bin build/npu/post_tools/candidates.bin \
    > build/npu/post_tools/candidates.json
# 可加 --int8-thresholds 110 110 110 --probability-threshold 8388608
```

JSON 包含未裁剪 signed Q8 坐标、Q24 概率、类别、全局 anchor 和最终 EDDT。
二进制文件仅含有效 24 B 记录；RTL AXI 尾拍的零填充不计入文件长度。
`check_post_tools.py` 的 TL-05、真实帧新旧路径对比和边界自检复现命令见
`docs/reports/2026-11-08-npu-post-tools.md`。

## YOLOv8n-pose 离线评估（T-POSE-EVAL）

编译入口增加 `--task detect|pose`，默认 detect；detect 的字节回归基线为
`69e96488`。pose 使用原始 cv3 中间宽度 64，末层从 1 类补成 80 类；
通道 1–79 为零权重，并直接编码整数 bias=-256、mult=1、shift=0，
在任意输出零点下饱和到 −128。cv4 的三层物理通道均为 64，逻辑通道为 51；
补齐输出权重和后续输入权重为零。末层按线性头标定，不使用激活 LUT。
三个关键点输出紧随原有六个 box/cls 输出，C16 布局与 box 相同。
OUTPUT 为 1,048,320 B，距 1 MiB 上限仅余 256 B；WORK 不变。
pose 缓存为 `build/npu/quantized_pose/`，不与 detect 缓存混用。

数据和权重来自 [Ultralytics 官方模型](https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n-pose.pt)
和 [COCO 官方 2017 标注及图像](https://cocodataset.org/#download)。
以下下载标注包（不下载完整 val2017 图像包），只提取关键点验证标注，
再按 image_id 升序选择有 person 标注的前 300 张，仅下载这些图像。
数据、权重均在 `~/.local/share/edrv32/npu/`；COCO128 标定数据沿用上面的安装步骤。
COCO 官方图像主机使用其提供的 HTTP 地址。

```sh
git submodule update --init third_party/ultralytics
python3 -m pip --python ~/.local/opt/edrv32-py/bin/python install -r tools/npu/requirements-pose.txt
mkdir -p ~/.local/share/edrv32/npu
curl -L --fail https://github.com/ultralytics/assets/releases/download/v8.3.0/yolov8n-pose.pt \
    -o ~/.local/share/edrv32/npu/yolov8n-pose.pt
curl -L --fail http://images.cocodataset.org/annotations/annotations_trainval2017.zip \
    -o ~/.local/share/edrv32/npu/annotations_trainval2017.zip
unzip ~/.local/share/edrv32/npu/annotations_trainval2017.zip \
    annotations/person_keypoints_val2017.json -d ~/.local/share/edrv32/npu
export PYTHONPATH="$PWD/third_party/ultralytics"
export OPENBLAS_NUM_THREADS=1
~/.local/opt/edrv32-py/bin/python tools/npu/pose_eval.py --download-images
~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py --task pose \
    --image ~/.local/share/edrv32/npu/val2017/000000000139.jpg \
    --out build/npu/pose_eval/compiled
~/.local/opt/edrv32-py/bin/python tools/npu/pose_eval.py \
    --out build/npu/pose_eval > build/npu/pose_eval/eval.log 2>&1
~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/npu -p test_compile.py
```

标定固定 COCO128 排序前 96 张、percentile 95、margin 1.05、torch 1 线程；
删除对应 `build/npu/quantized_pose/` 缓存才会重新标定。
FP32 使用 Ultralytics 融合模型，384 和 640 两种输入均居中 letterbox、填充 114；
INT8 直接运行 `ref/npu_ref.py` 的描述符执行器，由 `yolo_post_ref.py` 做
80 类最大值、Q24 概率、DFL、概率降序/anchor 升序排序以及严格 IoU>0.45 的 NMS。
三条路径统一 confidence>0.25、最多 100 人；这是板端工作阈值下的 COCO AP，
不是 Ultralytics 默认 confidence=0.001 验证指标。COCOeval 使用官方 17 点 OKS
sigma 和 0.50:0.05:0.95 阈值，box 指标只统计 person。
NMS 后按全局 anchor 读取原始关键点，用官方 `kpts_decode` 公式
`xy=(raw*2+cell)*stride`、`visibility=sigmoid(raw)` 解码，再逆 letterbox。

上半身偏差以框 IoU≥0.5 按 FP32 分数顺序一对一配对；
仅取 FP32 visibility>0.5 的鼻/肩/肘/腕，像素差按原图 x/y 分别缩放到 1280/720。
偏差包括 INT8 不可见的对应点；漏可见比例分母是配对人的 FP32 可见点。
另记录匹配人数和两条路径总人数，未配对人不混入像素偏差。
三套逐人预测、每图偏差和汇总分别保存在输出目录的
`fp32_384.json`、`int8_384.json`、`fp32_640.json`、
`comparisons.json`、`summary.json`。
前四张评估图以固定 800×300、128 色 PNG 并排展示两套骨架；
图片由实际预测绘制，不是生成式示意图。

性能估算沿用 `eval/npu_model.py:conv_stages` 的 MAC 日历：
每卷积 `C32输出块数×输出高度×输出像素对数×K_COUNT`；
包含 C16 尾块及关键点填充的实际计算，不计 DMA/控制/后处理开销。
pose/detect 的 MAC 周期比乘板端实测 detect 35.0 ms@180 MHz、
41.2 ms@150 MHz；这只给出估算，不代表 pose 上板测量。
