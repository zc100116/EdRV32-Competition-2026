# R-4a 纹理单元验收报告

- 结论：texture、texture_ram、palette 三项单元回归全部 PASS；RTL lint 和风格检查 0 告警。
- 环境：用户提供的仿真主机（环境不记录）。
- 提交：本报告与实现同一提交，标题 `gpu: texture unit, texture RAM and palettes`。
- 提交号复现：`git log -1 --format=%H -- verif/unit/gpu_texture/report.md`。

| 实测项 | I4 | I8 | RGB565 |
|---|---:|---:|---:|
| 最近邻，无 bank 冲突，像素/拍 | 4 | 4 | 4 |
| 双线性，任意 UV，像素/拍 | 2 | 2 | 2 |
| 三线性，任意 UV，像素/拍 | 1 | 1 | 1 |

每种格式/模式连续 512 个四像素组；首末输出间隔分别为 511、1022、2044 拍。
调色板预装实测 261 拍，低于 264 拍上限；独立测试覆盖 16 次组切换和响应反压。
最近邻每种格式的 128 组定向冲突/去重测试恰好产生 64 次 PERF5 事件。
完整纹理测试合计 PERF5=648；输出反压不计入该事件。

- texture：384 个描述符配置、13,248 个四像素组，逐位对比 `texture.py`，全部 PASS。
- 覆盖三种格式/取样、8–256 所有宽高组合、每一级 mip、矩形补齐、1×1、环绕和 LOD 偏置。
- 覆盖 96 位跨度、LOD=8.0、1:1 双线性、透明清 mask、顶点调制及 quad 全局 alpha。
- 覆盖输出反压保持、空 DRAW 完成、在途 stop 排空和 finish 重新开始。
- texture_ram：196,616 次双口响应逐位匹配；所有物理行、两半边界和最后字节使能写通过。
- palette：49,152 次完整/当前组读响应逐位匹配；每拍 4 个任意组及 8 个当前组读通过。
- RAM/调色板读延迟分别为 5/4 拍；完成聚合取三个 unit_done 的 AND，含装入写提交。
- 新增 3 个固定存储包装和对应 IP 说明；PDS 时序、资源和厂商 IP 等价性尚未实测。

复现（仓库根目录；仿真命令在仿真主机执行）：

```sh
/usr/bin/python3 tools/regress.py full --path verif/unit/gpu_texture -j 1
/usr/bin/python3 tools/regress.py full --path verif/unit/gpu_texture_ram -j 1
/usr/bin/python3 tools/regress.py full --path verif/unit/gpu_palette -j 1
python3 tools/check/verilog_style.py rtl/gpu/edrv32_gpu_{texture,texture_ram,palette}.v rtl/tech/edrv32_ram_gpu_{texture_segment,palette_segment,palette_current}.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include --top-module edrv32_gpu_texture rtl/gpu/edrv32_gpu_texture.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include --top-module edrv32_gpu_texture_ram rtl/gpu/edrv32_gpu_texture_ram.v rtl/tech/edrv32_ram_gpu_texture_segment.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include --top-module edrv32_gpu_palette rtl/gpu/edrv32_gpu_palette.v rtl/tech/edrv32_ram_gpu_palette_segment.v rtl/tech/edrv32_ram_gpu_palette_current.v
```

原始日志复现位置：`build/regress/full/unit/gpu_{texture,texture_ram,palette}/iverilog/`。
仿真运行后已按任务要求清理远端进程和构建产物，日志可由上述命令重新生成。
