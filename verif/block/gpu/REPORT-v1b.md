# V-1b 验证结果

结论：GT-09–GT-17 全部 PASS，89 个独立子场景，未读取 rtl/gpu 或修改模型。
测试提交：本报告所在提交（`git log -1 --format=%H -- verif/block/gpu/gt09`）。
公共 hooks 提交：15c1b8c8f、7e155beed、68be945b9、6039213e8。
模型基线：M-1c b3315ccb0，API 兼容 v0.2；期望每次重新生成。
环境：本机 Python 模型对模型（Task 明确允许），未运行 RTL 仿真。

| 测试 | 子场景数 | DDR 字节数 | Surface 区域 | 结果 |
|---|---:|---:|---:|---|
| GT-09 | 1 | 105120 | 2 | PASS |
| GT-10 | 1 | 761120 | 1 | PASS |
| GT-11 | 3 | 169248 | 9 | PASS |
| GT-12 | 54 | 4737024 | 702 | PASS |
| GT-13 | 16 | 12784128 | 1024 | PASS |
| GT-14 | 1 | 83328 | 16 | PASS |
| GT-15 | 2 | 2352640 | 2 | PASS |
| GT-16 | 8 | 308224 | 24 | PASS |
| GT-17 | 3 | 75072 | 6 | PASS |

合计：21375904 字节、1786 个 Surface 区域、1068 个功能寄存器读值。
完整九项模型流程 76.82 秒，峰值 RSS 172168 KiB（约 168.2 MiB，低于 1 GiB）。
GT-09：480 组模板状态，8 函数、6 操作、所有可达 sfail/zfail/zpass、ref/掩码/饱和。
GT-10：全部 10×10×5 混合组合各 4 组颜色/alpha/常数，另 128 组固定种子随机。
GT-11：3 格式、16 组调色板、A4=0–15；用深度/模板探针检查透明丢弃无写入。
GT-12：3 格式×3 取样×6 尺寸，全部 mip 至 1×1、偏置、环绕、相邻绘制切调色板组。
GT-13：x mod 4=0–3、宽 1–64、4 种翻转、屏外/裁剪矩形/物理目标右下边界。
GT-14：256 对相邻三角形/半透明四边形命令，同一 packed word 连续读改写。
GT-15：640×360 两条、1280×720 八条；TGT_X0=4，首条 STEP=1，其余 STEP=0。
两种拼合 Surface 和对象表均与整帧一次渲染逐位一致。
GT-16：8 种 CLEAR 开关组合；颜色、深度、模板经 RESOLVE/绘制探针观察。
GT-17：立即装入/绘制、恰好到 RAM 末端的合法操作、ERR3/4，错误后不再写 Surface。

复现：

```sh
python3 verif/block/gpu/run.py model gt09 gt10 gt11 gt12 gt13 gt14 gt15 gt16 gt17
python3 verif/block/gpu/run.py model gt01 gt02 gt03 gt04 gt05 gt06 gt07 gt08
verilator --lint-only --timing -Wall --top-module edrv32_gpu_tb -f verif/block/gpu/lint.f
python3 tools/check/verilog_style.py verif/block/gpu
```

本机端口契约 lint 0 告警；仓库工具不扫描 .sv，另对所有权内源码逐项检查行宽/缩进，0 告警。
公共 hooks：多子场景、区间/第 N 个事务读写 SLVERR、周期/取命令/AR/AW 触发 ABORT、
setup 前复位值/运行后 APB 读回、单条命令外部计时、180 MHz 选择；模型导出流程自检 PASS。
RTL 行为和周期等待集成任务验证；计时不声称是内部命令执行边界。
生成物位于 build/gpu/block/gt09–gt17；完整日志 build/gpu/v1b-final.log。
