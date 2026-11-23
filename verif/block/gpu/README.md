# GPU block verification

依据 gpu-spec v0.2、gpu-testplan v0.2；不读取 GPU RTL。测试观察点仅为 AXI DDR
与 APB 寄存器。片上颜色经 RESOLVE 导出；深度通过后续 LEQUAL 绘制探针转为颜色，
再 RESOLVE。GT-08 覆盖 d-1/d/d+1；新增模板测试同样用模板条件绘制探针。

在仓库根目录执行（运行、回归在用户提供的仿真主机，环境不记录）：

```sh
python3 verif/block/gpu/run.py model            # GT-01–08 模型对模型
python3 verif/block/gpu/run.py generate gt06    # 生成输入和期望
python3 verif/block/gpu/run.py compare gt06     # 比较已有导出
python3 verif/block/gpu/run.py rtl gt06         # 集成 RTL 后编译、运行、比较
python3 tools/regress.py smoke -j 1 --path verif/block/gpu
```

`files.f` 通过 `-f rtl/filelists/gpu.f` 使用真实 RTL（文件列表里的路径相对其所在目录）。
RTL 尚未提供时，本机只做端口契约 lint：

```sh
. ~/.local/opt/edrv32/env.sh
verilator --lint-only --timing -Wall --top-module edrv32_gpu_tb -f verif/block/gpu/lint.f
python3 tools/check/verilog_style.py verif/block/gpu
```

`lint/edrv32_gpu.sv` 只提供规格第 3 节公共端口、输出常量；不参与 RTL 文件列表，
没有 GPU 行为。`lint.vlt` 仅豁免验证过程的阻塞赋值、共用 APB 接口未用槽、
共用检查器的整数索引未用位及两个共用组件的复位采样方式差异，不豁免 DUT。
仓库风格工具只扫描 `.v/.vh`；本环境 `.sv` 的文件头、缩进和行宽另行检查。

生成物全部在 `build/gpu/block/<gtNN>/`：

- `initial.hex`：从 control.txt 的 DDR 基址开始，每行一个小端 32 位字。
- `commands.bin`、`writes.json`：32 B 命令列表、按名称表示的有序 APB 写入。
- `control.txt`：基址、字数、写入数、采样数；随后数值 APB 写入和采样偏移。
- `completion.txt`：期望 IRQ_STAT，正常 DONE 或指定错误；错误不计作 DONE。
- `expected.ddr.hex`、`expected.regs.json`：完整期望 DDR、功能寄存器。
- `regions.json`、`expected.regionN.bin`：Surface、对象表、命中/释放列表的区域和期望。
- `actual.ddr.hex`、`actual.regs.txt`：testbench 导出；比较后拆出 `actual.regionN.bin`。

比较覆盖全部 DDR 字节（含未写区域）、状态、完成计数、对象计数和 PERF1–4。
PERF0、5–8 保存于 actual.regs.txt，只采集不判定，模型不预测周期数（协调者确认）。
GT-06 额外按数学覆盖区域检查每像素恰好累加一次，并检查退化三角形不贡献像素。

APB host 按 SETUP/ACCESS 驱动，写 ENABLE、IRQ_EN、DESC_BASE/COUNT 后 DOORBELL，
轮询 IRQ_STAT 并检查 irq_o，等待统计计数稳定后导出。独立 AXI/APB 协议检查器全程运行；
完成时不得存在未完成 DDR 事务。testbench 总超时为 2,000,000 个 GPU 时钟。

DDR 模型复用共用 AXI256 接口/检查器，存储体放在本目录，支持独立读写、32 B/拍、
1–16 拍、任意 WSTRB 和响应背压。每个方向一个在途事务，顺序响应；ready 由固定种子
LFSR 随机扰动，R/B 延迟独立扰动。直接运行生成的 sim 时使用：
`+CASE_DIR=<生成物绝对目录> +SEED=202606 +MEM_LAT=3 +MEM_JITTER=5`。
`+MEM_RERR=<十六进制字节地址>` / `+MEM_WERR=<地址>` 对覆盖该地址的事务注入 SLVERR；
需生成对应错误期望后使用。SEED 来自 test.yaml，延迟默认 3，随机增量 0–5。

新增一个已分配测试需要三步：

1. 新建 `gtNN/scene.py`，实现 `build(case, rng)`；用 `case.scene` 的 Scene API
   生成命令和 APB 配置，使用 `case.resolve()` 观察渲染结果。每次 SET_TARGET 显式设置 VP_*。
   对象表/列表把 `{address, size, kind}` 加到 `case.regions`；可向 case.checks 添加模型断言。
