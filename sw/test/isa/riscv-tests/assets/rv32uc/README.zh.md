# riscv-tests `rv32uc-p-rvc` 冻结资产

本目录保存从官方 `riscv-software-src/riscv-tests` 生成的 RV32C 综合测试 `rv32uc-p-rvc.elf`。它与 ACT4 Zca 的逐指令 self-check 测试互补：该程序沿用 `riscv-tests` 的 p-env，在一个 ELF 中执行官方 `rv64uc/rvc.S` 对 RV32 的适用检查。

## 来源和构建口径

- 官方仓库：`https://github.com/riscv-software-src/riscv-tests.git`
- `riscv-tests` commit：`2ebecad997fa58cd9e5724340ba75aa4b59bd1d0`
- `riscv-test-env` submodule commit：`6de71edb142be36319e380ce782c3d1830c65d68`
- 源文件：`isa/rv32uc/rvc.S`，由官方文件包含 `isa/rv64uc/rvc.S` 并切换到 RV32U 测试环境。
- 工具链：xPack GNU RISC-V Embedded GCC 15.2.0。
- ISA/ABI：`-march=rv32imc_zicsr -mabi=ilp32`。
- 链接环境：官方 `env/p/link.ld`；ELF 符号表中的 `tohost=0x80003000`。
- 生成脚本：`scripts/test/build-riscv-tests-c.sh`；构建中间文件写入 `out/sw/riscv-tests-build/rv32uc/`，不修改官方工作副本。

## 完整性和运行

```text
SHA-256  7cc77dfc2d8be3d8c99c384d0b64b8b3144223b3180a823b10fa430c08de6ab0
```

`make isa-tests` 在默认 `COMPRESSED=1` 时自动包含 `rv32uc`；`COMPRESSED=0` 时自动排除。也可单独运行：

```bash
make isa-tests ISA_SUITES=rv32uc
```

运行入口必须从 ELF 符号表提取 `tohost`，不得使用项目 smoke 的默认地址代替。

