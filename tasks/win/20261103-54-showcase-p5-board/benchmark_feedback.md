# 卡54 LVGL benchmark低帧率反馈

用户确认本轮benchmark已完成，集成版帧率仍很低，主观明显慢于单独LVGL跑分。本次没有同步重测独立程序，暂不量化下降倍数。

板端原文报告平均7 fps，16场景为：11、3、27、15、4、7、5、8、4、5、7、7、7、5、4、7 fps，顺序见 F_benchmark_summary.txt。

ALL原文：frames=464，render_ms=129.276，rnd_ms=10.889，sw_ms=26.955，other_ms=91.432；cpu_ipc=0.245，icache_mpki=5.236，dcache_mpki=19.832。这些为程序输出口径，不用1000/render_ms替换其报告FPS。

其余耗时other_ms显著高于rnd_ms，提示需要继续拆分CPU/渲染框架/同步等待等开销，尚不能据此直接归因于调度器。xbar_rnd_p4相关计数在本轮ALL为0，不可解释为RND无总线流量，应核对采样/计数来源。

已保存16个场景及ALL共17条LVGL split记录；其中部分行混入CPU%/max_us输出，属于原始串口输出交错，并非采集时主动截断。该现象会影响解析，应一并修复串口输出调度。原始记录完整保留。

产物：artifacts/uart/F.log、F_benchmark_summary.txt；artifacts/tool/F_benchmark_buffer.json、F_benchmark_status.json。
本轮浮窗是否打开、结果页照片：未取得，不擅自认定为F1或F2均完成。此前A1进入视觉识别触发NPU error的现场另存A1_hang.log。
