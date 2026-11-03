# 卡54结果索引

第二轮已结束，完整结果见 [r2_result.md](r2_result.md)，用户异常反馈见 [r2_feedback.md](r2_feedback.md)。第二轮日志前缀r2_，第一轮文件保留。

---

# 20261103-54-showcase-p5-board 阶段结果

| 项 | 内容 |
|---|---|
| 代码输入 | c9aa1604；卡54 showcase-p5.elf，工具确认版本8ff94918 |
| 比特流路径、生成时间 | 本次未重新采集 |
| A1 | 失败：用户进入视觉识别后报告卡死；板端RX出现 `showcase vision: NPU error`，随后该轮板端RX停止，工具持续重连 |
| A–C其他项目 | 未完成，不能标通过 |
| D–E | 按任务卡跳过 |
| F benchmark | 完成一轮，平均7 fps，16场景3～27 fps；浮窗开关条件未确认，未声称F1/F2均完成 |
| G–I | 本次未完成 |

## NPU错误原文

优先查看 `artifacts/uart/A1_hang.log`：包含BIOS、Load result PASS、Run、启动、CPU行和 `showcase vision: NPU error`。该文件最初保存seq1–185，后追加seq186–260，后段时间戳为Unix毫秒，前段为北京时间ISO文本；均保留RX/TX/SYS内容。

`artifacts/uart/F.log` 是随后保存的完整当前缓冲seq1–725，包含两次 `showcase vision: NPU error` 以及后续重新启动后的benchmark。请结合各轮Boot/Run标记分开分析，不能当成同一次运行。

对应工具状态在 `artifacts/tool/A1_hang_*.json`。初次状态与随后状态属于不同采集时刻，不应把缓存的app/state字段当成错误后仍存活的证据。现有错误行未输出NPU IRQ/寄存器细分错误码，不能确定具体根因。

## LVGL结果

详细反馈见 `benchmark_feedback.md`，16场景及ALL耗时原文见 `artifacts/uart/F_benchmark_summary.txt`；原始RX见F.log。部分CPU统计和LVGL长行交错，按原样保存，没有主动截断。

用户反馈：集成版明显慢于独立LVGL。没有同步重跑独立基线，不量化下降倍数。ALL报告render_ms=129.276、rnd_ms=10.889、sw_ms=26.955、other_ms=91.432。

本次只上传已有现场证据，未修复软件，未将未完成项目写为通过。
