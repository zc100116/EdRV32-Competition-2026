# R 上板：RND通过，S3异常与NES松键不停止

## 测试结论

- RND：取得29组CRC和29条ERR_CODE=0，出现RND display ready。运行仓库expect.py比对29组全部PASS，退出码0。HDMI画面没有本轮照片和逐项用户确认，不替代目视验收。
- S3：用户反馈“s3的lvgl测试程序点开就卡死”。原始日志两次打印相同异常：`S3 CPU mcause=0x00000007 mepc=0x900663bc`（seq298、537）。mcause=7对应Store/AMO access fault。此前有`lv_obj_get_display: No screen found`及多条NULL display弃用警告。保留两次异常上下文，不把警告直接定为根因。
- 本次日志未见Benchmark Summary、LVGL split及RN-17完整结果，不能记为完成或PASS。用户没有明确卡死的是哪一个LVGL子菜单；不擅自归为benchmark或widgets。
- LAYERS：日志有画面1至5的入口说明，画面5多次`claimed=11 unclaimed=0`。只证明程序进入及打印计数，没有每幅画面的照片/目视结论，不能声明五项视觉验收通过。
- NES：最初只加载nes.elf时出现ROM slot empty；之后配入用户本地“超级马里奥1超级版”，加载3个段后Load result: PASS、Run: 0x90000000，ROM prg=32 chr=8 mapper=0，NES powered on。游戏ROM及含ROM的临时ELF均不上传。
- 用户反馈：键盘按右方向后，即使松开键盘，游戏人物也不会停下来。此项验收失败；当前日志不足以确定是GUI事件、串口接收、虚拟输入状态合并还是游戏端处理导致。

## NES虚拟输入证据

保存所有可取得的按键发送帧于virtual_input_frames.tsv（从原始TX hex解码，协议`1b 56` + `<HhhBB>`，keys的bit3为right）。首个可清晰配对的右键：seq732，keys=8；seq744，keys=0。另一组seq778/783也是8→0。说明主机日志确实记录过右键及释放帧，不能直接写成“工具从未发松开包”；发送日志并非板端接收确认，也不能证明用户反馈的每次松键都对应这些样本。

本次PC侧输入通过串口发送；快照的PEER未建立、UDP监听未开启。未主动发新输入或重跑测试，避免改变用户的复现场景。

## NES帧率

nes_fps.tsv保存64条串口采样：模拟fps范围52.6–67.0，样本算术平均54.703；shown范围17.5–19.2，样本算术平均18.102。采样间隔不等，均值不是按时间加权的整体吞吐率。shown才是程序报告的显示帧率；不能以模拟fps约54判定显示达到54fps。

## 日志范围及未完成项

session.log、entries.json为采集时工具全部可取得缓冲；rx.log仅接收文本；rnd_crc_joined.log仅把GUI分成相邻两条的`RND <name> crc=`与`0x12345678`拼回一行供expect.py使用，原始entries不变，比较结果见rnd_compare.txt。

status.json、program_status.json、ethernet.json、telemetry.json和edtm.csv保存工具状态。当前串口实际connected=true、COM7/115200；board.phase字段显示disconnected并残留旧Input error，不能据此断言串口物理断开。telemetry records=0，未取得本轮S3/NES的EDTM带宽数据；不以空CSV声称带宽正常。本轮可确认UART加载成功；未取得R的网口加载成功证据。

需要Claude排查：结合s3_fault_context.log和s3_fault_symbols.txt定位PC 0x900663bc的非法存储来源；检查场景/屏幕生命周期与NULL display警告关联；沿主机释放帧到板端NES键状态消费链排查松键失效。以上是排查方向，不是已确认根因。本轮没有修改RTL、S3、NES或调试工具代码。
