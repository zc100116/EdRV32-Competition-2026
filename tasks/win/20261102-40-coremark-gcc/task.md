# 任务卡 20261102-40-coremark-gcc：CoreMark 编译器与编译选项对比（GCC 15.2 / 16.1，8 个程序），不重新构建

## 1. 目标

在同一块板、同一个 bitstream 上，依次下载 8 个按不同编译器和选项构建的 monitor（内含 CoreMark），各跑一次 CoreMark，比较分数。其中 `g16-peer` 与另一支队伍的条件相同：GCC 16.1、`-O2 -funroll-all-loops -mtune=sifive-7-series -mstrict-align -mbranch-cost=3 -fno-if-conversion -fno-if-conversion2`。

不综合、不布局布线，可以与正在跑的布局布线同时进行（只占用板子和串口）。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡）。拉出 `win/20261102-40-coremark-gcc`，在 result.md 中记录完整哈希。
- **bitstream**：卡 34 的 B1-ILA（`G:\codex_project\EdRV32-FPGA\EdRV32-B1-ILA`，CPU + UART，100 MHz）。用不了就用卡 24 的 B3R bitstream，在 result.md 中写明用了哪个。
- **程序**：`src/<变体>/monitor.bin`，共 8 个；各变体的编译器、完整编译选项和大小见 `src/variants.md`。

| 变体 | 编译器 | 选项 |
|---|---|---|
| g15-o2 | GCC 15.2 | `-O2`（现在 SRAM 初始化里的 monitor 同此） |
| g15-tuned | GCC 15.2 | 我们的 tuned：`-O3 -funroll-all-loops -finline-limit=600 -falign-*=4` |
| g15-peer | GCC 15.2 | 对方的选项 |
| g15-combo | GCC 15.2 | tuned + 对方选项中 `-O2` 以外的部分 |
| g16-o2 / g16-tuned / g16-peer / g16-combo | GCC 16.1 | 同上 |

## 3. 环境

PG2L200H-6 FBB676；PDS Debugger 只用于下载 bitstream。串口 115200。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-40-coremark-gcc origin/zc100116/b3`；整理用户清单。 |
| 1 | 用户（U） | 下载 bitstream。 |
| 2 | U + C | 对每个变体（按第 2 节表格顺序）：KEY1 复位停在 BIOS 菜单，运行 `py tools/board/uart_tool.py tasks/win/20261102-40-coremark-gcc/src/<变体>/monitor.bin --addr 0x10000000 --entry 0x10000000 --baud 115200 --port COM3 --log build/board/cm40-<变体>.raw`（`COM3` 换成实际端口）。进入 monitor 后先核对启动信息中的 `Compiler version`、`Compiler flags` 与 `variants.md` 一致，再输入 `1`、`5000`。保存串口全文。 |
| 3 | C | 若某变体的 `Score status` 提示不足 10 秒，用 `8000` 再跑一次该变体，两次都记录。 |
| 4 | C | 从串口原文填写第 8 节的表。 |

## 6. 产物

放在 `tasks/win/20261102-40-coremark-gcc/artifacts/`：`uart/<变体>.log`（每个变体的串口全文）。

## 7. 通过判据

- 8 个变体都给出结果。CoreMark 自身的校验必须通过（串口中的 CRC 校验行），校验失败的变体照实记录，不计分数。
- 所有数字取自串口原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261102-40-coremark-gcc 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| bitstream | |
| 时钟（monitor 打印的 CLK_SYS_HZ） | |

| 变体 | Compiler version | Iterations | Iterations/Sec | CoreMark/MHz | Score status | 校验 | HPM round cycles / instructions（第 1 轮） |
|---|---|---|---|---|---|---|---|

## 问题与偏离
```
