# ETH视频采集与用户截图

新版demo_vision经COM7/115200加载并运行，Output mode=1（ETH），目标30fps、监控100Hz。采集期间没有运行PDS或修改PHY延迟。

0/10/30/60秒快照均PEER=192.168.1.2:6000，接收active且error=null，数据持续增长。0→60秒UDP累计包数79552→3284830，字节81416160→3361858048；这些是包/字节计数，不当作视频帧数或fps。

EDTM records165→6149，序号缺口lost0→16，decode errors保持0；video_skipped2→23。core/telemetry.py中的video_skipped为EDTM record['vid_skip']累计，不是PC丢弃的不完整视频帧计数。串口status的Video skips(current window)四次均0，反映查询当时窗口；不能用这四个零否定EDTM累计有跳帧。Monitor dropped records保持2381，连接前已有值未计为采集期间新增。

相机帧率：CLINT间隔60.00105375s，camera0/1各增加1800帧，均29.99947fps；VIN CH0 overflow四次均0。

用户反馈显示正常；采集后截图显示接收30.5fps、显示27.8fps、丢弃帧0、接收缓冲64MiB、网口跳帧33；DDR监控丢失16。截图是单时点、晚于API60秒窗口，不能当作窗口平均，也不能把截图跳帧33替换窗口末快照23。GUI起点帧率及丢弃计数没有截图记录，故不编造起末GUI差值。

用户截图已保存../photos/video_eth_gui.png，文字字段见gui_observation.md；串口查询、工具状态与CSV保存于本目录。视频正常/PHY10次成功与slow hold违例分别记录；未将所有丢失类指标都写成0或不增长。
