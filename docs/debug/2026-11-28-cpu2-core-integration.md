# CPU v2 NONE 核级集成调试

实现与验证提交、最终回归数字见 `verif/block/cpu2_core/README.md`。
工具：GCC 15.2.0；Verilator 5.051 devel（v5.050-99-gf8fb1d664）。

## 1. 现象

- 恢复拍旧 IB 分配：`rv32ui-add` 已通过 ADD 检查，ECALL 后最终却写 `tohost=0x539`。
- 完成锁：双发射 CoreMark 在 8920 条退休后停于 `0x10003c74`；另有分支背压 tag 别名问题。
- FENCE.I 分类：`rv32ui-fence_i` 在 `PC=0x800001d0` 的 `0x0000100f` 报非法指令。

## 2. 复现

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/cpu/build_cpu2_tests.py --suite isa
python3 tools/cpu/run_cpu2_core.py --width 1 --program rv32ui-add
python3 tools/cpu/run_cpu2_core.py --width 2 --program rv32ui-fence_i
```

旧 IB 问题在修复前两宽均复现。诊断仿真加 `+CONTROL_LOG`，或 `+TRACE=<文件>` 记录退休事件。
原始测试和构建日志归档于 `build/i06/`；完整测试输出位于 `build/cpu2_core/w{1,2}/`。

## 3. 观察

- 单发射 ADD：1296 拍 ECALL 在 `0x80000650` 触发 cause 11，并发出 cancel。
- 1297 拍 `commit_redirect_valid=1`，同时 `allocate_valid=1`、PC 为旧 IB 的 `0x80000654`。
- 1300 拍该年轻非法字 `0xc0001073` 再次触发 cause 2，覆盖原陷阱状态。
- FENCE.I：693 拍 cause 2、mtval `0x0000100f`；此前 store 已退休，FENCE.I 本身未退休。

- CoreMark 波形末态：branch pipe0 的 skid valid=1/tag0，local lock valid=1/tag2，
  compare0 valid=0；取消的旧结果已离开，但锁仍指向旧 tag。
- 分支单元新增复现：无效 pipe1 与 pipe0 同 tag 的背压用例在修复前报结果丢失。
- 分支/ALU 新就绪 MEM 取消用例均在修复前失败；ALU 新 tag 结果 valid=0。

## 4. 根因

- 恢复拍：commit 重定向注册输出，IB 在重定向边沿清空；边沿前旧头仍有效。
  issue 仅在 cancel 当拍禁止分配，下一拍仍能分配即将被前端清除的旧头。
- FENCE.I：所有有序系统指令共享 CSR 请求通道；`edrv32_cpu2_csr.v:129` 的 `req_illegal_w` 仅检查 funct3 非零，
  缺少 SYSTEM opcode 限定，将 funct3=1 的 FENCE.I 当作不存在的 CSR 0 访问。
- 最初怀疑 ECALL 译码合法性；检查发现 `legal_w` 默认已为 1，未实施该无效改动。

- 分支全局锁（`branch.v:1395`）以 `compare1_tag==lock_tag` 选管线，未检查 compare1 valid，旧无效 tag 可劫持结果。
- ALU/branch 局部锁（`alu.v:162/546`、`branch.v:615/1001`）只清“此前已锁定”的取消项；新就绪且同沿取消的结果仍能建立锁，
  随后结果被清而锁残留。branch 全局锁同类建立条件也缺取消限定。

## 5. 修复

- 经协调者批准，top 在寄存 commit/branch 重定向有效时屏蔽送 issue 的两个 IB 头 valid。
  其他字段直连；该拍 remove/allocate 自然为零，IB 在边沿清空。
- 按协调者“明确根因、≤10 行可先修”授权，为 CSR 非法判定加 opcode `7'h73` 限定。
- 观察线按授权由模块输出复用已有 trace/HPM/debug 状态；未使用层次引用或复制架构状态。

- 在已授权的 ≤10 行明确缺陷范围内，分支选择要求 pipe1 valid；ALU/branch 取消项不再建立锁。
  取消仍按原年龄边界，不新增状态/兜底；三处缺陷均由单元失败和修后通过证明。

## 6. 防回归

- `env/trap.S`：ECALL、EBREAK 后紧跟非法字；处理器跳过该年轻字，并校验 cause/mtval。
  同一程序检查未对齐 load/store 的 cause 4/6、原地址 mtval 和四次处理计数。
- `env/redirect.S`：条件分支循环与冷 JAL 后的错路非法字及失败 store 必须被取消。
- `tb.sv`：所有 commit/branch 恢复拍断言 allocate/remove 为零；两宽运行。
- `verif/unit/cpu2_csr/tb.sv` 增 FENCE.I 通道合法完成检查，六配置运行。
- 原 `rv32ui-add` 与自修改代码 `rv32ui-fence_i` 纳入两宽核级 smoke。

- branch 单元新增无效管线同 tag 背压、刚就绪 MEM 结果取消两例；ALU 单元增加后者。
  两模块六配置均测；核级 CoreMark 两宽复测，程序退休条数相同。

## 7. 同类排查

- branch 重定向与 commit 重定向使用同一 top 屏蔽点。
- CSR 架构写判定原本已有 opcode 限定，无须修改。
- FENCE funct3=0、MRET/WFI 均沿原系统请求/提交路径；未新增异常兜底或重试。
- 按同一取消建立规则检查 ALU 两管线、branch 两管线及全局锁，并补对应复现测试。
