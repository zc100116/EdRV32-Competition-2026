# B3R/B3N ETH 连通软件（T-ETH2）

- 源码：本报告所在提交；基线 `6bab90a0`，无 RTL、规格或 T-SW1 归属文件改动。
- 环境：用户提供的仿真主机（环境不记录）；软件/主机检查在本机，GCC 15.2.0 / 主机 GCC 13.3.0。
- 器件条件：PG2L200H-6/FBB676；未执行 PDS 或实板测试。
- 公共代码：`sw/lib/eth_monitor*`；demo 复用原 PHY/本机地址/PEER、DDR 快照及 EDTM 打包，发送调度不变。
- S3 平台与 board_npu：CLINT 100 Hz；WIN3 建立对端，固定 320 B EDTM，16 条/批、WIN3 NOTIFY。
- 无 PEER 不发送；沿用 demo 的 1024 条环及满环丢最新策略；TX 源保留到 DONE_COUNT 前进。
- 网口区域沿用 demo：WIN3 `0x0a000000`/64 KiB，发送区 `0x0a100000`；与两程序工作区分离。
- B3R：RND/DISP/ETH；B3N：NPU/ETH。工具均可建立对端和看 DDR，不开放 demo 场景、视频、模型/图像检查。
- 工具在 B3R/B3N 不发送串口 `status`；WIN3 通知后板端主动输出 PEER；NPU 原测试与结束输出保留，结束后监控继续。

## Linux 验证

- 初始化：`. ~/.local/opt/edrv32/env.sh`；`git submodule update --init third_party/lvgl`。
- 构建：`for p in s3 board_npu demo demo_vision demo_vnpu; do make -C sw PROGRAM=$p -j 1; done`：5/5 成功，0 warning。
- board_npu 数据复用 `../b3-int/build/sw/board_npu/data/{board_data.h,cases.bin,cases.o}`，未重新量化。
- `PYTHONPATH=$PWD/build/python-deps QT_QPA_PLATFORM=offscreen python3 -m unittest discover tools/debug_tool/tests`：66 项，63 通过、3 跳过。
- `build/python-deps` 安装 `tools/requirements.txt` 中的 PySide6；系统 Python 已有 pyserial。
- `make -C sw/apps/demo test`：2 个二进制通过，UBSan 无错误；覆盖原 demo 和 WIN3/EDTM/无对端/TX 生命周期/错误路径。
- `python3 tools/s3/rn17.py`：511 源文件主机构建 0 warning，11 帧 PASS，2 次返回菜单检查 PASS。
- `python3 tools/check/verilog_style.py rtl fpga/rtl`：188 文件、0 warning；`git diff --check`：通过。
- SoC 命令：`for t in board_render board_npu board_vnpu; do python3 tools/regress.py smoke --path verif/soc/$t -j 1; done`。
- ETH RX 命令：`python3 tools/regress.py full --path verif/soc/sc_06_eth_rx -j 1`。
- SoC 结果：4 PASS、0 FAIL、0 lint warning；板级测试包含 `-Wall` lint，既有板级 smoke 不运行完整 S3/board_npu 或实板网口。
- 本机 Verilator/regress 入口须加 `flock /tmp/edrv32-sim.lock`；远端独立目录运行并删除构建目录。
- 本机证据：`build/board-eth-sw/{build-*,host,unittest,rn17,style,soc-summary}.log`；远端只保留本人汇总结论。

## 卡 21 实板 ETH 检查步骤

1. PC 有线网卡 `192.168.1.2/24`，连接板网口，允许 UDP 6000；板端固定 `192.168.1.10:5000`。
2. B3R 经 BIOS 加载 `build/sw/s3/s3.elf`，B3N 加载 `build/sw/board_npu/board_npu.elf`；串口保持 BIOS 所选波特率（board_npu 2 Mbaud）。
3. 工具选择 B3R/B3N，点击“建立网口连接”；监听 6000、WIN3、PEER 地址/端口一致三项完成。
4. DDR 页收到 EDTM、七端口计数与曲线更新；固定 100 Hz、约 160 ms/批。B3R 运行原 benchmark；B3N 原测试 PASS 后仍应有监控。
5. B3VN 烧录 `build/sw/demo_vnpu/demo_vnpu.bin`，应用串口 115200；选择 B3VN，建立对端并核对 DDR 页数据。
6. B3VN S2 选择 HDMI+ETH、30 fps、100 Hz：检查完整视频/EDTM、PIX/GEO 切换；HDMI/ETH/同时三档分别核对，HDMI 档 DDR 仍更新。
7. B3VN 发送 EDNM，见 `EDNM: loaded` 后切 S1；检查同 frame_id 视频/EDDT 框与 CPU HDMI 框；WIN0/1 图像检查回传 CH2/OUTPUT/EDDT 并参考比对。
8. 图像检查后下发 S1/S2 恢复摄像头；导出 EDTM CSV、串口结果和必要截图；记录 PHY、视频丢帧与三板实际连通结论。
