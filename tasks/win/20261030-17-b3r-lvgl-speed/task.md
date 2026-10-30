# 任务卡 20261030-17-b3r-lvgl-speed：B3R 上测 LVGL 软件提速后的分场景耗时和 CPU 计数器

## 1. 目标

只换软件，不重新综合，沿用卡 14 的 B3R bitstream。跑新版 S3 benchmark，取得 17 行 `LVGL split`，确认以下两点：

1. **软件提速的效果**：S3 做了两处改动，见 `docs/reports/2026-10-30-perf-lvgl-split.md` 的 T-LVP2 小节。
   - 字形转成 A8 后放进缓存，以后直接用，不再每次转换和复制；
   - 每次门铃的 cache 维护从约 32 次降到约 3 次。
2. **CPU 侧的瓶颈**：卡 16 中，CPU 侧的 LVGL 逻辑占了 55% 的时间。本次新增 CPU 计数器（IPC、I$/D$ 缺失率），用来判断是不是 cache 太小造成的。

每行 split 由卡 16 的 34 个字段扩展到 52 个，原有字段的名称和含义不变。

## 2. 输入

- **代码分支**：`origin/zc100116/b3`（包含本卡的提交）。从这里拉出 `win/20261030-17-b3r-lvgl-speed`，在 `result.md` 中记录完整哈希。
- **bitstream**：卡 14 的 B3R（`G:\codex_project\EdRV32-FPGA\EdRV32-B3R`）。RTL 未变，不需要重新综合。
- **程序**：`src/s3.elf`，由 b3 `6bcce541` 构建。

## 3. 环境

与卡 16 相同：PG2L200H-6 FBB676，JTAG，USB 串口，HDMI 显示器。

## 4. 需要的 IP

无。

## 5. 操作步骤

| 步骤 | 执行者 | 内容 |
|---|---|---|
| 0 | Windows Codex（C） | `git fetch origin`，`git switch -c win/20261030-17-b3r-lvgl-speed origin/zc100116/b3`。 |
| 1 | 用户（U） | 下载卡 14 的 B3R bitstream，接好 HDMI 和串口。 |
| 2 | 用户（U） | 用 GUI（115200）加载 `src/s3.elf`，在主界面选择 benchmark，等它自然跑完，串口打印出 `Benchmark Summary` 和 `LVGL split scene="ALL"` 后再停。中途不要按 KEY4。出现 `S3 glyph cache full` 时，原文记下并停止。 |
| 3 | 用户（U） | 回到主界面后，运行一次 RN-17 自比对项，记下 PASS/FAIL 那一行。 |
| 4 | Windows Codex（C） | 收集第 6 节产物，填写 `result.md`，提交信息为 `win: 20261030-17-b3r-lvgl-speed results`，推送到同名分支。 |

## 6. 产物

放在 `tasks/win/20261030-17-b3r-lvgl-speed/artifacts/`：

| # | 产物 | 内容 |
|---|---|---|
| 1 | `uart/s3.log` | 从启动到 RN-17 结束的完整串口文本 |
| 2 | `lvgl_split.tsv` | 一个场景一行，每个 `key=value` 一列，列名就用 key，数值照抄原文，共 17 行 52 列 |
| 3 | `benchmark_summary.txt` | `Benchmark Summary` 原文 |

## 7. 通过判据

- benchmark 跑完，17 行 split 都已取得。
- RN-17 PASS。
- 所有数字照抄串口原文，找不到的写"未取得"。

## 8. result.md 模板

```markdown
# 20261030-17-b3r-lvgl-speed 结果

| 项 | 内容 |
|---|---|
| 代码 commit | |
| bitstream | 卡 14 B3R |
| 加载方式 | GUI 115200 |
| 完成情况 | |

## Benchmark Summary 原文

## split 摘要（完整见 lvgl_split.tsv）
| 场景 | render_ms | rnd_ms | sw_ms | other_ms | perf0_ms | clean_ms | wait_ms | finish_ms | cache_ops | glyph_cpu_ms | ipc | i_mpki | d_mpki |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|

## RN-17
```
