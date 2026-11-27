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

## M-6 吞吐、表容量和跨指令调度

```sh
mkdir -p build/gpu/m6
python3 tools/gpu/study/m6_model.py > build/gpu/m6/run.log
PYTHONPYCACHEPREFIX=build/gpu/m6/pycache python3 -m py_compile tools/gpu/study/m[56]_*.py
git diff --check
```

单进程约37秒、峰值约65MiB，只串行运行一次M-4 C场景，无远端依赖。
输出 `build/gpu/m6/m6-model.json` / `tables.md`，不提交生成物。

- `m5_setup.py`仅抽出可复用的DAG/39三角形语料，precision允许传入候选求值器和
  边界探针；原入口行为/默认语料保持不变，M-6入口断言原165/213周期未变。
- `m6_setup.py`运行4/6/8池、1/2/4/8在途和2/8规格化端口，每配置512三角形；
  中间256个退休样本计算平均间隔，JSON保留首两三角形发射表及退休间隔范围。
  该模型限制算术/行口，不模拟scratch具体bank地址冲突；不要当作物理严格II证明。
  源记录使用48位系数、60位无舍入整数重定位，共用SFU64项RCP种子；重新跑M-5
  语料加跨64边界±1/helper探针，并检查780组原始整数边界恒等式和全部定宽。
- `m6_sfu.py`比较小表/五阶和原表，9280有效bit可打包在单DRM，两条FP32算术核心
  模4预约给出II4混合请求的无冲突模型；算术延迟46/67/87/77是200MHz结构预算。
  用原M-5完整数值序列再次运行小表模型，广域pow仍有1.031e-5样本，设计记录引用
  ES §2.1.1解释复合误差，未掩盖或声称通过CTS。
- `m6_vertex.py`在SSA上进行16条前视的跨指令静态列表调度，再分配32物理寄存器。
  14变体×16输入×W1/2/4逐输出断言原程序、重排、物理执行完全一致；两套SFU延迟
  独立产出表。灯循环真实展开相对常量索引执行，保留颜色循环携带值；比较40/96/208
  静态字数与87/465/946完全展开字数。程序96bit行包含四context的32bit静态等待。
- `m6_model.py`重算逐模块三档资源、压缩默认候选及帧预算。资源均为结构估算±40%，
  帧预算计源平面DDR写一次/按F读取和UI平面流量；默认性能档超过44k LUT，不能
  用模型表宣布满足资源目标。完整结论见设计记录末尾第8节“M-6”。

没有改RTL，不运行无关RTL lint或CPU回归；没有改规格、驱动或加入运行保护路径。
