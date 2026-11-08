# NPU 后处理离线工具验收（2026-11-08）

- 提交：本报告所属 `npu: add offline postprocessing tables and candidate oracle`；旧路径基线 `65ea90ac5b3ddf573fc5569dde84b3385180667d`。
- 环境：Linux host、Python 3、torch 2.14.1+cpu；标定/BLAS 单线程，无 RTL 改动，Verilator lint 不适用。
- 六个检测头增加字 13/14 标签和配对 LUT 偏移；62 个普通描述符保持零；字 15 全零。
- 三表起点 0x317b00/0x318300/0x318b00；原模型 3242752 B 逐字节不变，追加 6144 B 后为 3248896 B。
- TL-05 PASS：68 条描述符逐字比对，三份表共 1536 个 u32 与 yolo_tables oracle 一致，21/25 bit、概率 1=2^24。
- COCO128 `000000000009.jpg`：新旧 raw 725760 B、37 条完整候选、5 条 EDDT、全部统计逐字段一致；24 B 记录逐字段回读通过。
- 阈值 PASS：默认 103/105/103、Q24 严格 >4194304；四个概率阈值遍历全部 INT8 值，等号、128 全拒绝、0/5040 候选通过。
- 现有编译器 12 项、C/Python 后处理 9 项单测通过；Python 语法/100 列/无 Tab、`git diff --check` 通过。
- 软件镜像：`python3 -S` 离线重建通过；showcase model.c 两个数组逐字节一致；board_npu 重定位后 725760 B 输出一致，完整包含三表；demo EDNM 上传格式不变。
- 原始数据：`build/npu/post_tools/{output.bin,candidates.bin,eddt.bin,ref_out.hex}`；旧路径 `build/npu/post_tools_legacy/`；嵌入文件 `build/showcase/model.c`。

复现（ultralytics 子模块须已初始化；本机复用 `../b3-int/third_party/ultralytics`）：
```sh
export PYTHONPATH=../b3-int/third_party/ultralytics OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 MKL_NUM_THREADS=1
TASK_PY=$HOME/.local/opt/edrv32-py/bin/python
TASK_IMG=$HOME/.local/share/edrv32/npu/coco128/images/train2017/000000000009.jpg
mkdir -p build/npu/legacy_source
git archive 65ea90ac5b3ddf573fc5569dde84b3385180667d tools/npu | tar -x -C build/npu/legacy_source
$TASK_PY tools/npu/compile_yolo.py --image "$TASK_IMG" --out build/npu/post_tools
$TASK_PY build/npu/legacy_source/tools/npu/compile_yolo.py --image "$TASK_IMG" --out build/npu/post_tools_legacy
flock /tmp/edrv32-sim.lock $TASK_PY tools/npu/ref/npu_ref.py build/npu/post_tools
flock /tmp/edrv32-sim.lock $TASK_PY tools/npu/ref/npu_ref.py build/npu/post_tools_legacy
flock /tmp/edrv32-sim.lock $TASK_PY tools/npu/check_post_tools.py --case build/npu/post_tools --legacy-case build/npu/post_tools_legacy --legacy-ref build/npu/legacy_source/tools/npu/yolo_post_ref.py
$TASK_PY -m unittest discover -s tools/npu -p test_compile.py
flock /tmp/edrv32-sim.lock $TASK_PY -m unittest discover -s tools/npu/tests -p test_yolo_post.py
python3 -S tools/npu/compile_yolo.py --model-source tasks/win/20261029-09-b3-software/src/npu --out build/npu/software_model
make -C sw/tests/showcase/vision "$PWD/build/showcase/model.c" -j 1
```
