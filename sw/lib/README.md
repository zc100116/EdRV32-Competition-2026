# CPU YOLO 后处理与 RGB565 绘图

依据 `docs/spec/npu-spec.md` 2.2/2.5、`docs/spec/edrv32-soc-spec.md` 7.3，
以及 `docs/design/2026-10-29-b2-software.md` 3.2、3.4、3.5a。
这里仅实现纯计算；OUTPUT 的 CPU 可见性、Surface 所有权和 cache 维护由调用方负责。

## 固定数值契约（C 与 Python 共用）

本节由 B2-4a 协调者批准；调试工具 B2-5b 按本节逐项比较 EDDT。

- 输入是 OUTPUT 区原样的 725760 B，INT8_C16：
  `[16 通道平面][行][像素][16 通道]`，每平面行紧凑。
  三尺度顺序为 stride 8/16/32、宽高 80×48 / 40×24 / 20×12，
  各尺度先 box C64（四个连续 16 bin 平面，顺序 left/top/right/bottom），再 cls C80。
  共 5040 个锚点，锚点编号按尺度、行、列递增。布局来自 `tools/npu/fixed_plan.py`。
- 量化参数来自 `tools/npu/quantize.py` 写出的 `quantization.json`，
  读取 `convolutions` 的 `D{0,1,2}.{box,cls}.out` 项，
  实数 logit = `(q - output_zero_point) * output_scale`。
  生成器把每个尺度的 box exp 差值表和 cls 概率表生成并入库。
- 每锚点在 INT8 域取 80 类最大值（相同值取较低类别号），再与整数阈值比较。
  阈值为首个满足 `(q - cls_zp) * cls_scale > log(1/3)` 的 INT8 值；
  即置信度严格大于 0.25。C 不算 sigmoid，不解码未通过阈值的锚点。
- exp 表：`floor(exp(-delta * box_scale) * 2^20 + 0.5)`，delta = 0..255。
  每个 DFL 分量先减最大 bin；box 零点因此抵消。
  `distance_q8 = (sum(bin * exp_q20) * 256 + sum(exp_q20)//2) // sum(exp_q20)`。
  四个分量各做一次非负整数四舍五入。锚点中心为 `(列+0.5, 行+0.5)`，
  左上减距离、右下加距离，再乘 stride；此时框为网络输入坐标 Q8。
- 概率表：`floor(sigmoid((q-cls_zp)*cls_scale) * 2^24 + 0.5)`，
  下标为有符号 q+128。按此 Q24 概率降序排列；相同 Q24 值按锚点编号升序。
  使用迭代堆排序，无递归、无预先截断候选。EDDT 千分比分数在最终输出时计算：
  `(probability_q24 * 1000 + 2^23) >> 24`。
- 在未裁切的网络 Q8 框上按类别做贪心 NMS。
  面积使用不含端点加一的连续矩形面积；IoU 严格大于 0.45 才抑制，
  比较式为 `20 * intersection > 9 * (area_a + area_b - intersection)`。
  面积和乘阈值使用 uint64，零面积框不互相抑制。最多保留 100 框，输出维持排序顺序。
- 最后映射到显示坐标：x×2、(y−12)×2，先裁到 x=0..1280、y=0..720，
  再将 Q8 以 `(value+128)//256` 四舍五入为整数。
  右/下边界为 exclusive；1280/720 是合法边界值。
  这是 VIN CH2 的 1280×720→640×360、上下各补 12 行的逆变换。
- 每项输出 `{x0,y0,x1,y1: int16, class_id:uint16, score:uint16}`，共 12 B。
  RV32 小端布局对应 EDDT 条目；16 B EDDT 帧头由应用整合任务提供。
  算法内部信任上述固定模型契约，不做额外输入校验、兜底或候选丢弃。

## API

```c
#include "yolo_post.h"
#include "draw.h"

/* workspace 放 DDR，120960 B；输出最多 1200 B；统计结构 28 B。 */
uint32_t count = yolo_post_process(output, yolo_default_heads, workspace, detections, &stats);
draw_surface surface = {rgb565_cpu_pointer, stride_bytes, 1280, 720};
for (uint32_t i = 0; i < count; ++i) {
    draw_detection(&surface, &detections[i], 0x07e0, 0xffff);
}
```

`yolo_post_process` 接收调用方提供的 OUTPUT、三个 `yolo_head` 量化表、
5040 项 `yolo_candidate` 工作区、100 项结果区和必填统计结构；返回框数。
`yolo_default_heads` 是已入库的单线程 COCO96 标定参数；换量化模型时重新生成表。
所有 C 文件可用 C11/RV32IM 编译，无浮点、堆分配、驱动或 BSP 依赖。
DFL 的 uint64 除法使用工具链 libgcc `__udivdi3`，最终应用需链接 `-lgcc`。

`draw_fill` 填充矩形，`draw_rect` 画一像素边框，`draw_text` 用透明背景写
8×16 可打印 ASCII（32..126）；坐标均为 exclusive 右/下边界并裁切到 Surface。
空矩形没有边框。`draw_detection` 使用 COCO 80 类名、千分比显示为 `person 0.875`，
填充标签底色；标签优先放在框上方 16 行，顶端空间不足时放在框内顶端。
颜色由调用方给定。字库为 console-setup 的 public-domain `Lat15-Fixed16.psf.gz`
中 95 个 ASCII 字形，共 1520 B，生成命令见下文。

调试工具的固定 Python 接口（仅标准库依赖）：

