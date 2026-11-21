# YOLO 候选后处理与 RGB565 绘图

依据 npu-spec v0.10 §2.6/4.5、SoC v0.23 §7.4/8.9。

板端 `yolo_post_candidates(candidates,count,detections,&stats)` 接收 NPU 成功 DONE 后
的有效候选，原地排序/NMS，不读取 raw OUTPUT。每条候选小端24B：四个 i32 xyxy_q8、
u32 probability_q24、u16 class_id、u16 anchor；最多5040条，独占区120960B。
CPU 接管前由调用方通过 BSP invalidate 有效记录覆盖的完整32B cache行；
再次交给 NPU 前 clean 整个候选区，CPU 不得在 NPU 所有权期间访问该区。

按 Q24 概率降序、相同概率按 anchor 升序堆排序。未裁剪 Q8 框按类执行贪心 NMS：
`20*intersection > 9*(area_a+area_b-intersection)` 才抑制，使用 uint64 面积运算，
保留最多100框，不提前截断候选。最后映射 x×2、(y−12)×2，裁至1280×720，
Q8 用 `(value+128)/256` 舍入；右/下边界 exclusive。
EDDT 分数为 `(probability_q24*1000 + 2^23)>>24`；每条最终记录12B。
UI 0.50 阈值和白名单只过滤展示副本，不改候选和 EDDT。

`stats.decoded_anchors` 现在是硬件提供的候选数，类别比较/DFL比较/exp查表均为0；
其余项继续统计 CPU 排序/NMS 比较次数。UART `decode` 是候选接管/快照开销，
硬件类别筛选及 DFL 时间已计入 NPU DONE 延迟。EDTM 字段名和偏移保持不变。

`yolo_post_process(output,heads,workspace,detections,&stats)` 仅保留供离线主机数值回归。
该入口以完整725760B raw box/cls执行类别筛选和整数DFL，板端不调用它。
`yolo_default_heads` 和表仍供离线回归使用；正常硬件模型由编译器附带相同表。
DFL 参考定义：`(sum(bin*exp_q20)*256 + sum(exp_q20)/2)/sum(exp_q20)`。

```sh
python3 -m unittest discover -s tools/npu/tests -p test_yolo_post.py -v
python3 sw/tests/npu_post/host_test.py
make -C sw/tests/showcase/vision test runtime
```

新增主机测试使用 `tools/npu/yolo_post_ref.py` 生成两帧完整候选和最终 EDDT，
并覆盖 IoU=.45 及两侧、异类同框、概率/anchor顺序、负坐标、100框上限和所有
1..5040条记录的cache行范围。SoC 程序为 pp_sw_01/02，入口在 verif/soc/pp_sw_01/02。

`draw_fill` 填充矩形，`draw_rect` 画一像素边框，`draw_text` 用透明背景写
8×16 可打印 ASCII（32..126）；坐标均为 exclusive 右/下边界并裁切到 Surface。
空矩形没有边框。`draw_detection` 使用 COCO 80 类名、千分比显示为 `person 0.875`，
填充标签底色；标签优先放在框上方 16 行，顶端空间不足时放在框内顶端。
颜色由调用方给定。字库为 console-setup 的 public-domain `Lat15-Fixed16.psf.gz`
中 95 个 ASCII 字形，共 1520 B，生成命令见下文。

以下为软件 DFL 路径的历史测量，不代表当前硬件候选路径的性能。

## B2-4a 验证结果（2026-10-29）

代码提交：`6c36a14`，分支 `zc100116/task-yolo-post`；本节为该提交的测量记录。
主机 GCC 13.3.0、Python 3.12.3；真实模型环境 torch 2.14.1+cpu、numpy 2.5.2、
ultralytics 8.4.160（子模块 `9d25f80daa5b3af71c16521eba353cb6e7fb66e2`）。
标定固定单线程，原始 96 张 COCO128，未改模型量化或既有工具。
目标为 RV32IM/ILP32；本任务没有 FPGA、Verilator 或上板测量。

- 上述 unittest 命令：9/9 PASS（18.826 s），29 份定向/随机 OUTPUT 的
  坐标、类别、分数、顺序、全部七项运算计数 C/Python 完全一致；绘图测试全部通过。
- 上述真实/浮点比较命令：9/9 帧 C/Python 完全一致（含 `run` 公共接口），
  三张真实图像额外执行了各 68 条 NPU 描述符；六张随机帧与主机测试部分重叠。
  合计 32 种不同后处理输入全部通过，无 UBSan 报错。
- 交叉编译 C11、`-Wall -Wextra -Werror`：零告警；最终 ELF 无未解析符号。
  `py_compile`、`git diff --check` 通过，仓库 Verilog 风格检查 0 文件、0 告警；
  本次无 RTL，Verilator lint 不适用。

