# 卡24 B3R：布局布线前阶段报告

本次只归档已完成的Compile、Synthesize（ADS）和Device Map，不引用旧布局布线/时序报告。没有启动、停止或修改正在进行的PDS流程。

| 阶段 | 实际耗时 | CPU | Process CPU | 峰值内存池 |
|---|---|---|---|---|
| Compile | 2m1s | 7s | 7s | 561MB |
| Synthesize | 5m58s | 27s | 28s | 2955MB |
| Device Map | 58s | 8s | 8s | 1655MB |

耗时和警告/E错误行数原文见flow_summary.txt；各阶段警告按代码分组见warning_counts.txt，警告/E错误原文和Action摘要见logs/。消息行数不等于独立问题数量。

消息行统计：Compile W=3166/E=0；Synthesize W=10239/C=34/E=0；Device Map W=40/E=0。综合C级提示包括ConstraintEditor-2002共享引脚22行、ConstraintEditor-2009未设置PAP_IO_DRIVE 12行。Compile constant probe loop提示909行。原文保留，未自行修改约束。

## 资源

Device Map：LUT 66805（42%），FF 56157（18%），DRM 117.5（29%），APM 131（18%），Distributed RAM 750（2%），IO 109（28%），GPLL 5、PPLL 2。其余资源及PDS显示百分比原文见resource_summary.txt。

保存完整时钟、复位、CE和Other High Fanout Signal表于high_fanout.txt，RND条目另见rnd_high_fanout.txt；这只是报告覆盖到的网络，不代表所有RND网络。综合controlsets和APM/DRM/LUTRAM实例信息一并保存。本次后续归档已从SNR补取完整按模块资源表，见resource_hier.txt。

## 警告与后续

Compile的“Loop was found during constant probe”原文保留，不仅凭这条消息推断存在功能性组合环。综合报告保留未约束端口等Timing警告；Device Map包含PCF覆盖提示，原文均保留，没有修改RTL或FDC来消除警告。

本轮用户GUI显示Multi-thread routing thread size为5，本报告按5记录，不沿用手册表的10。后续等待R单独完成布局布线，再补布线轮次、Detailed routing耗时、clk_mem路径、全局及RGMII RX双沿时序和站点；这些当前不填通过值。

完整CMR/SNR/DMR见native_reports/。DMR约2.15MB，保留它用于分析完整约束、控制网络和资源信息；不提交数据库、网表、PCF、bitstream或完整原始PDS run.log。
