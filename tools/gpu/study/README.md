# GPU v2 architecture study

依据：`docs/design/2026-11-27-gpu-v2-architecture.md`。只做研究，不改RTL/规格/软件驱动。
Python 3标准库、gcc C11；仓库根目录执行，单进程编译和单线程模拟器，无额外Python包。

```sh
mkdir -p build/gpu/m4
python3 tools/gpu/study/v2_model.py > build/gpu/m4/model.log
PYTHONPYCACHEPREFIX=build/gpu/m4/pycache python3 -m py_compile tools/gpu/study/*.py
git diff --check
```

输出 `build/gpu/m4/v2-model.json`：

- `resources`：锁定PDS报告直属层次资源、优化净省额、三档逐模块分配额及CLM。
  次序为总LUT/FF/APM/DRM36K/LUTRAM，LUTRAM已经包含在总LUT；模块含子项，不重复相加。
- `vertex_comparison`：定点扩展/FP32三宽度/CPU F的资源和1灯/8灯周期公式。
- `measured_workload`：直接使用现有stress scene，C模拟器公共API读取PERF事件计数；
  纹理上传字节、状态数、原始顶点和tile/strip bbox引用数由同一场景解析。
- `performance_estimates`：三档、两灯数、方向/完整灯模型共12组合；几何、纹理、
  setup、DDR可分别查看。主机执行速度从不当作GPU速度。输入数据和成本假设都在脚本。
- `interpolation`：当前P-A/P18与Q24重心/24bit块浮点候选的屏幕插值抽样；种子20261127，
  4个既有屏幕三角形+48个生成三角形，两套不同projective texture分母，57988样本。
  UV纹素、Z u16、RGB u8分别max/RMS；此抽样未评估完整ES geometry或新增像素状态。
  P-A含整数Z/RGB读出，候选保留小数，不能把后两者小误差解释为整帧更准确。

PDS报告锁定提交 `96fd08ecee9c771f840f1ccad75a62bcb55d54fc`，来源为任务给定远端分支；
`git show <该提交>:tasks/win/20261124-107-gpu-board/artifacts/round11/resource_hier.txt`
可独立查看。脚本输出当前源码commit；复现脚本版本取设计记录同一提交。
resource向量中的v2输入是明确分配额，带约±40%不确定性，未经PDS；不构成拟合预测。
CLM=`ceil(max(LUT/4, FF/8)/0.70)`，不能等同CLMA/CLMS或布局布线成功。

外部gl4es体量的独立复现（需网络，不提取源码到工作树）：

```sh
python3 tools/gpu/study/gl4es_size.py > build/gpu/m4/gl4es-size.json
```

锁定 `8b1a3da5d2331d0f88b70be25963182d46eed857`，只统计src下.c/.h文件；
结果161文件/73142行/2933015源字节。不是固件链接体积或运行内存实测。

本轮不运行RTL lint（没有RTL变化），不运行无关CPU回归。完整ES状态参考、Mesa/Piglit
环境、微码编译trace和Windows PDS均列在设计记录的后续验证项，未声称已经运行。

## M-5 可执行微码和共享 setup

```sh
mkdir -p build/gpu/m5
python3 tools/gpu/study/m5_model.py > build/gpu/m5/run.log
PYTHONPYCACHEPREFIX=build/gpu/m5/pycache python3 -m py_compile tools/gpu/study/m5_*.py
git diff --check
```

输出 `build/gpu/m5/m5-model.json` 和 `tables.md`。约9秒、37MiB峰值RSS，单进程；
只调用一次M-4的串行C工作负载，不需要numpy、RTL仿真或远端主机。

- `m5_vertex.py`：状态选择生成可执行微码IR；DP3/4展开、物理32寄存器分配，FP32
  通过标准库struct与主机libc的fmaf舍入。每变体128个顶点逐项对照独立双精度公式，
  再断言物理寄存器程序与虚拟寄存器程序输出完全一致；含双面、透视眼坐标、两套
  texture q、用户面距离、fog和非整数spot/specular。LOOP、swizzle、abs/negate及
  掩码另有定向执行。输出`programs`可读全部物理指令，`schedule_W2L10`可读静态发射表。
  周期是四上下文固定批次重复的服务间隔；FMA8/10/12、W1/2/4全表在JSON。
  SFU延迟/II是排程输入估算，程序未编码为最终64bit二进制，不是RTL周期实测。
- `m5_setup.py`：4个49×33乘法池、4个活动属性的静态DAG，RAM字段寿命和资源公式；
  signed48工作尾数、signed24/32共享指数系数、整数64²局部域，所有宽度断言实跑。
  39个三角形（7个定向+32随机）、两个独立纹理分母；`aggregate`含系数压力探针，
  `common_covered_quantized`只含640×360共同top-left覆盖像素并匹配输出量化，
  不能把压力探针或超出现有P-A坐标域的失败当作当前RTL画面错误。
  LOD用屏幕对齐2×2 helper差分，单位为mip level，沿用既有max/RMS误差方法。
- `m5_model.py`：沿用M-4场景和DDR公式，以真实生成的双纹理灯光程序以及新setup周期
  重算三档150/200MHz；包含2000quad展开。setup全部档使用同一四池候选；满配带宽
  沿用565条件，不把RGBA8吞吐视为已验证。

结果解释、完整表格及对M-4的修正见设计记录末尾“M-5 验证”。数值误差是研究结果，
脚本不以整条表达式相对误差1e-5设通过门禁；ES §2.1.1讨论单次运算精度，非复合
pow/光照/抵消后输出的统一相对阈值。没有运行Khronos一致性、PDS或新RTL测试。
