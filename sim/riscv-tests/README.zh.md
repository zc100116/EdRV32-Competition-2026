# 冻结 ISA / ACT 双发射对照

```sh
python3 sim/script/run_dual_isa.py --mode both --memory both --jobs 8
```

每种配置 riscv-tests 62 项、ACT 82 项，四种配置共 576 次。riscv-tests 必须写 tohost=1；ACT 沿用冻结自检 ELF 的完成编码（1 或偶数通过）。测试输出记录完成值，不把重复异常、超时、非零进程退出码或 FAIL 当成通过。

资产范围为 RV32IMC + Zicsr + Zifencei + Zicntr + M-mode。rv32mi-p-breakpoint 的 Debug trigger 与 rv32mi-p-pmpaddr 的 PMP 沿用 [原范围说明](../../sw/test/isa/riscv-tests/assets/rv32mi/README.zh.md) 明确排除，F/D 不属于本核。本目录与 `sim/riscv-arch-test` 维护相同的可选 DUAL_ISSUE 参数及双槽 trace/保持断言。

所有 ELF/归档来自仓库冻结资产；Zca 是包含 Sail 参考 signature 的最终自检 ELF，见 [来源说明](../../sw/test/isa/riscv-arch-test/assets/act4/rv32imc-zca-ilp32/xpack-gcc-15.2.0/README.zh.md)。运行器只解包到独立输出目录并转换 ELF，不重新编译测试或更改参考数据。manifest 保存源码、ELF、HEX、工具版本和完整命令。输出位于 `sim/build/dual-isa/`，每次新建独立目录。

`--mode all` 增加 wide（双 ALU 加 64 位命中取指），共 864 次；direct 仍按实际单 word 返回，cached 才供应双 word。
