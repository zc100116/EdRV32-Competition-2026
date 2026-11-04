# EdRV32 调试工具

PySide6 桌面工具。GUI、CLI 和 REST 共用串口、UDP 接收端和板端会话。
所有功能均可见；页面垂直滚动，长状态与日志自动换行，路径提供全文提示。
本版协议与板端演示程序 `sw/apps/showcase` 配套。

## 安装和启动

Windows 安装 `tools/requirements.txt` 中的依赖，双击 `启动调试工具.bat`，或运行：

```sh
python tools/debug_tool/main.py
python tools/debug_tool/main.py --connect COM7 --baud 115200
python tools/debug_tool/main.py --headless
```

Linux 验收使用 `~/.local/opt/edrv32-py/bin/python`，已安装 PySide6、pyserial、numpy、
torch 等 requirements 依赖。游戏名称位图使用
`third_party/lvgl` 中的 Noto Sans SC 字体，首次使用需初始化相应子模块。

## 连接与输入

1. PC 有线网卡配置 `192.168.1.2/24`，板端默认 `192.168.1.10:5000`，允许 PC UDP 6000。
2. 在输入页或调试页填写设备地址和本机地址，点击“建立网口连接”。绑定失败明确报错。
3. 工具每 2 秒发送一次连接请求，直到收到 HELLO；串口上的对端地址文字只作为日志。
4. 收到 HELLO 才显示网口已连接，并显示 HELLO 中的板端程序版本。
   连续 3 秒没有 STATE 即断开，并重新每 2 秒发送连接请求。
5. 全局标题栏始终显示网口连接状态和板端版本。串口连接状态独立显示。

虚拟键盘和鼠标只走网口。未连接时禁用，显示“网口未连接，虚拟设备不可用”；
串口页仅用于日志和串口调试，不影响虚拟设备。输入变化立即发送，连接期间每 100 ms
发送完整快照，包括所有按键松开的状态；断开时清空本机按下状态。

输入面板无需先点击即可使用快捷键；焦点在文本输入框时按键交给输入框。
方向键 / WASD、J=A、K=B、U=Select、I=Start、Enter、Esc、Tab=Next、Shift+Tab=Prev。
同一按钮的所有键盘映射松开后才释放。16:9 触控板映射到 1280×720 绝对坐标；
左 / 右 / 中键发送对应按钮，滚轮发送累计值。面板不回传 HDMI 画面。
离开面板或应用失去焦点时释放按键。

输入数据为 8 字节小端 `<HhhBB`：按键位图、X、Y、鼠标位图、滚轮累计值。
按键 bit0…11 依次为上、下、左、右、A、B、Select、Start、Enter、Esc、Next、Prev；
鼠标 bit0…2 为左、右、中键。UDP 应用头为大端 `!BBHI`，输入用途值 2、通知 1、
保留和偏移均为 0。不再提供串口虚拟帧或串口导出选项。

原始 UDP 发包示例（用于协议调试，末帧释放）：

```sh
python tools/debug_tool/virtual_input.py --udp 127.0.0.1:5000 --keys b,start --hold .2
```

## 应用、状态和命令

“调试 → 设备与输出”的板端应用区域可以打开应用、暂停、继续、重试，并输入游戏序号。
板端当前应用、会话状态、图像处理参数、检测门槛与类别均由 STATE 更新；
发送命令或收到 ACK 不会将请求参数当作板端实际状态。

APP、IMAGE_INFO、PROCESS、DETECT、CANCEL 都有独立序号和 ACK 流程。
ACK(1) 表示收到；ACK(2) 表示完成；ACK(3) 表示错误并给出原因。
同类型命令在 ACK(2/3) 前不再发送；PROCESS 和 DETECT 只保留最新整组参数，
上一条完成时立即发送保留的一组。不存在 CAMERA 命令，切回摄像头发送 APP(1, 打开)。

HELLO、STATE、ACK、DONE、完整检测结果由网口接收路径直接处理；
完成判定、后续命令和板端翻图请求均不等待 GUI 周期刷新。Qt 信号负责跨线程刷新界面。

