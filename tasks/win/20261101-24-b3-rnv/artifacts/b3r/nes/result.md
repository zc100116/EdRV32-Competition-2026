# 卡24 B3R NES测试

使用卡24src/nes.elf，ROM单独加载本地用户提供的“超级马里奥1超级版.nes”，未打入ELF、未复制ROM至任务产物。使用tools/board/uart_tool.py --elf --rom <本地ROM> --baud 115200 --port COM7；用户按KEY1复位后Load result: PASS、Run: 0x90000000，NES powered on，PRG32KiB/CHR8KiB、mapper0。

加载器采集155条fps样本，模拟fps平均54.53，shown平均18.07；完整范围见fps_summary.txt。样本含标题/游戏阶段，不当作固定场景跑分。原始加载及运行串口见load_and_run.raw/log，恢复GUI后日志见gui_session.log。

按前一条操作清单（键盘左右按住1–2秒后松开、左右各5次，鼠标虚拟方向键复测），用户反馈“ok了，正常”，据此记录松键功能正常。此前NES独立加载时ROM槽为空的失败现象已经通过单独加载ROM解决，不归为游戏兼容失败。

未取得本轮NES EDTM数据或画面照片，未填遥测性能。