```python
from yolo_post_ref import run
detections = run(output_bytes, quant_params)
```

`quant_params` 是 `json.loads(quantization_json.read_text())` 的原样 dict；
返回 `list[tuple[x0,y0,x1,y1,class_id,score]]`，可直接与 EDDT 条目逐项比较。
`run` 先以标准库数学函数构造与生成器相同的查表常数，之后后处理全用整数。
`postprocess(output_bytes, heads)` 另返回相同条目和运算计数，供主机测试使用。
`pack_detections` 生成小端 12 B 条目串。命令行可直接读取板上原始 OUTPUT：

```sh
python3 tools/npu/yolo_post_ref.py build/npu/yolo_post/000009/output.bin
```

## 生成与验证命令

首次准备真实权重、COCO128 和 Python 环境，按 `tools/npu/README.md`；
不需要 Verilator。所有测试产物在 `build/npu/yolo_post/`。

```sh
git submodule update --init third_party/ultralytics
export PYTHONPATH="$PWD/third_party/ultralytics"
OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python tools/npu/compile_yolo.py \
    --image ~/.local/share/edrv32/npu/coco128/images/train2017/000000000009.jpg \
    --out build/npu/yolo_post/000009
python3 tools/gen/yolo_post.py build/npu/quantized/quantization.json
python3 tools/gen/font8x16.py /usr/share/consolefonts/Lat15-Fixed16.psf.gz sw/lib/font8x16.h
python3 -m unittest discover -s tools/npu/tests -p test_yolo_post.py -v
OPENBLAS_NUM_THREADS=1 ~/.local/opt/edrv32-py/bin/python \
    tools/npu/tests/validate_yolo_post.py
python3 tools/check/verilog_style.py sw/lib tools/gen tools/npu/tests
git diff --check
```

主机测试以 gcc C11、`-Wall -Wextra -Werror -O2` 编译同一份 C，
并启用 UBSan（遇到未定义行为立即失败）。测试比较全部坐标、类别、分数、顺序和计数。
定向覆盖空帧、三个尺度阈值边界、类别/锚点同分、按类别 NMS、IoU 恰好 0.45、
极端 bin 差值 255、零面积框、letterbox 逆映射、裁切、5040 候选与 100 框上限；
另有五组完整随机 OUTPUT 和五组稀疏随机 OUTPUT。
绘图覆盖字节 stride、四边裁切、空矩形、ASCII 字形方向、95 个字符、80 类、
0.250/0.875/1.000 标签，以及标签在框上方和框内顶端的放置。

真实图像测试按原工具预处理 COCO128 图像 9、529、650，
执行 `compile_yolo.py` 和 `ref/npu_ref.py`，保存原始 `output.bin` 后逐项比较 C/Python。
再增加三组完整随机和三组稀疏随机 OUTPUT。
浮点路径直接使用子模块的 `DFL`、`dist2bbox` 和 `non_max_suppression`，
反量化同一份 INT8 OUTPUT，参数 conf=0.25、IoU=0.45、max_det=100、nc=80，
采用 TorchNMS 后端；单图时间预算设为 60 s，允许完整完成稠密随机帧 NMS。
浮点框也执行相同显示变换和裁切，但保留非整数坐标。
只对两条路径均保留的同一原始锚点且类别相同的框计算坐标/分数误差，
同时单列两边未匹配框数，避免把同分排序差异混入坐标误差。
浮点统计只记录，不作验收判据，也不评价量化模型相对原 FP32 网络的精度。

交叉编译与大小测量（与 `sw/Makefile` 一致用 `-O2`，ISA 限为 RV32IM）：

```sh
. ~/.local/opt/edrv32/env.sh
mkdir -p build/npu/yolo_post/rv32
for source in yolo_post yolo_tables draw; do
    riscv-none-elf-gcc -march=rv32im -mabi=ilp32 -std=c11 -Wall -Wextra -Werror \
        -O2 -ffreestanding -fno-builtin -fstack-usage -c sw/lib/$source.c \
        -o build/npu/yolo_post/rv32/$source.o
done
riscv-none-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -Wl,-e,yolo_post_process \
    -Wl,-Ttext,0x0 build/npu/yolo_post/rv32/yolo_post.o \
    build/npu/yolo_post/rv32/yolo_tables.o build/npu/yolo_post/rv32/draw.o \
    -lgcc -o build/npu/yolo_post/rv32/yolo_post.elf
riscv-none-elf-size -A build/npu/yolo_post/rv32/yolo_post.elf
riscv-none-elf-size build/npu/yolo_post/rv32/*.o
riscv-none-elf-nm -u build/npu/yolo_post/rv32/yolo_post.elf
```

`yolo_post_stats` 计数含义：每锚点 80 次类别 argmax 加一次阈值比较，
每次解码四组各 15 次 bin 最大值比较、16 次 exp 查表；
排序计数每次候选比较，NMS 另数类别比较和同类别 IoU 阈值比较。
由解码数 D 可得 DFL 除法 4D、bin 加权乘法 64D、加权和/权重和加法 128D。
这些都是算法运算次数；不包括地址计算、循环控制、排序比较内部的每条机器指令，
也不是 CPU 周期实测。对照设计 3.4：408240 次筛选比较若每次取 2.5–5 周期，
则估算 1.02–2.04 M 周期（100 MHz 下约 10.2–20.4 ms），
尚需加 DFL、排序、NMS、内存等待和绘图；真实周期由 B2-4b 上板另测。
