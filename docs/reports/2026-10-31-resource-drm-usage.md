# DRM 使用量测量（T-DRM1）

| 条件 | 值 |
|---|---|
| RTL commit | `31e21bd11ade4e967caf4e3bf885f709c2343d63` |
| 探针提交 | `e966d2d49dce001f48304634729690c359ca5424` |
| 探针 | 同分支 `verif/common/drm_budget.py`、`edrv32_drm{,_level}_probe.sv`；只读 bind，不改变判定 |
| 环境 | 用户提供的仿真主机（环境不记录） |
| 目标 | PG2L200H-6/FBB676；NPU 150 MHz，mem 125 MHz，DISP 74.25 MHz |
| 工具 | 现有 Verilator 流程，`-Wall -j 1`；不记录主机工具版本；本轮没有新 PDS |
| 统计 | RAM写/读地址闭区间；FIFO最高占用项数；NPU已分配行槽；无访问记−1 |
| 日志 | `build/drm_budget/<模块>/<baseline或扫描名>/<tier>-usage.txt`；原runner日志位置不变；主机构建按要求清理，仅保留本报告自主汇总 |

所有命令在仓库根执行并先 `. ~/.local/opt/edrv32/env.sh`；本机复现仿真命令加 `flock /tmp/edrv32-sim.lock`，不加 `--parallel`。
NPU真实负载准备：`python3 verif/block/npu/run.py --test NET-01 --prepare-only`（既有依赖/模型和COCO128首张图），再用下表命令；68描述符、63 CONV/3 POOL/2 UPSAMPLE，参考模型逐字节检查。

| 负载 / 对象 | 测量结果 | 命令（统一前缀 `python3 verif/common/drm_budget.py`） |
|---|---|---|
| NPU整网，权重/行/scratch/LUT/量化/结果/残差 | PASS；PERF0=6955048（46.366987 ms）；行0…799/bank、槽峰5；权重段写511/511/127；scratch平面0…119、行0…19；LUT0…2047；量化/结果/残差0…31 | `npu NET-01 --case-dir build/npu/yolo` |
| NPU整网，scratch共享模型 | PASS；PERF0=6955048，与基线Δ0；平面/行共用一个物理槽，原逻辑地址与输出一致，同拍读/写端口峰1/1 | `npu NET-01 --case-dir build/npu/yolo --share scratch` |
| NPU尾段128深模型 | PASS；PERF0=6955048，与基线Δ0；8个第三段128项，另16段保持512 | `npu NET-01 --case-dir build/npu/yolo --weight-tail` |
| NPU容量边界 | PASS三例；行写0…1023；行槽峰L15.split=2、K1=2、K3=4 | `npu CP-02` |
| RND smoke，26个原用例 | PASS；DRAW在用bank峰2；DRAW/BLIT/COPY活动引擎峰1；source/source_next使能读可达511（含屏蔽的采样）；目标/结果在小图用例最大4 | `rnd smoke` |
| RND perf，8个原用例 | 延迟0：PERF0=125297/64097/269217/502001；延迟40：125336/64136/269334/1911001（依次ARGB填充/RGB填充/BLIT/1000字形） | `rnd perf` |
| RND共享并浅化模型，同8例 | PASS；8例PERF0逐项相同，Δ=0；共享BLIT/COPY源RAM且DRAW目标/结果按64项寻址 | `rnd perf --share rnd` |
| RND共享并浅化 smoke | PASS，26例原判定通过 | `rnd smoke --share rnd` |
| VIN CH0/1与内存源，720p及VI-01…17 | PASS VI-01…17；正常720p VI-01 CH0峰16；CH0/1峰512（故障注入），msrc峰249；环读写0…511；共116341667 mem边沿；CH2未启用，由下一项覆盖 | `vin full` |
| VIN CH2，1280×720输入 | PASS VI-19…23；CH2正常VI-19峰479，故障注入峰512，最后VI-23峰132；行读写0…639，FIFO0…511；共117365832 mem边沿 | `vin_ch2 full` |
| GEO，1280×720输出、45°、s=1/2 | PASS；PERF0=1209097/2458837，即9.672776/19.670696 ms；写0…203，读使能0…2047；源组峰2 | `geo perf` |
| PIX，1280×720两级滤波 | PASS full 25场景；四RAM读写0…639；PX-07含3个720p帧，共1388047 mem边沿 | `pix full` |
| DISP，两层720p完整扫描 | PASS DS-06；L0/L1最高326/500项，地址0…511；扫描1帧，读空0/0；共4152687 mem边沿 | `disp frame` |
| mem_xbar既有smoke | PASS；1866 mem边沿；读credit峰128、地址0…127；W占用P1…P6=16/3/4/16/16/16，W地址最大15 | `mem_xbar smoke` |
| SRAM既有smoke | PASS 1555检查；7757 sys边沿；读0…8191、写0…3 | `sram smoke` |

