# 本轮串口采集



原始会话见serial_console_session.log；分段日志保留原时间戳和方向。未向板卡发送新指令。

按键第一次NOT PRESSED within wait，第二次按下3748 ms、松开4003 ms、保持255 ms、PASS；两次均保留。

菜单3系统信息：PASS

本轮LED目视观察未另行提供；串口打印按下时LED应全亮，不冒充用户已确认。

O2: {'Iterations': '5000', 'Cycles': '1387629692', 'Instructions': '1441025033', 'Iterations/Sec': '360.326', 'CoreMark/MHz': '3.603', 'IPC': '1.038', 'CoreMark result': 'PASS', 'Compiler flags': '-march=rv32im_zicsr_zifencei -mabi=ilp32 -std=c11 -Wall -Wextra -Werror -O2 -ffreestanding -fno-builtin -ffunction-sections -fdata-sections -DITERATIONS=10', 'Score status': 'duration >= 10 s; see CoreMark reporting rules', 'seconds': 13.87629692}

tuned: 未取得；当前会话没有相应构建运行记录。
