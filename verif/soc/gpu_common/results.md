# T-1a GPU SoC 连接验证

环境：用户提供的仿真主机（环境不记录）。
提交：本文件所属的 `gpu_soc: SoC top and connectivity tests` 提交；
用 `git log -1 --format="%H %s" -- rtl/soc/edrv32_gpu_soc_top.v` 获取提交号。

- 顶层：GPU SoC、系统子系统副本、GPU AXI256/APB 边界、5 端口存储互连。
- 视觉项目 RTL 和文件列表未修改；sw/Makefile 只增加 SOC=gpu 的地址头选择。
- 风格：3 个新增 SoC RTL 文件，0 告警。
- 顶层与两套测试台：Verilator --lint-only -Wall，0 告警。
- ST-08：PASS，总计 665 s，仿真 608.852 s；真实启动信息、BIOS 菜单、
  UART Run 0x10000000、CHIP_ID = 0xED320002 与 SIM_EXIT 均通过。
- ST-08 首轮场景漏写 Run 地址的 0x 前缀，菜单拒绝地址；修正输入后完整重跑。
- ST-09 非 GPU 子集：PASS，总计 88 s，仿真 26.987 s。
- ST-09：4 个 ID；11 个预留媒体槽，22 次读写 SLVERR/CPU access fault。
- ST-09：PLIC 源 8、12、14、15，逐一检查 pending、claim、deassert、complete。
- GPU 槽 6、源 13 尚未验证；占位模式明确跳过，真实 GPU 集成后重跑。
- 真实 GPU 测试入口：python3 verif/soc/gpu_regs/run.py（不加占位参数）。
- IRQ 注入仅在测试台边界；功能中断验证留给 ST-11/12。
- 共用环境与软件构建接口：README.md；ST-10--14 可在各自目录提供 scenario。
- 主机工具较新，对沿用 ETH/UART 模型增加警告；例外仅限这些模型，
  顶层 RTL lint 不读取例外文件；本机与主机最终 lint 均无告警。
- 仿真构建目录按要求清理，不保留主机环境信息或原始日志。

复现（在仿真主机，工作树同步时排除 Task 指定目录）：

```sh
python3 tools/check/verilog_style.py rtl/soc/edrv32_gpu_soc_top.v \
  rtl/soc/edrv32_sys_subsys_gpu.v rtl/soc/edrv32_soc_gpu_boundary_gpu.v
python3 tools/regress.py full --path verif/soc/gpu_boot -j 1
python3 tools/regress.py full --path verif/soc/gpu_regs -j 1
```

两项回归的 test.yaml 显式选择 --gpu-placeholder；占位模型不进 RTL 文件列表。
真实 GPU 集成后删除占位文件和 test.yaml 中的 --gpu-placeholder。
