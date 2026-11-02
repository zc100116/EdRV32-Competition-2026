# 当前状态

A/B用户均已开始Place & Route。

A：G:/codex_project/EdRV32-FPGA/EdRV32-B3F/EdRV32-B3F-card31.pds。
B：G:/codex_project/EdRV32-FPGA/EdRV32-B3F-B/EdRV32-B3F-card33-B.pds。

B首次复制后只跑Map没有加载区域，现已重新Compile、Synthesize ADS、Device Map，并确认fp_left生效。B不要重执行通用导入脚本，以免添加回A默认FDC。

A/B：decongestion2、拥塞图开启、路由线程5。
任一版本第40轮unrouted>18000停止该版本。PnR完成或止损后回传进度和时序；成功版本再生成bitstream、按任务卡上板。
