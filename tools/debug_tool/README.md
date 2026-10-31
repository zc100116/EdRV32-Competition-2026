# EdRV32 调试工具

PySide6 桌面工具，GUI、CLI 和 REST 共用串口、UDP 接收端和会话状态。
全部功能始终提供，用户选择要烧录的镜像；工具不选择板型、不探测模块是否存在，
也不判断某项操作在当前硬件上是否有效。

“调试”导航中按功能分成三个页面：

- **设备与输出**：BIOS 烧录、摄像头功能、HDMI / 网口输出、视频目标帧率与监控采样率。
- **图像处理**：点运算、两级滤波和几何变换；修改后约 200 ms 自动下发。
- **目标检测**：模型加载、单张图片或文件夹、原图叠框、实测往返时间与 fps、可选参考比对。

右侧统一显示视频、原图或检测结果；底部显示 DDR 监控和会话日志。
控件过多时按页垂直滚动，每个分组保持完整；文件路径可编辑并悬停查看全文，
长日志使用横向滚动，规则正则可悬停查看全文。表头完整显示，长数值提供全文提示。

![图像处理，1366×768](assets/processing-1366x768.png)
<!-- 截图：QT_QPA_PLATFORM=offscreen python tools/debug_tool/render_shot.py tools/debug_tool/assets/processing-1366x768.png --state vision --page 1 --width 1366 --height 768；telemetry_sim 合成数据，非实板测量。 -->

## 安装与启动

Windows 安装 `tools/requirements.txt` 中的 PySide6、pyserial，双击
`启动调试工具.bat`，或执行：

```sh
python tools/debug_tool/main.py
python tools/debug_tool/main.py --connect COM7 --baud 115200
python tools/debug_tool/main.py --headless
```

Linux 使用已安装同一 requirements 的 Python 环境；本次验收使用
`~/.local/opt/edrv32-py/bin/python`。NPU 参考执行另需 requirements 中已有的
numpy、torch 等依赖和 `third_party/ultralytics` 子模块。

## 连接、烧录与监控

1. PC 有线网卡设为同网段地址，例如 `192.168.1.2/24`；板子固定 `192.168.1.10`。
   允许 PC UDP 6000，板端 UDP 5000。串口页选择端口、115200、8N1 并连接。
2. KEY1 + 复位进入 BIOS。“设备与输出”选择 ELF 或 `.bin`，选择串口 / 网口传输。
   `.bin` 显式填写烧录和运行地址，SRAM 通常均为 `0x10000000`；ELF 按 PT_LOAD
   加载并跳转 e_entry。网口传输填写本机 IP。烧录后自动运行，状态 / 失败原因见原位置和日志。
3. 点击“建立网口连接”，依次监听、发送连接短包、核对板端 PEER、累计视频 / EDTM 数据。
   四格分别记录时间；数据包数与完整视频帧数分开统计。同一个 socket 接收全部业务。
4. 按功能设置摄像头输入、输出、视频 fps、采样 Hz。视频 fps 是实收完整帧计算值；
   目标帧率受源帧率、推理和网口带宽限制。串口 `status` 摘要显示板端设置与计数。
5. DDR 曲线保留 60 s，提供带宽 / 利用率 / 可选读延迟；七端口表列平均等待、最长等待、
   紧急授权数，等待单位为 clk_mem 周期。暂停只暂停绘图，CSV 仍保留原始数据。
   导出 / 回放 / 清空按钮用于记录和复现；溢出、读空计数非零标红。

## 图像处理

点运算 1：亮度 / 对比度开关、对比度 Q8（256 = 1 倍）、亮度 −256–255、
Gamma 开关和任意正 Gamma 值。固件计算 Gamma 表，写入未使用的 bank 后切换。
两个 3×3 级独立选择关闭、均值、高斯、锐化、Sobel、腐蚀或膨胀。
点运算 2：灰度、二值化及 0–255 阈值、反色，各开关可同时启用。

