# AD-01：板级 DDR 适配器

依据 `mem-subsys-spec.md` v0.1 附录 A、SoC v0.5 3.2/4.2/5.3 和
`mem-subsys-testplan.md` v0.1 AD-01。

测试先用 128 组组合激励检查全地址范围的 `[29:2]` 换算、AW/AR/W 直通、
B 合成、R 直通、自动预充电固定 0 和初始化状态直通，再接 IP 用户端口模型。
使用独立字节参考存储，先全写初始化 8 KiB，覆盖全部 1–16 拍长度和 16 个 ID、
4 KiB 边界结尾、32 个单独字节使能、全零/全一使能，再执行 256 组随机地址、
长度、ID、字节使能和数据的先写后读，最后完整扫读 8 KiB。
随机序列种子固定为 `0x1bad2026`，两种仿真器使用同一 LFSR 序列。

测试在每个 IP WREADY 采样沿检查 SoC WVALID 和 WLAST，验证已确认的
“AW 接受后连续提供 W”契约。`delayed/` 将 `WUSER_DELAY` 设为 3，覆盖
完成脉冲出现在 WREADY 拉低之后的 B 合成。默认配置在最后一个 W 拍合成 B。
两种配置均登记为 smoke/full，均使用 Verilator 和 Icarus。

从仓库根目录只运行本任务的四项测试（调用统一回归入口的编译/判定函数，
Verilator 默认使用单编译进程，MAKEFLAGS 同时限制 make 为 1）：

```sh
. ~/.local/opt/edrv32/env.sh
MAKEFLAGS=-j1 python3 - <<'PY'
from pathlib import Path
from tools.regress import read_test, run_test
for name in ('fpga_ddr_adapter', 'fpga_ddr_adapter/delayed'):
    path = Path('verif/unit') / name / 'test.yaml'
    for sim in ('verilator', 'iverilog'):
        if not run_test(path.resolve(), read_test(path), sim, 'smoke'):
            raise SystemExit(1)
PY
```

集成回归入口为 `make smoke` / `make full`。日志保存在
`build/regress/smoke/unit/fpga_ddr_adapter/`。

```sh
make lint
python3 tools/check/verilog_style.py fpga/rtl/edrv32_fpga_ddr_adapter.v
verilator --lint-only -Wall fpga/rtl/edrv32_fpga_ddr_adapter.v
verilator --lint-only --timing -Wall --top-module tb \
    fpga/rtl/edrv32_fpga_ddr_adapter.v \
    verif/models/pango_ddr3_ip_model.sv verif/unit/fpga_ddr_adapter/tb.sv
```

单元测试证明行为模型下的契约；控制器读写顺序仍由后续真实 IP 文档/上板确认。