日志和原始数据：`build/npu/yolo_post/{host.log,host_stats.json,validate.log,`
`float_comparison.json}`；三张图的 `000009/`、`000529/`、`000650/` 下有编译镜像、
`ref_out.hex` 和原始 `output.bin`。`rv32/` 下有目标对象、ELF 和 `.su` 栈使用记录。
全部均可用前文命令重建，不入库。

### 浮点差异（仅记录）

| 输入 | 定点/浮点框数 | 框数差 | 共同锚点且同类 | 未匹配框（定点/浮点） | 最大显示坐标误差/像素 |
|---|---:|---:|---:|---:|---:|
| COCO 000009 | 5 / 5 | 0 | 5 | 0 / 0 | 0.5859375 |
| COCO 000529 | 2 / 2 | 0 | 2 | 0 / 0 | 0.6059570 |
| COCO 000650 | 2 / 2 | 0 | 2 | 0 / 0 | 0.6079102 |
| random_full_0 | 100 / 100 | 0 | 89 | 11 / 11 | 0.6131592 |
| random_sparse_0 | 100 / 100 | 0 | 100 | 0 / 0 | 0.6066284 |
| random_full_1 | 100 / 100 | 0 | 97 | 3 / 3 | 0.6241455 |
| random_sparse_1 | 100 / 100 | 0 | 99 | 1 / 1 | 0.6241455 |
| random_full_2 | 100 / 100 | 0 | 86 | 14 / 14 | 0.6219482 |
| random_sparse_2 | 100 / 100 | 0 | 99 | 1 / 1 | 0.6219482 |

三张真实图全部框均对应同一锚点、同一类别；最大坐标误差 0.60791015625 像素。
九帧整体共同框的最大坐标误差 0.6241455078125 像素，
最大千分比分数误差 0.49979162216186523。
随机帧有不同保留锚点，已单列未匹配数量；误差数值不包含这些框。
这些数据比较同一份 INT8 输出的定点/浮点后处理，不代表原 FP32 网络的检测精度。

### 每帧算法运算量（用于周期估算，非周期实测）

所有帧类别筛选均为 408240 次（5040×81）。下表为独立算法计数：

| 输入 | 解码锚点 D | DFL bin 比较 | exp 查表 | DFL 除法 4D | 排序比较 | NMS 类别比较 | IoU 比较 |
|---|---:|---:|---:|---:|---:|---:|---:|
| COCO 000009 | 37 | 2220 | 2368 | 148 | 270 | 95 | 54 |
| COCO 000529 | 20 | 1200 | 1280 | 80 | 112 | 28 | 18 |
| COCO 000650 | 17 | 1020 | 1088 | 68 | 88 | 22 | 15 |
| random_full_0 | 5039 | 302340 | 322496 | 20156 | 108443 | 496373 | 6256 |
| random_sparse_0 | 213 | 12780 | 13632 | 852 | 2652 | 15775 | 181 |
| all_max | 5040 | 302400 | 322560 | 20160 | 109100 | 387066 | 387066 |

逐帧完整数值见两个 JSON 结果文件；解码、排序和 NMS 会随输入变化。
设计 3.4 的 1–2 M 周期估算只覆盖类别筛选，不能作为整帧后处理实测延迟。

### RV32IM 大小（字节）

工具：xPack `riscv-none-elf-gcc` 15.2.0，前文 `-O2` 配置，未使用 LTO 或压缩指令。

| 项目 | 指令 `.text` | 只读数据 | 合计 |
|---|---:|---:|---:|
| `yolo_post.o` | 2088 | 0 | 2088 |
| `yolo_tables.o`（三尺度量化参数/查表） | 0 | 6216 | 6216 |
| `draw.o`（含 1520 B 字库、COCO 类名和指针） | 1640 | 2599 | 4239 |
| 只链接后处理/查表与 libgcc | 3196 | 6472 | 9668 |
| 三模块与 libgcc 完整链接 | 4828 | 9068 | 13896 |

链接包含 libgcc 的 `__udivdi3` 及其依赖和 256 B 除法常数；链接松弛/对齐导致
总量与对象简单求和略有差异。两个 ELF 均另有 40 B `.eh_frame`，
因此完整链接的装载内容为 13936 B；`.data`/`.bss` 为 0。
静态栈记录：`yolo_post_process` 128 B，`sift`/`swap` 各 32 B，
`draw_detection` 80 B、`draw_text` 48 B；这些为各函数自身帧，不含被调函数或 libgcc。
调用方工作区 120960 B 必须放 DDR，结果区最多 1200 B。

后处理含表和除法约 9.44 KiB，高于设计 3.1 的约 6 KiB **估算**；
完整后处理/绘图/字库/类名约 13.57 KiB（另加 40 B `.eh_frame`）。
此前没有这些库的大小基线；演示程序的 SRAM 总占用与板上周期留给 B2-4b 整合核实。
