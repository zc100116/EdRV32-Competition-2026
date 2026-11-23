# R-3r 验证报告

实现提交：`20f072dcd`（`gpu: rasterizer, quad path and perspective correction`）。
环境：用户提供的仿真主机（环境不记录）。
结论：18 组自检场景全部 PASS；14 个 RTL 文件风格检查和 lint 均为 0 告警。

| 单元 | 场景数 | 每场景输出组数 | 结果 |
|---|---:|---|---|
| raster | 4 | 32813 / 32487，两种目标、各含停顿和无停顿 | PASS |
| quad | 12 | 功能 27771 / 27793；性能 2048 / 2560 | PASS |
| perspective | 2 | 各 1800，含停顿和无停顿 | PASS |

期望值调用 `tools/gpu/model/`；四 lane 的 T、Q8 UV、Q16 跨度、深度、RGB 逐位比较。
覆盖共享边恰好一次（模型核对 320 个唯一像素）、空/退化输入、非整组起点、两种目标、
裁剪和目标边界、宽 1–64、四种 x mod 4、翻转、对象 s17 位置、stop/finish 和新命令重启。
P18 覆盖全部 1024 种子索引、归一化进位、负值、零项/相消及深度/RGB 夹取。
quad 检查 PERF3：空四边形也计数；两输入源分别测试。

实测无背压单元核吞吐（不含外部纹理/目标流水线或 DDR 命令周期）：
- 三角形每拍 1 组、4 lane；两目标连续输出分别为 28480 组 / 28480 拍、28160 组 / 28160 拍。
- 对齐 16×16：连续 32 个共 2048 拍，即 64 拍/个。
- 非对齐 16×16：连续 32 个共 2560 拍，即 80 拍/个；DRAW_QUAD/对象及两目标均成立。
- 透视每拍 1 组；1800 组连续 1800 拍。

逐级结构说明见 [README.md](README.md)：70 位运算按 20/20/20/10 切片，四相位反馈；
18×18 APM 输入/乘积/输出三拍，ROM 地址/阵列/输出三拍，所有规定舍入点保持。
扫描的组反馈/lane 展开/覆盖为 4+4+2 拍，短行等待预建；quad 的位置/翻转/UV 为 3 拍。
透视数据路径为 105 拍，逐级累计 14→17→22→28→41→79→92→105；II 始终为 1。

Yosys 通用 LUT6 最大寄存边界逻辑深度：raster **10**、quad **8**、perspective **9**。
APM 和 ROM 为技术边界；通用映射把专用进位链及 CE 选择也算作 LUT。
该参考不是 Pango LUT/进位链级数或资源结论；200MHz 的物理时序尚待 PDS 测量。

复现（仿真和 Yosys 在仿真主机；风格和 lint 在本机）：
```sh
python3 tools/regress.py full --path verif/unit/gpu_raster -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_quad -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_perspective -j 1
python3 verif/unit/gpu_perspective/logic_depth.py
python3 tools/check/verilog_style.py rtl/gpu/edrv32_gpu_raster*.v rtl/gpu/edrv32_gpu_quad.v rtl/gpu/edrv32_gpu_perspective*.v rtl/tech/edrv32_rom_gpu_recip_p18.v
verilator --lint-only -Wall --top-module edrv32_gpu_raster rtl/gpu/edrv32_gpu_raster*.v
verilator --lint-only -Wall --top-module edrv32_gpu_quad rtl/gpu/edrv32_gpu_quad.v
verilator --lint-only -Wall -DSIM_MODE +incdir+rtl/include --top-module edrv32_gpu_perspective rtl/gpu/edrv32_gpu_perspective*.v rtl/tech/edrv32_rom_gpu_recip_p18.v
```

本次仿真进程均已结束，独立同步目录和构建产物均已清理；上述命令重新生成临时日志/JSON。
剩余：协调者评审 IP 包装及创建说明、Windows 生成 ROM IP、PDS 时序确认。
