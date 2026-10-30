# 测试清单

| 项目 | 结果 | 证据 |
|---|---|---|
| 复用卡14 B3R bitstream | 本轮不重新综合或布线 | 用户按任务继续测试 |
| 新版S3 benchmark自然结束 | 已完成 | Benchmark Summary及ALL行 |
| LVGL split 16场景+ALL | 17/17 | lvgl_split.tsv |
| RND type统计 | 已保存 | rnd_type_statistics.txt |
| 外部演示ROM加载 | PASS | 三段Load result: PASS，ROM mapper=0 |
| 演示画面、人物移动、板上按键 | 用户确认正常 | 用户回复“正常的” |
| NES帧率 | 已取得51行 | nes_template_fps.tsv |
| 用户自备SMB ROM | 未执行 | 用户暂无ROM，要求结束测试并上传 |
| 结束采集 | 已停止本次UART辅助进程，释放COM7 | 板端程序未复位或停止 |
