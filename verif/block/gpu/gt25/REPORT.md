# GT-18–GT-25 验证结果

环境：用户提供的仿真主机（环境不记录）。
提交：`gpu: block tests GT-18..25`；精确提交用以下命令定位：
`git log -1 --format=%H -- verif/block/gpu/gt25/REPORT.md`。

- GT-18–GT-25 模型回归通过；8 个测试项，28 个独立场景。
- GT-18：42 项定向/随机对象，位置/速度回绕、寿命、存活区域、STEP=0、保留位。
- GT-19：8 个目标、18 次命中、4 次释放、9 个存活；列表容量 0、溢出、充足。
- GT-20：640×180、1280×90；AA 关闭/开启，阈值 0/1/64/255；非紧凑跨度和边界。
- GT-21：命令/顶点/纹理读及写出写错误，共 4 个场景，模型生成 ERR_CODE=2。
- GT-22：绘制/装纹理/对象/写出，共 4 个场景；按目标 AR/AW 握手后 32 周期 ABORT。
- GT-23：53 个寄存器复位/读回，RW 两组位模式、RO 写忽略、PERF1–4 功能计数。
- GT-24：固定种子 202624，12 组混合命令；三种格式、三种过滤及随机像素状态。
- GT-25：10 个测量场景；四边形、三种过滤、I4/I8 预装、顶点、建立、对象、AA 写出。
- 本机公共端口契约 lint：0 告警；Python 语法/行宽检查通过；未新增 RTL/SV。
- 性能后处理器的合成数据边界检查通过：80/81 周期/四边形、90000/90001 周期写出。
  这些数字是判据测试输入，不是 GPU 实测结果。

GT-21、22、25 的模型 PASS 仅说明场景和期望生成/导出/比对流程可运行。
AXI 事务排空、中途 ABORT、真实周期和是否达到性能指标，需要 RTL 联调确认。
PERF0/5–8 按公共环境约定只采集；模型不预测周期。PERF1–4 与模型逐位比较。
当前未取得 RTL 周期数，不对性能达标作结论；资源指标留给 PDS。

性能测量口径（协调者确认）：180 MHz，DDR 默认延迟；逐命令记录含 DDR 的总周期。
四边形及单元主导负载：总周期减同类 COUNT=0 命令的实测固定开销，除以工作数量。
四边形判定 ≤80 周期/个；两条 640×180 开 AA 的 RESOLVE 总计判定 ≤90000 周期。
其余等效速率只报告并对照第 7 节；内部无背压稳态吞吐和预装间隔由单元测试判定。
`performance.txt` 记录每条命令周期、固定开销、等效速率及 PASS/FAIL。

复现（仓库根目录；模型回归及 RTL 运行均在仿真主机）：

```sh
python3 verif/block/gpu/run.py model gt18 gt19 gt20 gt21 gt22 gt23 gt24 gt25
python3 verif/block/gpu/run.py rtl gt18 gt19 gt20 gt21 gt22 gt23 gt24
python3 verif/block/gpu/gt25/performance.py
. ~/.local/opt/edrv32/env.sh
verilator --lint-only --timing -Wall --top-module edrv32_gpu_tb -f verif/block/gpu/lint.f
python3 tools/check/verilog_style.py verif/block/gpu/gt{18..25}
```

生成物：`build/gpu/block/gt18`–`gt25`；子场景顺序见各目录 `runs.json`。