几何变换：总开关，任意角度（精度 0.1°），独立 X/Y 缩放（精度 0.001），
“锁定比例”默认打开，关闭后两轴独立；X/Y 平移和水平 / 垂直镜像。
比例 1.000 为原尺寸、0.500 为缩小一半、2.000 为放大两倍，正角度顺时针。
放大没有人为倍率上限；固件按 GEO 2.4 检查实际 Q16.16 矩阵，超出范围明确报错且不下发。
连续编辑同一组参数会合并，停顿约 200 ms 后通过串口发送一条完整参数命令。
原有预设和 KEY 循环仍可使用；线格式及单位见[演示程序命令表](../../sw/apps/demo/README.md#串口命令)。

## 目标检测

选择 `compile_yolo.py` 输出目录并发送模型，等待串口 `EDNM: loaded`。
选择任意尺寸图片后点击发送，工具统一缩放到 1280×720、小端 RGB565；
所有演示检测程序采用相同图像协议，图像缓冲自动交替。
回传顺序统一为 CH2（983040 B）、OUTPUT（725760 B）、EDDT；最后的检测通知结束该图。
接收完成后在原图尺寸上叠框，记录从开始发送到最终通知的往返 ms 和平均检测 fps。

“文件夹”按文件名排序处理 png/jpg/jpeg/bmp，收到本张完整回传后才发下一张，
显示包含主机转换和传输开销的文件夹平均 fps。检测不要求安装参考模型依赖。
需要核对数值时选择配套量化 JSON 并点击“运行参考模型并比对”：CH2 使用实际发送的
RGB565 按 VIN 2.8 展开、平均、量化和 letterbox；OUTPUT 执行 NPU 参考模型；
EDDT 使用 Python 后处理逐项比较，显示差异字节数、首差异和框差异。

![目标检测，1366×768](assets/detection-1366x768.png)
<!-- 截图：render_shot.py --state detection --page 2 --width 1366 --height 768；输入和检测结果由 telemetry_sim 通过真实 UDP 回环生成，非实板测量。 -->

## CLI 与 REST

CLI 使用同一个本机 REST 引擎，默认 `http://127.0.0.1:8765`。
路径按工具所在主机解析，参数线单位为整数：角度 0.1°、比例/Gamma 千分值、平移像素。

```sh
python tools/debug_tool/cli.py connect COM7 --baud 115200
python tools/debug_tool/cli.py program app.bin --addr 0x10000000 --entry 0x10000000
python tools/debug_tool/cli.py program app.elf --elf --eth --local-ip 192.168.1.2
python tools/debug_tool/cli.py scene s2
python tools/debug_tool/cli.py processing pix '{"bc":1,"contrast":320,"brightness":24,"stage1":2}'
python tools/debug_tool/cli.py processing geo '{"enabled":1,"angle":123,"scale_x":1500,"scale_y":750}'
python tools/debug_tool/cli.py yolo model build/npu/yolo
python tools/debug_tool/cli.py yolo image image.png
python tools/debug_tool/cli.py telemetry latest
python tools/debug_tool/cli.py telemetry export build/debug_tool/capture.csv
python tools/debug_tool/cli.py tail -f
```

| 方法 | 路径 | 参数 / 结果 |
|---|---|---|
| GET | `/api/status`、`/api/board` | 串口 / 烧录状态；阶段、四步连接、数据计数、peer、摘要、错误 |
| POST | `/api/board/network` | `{boardIp?,boardPort?}`；建立网口连接 |
| GET / POST | `/api/processing`、`/api/processing/pix`、`/api/processing/geo` | 读取两组设置 / 修改一组；省略项沿用该组当前值 |
| GET | `/api/ports` | 串口枚举 |
| POST | `/api/connect`、`/api/disconnect` | `{port,baud,dataBits?,parity?,stopBits?,dtr?,rts?}` / `{}` |
| POST | `/api/send`、`/api/options`、`/api/modem` | `{text,ending?,hex?}` / `{encoding}` / `{dtr?,rts?}` |
| GET | `/api/buffer`、`/api/buffer/download` | 增量日志 / 全部日志 |
| POST | `/api/clear`、`/api/save` | `{}` / `{path?}` |
| GET / POST | `/api/commands`、`/api/rules` | 列表 / 创建；PUT、DELETE `/{id}` 与命令 `/{id}/send` 保留 |
| POST | `/api/commands/replace` | `{commands}` |
| GET / POST | `/api/params`、`/api/params/clear` | 规则提取值 / 清空 |
| POST / GET | `/api/file/send`、`/api/file/status` | `{path,echo?}` / 串口文件状态，取消 `/api/file/cancel` |
| POST / GET | `/api/program`、`/api/program/status` | `{path,elf?,baud?,addr?,entry?,eth?,localIp?}` / BIOS 状态 |
| GET | `/api/ethernet/status` | 共用 UDP 传输状态 |
| POST | `/api/ethernet/send` | `{path,boardIp,boardPort,localPort,window?,offset?,interval?}`；底层数据用途编号见 demo 协议表 |
| POST | `/api/ethernet/receive/start`、`/api/ethernet/receive/stop` | `{localPort,directory?,mode?}` / `{}`；mode=files/video/yolo/console |
| GET | `/api/telemetry`、`/api/telemetry/csv` | 监控最新值 / 原始 CSV |
| POST | `/api/telemetry/export`、`/api/telemetry/replay`、`/api/telemetry/clear` | `{path}` / `{path}` / `{}` |
| GET / POST | `/api/scenes`、`/api/scenes/send` | 预设映射 / `{name,rate?}` |
| POST | `/api/yolo/model`、`/api/yolo/image` | `{path,boardIp,boardPort,localPort}`；图像缓冲自动交替 |

PIX 键：`bc,contrast,brightness,gamma_en,gamma,stage1,stage2,gray,binary,threshold,invert`。
GEO 键：`enabled,angle,scale_x,scale_y,translate_x,translate_y,mirror_x,mirror_y`。
GUI 比例锁定只联动输入控件，线上始终发送两个独立比例。
通用串口页保留文本 / HEX、行尾、保存、原始文件发送、快捷命令、规则和数据面板；
通用网口页按“图像缓冲 A/B、模型、控制与监控”选择用途，保留原始偏移收发。

## 测试、模拟与截图

```sh
python -m unittest discover -s tools/debug_tool/tests -v
python -m unittest discover -s tools/board/tests -v
make -C sw/apps/demo test
python tools/debug_tool/telemetry_sim.py --mode detection --host 127.0.0.1 --port 5000 \
  --model tasks/win/20261029-09-b3-software/src/npu \
  --quant tasks/win/20261029-09-b3-software/src/npu/quantization.json --frames 2
```

检测模拟板收到真实 RGB565，按 VIN 参考生成 CH2，执行真实 NPU / 后处理参考，
经 UDP 按三块协议返回。串口参数端到端测试使用 `telemetry_sim.run_processing` 与真实 PTY，
REST / CLI → SerialEngine → 模拟串口 → 状态摘要；只替换 PTY 不支持的 DTR/RTS ioctl。
`test_processing.py` 另测 200 ms 合并、比例锁定/解锁和同时启用全部 PIX 阶段。

全部页面截图如下；图像处理分顶端和几何区域，滚动可访问所有参数。

| 页面 | 1366×768 | 1920×1080 |
|---|---|---|
| 串口连接 | [截图](assets/connection-1366x768.png) | [截图](assets/connection-1920x1080.png) |
| 快捷命令 | [截图](assets/commands-1366x768.png) | [截图](assets/commands-1920x1080.png) |
| 规则与数据 | [截图](assets/rules-1366x768.png) | [截图](assets/rules-1920x1080.png) |
| 通用网口 | [截图](assets/network-1366x768.png) | [截图](assets/network-1920x1080.png) |
| 设备与输出 | [截图](assets/device-1366x768.png) | [截图](assets/device-1920x1080.png) |
| 图像处理 | [截图](assets/processing-1366x768.png) | [截图](assets/processing-1920x1080.png) |
| 点运算 2 | [截图](assets/point-1366x768.png) | [截图](assets/point-1920x1080.png) |
| 输出与状态 | [截图](assets/output-1366x768.png) | [截图](assets/output-1920x1080.png) |
| 检测参考比对 | [截图](assets/reference-1366x768.png) | [截图](assets/reference-1920x1080.png) |
| 网口接收 | [截图](assets/receive-1366x768.png) | [截图](assets/receive-1920x1080.png) |
| 几何区域 | [截图](assets/geometry-1366x768.png) | [截图](assets/geometry-1920x1080.png) |
| 目标检测 | [截图](assets/detection-1366x768.png) | [截图](assets/detection-1920x1080.png) |

截图统一由 `render_shot.py` 生成，使用 `--width/--height`、`--main-page 0..4`、
`--page 0..2`；`--state vision/detection` 注入模拟串口并通过 telemetry_sim 真实 UDP
回环生成数据，`--scroll-bottom` 显示几何区域。工具实际核对窗口尺寸、完整视频/检测与 EDTM。

## T-UI1 验收记录

- 基线 `5000fe71`；实现为本提交，可用 `git log -1 --format=%H -- tools/debug_tool/README.md` 定位。
- 环境：xPack GCC 15.2.0，主机 GCC 13.3，Python 3.12，PySide6 6.12.0、pyserial 3.5。
- 四程序：`. ~/.local/opt/edrv32/env.sh` 后逐个 `make -C sw PROGRAM=<程序> MEMORY=sram -j1`。
- 编译均采用 C11、`-Wall -Wextra -Werror`，0 warning；摄像头程序额外 `-Os`，NPU 程序 `-O2`。
- `riscv-none-elf-size`，单位 B：

| 程序 | text | data | bss | 合计 |
|---|---:|---:|---:|---:|
| demo | 57440 | 0 | 5568 | 63008 |
| demo_vision | 39352 | 0 | 1084 | 40436 |
| demo_vnpu | 56432 | 0 | 5516 | 61948 |
| demo_npu | 22572 | 0 | 1920 | 24492 |

- `make -C sw/apps/demo test`：原主机测试、监控、NPU 实际网络/推理、参数应用及 Python 3 项全部通过，UBSan 无错误。
- 新增覆盖：PIX 字段/完整 Gamma 表、两个 bank 交替；GEO 全角度/两轴比例/镜像/平移、覆盖与 Q16.16 超限，不下发错误配置。
- CPU CH2：固定种子 20261031 的完整 1280×720 随机 RGB565，983040 B 与独立 Python VIN 2.8 参考逐字节一致。
- `QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests -v`：71 项通过，无跳过。
- 同环境 `python -m unittest discover -s tools/board/tests -v`：全部 10 项通过。
- 参数 E2E：真实 REST / CLI / PTY，经 telemetry_sim 收到完整 PIX 和 GEO 命令并返回状态；Qt 验证 200 ms 合并和比例锁定。
- 检测 E2E：telemetry_sim 接收两张不同尺寸图片、自动交替缓冲，真实 NPU 参考；CH2/OUTPUT/EDDT 三块和逐项比对全部一致。
- 24 张截图：1366×768、1920×1080 的全部页面及几何区域，数据来自模拟 UDP。
- 布局检查：逐页检查 QLabel 换行高度、按钮文字宽度、数字内部编辑区宽度、滚动控件可达性、规则编辑按钮与七行表格可视范围；长正则/路径/数值用全文提示，日志横向滚动。
- 人工逐张查看截图，核对标签、按钮、表头、数值和滚动后的几何控件，无裁字。
- `python -m compileall -q tools/debug_tool`、`git diff --check`、`python tools/check/verilog_style.py sw/apps/demo sw/lib tools/debug_tool` 通过；无 RTL 文件，Verilator lint 不适用。
- 日志：`build/t-ui1-{demo,demo_vision,demo_vnpu,demo_npu,host,tools,board,shots}.log`，大小 `build/t-ui1-size.txt`。
- 未运行 RTL 仿真或实板测试；截图与 fps 为合成环境数据，实板摄像头、HDMI、PHY 效果待上板确认。
