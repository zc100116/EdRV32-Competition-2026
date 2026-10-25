# 独立双 ALU 回归

从项目根目录执行：

```sh
python3 sim/script/run_dual_issue.py --suite backend
python3 sim/script/run_dual_issue.py --case dual-alu --seed 7 --wave
```

`dual-alu`：双退休逐条参考模型，980 条混合压缩/32 位指令，全部整数 ALU 运算、LUI/AUIPC、RAW/WAW/WAR/x0、立即数假相关、Load 阻塞与恢复、固定随机背压，128 条独立压缩 ALU 连续段应在 64 周期退休。种子同时固定程序和背压；日志、波形和 source SHA256 位于输出目录。

`if2-dual-missing`：仅一条完整 32 位指令与未初始化的 B payload，验证控制不会出现 X 或虚假双捕获。

`dual-regfile`：四读口写透，固定地址下写数据变化、年轻写口优先、x0。

`dual-operand-resolve`：四个寄存边界的 B 旁路及 MDU 相对年龄，年轻未完成 Load 遮蔽旧 B，父包失效、unused source 和 x0。

`dual-hpm-csr`：40 个计数器的双事件、+2 进位、仅第二事件、inhibit，以及 minstret 跨 32 位低字进位。

`dual-pair-irq`：IRQ 在成对 A/B 提交前取消整组，核对两条均无写回、mepc=A、MRET 后恰好一次成对重放。

`dual-alu-csr-trap`、`dual-alu-irq-fencei`、`dual-alu-mdu-raw-irq`：沿用原场景和断言，打开双发射；包括缓存 MDU 取消/重放。

功能回归、冻结架构测试和 CoreMark 均须通过，详细口径见 [开发记录](../../../../docs/architecture/2026-10-07-dual-alu.zh.md)。
