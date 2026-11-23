# V-1b2 公共时钟设置验证

结论：Case.clock_mhz 的完整传递链已在 6039213e8 实现，本次补充 TB 所选频率日志和说明。
提交：本报告所在提交（`git log -1 --format=%H -- verif/block/gpu/REPORT-clock.md`）。
输入基线：02f2642d0；GT-25 场景来自 6fccf92b4；模型来自 b3315ccb0。
环境：用户提供的仿真主机（环境不记录）。本机仅风格检查和端口契约 lint。

GT-01–25 模型对模型：25 项、125 个子场景全部 PASS。
GT-25 的 10 份配置和启动参数均为 180 MHz；其余 115 份均为默认 150 MHz。
主机上的本任务进程和构建目录已清理。

Case 默认 150；每个子场景分别生成 config.json 和带 +CLOCK_MHZ 的 sim_args.json。
runner 的 RTL 分支逐场景传入这些参数；performance.py 委托此分支，保留全部参数。
TB 用 $value$plusargs 读取 CLOCK_MHZ，半周期为 500.0/clock_mhz ns。
TB 在日志输出 GPU_CLOCK_MHZ，直接记录每次运行所选频率。

复现（python3 指主机已有、支持测试所用语法的兼容解释器）：

```sh
python3 verif/block/gpu/run.py model \
  gt01 gt02 gt03 gt04 gt05 gt06 gt07 gt08 gt09 gt10 gt11 gt12 gt13 \
  gt14 gt15 gt16 gt17 gt18 gt19 gt20 gt21 gt22 gt23 gt24 gt25
verilator --lint-only --timing -Wall --top-module edrv32_gpu_tb -f verif/block/gpu/lint.f
python3 tools/check/verilog_style.py verif/block/gpu
```

本机 lint 0 告警；变更源码语法、行宽、缩进检查通过。
首轮默认解释器不支持测试使用的字典合并语法，改用主机已有兼容解释器重跑。
模型对模型不预测时钟周期，真实 RTL 行为和性能由集成任务验证。
