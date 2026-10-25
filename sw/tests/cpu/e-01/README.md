# E-01

逐个检查取指错误、非法指令、断点、不对齐、访问错误及 M 态 ECALL。

档位：`smoke`（full包含smoke）。

检查：每个异常比较 mcause/mepc/mtval、进入时 MIE=0/MPP=3；ECALL 检查 MPIE 保存原 MIE，MRET 后 MIE/MPIE 恢复；C 开启时 mcause=0 不适用；关闭 C 的补充镜像检查半字跳转目标。

B1 激励：fault_fetch 所在块返回 I$ 错误；仅在 fault_load/fault_store 请求时对 scratch 返回 D$ 错误，其他访问正常。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。

另构建 `no-c/` 镜像：`RVC_DISABLED`、`RVC_EN=0`，验证跳转目标最低两位约束。Spike 的 EBREAK `mtval` 为断点PC，冒烟版按此检查；B1版严格检查规格规定的0。
