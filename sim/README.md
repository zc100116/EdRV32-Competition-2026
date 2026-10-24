# RTL 仿真

`sim/` 按测试目的分为四类：

- `riscv-tests/`：传统 RISC-V 指令测试；
- `riscv-arch-test/`：ACT 架构测试；
- `cases/`：CPU、SoC 和 Vision 模块的定向测试；
- `soc/`：运行软件镜像的完整 SoC 测试。

公共行为模型放在 `models/`，checker 和波形记录模块放在 `common/`。每个
定向测试和 SoC 测试目录使用一个 `files.f` 描述顶层、宏、RTL、模型和
testbench。所有路径均相对项目根目录。

生成的仿真程序、展开后的 filelist、日志和波形统一写入 `sim/build/`。
该目录不保存源文件。

常用命令：

```sh
make riscv-test TEST=rv32ui/rv32ui-p-add
make riscv-regress SUITE=rv32ui
make arch-test TEST=I/I-add-00
make arch-regress SUITE=I
make case-sim CASE=soc/memory-hub
make case-sim CASE=soc/memory-hub WAVE=1
make soc-sim SOC=soc-coremark SW=test/soc/soc-hello
```

`*-compile` 只编译，`*-run` 运行已有仿真程序，`*-clean` 删除对应的
`sim/build/` 子目录。`case-list` 和 `soc-list` 用于查看可用测试。

当前 ACT testbench 延续原有的 `tohost` 完成判定；参考 signature 的生成和比较
尚未接入，因此现阶段结果只能作为架构回归，不能单独作为完整合规认证结论。