## 图像处理

“调试 → 图像处理”按硬件顺序显示全部 12 项，每项先是启用开关，再是参数与
“本项恢复默认”。关闭开关保留参数；“本项恢复默认”恢复该项参数；
“全部恢复默认”恢复所有参数并关闭所有功能。

- PIX：亮度 / 对比度 → 伽马 → 第一级滤波 S1 → 第二级滤波 S2 → 灰度 → 二值化 → 反色。
- GEO：旋转 → 缩放 → 平移 → 水平镜像 → 垂直镜像。
- 亮度 −256…255，对比度 Q8 0…512，伽马十分值 3…30。
- S1 / S2 各选均值、高斯、锐化、Sobel、腐蚀、膨胀；独立开关负责旁路。
- 二值化阈值 0…255，旋转 −180…180°，缩放 50…400%，平移 X ±1280、Y ±720。
- 提供原图 / 处理结果切换。编辑停顿 200 ms 后整组发送 24 字节 PROCESS。

默认：全部关闭、亮度 0、对比度 256、伽马 10、S1/S2 高斯、阈值 128、
处理结果视图、角度 0、比例 100%、平移 0。

## 图片识别

“调试 → 目标检测”可发送模型，选择单张图片或文件夹。
文件夹按文件名排序建立 png/jpg/jpeg/bmp 列表；选择后等待手动发送，
“上一张 / 下一张”每次只发送并识别一张，不自动继续。
界面显示文件名、序号 / 总数，以及发送中 / 识别中 / 完成 / 失败。

发送前，若板端不在图片识别应用的运行状态，先发送 APP(2, 打开)，等 ACK(2)；
然后发送 IMAGE_INFO（序号从 1 开始、总数、UTF-8 文件名），等 ACK(2) 后发送 BULK_BEGIN。
收到 READY 后上传统一转换的 1280×720 小端 RGB565，等待 CH2 / OUTPUT / EDDT 和 DONE。
只接受 EDDT `request` 等于当前 BULK_BEGIN 序号的结果，其余丢弃。
完整检测结果在 DONE 时提交，缺包、板端拒绝或 5 秒应答超时使本张失败，不重传。

板端 IMAGE_STEP 直接触发本机列表的上一张 / 下一张。在途收到翻图请求时忽略并记录
“当前图片未完成，忽略翻页”，不排队；本机翻图按钮在图片进行中禁用。
“取消”发送 CANCEL，等待 ACK(2) 和当前传输的 DONE(status 6)；空闲时仅有 ACK(2)。
“回到摄像头检测”使用 APP，不重载模型。

检测设置提供 25…90% 门槛和全部 80 个 COCO 类别。收到 STATE 后同步所有选择。
可选参考模型比对：CH2 按 VIN 的 RGB565 展开、平均、量化与 letterbox 计算；
OUTPUT 使用 NPU 参考执行，EDDT 使用 Python 后处理比较。检测本身不要求安装参考依赖。

模型、图片和游戏共用 BULK_BEGIN → READY → 数据 → DONE。
模型保留 EDNM 布局（头偏移 0、描述符 0x1000、模型 0x100000，间隙补零）；
游戏上传单条 EDG2，完成后显示板端返回的游戏序号。游戏封面可留空或选 PNG / JPG。

## 串口、监控与其他工具

串口页保留文本 / HEX、行尾、保存、原始文件发送、快捷命令、规则和数据面板。
设备页保留 BIOS 串口 / 网口烧录、摄像头、HDMI / 网口输出、视频帧率与监控采样率。
“读取状态”由用户显式发送串口 `status`，建立网口连接不自动发串口命令。

视频由独立 16 ms 定时器刷新，显示接收帧率、显示帧率、丢帧及实际 socket 缓冲大小。
接收使用独立进程和共享帧槽，只有完整帧交给显示，缺包帧丢弃；不重传。
DDR 曲线保留 60 秒，支持图例筛选、高亮、拖动、缩放、自动 / 满量程纵轴、导出和回放。
七端口表显示平均等待、最长等待和紧急授权数；溢出、读空计数非零标红。
统一显示区、DDR 监控、日志和状态摘要可“放大”，按 Esc 或“复原”返回。

