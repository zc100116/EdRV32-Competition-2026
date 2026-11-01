# ETH视频60秒采集

串口加载新版demo_vision成功，输出设为ETH（Output mode:1），保持60秒。0/10/30/60秒快照rx packets均0、bytes均0、PEER=0.0.0.0:0，未建立对端。EDTM records=0。用户反馈视频窗口“什么都没有”。

Video skips四次均为0，但视频未成功建立，不能据此记为无丢帧或流畅。GUI接收/显示fps及丢弃帧数数值未取得，未编造；空EDTM CSV不代表带宽正常。

按两端status的mtime/100MHz计算，CLINT采样间隔60.024137s，camera0/1帧率分别29.98794/29.98794fps。相机有帧不等于网口输出成功；计数/mtime原文见serial_status_samples.json及uart.log。

只发送任务要求的连接请求、输出切换和状态查询；没有改PHY延迟或自动复位重试。本次网口失败如实保留。
