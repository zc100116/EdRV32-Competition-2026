# 任务卡 20261102-36-b1-ila-frozen：B1 ILA 补测冻结计数（不重新构建）

## 1. 目标

补做卡 34 第 6 步。用卡 34 已生成的 B1-ILA bitstream，按修正后的方法（`fpga/ip/ila_cpu.md` "运行时使用"第 1 条），在 CoreMark 两轮各自计数冻结的时刻抓 A 组计数器，和串口打印逐项对比。

卡 34 的问题：`monitor_hpm_release()` 在串口打印之前就重新放开了 mcycle/minstret（HPM 仍冻结），所以"打印后手动触发"抓到的 mcycle/minstret 已不是最终值。修正后的方法：触发条件设为 `minstret == 本轮指令数`。冻结时 minstret 停在这个值上，冻结期间 mcycle 不变，HPM 是本轮的最终计数。

## 2. 输入

- **代码**：`origin/zc100116/b3`（包含本卡的提交）。拉出 `win/20261102-36-b1-ila-frozen`，在 result.md 中记录完整哈希。
- **bitstream 和 Debugger 工程**：卡 34 的 `G:\codex_project\EdRV32-FPGA\EdRV32-B1-ILA`，不重新综合、不重新布局布线。
- **触发值**：卡 34 两次 CoreMark（O2，5000 次）的两轮指令数都是 1441025033 = `0x55E44C09`（40 位为 `0x0055E44C09`）。

## 3. 环境

PDS 2022.2-SP6.1 的 Debugger；PG2L200H-6 FBB676。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261102-36-b1-ila-frozen origin/zc100116/b3`；整理用户清单。 |
| 1 | 用户（U） | 下载卡 34 的 bitstream，打开 Debugger 连上 ILA。触发条件：TriggerPort0（minstret）`==` `0x0055E44C09`；触发位置保持 10%；深度 1024。 |
| 2 | U | 串口 115200 进入 monitor，**先布防**，再输入 `1`（CoreMark）、`5000`。第 1 轮结束时 ILA 应自动触发。导出 CSV，截图。 |
| 3 | U | 第 1 轮触发后，在第 2 轮结束前（第 2 轮约 14 s）**马上重新布防**（触发条件不变）。第 2 轮结束时应再次触发。导出 CSV，截图。保存串口全文。 |
| 4 | C | 用两份 CSV 计算，写进 result.md：(1) 在触发点之后找出 mcycle 连续不变的那一段（冻结期，只持续到 monitor 读完计数器、再次放开为止，可能只有几十到几百个采样点），记下这一段的长度和 mcycle 值；(2) 冻结期内 hpm3–10 的值；(3) 与串口逐项对比：mcycle 对 `HPM round cycles`，minstret 对 `HPM round instructions`，第 1 轮 hpm3–10 对 `HPM 01`–`HPM 08`，第 2 轮对 `HPM 09`–`HPM 16`；(4) 第 1 轮自洽检查：hpm3 + hpm4 + hpm5 = mcycle，hpm4 + 2 × hpm3 = minstret。只用 CSV 原始数据计算，写出计算方法。 |

如果第 3 步来不及在第 2 轮结束前布防，就在第 2 轮跑完、回到菜单后，按第 2 步的方法再跑一次 CoreMark，抓这次的第 2 轮（第 1 轮不抓）。

## 6. 产物

放在 `tasks/win/20261102-36-b1-ila-frozen/artifacts/`：

| 产物 | 内容 |
|---|---|
| `ila/round1.*`、`ila/round2.*` | 两次触发的 CSV、Debugger 原始导出、截图 |
| `uart/coremark.log` | 串口全文 |
| `compare.txt` | 第 4 步的对比表和计算方法 |

## 7. 通过判据

- 两轮都在 `minstret == 0x0055E44C09` 时触发，触发点之后有 mcycle 不变的冻结期。
- 冻结期内 mcycle、minstret、hpm3–10 与串口打印**逐项相等**；第 1 轮自洽检查两式都成立。
- 所有数字取自 CSV 和串口原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261102-36-b1-ila-frozen 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| bitstream | 卡 34，路径 |
| 触发 | 第 1 轮 / 第 2 轮是否触发，触发采样点 |

## 冻结期
| 轮 | 冻结期采样点范围与长度 | mcycle |
|---|---|---|

## 逐项对比
| 计数器 | 第 1 轮 串口 | 第 1 轮 ILA | 第 2 轮 串口 | 第 2 轮 ILA |
|---|---|---|---|---|

## 第 1 轮自洽检查

## 问题与偏离
```
