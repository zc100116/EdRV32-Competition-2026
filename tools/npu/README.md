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
