# ACT4 RV32 Zca 冻结自检 ELF

本目录固化 26 个 `riscv-arch-test` ACT4 `rv32i/Zca` 最终自检 ELF，用于 EdRV32 RV32IMC 配置的 C 扩展架构回归。资产只作为可复用测试输入；每次 RTL 变更仍须重新运行并保存本次日志。

## 来源与生成口径

- 导入来源：相邻独立项目 `EdRV32-sim-env/assets/act/act4/rv32imfdcb-ilp32/xpack-gcc-15.2.0/`。
- 上游：`riscv-non-isa/riscv-arch-test` ACT4，项目记录 commit `a7c9930`（2026-04-16）。
- 对应源码：`third_party/riscv-arch-test/tests/rv32i/Zca/`，共 26 个 `.S`。
- 工具链：xPack GNU RISC-V Embedded GCC 15.2.0。
- 参考模型：Sail RISC-V `sail_riscv_sim`。
- 原始生成流程：先编译 signature ELF，由 Sail 生成期望 signature，再把 signature 编译进最终 self-check ELF。
- 文件保留原始 `.sig.elf` 名称；这里的文件是最终自检 ELF，不是仅供 Sail 取签名的中间 ELF。

本次只导入 EdRV32 基础 C profile 对应的 `Zca`，没有导入项目未实现的 Zba/Zbb/Zbs，也没有把父目录作为运行时依赖。导入前已验证父资产中 26 个 Zca ELF 与原 `manifest.sha256` 一致；本目录使用裁剪后的独立 manifest 再次固定哈希。

## 使用方法

从当前项目根目录运行：

```bash
make arch-tests-c
```

入口会先执行 `sha256sum -c manifest.sha256`，然后逐个从 ELF 符号表提取 `tohost` 地址、转换为 HEX，并用缓存核仿真。通过要求为 26/26；缺少 `tohost`、数量不等于 26 或任一测试未产生 PASS 都判失败。

