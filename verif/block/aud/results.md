# AUD AT-01–AT-09 验证结果

- 日期：2026-11-23。
- 环境：用户提供的仿真主机（环境不记录）。
- RTL commit：`0ea3c68b7`（`aud: add AUD RTL and unit tests`）。
- 测试与本报告同提交：`aud: add AUD block tests AT-01..09`。
- 结论：9/9 PASS；未发现 RTL 错误或新的规格歧义。

| 测试 | 结果 | 比对样本帧 | AXI 读事务 | 关键判定 |
|---|---|---:|---:|---|
| AT-01 | PASS | 256 | 2 | I2S 时钟、相位、左右声道和填充位 |
| AT-02 | PASS | 1760 | 19 | 多次回绕、4 KiB/环末拆分、短读 |
| AT-03 | PASS | 384 | 3 | LOW 跨越置位、清除后不重复、再次跨越 |
| AT-04 | PASS | 64 | 1 | 八帧欠载计数增加 8，补数恢复且非 ERROR |
| AT-05 | PASS | 64 | 3 | 在途读完成、关闭清空、计数稳定、重开 |
| AT-06 | PASS | 128 | 2 | 成功前缀、ERR_CODE=1、停止新读、最终输出零 |
| AT-07 | PASS | 128 | 1 | FIFO 剩余 64/63 帧时 urgent 为 0/1 |
| AT-08 | PASS | 0 | 0 | 复位、TYPE、对齐屏蔽、运行时配置写忽略 |
| AT-09 | PASS | 1440 | 12 | 80 轮随机补数机会，UNDERRUN_CNT=0 |

AT-06 出错事务数据是否进入 FIFO 不作规定，按协调者确认的判据执行；
成功前缀逐样本比对，等待超过 FIFO 深度后连续八帧检查零输出。
全部九项编译告警为 0；本机真实 DUT 集成 lint 告警为 0。
三个 SV 源文件的文件头、缩进、行宽、Tab 检查为 0 问题，`git diff --check` 通过。
主机与本机工具存在告警差异，已调整测试环境写法后通过，未豁免 RTL 告警。
仿真进程已结束，仿真构建目录已清理。

复现命令（仓库根目录；full 包含 smoke 八项及 AT-09）：

```sh
python3 tools/regress.py full --path verif/block/aud -j 1
python3 tools/check/verilog_style.py verif/block/aud
```

本机 lint 的可复现命令见 [README.md](README.md)。仓库风格工具仅扫描 RTL
扩展名；本任务的三个 `.sv` 文件另外按 CLAUDE.md 第 7 节检查格式。
