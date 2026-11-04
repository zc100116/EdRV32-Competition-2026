# clk_npu 200 MHz RTL 路径切分
基线 `e54e471e`；改后为本报告所在提交（`git log -1 -- docs/reports/2026-11-04-npu-fmax-rtl.md`）。
工具：Verilator 5.020、Icarus 12.0、Yosys 0.70+219；本机，NPU/mem 仿真仍 150/125 MHz。
目标 PG2L200H-6、5.000 ns（175 MHz 中间点 5.714 ns）；未运行 PDS，不宣称物理 200 MHz 收敛。
旧路径/扇出来自卡48 `origin/win/20261103-48-vrn-f-rnd1slim` 的 F-cpu125m-r2 三份时序/扇出文件。
以下改后级数和扇出是 RTL 结构预算；保留本地副本的属性须由 PDS 确认，不能当作路后实测。

| 路径 | 改前级数/扇出 | 改后寄存边界、级数/每份扇出预算 |
|---|---|---|
| APM P→D2/R4 | 0–4级/2，走线5.166 ns | P→本地FF：0级/1；FF→R4：单carry/≤2；R5选择：1级 |
| 激活→APM | 0级/8，走线5.593 ns | 八个四链簇，本地输入FF和skew副本：0级/4；D2输入选择先寄存 |
| 权重→APM | 0级/2，走线5.656 ns | 每字节本地FF：0级/2；原bank/skew不变，不做6.8K FF重排 |
| unpack→行RAM | ≤3级，73条；旧扇出未逐条导出 | 预译码/地址寄存→本地写：≤1级；32-bit数据片选择/移位控制≤32 |
| desc[262]→plane地址CE | 10级；旧扇出未逐条导出 | start寄存行长度/末plane/stride，去掉min后加回比较；移除descriptor组合选择；剩余减法/比较与CE锥待PDS验证 |
| state→retire_min CE | 4级/13 | 退休选择/单carry值先寄存，下一拍CE：1级/13；行槽释放相应后移 |
| window几何/地址 | pair→x最高6级；x0→x1、row+channel+x串接carry | 双像素原点并行递增；row/channel预加；A0坐标/行选择→A1地址单carry，连续发射 |
| D2 fold控制 | 每通道38 | MAC/accum内部32→64位，按像素复制；链尾源32、每像素19/20 |
| ACC valid/first | 每通道64个数据位 | 每像素保留一份，≤32；反馈仍单拍carry，不插反馈流水 |
| Q hold捕获控制 | 每份128 | 每INT32值独立副本：32；量化4 lane及16/8组节拍不变 |
| 寄存器soft reset/写控制 | 537；地址到配置寄存器最高6级 | SETUP本地预译码、32位配置/性能bank：≤4级/32；小状态单独更新 |
| 结果RAM读保持 | 512/513 | 公共wrapper第一级持续采样，第二级16个本地CE：32；源≤18 |
| 参数RAM读保持 | 432/433 | 八bank×两CE副本，每份32；源16；两拍、禁读保持及同址旧值不变 |
| 写DMA接受→W保持 | 512 | 九份保留的本地组合握手译码（数据8+strb1）：≤4级/32；端口时序不变 |

正remaining下，`min(remaining,boundary)==remaining` 等价于 `remaining<=boundary`；无需给line_accept插级，也不产生burst气泡。
R4无条件计算D2和及普通值，R5只选择，ACC只更新原反馈；MAC仍512 MAC/拍。
新增数据寄存器不复位；valid与负载分开；无全局MAC CE，无时钟/复位复制改动。
固定延迟：MAC 10→12边界；window读完成2→3拍；ACC 2→3边界；最终A1→WB2 dual/half 46/38→50/42。
unpack接收到本地RAM写+1拍，row_done仍与实际最终写同沿；退休延迟+1拍。
测试适配经协调者批准：mac_array队列/取消边界、accum/window/datapath固定延迟、unpack写到期；内部fold宽度纯复制，数据判据不变。

资源：新增寄存位估算约9K FF，DRM/APM增量0；一次Yosys中间参考为36,841 LUT6/38,627 FF、264 MAC/量化APM实例。
Yosys将RAM/APM包装作为黑盒，且会合并PDS专用副本；其最高普通逻辑锥23级、合并后局部控制最高2050负载，不代表物理预算已通过。
剩余项按协调者最终收尾要求交PDS探针：整机状态/描述符切换8级、模型边界9级、非卷积控制6–7级，以及行burst减法/比较、跨模块控制输入、综合保留副本、实际布线和扇出。
探针例化真实NPU，两个域同接唯一时钟引脚；串行输入、逐输出寄存及逐位XOR移位链；FDC周期变量初值5.000 ns，时钟D18。

验证：风格12个RTL文件0告警；NPU/datapath/探针`-Wall` lint均0告警；12单元目录13项PASS，block smoke 22/22 PASS。
NET-02 latency94：725,760 B检测头逐字节PASS；PERF0=6,194,390，较6,193,335增加1,055拍（+0.017034%）；PERF1=5,347,440，512 MAC/拍不变；读/写512,472/309,000 beat。
复现先 `. ~/.local/opt/edrv32/env.sh`；初始化锁定子模块 `git submodule update --init third_party/ultralytics`。
风格：`python3 tools/check/verilog_style.py $(git diff e54e471e --name-only -- '*.v')`。
lint：用`tools.regress.expand_files`展开`rtl/filelists/{npu,npu_datapath}.f`，对应top执行`verilator --lint-only -Wall -DSIM_MODE`。
探针lint同npu文件列表，另加`rtl/common/edrv32_reset_sync.v`及探针.v，top为`edrv32_npu_timing_probe`。
单元目录：mac_array、accum、window、input_unpack、quant_param_store、writeback、result_quant、regs、write_dma、conv、datapath、top。
单元：每条前加`flock /tmp/edrv32-sim.lock`，`python3 tools/regress.py smoke --path verif/unit/npu_<模块> -j 1`。
模块同锁：`python3 tools/regress.py smoke --path verif/block/npu -j 1`；不运行整套perf三档。
NET仅latency：同锁执行下面Python，沿用原bench和Python逐字节参考，编译`-j 1`。
```python
import sys
sys.path.insert(0, 'verif/block/npu')
from run import build, simulate
from prepare import prepare_network
p, a = prepare_network('NET-02')[1]
rc, text, log = simulate(build(False), p, a, 'fmax_latency94')
print(text)
assert rc == 0 and 'PASS NB' in text and 'FAIL' not in text
```
综合：`python3 verif/block/npu/synth.py`；原始数据`build/npu-opt1/synth/`。
日志：`build/npu-fmax/`、`build/regress/smoke/`、`build/npu/yolo/fmax_latency94.log`。
