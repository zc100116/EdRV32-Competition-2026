# CPU RTL

实现 `docs/spec/cpu-spec.md`；单一 clk_sys 时钟域，Verilog-2001。
CPU 不实现 C 扩展，无 RVC_EN 参数；misa=0x40001100，mepc 低两位清零。

前端按 8 字节组取指，每个响应贡献一条或两条完整 32 位指令。
响应缓冲容量四条，随后写入四条 IB；保留原 no-C 路径的容量和推进条件。
无跨组拼接、RVC 展开、长度预测或 F2 边界恢复。
D 级冷 JAL 重定向在无法发射时保留 IB 头，M/E 重定向清空 IB。

内部记录仍为 179 位，以保持现有观测接口：

|位|含义|
|---|---|
|31:0|PC|
|63:32|32位指令|
|95:64|原始编码|
|96|保留的compressed观测位，恒0|
|97|保留的前端illegal观测位，恒0；非法编码由D译码|
|98|取指错误|
|99|BTB命中|
|100|预测跳转|
|132:101|预测目标|
|141:133|原始gshare索引低9位|
|178:142|RAS检查点：count[2:0]、ptr[1:0]、栈顶[31:0]|

本次按步骤提交：0 删除 C 残留；1 预测器扩容与分布式 RAM；2 V3s。
第0步删去 cpu_rvc、cpu_f2_recover 单元测试，迁移 cpu_core_smoke、cpu_frontend
共用文件至 *_no_c，保留无 C 测试；cpu_redirect_wait 删除重复配置。

检查与测量结果见 `docs/reports/2026-11-02-perf-cpu-v015.md`。
仿真前执行 `. ~/.local/opt/edrv32/env.sh`，全部仿真独占
`flock /tmp/edrv32-sim.lock`，`tools/regress.py` 使用 `-j 1`。

预测器为 BTB 128 项（PC[9:3]、tag PC[31:10]）、gshare 4096 项
（PC[13:2] XOR 12 位非推测 GHR）、RAS 4 项。
`edrv32_ram_cpu_btb` 为 128×58：{tag22,target32,position1,type3}，
一同步写、一异步读，无初始化或复位；有效位由预测器 FF 复位清零。
`edrv32_ram_cpu_direction` 为 4096×2，一同步写、查询/更新各一异步读，
上电全01、复位不清除。两包装行为阵列均名 `memory_r`，读延迟0拍，
写入时钟边沿后读端看到新内容；同沿更新使用沿前旧计数器值。
IB 新增 `push_index_hi_i`/`index_hi_o`（各6位，按槽各3位），
前端 `decode_index_hi_o` 接核心 `d_index_hi_w`；E 用 `e_predict_index_r`
保存完整12位索引，供唯一控制转移训练。取指组合查询时序不变。