2. 复制一个 `test.yaml` 和 `files.f`，修改 runner 的 gtNN、固定 seed、档位；不新增顶层。
3. 执行 `run.py model gtNN`；RTL 就绪后执行 `run.py rtl gtNN`，检查自检 PASS。
   单个测试可追加多次 RESOLVE 保留中间结果；同一构建组串行，构建目录可复用。

## 子场景和观测 hooks（V-1b）

`build(case,rng)` 的主场景仍写入 `<gtNN>/`；向 `case.runs` 追加 `Case()` 实例，
依次执行独立复位的子场景 `run01/`、`run02/`。每个实例自行调用 `ready()` 和设置状态。
生成的 `runs.json` 是执行顺序，generate/model/rtl/compare 都按该顺序处理。

- `case.axi_errors['read'|'write'] = {'first': a, 'last': b}`：闭区间字节地址。
  AXI 事务覆盖该区间时返回 SLVERR；读、写可以分别设置。
- `case.axi_errors['read'|'write'] = {'nth': n, 'model_address': a}`：第 n 个 AR/AW
  事务（从 1 开始）返回 SLVERR。模型没有 AXI 事务划分，`model_address` 显式指定
  对应模型访问的字节地址；不把模型调用次数当作 AXI 次数。仅在执行命令时注错。
  直接运行 sim 使用 `+MEM_RERR=a +MEM_RERR_LAST=b` 或 `+MEM_RERR_NTH=n`，写侧用 WERR。
- `case.abort = {'cycle': n}`：从 DOORBELL 被 APB 接收的周期起，经过 n 个时钟后
  发起 CTRL=5（ENABLE|ABORT）写入。APB 传输本身还需要 SETUP/ACCESS 周期。
- `case.abort = {'command': n, 'after': d}`：第 n 条命令（从 1 开始）的地址第一次
  被 AR 请求覆盖后经过 d 个周期发起 ABORT。这是**取命令**事件，不能解释为内部执行边界。
  已发事务排空、STATUS.BUSY 清零后采样。模型不执行中途 ABORT；此类场景必须设置
  `case.compare_ddr=False`、`case.checked_registers=['STATUS','IRQ_STAT','ERR_CODE',
  'DONE_COUNT']`，只检查规格保证的状态；模型以未执行命令的初始状态作为期望。
- `case.sample_registers = ['TGT_CFG', ...]`：结束后追加 APB 读回并与模型寄存器比较。
  `case.checked_registers` 可指定完整的功能检查集合；默认仍为原来的 12 个。
  所有 PERF 和计数寄存器均可按名称指定，PERF0/5–8 已默认采样而不比较。
  `case.expected_registers` 是显式期望覆盖，供模型不描述的状态检查使用。
- `case.command_timing=True`：把原命令流拆为多次 DESC_COUNT=1/DOORBELL，保留状态，
  每次启动前清 IRQ_STAT，并等待完成后才发下一条；DONE_COUNT 因此按命令数递增。
  `timing.txt` 每行：`DESC_BASE(hex) DESC_COUNT START_CYCLE END_CYCLE IRQ_STAT(hex)`。
  START 是 DOORBELL 的 APB 接收周期，END 是 APB 观测到 DONE/ERROR 并排空事务的周期。
  未拆分时记录整份列表的外部耗时；文件不声称提供内部命令开始/结束周期。
  稳态吞吐用大列表总耗时减去另测固定开销后除以数量（协调者确认）。

ABORT 后的像素内容/部分计数不作保证；错误后的已执行写入仍由对应场景定义观察范围。
所有 hooks 都只观察公共 APB/AXI 和验证存储模型，不访问 RTL 内部信号。

`case.reset_registers=['ID','STATUS','PERF[0]',...]`：复位释放后、任何 setup 写之前，
按列表顺序读取 APB，并直接与 `gpu.json` 的复位值比较。`reset.txt` 是采样数和
`offset expected`，`actual.reset.txt` 保存实际读回；模型对模型也走这两个文件的比对。

`case.abort={'read_address':(first,last),'after':n}` 或
`case.abort={'write_address':(first,last),'after':n}`：AR/AW **握手**覆盖闭区间后，
经过 n 个周期再发起 ABORT；只取第一次命中。等待触发期间不会结束测试，始终受总超时约束。
用于顶点/DMA/对象的首读，或 RESOLVE 的首个写地址；同一场景选择一种触发方式。
