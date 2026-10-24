# RV32MI 冻结测试范围

本目录的 ELF 来自较宽的 privileged/debug 测试集合，并不都属于本核冻结的
`RV32IMC + Zicsr + Zifencei + Zicntr + M-mode` profile。

默认回归运行 14 项属于该 profile 的 M-mode/CSR/异常测试。以下两项明确显示为 `SKIP`：

- `rv32mi-p-breakpoint.elf`：测试 Debug trigger module 的 `tselect/tdata1/tdata2`
  和地址/数据断点；它不是基础 `EBREAK` 异常测试。基础 `EBREAK` 由
  `rv32mi-p-sbreak.elf` 覆盖。
- `rv32mi-p-pmpaddr.elf`：测试 `pmpcfg0/pmpaddr0`、粒度和 lock 语义；PMP 不属于
  本版 M-mode-only 竞赛 profile。

默认的 `make riscv-regress SUITE=rv32mi` 会跳过这两项；使用
`make riscv-regress SUITE=rv32mi ALL_TESTS=1` 可明确运行它们，但其失败
不能被误报为当前 profile 的 ISA 失败。如果未来决定加入 Debug trigger 或 PMP，必须先更新
架构契约、CSR 清单、精确异常/kill 矩阵和时序预算，再把相应用例移出 SKIP。
