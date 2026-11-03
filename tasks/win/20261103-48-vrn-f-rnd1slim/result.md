# 卡48：阶段性结果与比特流归档

输入11046fb0627afc3d182a072c8b150edab44191f3，精简RND v1、Q6/OPT2 NPU，无ILA。用户另要求VRN/F各复制一份CPU125MHz实验工程；同一卡内按版本分别保存结果，不覆盖基线。

| 版本 | 本次保存内容 | 时序结论 | 比特流 |
|---|---|---|---|
| VRN CPU100MHz第一次结果 | 时序报告、关键路径、参数建议；cpu100_timing_notes.md、artifacts/VRN-cpu100m/ | CPU+0.439ns、mem-0.124ns、NPU-0.022ns；RGMII hold-0.361ns | fpga/bitstreams/EdRV32-VRN-cpu100m.sbit |
| VRN CPU125MHz | 完整阶段汇总、原生报告gzip、层次资源、高扇出、拥塞、扩展时序；cpu125_results.md、artifacts/VRN-cpu125m/ | CPU-0.436ns、mem-0.167ns、NPU+0.051ns；RGMII hold-0.361ns | fpga/bitstreams/EdRV32-VRN-cpu125m.sbit |
| VRN CPU100MHz参数重跑 | 用户已重新运行，本次不采集新结果，不覆盖第一次归档 | 未整理 | 未另归档 |
| F CPU100MHz | 进行中快照：第25轮22877未布通/65077过用；artifacts/F-cpu100m-progress/ | 未取得最终时序 | 未归档 |
| F CPU125MHz | 第117轮布通；完整报告见f_cpu125_results.md、artifacts/F-cpu125m/ | CPU-0.033ns、mem-0.010ns、NPU-0.120ns；RGMII hold-0.242ns | fpga/bitstreams/EdRV32-F-cpu125m.sbit |
| F CPU125MHz重跑r2 | 第210轮布通；f_cpu125_r2_results.md、artifacts/F-cpu125m-r2/ | CPU+0.087ns、mem+0.179ns、NPU+0.048ns；只剩已知RGMII输入慢角hold-0.242ns/5端点 | fpga/bitstreams/EdRV32-F-cpu125m-r2.sbit |

VRN125第174轮0未布通/0过用，PnR1h10m24s，Map LUT77175/FF82542/DRM250/APM345。CPU最终时钟周期8.0000ns，PLL和私有头文件频率一致。F125-r2内部时序满足，只剩项目已知RGMII输入hold例外；其他归档仍按各自报告列明违例。本轮没有取得r2上板结果，旧版上板反馈在卡51结果分支，不能代替r2。

本地工程均位于G:/codex_project/EdRV32-FPGA；100MHz为EdRV32-B3F-VRN-RND1S，125MHz为EdRV32-B3F-VRN-RND1S-CPU125。完整日志和数据库留在各工程；本卡仅回传任务要求的报告/摘要，以及用户明确要求归档的比特流。

工程准备说明见user_steps.md；125MHz局部修改及原等待队列停止说明见cpu125_experiment.md。用户从PDS直接启动125MHz流程后，Codex停止的只是仍等待的后台队列，没有结束任何PDS流程。
