# EdRV32 调试工具

PySide6 桌面工具。GUI、CLI 和 REST 共用串口、UDP 接收端和板端会话。
所有功能均可见；页面垂直滚动，长状态与日志自动换行，路径提供全文提示。
本版协议依据[演示系统设计](../../docs/design/2026-11-03-showcase-p5-replan.md)第 8 节。

## 安装和启动

Windows 安装 `tools/requirements.txt` 中的依赖，双击 `启动调试工具.bat`，或运行：

```sh
python tools/debug_tool/main.py
python tools/debug_tool/main.py --connect COM7 --baud 115200
python tools/debug_tool/main.py --headless
```

Linux 验收使用 `~/.local/opt/edrv32-py/bin/python`，已安装 PySide6、pyserial、numpy、
torch 等 requirements 依赖。参考模型使用 `third_party/ultralytics`；游戏名称位图使用
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
板端应用、会话状态、检测门槛与类别由 STATE 更新；积木链由 CHAIN_STATE 更新；
发送命令或收到 ACK 不会将请求参数当作板端实际状态。

APP、IMAGE_INFO、CHAIN、PRESET、DETECT、CANCEL 都有独立序号和 ACK 流程。
ACK(1) 表示收到；ACK(2) 表示完成；ACK(3) 表示错误并给出原因。
同类型命令在 ACK(2/3) 前不再发送；DETECT 只保留最新整组参数，
上一条完成时立即发送保留的一组。不存在 CAMERA 命令，切回摄像头发送 APP(1, 打开)。

HELLO、STATE、ACK、DONE、完整检测结果由网口接收路径直接处理；
完成判定、后续命令和板端翻图请求均不等待 GUI 周期刷新。Qt 信号负责跨线程刷新界面。

## 视觉流水线

“调试 → 视觉流水线”合并图像处理与目标检测，提供 8 个预设、来源选择、
横向积木链和硬件路径。积木库支持拖入或双击添加；链内拖动排序，选中后可删除、
查看此级输出、看来源原图、返回最终输出，或编辑全部参数（包括几何镜像和叠加选项）。
检测门槛和类别在同页下方的检测设置中编辑。

每次修改整组发送 CHAIN（100 字节），预设按钮发送 PRESET；接受后的链以
CHAIN_STATE 为准。修改后 preset 清零；ACK(3) 显示对应中文规则，板端原链保持不变。
最多 8 块积木、1 块检测；叠加框之前必须有检测，叠加必须选框或界面。
硬件路径显示 PIPE_STATS 中每跳的引擎、积木范围和耗时，以及端到端延迟、帧率、
框滞后、NPU 耗时和 DDR 带宽（预算 1.95 GB/s）。
流水线页集中显示链与图像；完整 DDR 端口监控和日志在设备与输出页。

## 图片识别

“调试 → 视觉流水线”可发送模型，选择单张图片或文件夹。
文件夹按文件名排序建立 png/jpg/jpeg/bmp 列表；选择后等待手动发送，
“上一张 / 下一张”每次只发送并识别一张，不自动继续。
界面显示文件名、序号 / 总数，以及发送中 / 识别中 / 完成 / 失败。

每张图片发送前先发送 APP(1, 打开)，等 ACK(2)，再发 CHAIN（来源改为 PC 图片、
保留当前积木并清除预设编号），等 ACK(2)；
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
python tools/debug_tool/cli.py pipeline '{"source":0,"view":255,"preset":0,"blocks":[]}'
python tools/debug_tool/cli.py yolo model build/npu/yolo
python tools/debug_tool/cli.py yolo image image.png
python tools/debug_tool/cli.py telemetry export build/debug_tool/capture.csv
python tools/debug_tool/cli.py tail -f
```

| 方法 | 路径 | 内容 |
|---|---|---|
| GET | `/api/status`、`/api/board` | 串口状态；连接、版本、STATE、日志摘要与错误 |
| POST | `/api/board/network` | `{boardIp?,boardPort?,localIp?}` 建立网口连接 |
| GET / POST | `/api/pipeline` | 已确认的积木链 / 整组替换积木链 |
| POST | `/api/yolo/model`、`/api/yolo/image` | `{path,boardIp,boardPort,localPort,localIp?}` |
| POST | `/api/virtual-input` | `{keys,x,y,mouse,wheel?}`，未连接明确报错 |
| GET | `/api/ethernet/status` | UDP、上传、ECHO 状态 |
| POST | `/api/ethernet/receive/start`、`/api/ethernet/receive/stop` | `{localPort,localIp?,directory?,mode?}` / `{}` |
| POST | `/api/ethernet/send` | 原始数据上传 |
| GET | `/api/telemetry`、`/api/telemetry/csv` | 最新监控值 / CSV |
| POST | `/api/telemetry/export`、`/api/telemetry/replay`、`/api/telemetry/clear` | 导出 / 回放 / 清空 |

串口连接、快捷命令、规则、文件传输和 BIOS API 保持原用途。
CHAIN JSON 为 `{source,view,preset,blocks:[{type,flags,p:[p0,p1,p2,p3,p4]}]}`，
二进制字段及范围见 `docs/design/2026-11-14-showcase-vision-pipeline.md` 第 7 节。
旧 PROCESS、串口 PIX/GEO 参数接口已删除。

## 验证与截图

```sh
git submodule update --init third_party/lvgl
QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests
python3 -m compileall -q tools/debug_tool
python3 tools/check/verilog_style.py tools/debug_tool
git diff --check
```

假板端覆盖 HELLO、STATE 断开和重新连接、无串口虚拟输入、100 ms 快照、链命令的
ACK、DETECT 参数合并、STATE 驱动界面、IMAGE_INFO 顺序、手动翻图、IMAGE_STEP、CANCEL、
请求号过滤、链编解码与规则拒绝，以及不依赖 GUI 定时器的完成处理。
原有实际 UDP CH2 / OUTPUT / EDDT 与 NPU 参考比对测试仍保留。

截图脚本使用模拟串口和 UDP 数据，显示的版本为 SIMULATED，不是实板测量。

```sh
QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python tools/debug_tool/render_shot.py \
  build/debug_tool/pipeline/pipeline-1366x768.png --state pipeline --width 1366 --height 768
```

`--page 0/1` 选择设备 / 视觉流水线，`--scroll-bottom` 或 `--scroll-position 0.5`
显示其他滚动区域，`--main-page 5` 显示输入，`--state detection` 生成图片回传。
P5 验收截图保存在任务指定的 `SOC系统设计/outputs/p5-tool/`，不提交。

流水线模拟板端（纯主机 UDP，所有耗时均为示例）：

```sh
python tools/debug_tool/telemetry_sim.py --mode pipeline --host 127.0.0.1 --port 5000 --seconds 60
QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover \
  -s tools/debug_tool/tests -p test_pipeline.py
```

GUI 本机地址和板端地址均选 127.0.0.1，建立连接后打开视觉流水线应用。
完整流程测试实际运行 UDP 模拟端、点击预设、投递 Qt 拖放事件并检查中文拒绝原因。