| 压缩对照（同一主机） | 结果 | 命令（同上前缀） |
|---|---|---|
| GEO：128→64位分两拍写 | 53 smoke+2 perf全部PASS且周期逐项Δ0；待拆写项峰3/2、物理同址读写0；720p仍9.672776/19.670696 ms | `geo smoke --pack-geo`；`geo perf --pack-geo` |
| PIX：36+12位拼接 | full 25场景全部PASS，周期逐项Δ0；PX-07仍1388047 mem边沿 | `pix full --pack-pix` |
| NPU：252+4位拼接，同时LUT缩2048 | 整网PASS；PERF0=6955048，Δ0 | `npu NET-01 --case-dir build/npu/yolo --pack-npu-line --scan edrv32_ram_npu_lut 2048` |
| NPU行裁为512（预期否决） | 原CP-02输出比较失败：addr=0x01020000，expected=7f、actual=80；退出非0 | `npu CP-02 --scan edrv32_ram_npu_line 512` |
| SRAM裁为4096（预期否决） | 初始化文件@0x1fff超出4096项，readmem越界退出非0，未进入事务检查 | `sram smoke --scan edrv32_ram_sram 4096` |

NPU模型条件：`MEM_MODE=bw`，首拍94 mem周期、共享读写1400 MB/s、8在途；这是现有整网三档中最慢档。GEO perf：首拍40周期、模型共享1.2 GB/s；RND perf：0/40周期、无随机反压；VIN full包含随机AW/W/B反压与刻意停写溢出场景，故全套水位不代表正常帧水位。DISP延迟条件随原用例，PIX无DDR接口。
各模块模型参数不能合成为全SoC最坏等待上界；现有SC-05仅3个CONV，未覆盖整网和全部媒体720p同时争用；本轮未取得对应SoC最坏DDR配置测量，不用模块水位批准缩FIFO。

历史三卡工具为仓库结果注明的PDS 2022.2-SP6.1；器件同上。

| 历史资源核对（当量） | commit / 条件 | 原始来源 |
|---|---|---|
| B3F：325；CPU6/SYS20/MEM28/NPU156/VIN17/PIX11/GEO16/DISP8/ETH3/RND60 | RTL `05088f4b`，综合；原结果提交`2f43834d` | 卡10分支 `tasks/win/20261030-10-b3-timing-rerun/artifacts/B3F/resource_hier.txt` |
| B3R：110；CPU6/SYS20/MEM16/DISP8/RND60 | 结果注明检出`3a344936`，未核验源码/报告时间；PnR | 卡14分支 `tasks/win/20261030-14-b3r-rnd/artifacts/resource_hier.txt` |
| B3N：210；CPU6/SYS20/MEM28/NPU156 | 检出`3a3449369d078e38951201f74caff76489f5c17c`；PnR | 卡15分支 `tasks/win/20261030-15-b3n-rerun/artifacts/resource_hier.txt` |

取数提交：卡10 `2f43834d5d5a2759f200c7c4a86e020125748b61`，卡14 `b786eefc6e124380073ff505d09e0bcd844aa570`，卡15 `d1e4c6d7e8b2a493f8b42b64f4699c7721499529`。

验证：上述所有基线/正向变体原判定PASS；NPU行512和SRAM4096两项为有意否决的容量扫描，退出非0，未修改原判据。
RND最终验证：8 perf+26 smoke PASS，8项PERF0对基线逐项Δ0；NPU RG-01 smoke PASS，GEO smoke 53 PASS，PIX smoke及full PASS，VIN full/CH2 full PASS，DISP原smoke参考模型及DS-06 PASS，mem_xbar/SRAM smoke PASS。
`python3 tools/check/verilog_style.py verif/common/edrv32_drm_probe.sv verif/common/edrv32_drm_level_probe.sv`：2文件0告警；两探针单独Verilator `--lint-only --timing -Wall -j 1` 为0告警；Python `py_compile`通过。
