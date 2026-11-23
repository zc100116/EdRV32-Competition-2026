# R-2 几何与三角形建立

环境：用户提供的仿真主机（环境不记录）。
代码/报告提交：`gpu: geometry unit and triangle setup`（完整 commit 随 worker_done 回报）。
本报告对应的固定提交可用 `git log --diff-filter=A -1 --format=%H -- verif/unit/gpu_geometry/REPORT.md` 取得。

- 几何 PASS：63 次模型 DRAW、615 顶点、179 输出三角形，全部逐位一致。
- 无裁剪、无背压时，192 连续顶点实测输入 II=2，64 连续三角形实测输出间隔=6。
- 建立 PASS：264 输入、262 非退化输出，全部平面、边、指数及归一化梯度逐位一致。
- 建立无背压实测输入/输出 II=8；七个属性每拍发射一个，属性之间重叠。
- 覆盖随机矩阵/光照、光照上下饱和、40 位坐标饱和、近面后 1/2 顶点、四个保护面、
  完全在外、两种剔除方向、退化、负规范起点、起点/增量、背压保持、空 DRAW、stop 后复用。
- Q30 ROM 的 1024 项与模型完整种子逐位一致，读使能保持检查 PASS。
- 本地 Verilator `--lint-only -Wall`：两个顶层各 0 告警；风格：8 文件、0 告警。
- 仿真主机 Icarus `-g2001 -tnull`：两个 RTL 顶层编译 PASS；没有功能版本差异。
- 仿真进程已结束，任务构建目录已清理。

资源为结构估算，非 PDS 实测。M(a,b)=ceil(a/18)ceil(b/18)，不假设小乘法打包：

| 单元 | APM 估算 | DRM | LUT 保守代理估算 |
|---|---:|---:|---:|
| transform | 27 = 矩阵12 + 法线3 + 光照12 | 0 | 纳入下方几何合计 |
| clip | 18 = 两个40×43交点积 | 0 | 纳入下方几何合计 |
| project | 40 = 牛顿8 + XYZ18 + 视口10 + UV4 | 1 | 纳入下方几何合计 |
| 剔除 | 2 = 两个18×18面积积 | 0 | 纳入下方几何合计 |
| geometry 合计 | 87 | 1 | 约16824 |
| setup | 42 = 分子8 + 倒数积16 + 起点8 + 牛顿8 + 面积/边起点共享2 | 1 | 约6011 |

几何 4.11 原估48→87，原估未计完整视口、UV、裁剪交点及分离光照流水开销；协调者已批准87。
建立预算由协调者放宽为≤44，当前42；不采用增加选择逻辑的进一步乘法池复用。
其余单元不变时，全芯片同口径 APM=192+(87−48)+(42−16)=257/740=34.73%，协调者已确认。
LUT 沿用4.11配额与容量代理：geometry=5000+7884+(792+2112+259+777)=16824；
setup=8×(32+55)+1200+384+ceil(52384/32)+2094=6011。
52384 是16个建立上下文的总存储位数；32bit/LUT沿用设计记录，双槽输出选择保守按1 LUT/位。
上述 LUT 数字把缓冲/选择开销全额叠加在原配额上，可能重计；FF、LUTRAM、mux 的实际映射及
200MHz 时序仍须 PDS 验证；本次没有综合或时序实测，不据此宣称整 GPU 资源闭合。

复现（仓库根目录；仿真命令在上述主机执行）：

```sh
python3 tools/gpu/rom/gen_recip_q30.py
python3 tools/regress.py smoke --path verif/unit/gpu_geometry -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_setup -j 1
python3 tools/check/verilog_style.py rtl/gpu/edrv32_gpu_{geometry,transform,clip,project,project_recip,setup,setup_plane}.v rtl/tech/edrv32_rom_gpu_recip_q30.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_gpu_geometry rtl/gpu/edrv32_gpu_{geometry,transform,clip,project,project_recip}.v rtl/tech/edrv32_rom_gpu_recip_q30.v
verilator --lint-only -Wall -Irtl/include --top-module edrv32_gpu_setup rtl/gpu/edrv32_gpu_{setup,setup_plane,project_recip}.v rtl/tech/edrv32_rom_gpu_recip_q30.v
```
