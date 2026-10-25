# 基础设施实施方案（P0）

| 项 | 内容 |
|---|---|
| 版本 | v0.1 |
| 日期 | 2026-10-25 |
| 依据 | `CLAUDE.md` 第 2、4、5、8、9 节；SoC 规格第 5、6 节 |

状态标记：`[ ]` 未开始，`[~]` 进行中，`[x]` 完成，`[!]` 阻塞。

---

## 1. 目标和完成标准

建立新工程的目录、工具链和开发流程，使后续模块可以直接开发和回归。完成标准：

- 旧工程全部移入 `legacy/`，新目录骨架符合 `CLAUDE.md` 第 2 节。
- Verilator 5、Icarus、RISC-V GCC、Spike 在 Linux 端可用，安装方法写在 `docs/guides/env-setup.md`。
- `tools/regress.py smoke` 能运行一个示例测试并输出 PASS。
- 风格检查和 Verilator lint 能对 `rtl/` 运行。
- 地址映射和寄存器生成器能生成 RTL 头文件、C 头文件和文档表格。
- 公共原语（复位同步、CDC、FIFO）完成并通过单元测试。
- 软件能编译出一个最小程序，并生成 `rom.hex`、`sram.hex`。

## 2. 前置条件

- 规则和规格已提交并合入 `main`（等待用户批准）。

## 3. 待办清单

| 编号 | 内容 | 执行者 | 依赖 | 验收 | 分支 / 任务卡 | 状态 |
|---|---|---|---|---|---|---|
| I-00 | 提交规则、规格、方案，合入 main 并推送 | 协调者 | 用户批准 | `main` 上可以看到 `CLAUDE.md`、`AGENTS.md`、`docs/` | main | [x] 2026-10-25（d64fb11） |
| I-01 | 迁移 legacy：把旧的 `rtl/ sim/ sw/ scripts/ thirdparty/ third_party/`（子模块除外）、`doc/architecture/`、`doc/axi4/`、`2026-ziguang-guide.md` 移入 `legacy/`；开发板资料 `doc/fpga/` 移到 `docs/reference/board/` 并保持不入库；建立第 2 节的新目录骨架 | Codex · GPT-6 Luna | I-00 | `git status` 中只有移动和新增；新目录存在；旧 README 更新为指向 `CLAUDE.md` | zc100116/task-infra-legacy \| [x] 已合入 main（6580c12） |
| I-02 | 工具链：Verilator 5.020、Icarus 12、GTKWave、xPack GCC 15.2.0、dtc、Spike，安装到用户目录；`docs/guides/env-setup.md` 和 `~/.local/opt/edrv32/env.sh` | 协调者 | — | 各工具版本检查通过；Verilator `--timing` 测试 PASS；Spike 输出提交日志 | — | [x] 2026-10-25 |
| I-03 | 回归框架：`tools/regress.py`（读取 `test.yaml`、展开 `files.f`、调用 Verilator/Icarus、收集 PASS/FAIL、按档位运行）、`test.yaml` 格式说明、顶层 `Makefile`；附一个示例单元测试 | Codex · GPT-6.1 Sol | I-01、I-02 | `tools/regress.py smoke` 运行示例测试输出 PASS，故意改错后输出 FAIL 并返回非零 | zc100116/task-p0-rest \| [~] 工作包 P0-rest（Codex 项目经理） |
| I-04 | 风格检查和 lint：移植旧的 `verilog_style.py` 到 `tools/check/`，规则按 `CLAUDE.md` 第 5–7 节修订；`tools/check/lint.sh` 调用 Verilator `--lint-only -Wall` | Codex · GPT-6.1 Sol | I-01、I-02 | 对示例 RTL 运行通过；对故意违规的样例能逐条报出 | zc100116/task-p0-rest \| [~] 工作包 P0-rest（Codex 项目经理） |
| I-05 | 生成器：按 SoC 规格第 6 节重写 `rtl/include/soc_address_map.json`；生成 `rtl/include/edrv32_soc_map.vh`、`sw/bsp/include/soc_map.h` 和 Markdown 表格；寄存器描述格式和生成器（RTL 寄存器块骨架、C 头文件） | Codex · GPT-6.1 Sol | I-01 | 生成的地址表与 SoC 规格 6.1 完全一致；重复运行输出不变 | zc100116/task-p0-rest \| [~] 工作包 P0-rest（Codex 项目经理） |
| I-06 | 公共原语：`reset_sync`、`cdc_sync_bit`、`cdc_pulse`、`cdc_handshake`、`cdc_gray_cnt`、`async_fifo`、`sync_fifo`、`rtl/include/edrv32_build_mode.vh`；各自的单元测试 | Codex · GPT-6.1 Sol | I-03、I-04 | 单元测试在 Verilator 和 Icarus 下都通过；lint 0 告警 | zc100116/task-p0-rest \| [~] 工作包 P0-rest（Codex 项目经理） |
| I-07 | 软件骨架：`sw/Makefile`、启动代码、链接脚本 `rom.ld`/`sram.ld`/`ddr.ld`、`tools/elf2mem`（按地址段切分 hex）、`tohost` 和 `SIM_EXIT` 的约定实现；CoreMark 子模块初始化和移植框架 | Codex · GPT-6.1 Sol | I-01、I-02 | 最小程序编译出 ELF 和各段 hex；CoreMark 能编译 | zc100116/task-p0-rest \| [~] 工作包 P0-rest（Codex 项目经理） |
| I-08 | 评审：I-03 至 I-07 的交叉评审 | Codex · GPT-6.1 Sol | 各项完成 | 评审意见全部处理 | zc100116/task-p0-rest \| [~] 工作包 P0-rest（Codex 项目经理） |
| I-09 | 合入 main 并更新路线图 | 协调者 | I-08，用户批准 | `main` 上 smoke 通过 | main | [ ] |

可以并行的波次：
- 波次 1：I-01（I-02 已由协调者完成）
- 波次 2：I-03、I-04、I-05、I-07
- 波次 3：I-06、I-08

## 4. 规格定稿项

无。

## 5. 风险和阻塞

| 风险 | 应对 |
|---|---|
| 没有 root 权限，部分工具需要从源码构建 | 统一安装到用户目录，在 env-setup 文档中写明 |
| Spike 构建依赖缺失 | 缺什么就从 Ubuntu 官方包解压到用户目录 |

## 6. 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-10-25 | v0.1 | 初稿 |
