# GPU raster、quad 与 perspective 单元验证

三个目录共用 `vectors.py`，期望值来自 `tools/gpu/model/` 的 v0.4 算术。
raster 比较每个 4×2 块的两行（包含零 mask）；quad 通过模型纹理探针检查直接坐标；
perspective 比较成对八个 lane 的 U/V、八个相邻差分的最大 Q16 跨度和逐像素深度/RGB。
包含 Q=0、负 Q 的未覆盖 helper、所有倒数种子、符号/舍入边界、反压、finish 和 stop 重启。
规格化独立测试以模型覆盖 23/36/66 位全部二进制边界、舍入进位、零、符号及共同 enable 停顿。

所有仿真在指定仿真主机运行：

```sh
python3 tools/regress.py full --path verif/unit/gpu_raster -j 1
python3 tools/regress.py full --path verif/unit/gpu_quad -j 1
python3 tools/regress.py full --path verif/unit/gpu_perspective -j 1
```

## 扫描流水

| 运算 | 拍数 | 数据边界 |
|---|---:|---|
| 宽加法 | 2 | 低 35 位结果、进位及未消费的高位；第二拍拼接完整结果 |
| 偏移准备 | 3 | 一拍 CSA、两拍加法；规范起点偏移每位另用一拍回写 |
| 组反馈 | 2 | 两相位分别保存偶数行和奇数行，同相位加 4gx 并转发 |
| lane 展开 | 2 | 并行加 0/gx/2gx/3gx |
| 覆盖 | 2 | 边符号/非零寄存，随后合并裁剪和左上规则 |

平面按 W=62/66/58、边按 40 位完整步进。块内先偶数行再奇数行，下一块 x 加四；
一整排块结束后 y 加二。下一排的两行种子是当前偶数行首加 2gy、3gy。
第一行先写入结果队列，第二行覆盖确定后成对提交；两行 mask 都为零时整块省略，其余零 mask 行保持配对。四边形仍为原有三拍坐标/翻转/UV 路径。

## 透视流水

从输入槽出队计：绝对值两拍，N 三拍，Q/UQ/VQ 在第 5 拍完成；倒数再用 14 拍，
U/V 乘法三拍、N 三拍，在第 25 拍完成，Q8 坐标在第 30 拍完成。
两槽入口在第二行可用后才发第一行，保证八个 lane 的 U/V 连续到达。
第一行的 U/V 寄存至第二行；每个 2×2 组并行计算四条边的 U/V 差。
subtract 为十拍（指数选择、指数差、对齐、舍入、符号、减法、绝对值各一拍，再 N 三拍），
scale 为四拍，三级一拍 maximum 树取八项最大值。结果在第 43 拍与两行 metadata 对齐。
Q8 的 32 位输出及 Q16 跨度分别使用固定输出宽度的 scale；N 的输入宽度来自平面、
36 位乘积或 23 位差值。没有逐像素偏导乘法及归一化梯度端口。

入口/出口使用 credit，算术每拍推进，出口反压不扇出到整条流水。
`logic_depth.py` 的通用 LUT6 统计只作参考，不代表 Pango 进位链或 PDS 时序。
