# X-1：5 端口 mem_xbar 验证报告

结论：ST-01、ST-02、ST-03 全部 PASS；共 47 次仿真，0 FAIL。
环境：用户提供的仿真主机（环境不记录）。
Commit：`mem_xbar: 5-port variant for the GPU SoC`（本报告所属提交）。
取得提交号：`git log -1 --format=%H -- verif/block/mem_subsys_gpu/REPORT.md`。

改动要点：
- xbar：五端口 P0 DISP、P1 AUD（只读）、P2 CPU、P3 GPU、P4 ETH；移除原 P4/P5。
- sched：端口掩码/循环缩至 5，ETH 令牌桶从 P6 移至 P4，P2 保持原样。
- rbuf：只缩减端口维度；128 拍环形缓冲、8 个描述符和按序释放保持原样。
- regs：复位值按 GPU SoC 6.2，删除 p=5/6 的参数/统计银行；地址读零、写忽略。
- subsys：保留 DDR 网关，删除无用端口/区域复位副本，ETH 接 P4；下游 ID 保持 4 位。
- 调度规则、流控、统计时序及错误处理沿用原实现；视觉项目文件未修改。

结果：
- ST-01：原单元测试 3 次仿真、原模块/环境测试 42 项全部 PASS，含 20 个随机种子。
- ST-02：5 个端口 × 2 个本地 ID；ERR_PORT=0–4；p=5/6 读零/写忽略全部 PASS。
- ST-02 ETH：P4 共 512 拍、9466 周期（初始桶 32 拍），通过 13/256 限速判据。
- ST-03：2048 笔授权、160826 周期；P0/P1 各 256 次紧急授权；协议检查 0 错误。
- BW-01：65536 拍 / 69650 周期，有效利用率 94.093%。
- 功能覆盖：94/94 bins；在途上限：9/9；统计饱和由单元 full 覆盖。
- 本地风格：5 个 RTL 文件，0 告警；本地及主机 RTL lint：0 告警。

复现命令（仿真命令在仿真主机运行）：
```sh
python3 tools/regress.py smoke --path verif/unit/mem_xbar_gpu -j 1
python3 tools/regress.py full --path verif/block/mem_subsys_gpu -j 1
python3 verif/block/mem_subsys_gpu/coverage.py build/regress/full/block/mem_subsys_gpu
python3 tools/check/verilog_style.py rtl/mem/edrv32_mem_xbar*_gpu.v rtl/soc/edrv32_mem_subsys_gpu.v
(cd rtl/filelists && verilator --lint-only -Wall -DSIM_MODE --top-module edrv32_mem_subsys_gpu -f mem_subsys_gpu.f)
```
模块 full 命令包含全部 smoke 测试；ST-03 仅 full。
主机工具差异：可变非零时钟延迟使用 `--no-sched-zero-delay`；Icarus 所需声明移至引用之前。

逐文件 `git diff --no-index --stat 原文件 GPU文件`：
```text
 rtl/mem/{edrv32_mem_xbar.v => edrv32_mem_xbar_gpu.v} | 363 ++++++++++++++++++++++-------------------------------------
 1 file changed, 133 insertions(+), 230 deletions(-)
 rtl/mem/{edrv32_mem_xbar_sched.v => edrv32_mem_xbar_sched_gpu.v} | 104 +++++++++++++++++++++++------------------------
 1 file changed, 51 insertions(+), 53 deletions(-)
 rtl/mem/{edrv32_mem_xbar_rbuf.v => edrv32_mem_xbar_rbuf_gpu.v} | 94 +++++++++++++++++++++++++-------------------------
 1 file changed, 47 insertions(+), 47 deletions(-)
 rtl/mem/{edrv32_mem_xbar_regs.v => edrv32_mem_xbar_regs_gpu.v} | 188 ++++++++++++++-----------------------------------
 1 file changed, 51 insertions(+), 137 deletions(-)
 rtl/soc/{edrv32_mem_subsys.v => edrv32_mem_subsys_gpu.v} | 234 +++++++++----------------------------------------------
 1 file changed, 38 insertions(+), 196 deletions(-)
 rtl/filelists/{mem_subsys.f => mem_subsys_gpu.f} | 10 +++++-----
 1 file changed, 5 insertions(+), 5 deletions(-)
```
未完成项：无；等待协调者逐行评审。