网口页保留原始偏移收发和 ECHO 回环测试。每个样本只发一次，超时计为丢失。
READY / DONE / ECHO_REPLY 应答上限为 5 秒，错误明确显示，不切换备用通道。

## CLI 和 REST

本机 REST 默认 `http://127.0.0.1:8765`，CLI 使用同一引擎。

```sh
python tools/debug_tool/cli.py connect COM7 --baud 115200
python tools/debug_tool/cli.py program app.elf --elf --eth --local-ip 192.168.1.2
python tools/debug_tool/cli.py processing '{"enabled":129,"brightness":24,"angle":30}'
python tools/debug_tool/cli.py yolo model build/npu/yolo
python tools/debug_tool/cli.py yolo image image.png
python tools/debug_tool/cli.py telemetry export build/debug_tool/capture.csv
python tools/debug_tool/cli.py tail -f
```

| 方法 | 路径 | 内容 |
|---|---|---|
| GET | `/api/status`、`/api/board` | 串口状态；连接、版本、STATE、日志摘要与错误 |
| POST | `/api/board/network` | `{boardIp?,boardPort?,localIp?}` 建立网口连接 |
| GET / POST | `/api/processing` | STATE 参数 / 修改参数，省略项沿用 STATE，发送整组 PROCESS |
| POST | `/api/yolo/model`、`/api/yolo/image` | `{path,boardIp,boardPort,localPort,localIp?}` |
| POST | `/api/virtual-input` | `{keys,x,y,mouse,wheel?}`，未连接明确报错 |
| GET | `/api/ethernet/status` | UDP、上传、ECHO 状态 |
| POST | `/api/ethernet/receive/start`、`/api/ethernet/receive/stop` | `{localPort,localIp?,directory?,mode?}` / `{}` |
| POST | `/api/ethernet/send` | 原始数据上传 |
| GET | `/api/telemetry`、`/api/telemetry/csv` | 最新监控值 / CSV |
| POST | `/api/telemetry/export`、`/api/telemetry/replay`、`/api/telemetry/clear` | 导出 / 回放 / 清空 |

串口连接、快捷命令、规则、文件传输和 BIOS API 保持原用途。
PROCESS 的 JSON 字段与冻结协议同名：`enabled,brightness,contrast,gamma_tenths,stage1,stage2,`
`threshold,view,angle,scale_percent,translate_x,translate_y`。不再使用旧的串口 PIX/GEO 参数接口。

## 验证与截图

```sh
git submodule update --init third_party/lvgl
QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests
python3 -m compileall -q tools/debug_tool
python3 tools/check/verilog_style.py tools/debug_tool
git diff --check
```

假板端覆盖 HELLO、STATE 断开和重新连接、无串口虚拟输入、100 ms 快照、五种命令的
ACK、参数合并、STATE 驱动界面、IMAGE_INFO 顺序、手动翻图、IMAGE_STEP、CANCEL、
请求号过滤、逐项启用与默认值，以及不依赖 GUI 定时器的完成处理。
原有实际 UDP CH2 / OUTPUT / EDDT 与 NPU 参考比对测试仍保留。

截图脚本使用模拟串口和 UDP 数据，显示的版本为 SIMULATED，不是实板测量。

```sh
QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python tools/debug_tool/render_shot.py \
  build/debug_tool/processing.png --state vision --page 1 --width 1366 --height 768
```

`--page 0/1/2` 选择设备 / 处理 / 图片，`--scroll-bottom` 或 `--scroll-position 0.5`
显示其他滚动区域，`--main-page 5` 显示输入，`--state detection` 生成图片回传。
P5 验收截图保存在任务指定的 `SOC系统设计/outputs/p5-tool/`，不提交。
