# 卡24 B3R：2 Mbaud加载失败

用户反馈2000000仍不行。工具实际本轮选择s3.elf，串口COM7。日志清晰打印Baud result: 2000000后，出现乱码及大量NUL，未取得新速率下的正常BIOS菜单；程序镜像sent=0，没有开始有效加载。随后串口断开，工具最终error为serial port disconnected during BIOS programming。不能将最终断开原因当作最初乱码原因。

同一会话在BIOS菜单附近仍有大量TX 1B 56...虚拟输入帧，并出现Input error，属于需要向工具维护方回传的干扰证据；未据此认定2M失败根因。

设备：Silicon Labs CP210x USB to UART Bridge (COM7)，USB VID_10C4/PID_EA60；驱动Silicon Laboratories Inc.，版本11.3.0.176。未修改驱动、波特率实现、RTL或ROM。

完整工具状态、加载状态和已解码串口日志见本目录。API缓冲仅包含seq/ts/dir/text，没有原始接收字节，故本次不伪造.raw。921600复测待用户执行，不自动降速重试。
