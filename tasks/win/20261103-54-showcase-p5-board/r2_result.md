# 卡54第二轮 P5b 上板结果

用户已结束本轮测试，反馈“其他问题不是很大”；以下三类问题仍需处理，附带保留图片拉伸反馈。未取得完整实测证据的任务项不标记为通过。

## 输入与范围

- 本轮程序：卡54第二轮showcase-p5.elf；工具状态版本64aec2b6，代码输入efdd12e2。
- 本轮未跑PDS，未重新核对比特流时间和源码版本；既有比特流路径与硬件报告沿用之前的归档，不虚构本次重新采集的时序/资源数据。
- 第一轮NPU error和平均7fps结果保留，见result.md后半及A1_hang.log、F.log。

## 1. 实时识别仍低帧率、端到端延迟大

用户照片：识别9fps、NPU41.3ms、后处理23.2ms、端到端112.9ms；顶部CPU43%、GUI11FPS。阈值≥0.50、80类，行人1。

当前缓冲有119条vision性能行。已观察到多条npu约41ms、decode约23ms、gui约37–43ms、e2e约113–122ms，作为原文示例而非全程统计范围。后处理较第一轮177.1ms明显下降，但整体仍不到10fps，用户不满意。继续分析GUI、调度间隔、采集和显示串联开销；不要将NPU硬件耗时或后处理达标等同于系统达到目标。没有完成15分钟长测证据。

## 2. 换图片文件夹后请求卡住、虚拟输入不恢复

用户顺序：发送几张图片成功→换文件夹→卡住→虚拟按键失效→板载按键有效→退出后虚拟按键仍失效。板载按键有效，因此不能称为整机CPU死机。

- 图片request2、4、6、8完成，upload_to_done原文依次100、88、88、89；receive依次119.6、142.9、90.9、122.0ms。计时口径有待核对：部分receive大于upload_to_done，不直接认定后者包含整个传输。
- 异常现场图片TX失败、sent0/1843200，原文“同类命令正在等待设备完成”。请求10尚无对应完成证据。
- 现场工具phase=disconnected、PEER未完成，缓存app2/state2/request10/frame3/image_status1，不将缓存状态当板端仍运行在该阶段的证据。
- 需排查换目录时旧请求的取消/完成确认、命令占用释放以及虚拟输入与会话连接的耦合。具体根因未确认。
- 附带用户反馈：图片强行撑满全屏导致变形；后续应讨论保留宽高比显示、补边及预处理与框坐标映射一致性。

## 3. LVGL仍未恢复独立版本性能

用户确认跑完，集成版仍明显慢于最初单独LVGL跑分。本轮一套完整16场景和ALL，程序报告平均14fps；第一轮平均7fps。本次未重新跑独立基线，不能量化相对最初版本的下降倍数；浮窗开关未取得明确记录，不写F1/F2均完成。

| 场景 | fps |
|---|---|
| Empty screen | 28 |
| Moving wallpaper | 4 |
| Single rectangle | 28 |
| Multiple rectangles | 28 |
| Multiple RGB images | 8 |
| Multiple ARGB images | 28 |
| Rotated ARGB images | 5 |
| Multiple labels | 19 |
| Screen sized text | 7 |
| Multiple arcs | 14 |
| Containers | 12 |
| Containers with overlay | 10 |
| Containers with opa | 14 |
| Containers with opa_layer | 7 |
| Containers with scrolling | 8 |
| Widgets demo | 11 |

ALL原文：frames884、render_ms62.186、rnd_ms13.196、sw_ms21.939、other_ms27.050、clear_rnd3.164、clear_cpu0、clear_cpu_bytes0、CPU IPC0.353、icache_mpki5.640、dcache_mpki4.760。以上沿用程序统计口径，不以1000/render_ms替换其平均FPS。

Empty screen：render_ms15.668、other_ms6.335；第一轮94.639、88.827。可确认清屏路径修改带来改善，不能据此宣称性能问题全部解决。

ALL的RND p4 rd_txn15458431、wr_txn17305924、rd_beats141042672、wr_beats214336469，计数非零。原文17条split记录已保留，新增clear字段可供进一步分析。

最后一条已采集CPU统计原文：`CPU%/max_us 2/1662 0/18223855 1/823041 overlay_cpu=0.00% max_us=0`。应用最长单次18223855us、GUI823041us为本轮记录值，是否跨测试累计、是否包含阻塞需核对，不解释成稳态每次都如此。

## 用户结论与验收边界

用户反馈除上述问题外其他问题不大；这属于用户体验结论。A/B/C存在功能失败，D/E性能与长测未按完整门槛完成；CoreMark3次、20张逐张及5张参考比对、ECHO/断网恢复、完整22项和四场景采集等缺少本轮完整证据，均不补写为通过。实时性能是探索采集，不声称已通过A–C后进行正式D/E。

## 产物索引

- `artifacts/uart/r2_final.log`：最终当前会话2735条，seq1–2735，完整保留RX/TX/SYS。
- `artifacts/uart/r2_benchmark_excerpt.txt`：LVGL16场景、ALL及FPS原文。
- `artifacts/uart/r2_A_C_folder_switch.log`、`r2_vision_image_excerpt.txt`：换目录异常现场及视觉/图片耗时。
- `artifacts/tool/r2_image_folder_*`：异常现场状态；`r2_final_*`：最终工具状态、原始缓冲、压缩遥测（约2MB，保留用于性能/带宽分析）。各接收器可能重建，累计计数不作为本轮独立统计。
- `artifacts/photos/r2_vision_9fps_e2e112ms.jpg`：实拍。
- `artifacts/uart/r2_A_camera.log`、`r2_HDMI.log`及对应tool文件：早先无画面/连接问题现场；用户随后确认HDMI恢复，具体恢复原因未确认。

本次仅整理与上传，未修改软件、RTL或设备配置。
