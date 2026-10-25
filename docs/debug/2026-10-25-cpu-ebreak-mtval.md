# EBREAK 的 mtval 与参考平台对齐

## 1. 现象

C-cebreak-01、privilege-ebreak 的有 C / 无 C 配置均成功写 tohost，
但严格退休追踪在处理程序读取 mtval 时失败：RTL 返回 0，Spike 返回断点指令 PC。

## 2. 复现

联调基线 `a9420fb`，Verilator 5.020、Spike 1.1.1-dev。
执行 `. ~/.local/opt/edrv32/env.sh` 后运行：

```sh
python3 tools/cpu/run_b1.py verif/block/cpu/arch-c-cebreak-01-c/case.json
python3 tools/cpu/run_b1.py verif/block/cpu/arch-privilege-ebreak-no-c/case.json
```

日志、ELF、追踪与签名位于 `build/cpu/arch-test/C-cebreak-01/` 和
`build/cpu/arch-test/privilege-ebreak/no-c/`。

## 3. 观察

C-cebreak-01 的首次不一致为第 194 个事件，读取 mtval 的 PC 为 `0x800005b4`：
RTL 写回 x7=0，Spike 写回 x7=`0x80000268`。
其他指令、异常原因和退休顺序在该位置之前一致。

## 4. 根因

旧 cpu-spec 第 5 节要求 EBREAK 的 mtval 为 0，旧 RTL 按该规定实现。
Spike 默认记录断点 PC；两者都是特权规范允许的行为。
协调者经用户确认，将 cpu-spec v0.9 第 5 节改为 EBREAK 记录指令 PC。
因此这是已确认的规格调整，不是比对豁免。

## 5. 修复

D→E 异常负载对 EBREAK 保存该指令 PC，ECALL 仍保存 0。
公共定向测试 EXPECT 宏对 cause=3 统一以 fault 标签为 mtval 期望，
不再区分 B1 和 SPIKE_SMOKE。未修改 Spike 的 EBREAK 语义。

## 6. 防回归

三个原失败的 arch 配置均重跑严格追踪和完整参考签名比对通过。
E-01、P-01 的有 C / 无 C 配置也重新检查异常元组通过。

## 7. 同类排查

检查了 C.EBREAK 展开后的异常负载、普通 EBREAK、ECALL、非法指令与地址错误。
另发现无 C 配置非法短编码的 mtval 不应包含下一半字，独立修复并由
privilege-misalign-jal-01 no-C 的逐条追踪及 69 个签名词复现、验证。
