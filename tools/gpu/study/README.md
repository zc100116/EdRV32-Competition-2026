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
