# B3N BIOS 网口烧录与 2 Mbaud 切换

## 1. 现象

卡 23 B3N 结果分支 `origin/win/20261031-23-b3-converged`（80baca24），
`tasks/win/20261031-23-b3-converged/artifacts/b3n/uart/eth_load_*`：

- 2 Mbaud：旧速率正确读到 `Baud result: 2000000`，随后乱码及零字节，主机停在
  `wait_menu`。日志没有可识别的新速率菜单。
- 115200：板端打印 link up、load ready；主机 `sent=total=5212944`、
  `wait_result`，未收到 PASS、FAIL bytes 或 Run；邻居项 Unreachable。
- 同一 bitstream 的 demo_npu 上传模型成功，打印 `EDNM: loaded`。

原始观察文件为 `eth_load_observation.txt`。115200 串口日志报告固件 build commit
`506f07e4`；该提交与本次开发基线 `63a14aba` 的相关 BIOS、共享工具和 ETH 初始化
源码相同。结果分支的提交号不等于 ROM 内固件的 build commit。

## 2. 复现

开发基线：`63a14aba`；规格授权：`22440f44` 的 SoC v0.22 7.5(3a)。
最终实现提交可由 `git log -1 --format=%h -- docs/debug/2026-11-01-bios-eth-load.md` 查询。
软件编译器 GCC 15.2.0；SoC 仿真器版本、结果见第 6 节；定向激励无随机种子。

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=bootloader -j1
python3 -m unittest discover -s sw/boot/tests -v
python3 -m unittest discover -s tools/board/tests -v
python3 -m unittest tools.debug_tool.tests.test_program -v
QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests
flock /tmp/edrv32-sim.lock python3 verif/soc/sc_bios_eth/run.py
flock /tmp/edrv32-sim.lock python3 verif/soc/board_b1/run.py load
```

2 Mbaud 的主机时序复现为 `test_menu_before_host_switch_is_lost`：fake 板端在结果行
之后 1 ms 发新速率菜单，主机用 80 ms 配置串口，模拟错误速率字节后确认停在
`wait_menu`。配套用例 `test_2000000_host_takes_80ms_to_reconfigure` 在 100 ms 后发菜单，
相同主机延迟下完成 ELF 加载。它验证主机与时序模型的交互，不等于 Windows USB 实测。

## 3. 观察

### BIOS 与能工作的应用、诊断路径

| 项目 | BIOS `sw/boot/main.c:eth_load` | demo `sw/lib/eth_monitor.c`、`sw/apps/demo/network.c` | `sw/tests/eth_diag/main.c` |
|---|---|---|---|
| 入口控制 | 先 cache 维护、CTRL=0 | 本地初始化，配置窗口、注册 IRQ 后 ENABLE | PHY 初始化、配置窗口和广播对端后 ENABLE |
| PHY 复位 | assert 10 ms，release 后 100 ms，可串口取消 | assert 10 ms，release 后 100 ms | 相同 |
| PHY 地址 | 固定 PHYAD 0，BMSR 连读两次取当前 link | 不读 BMSR，不扫描 | 扫描 0–31，取首个有效 ID；B3V 地址 0、1 都响应 |
| RGMII 延迟 | 不写 PHY 延迟寄存器 | 不写 PHY 延迟寄存器 | 先读默认值，可用 d 命令依次修改四种组合 |
| 本机配置 | `eth_local_configure`，MAC 02:45:44:52:56:32，IP 192.168.1.10，port 5000 | 同一函数和数值 | 同一函数和数值 |
| 窗口 | win2=整个 DDR；win3=0x0a000000 起 68 KiB，计数清零 | demo_npu win0/1 图像、win2 模型、win3 控制 | win3 控制窗口 |
| 使能顺序 | 本机/窗口/通知清除 → BMSR link → 打印 link up → ENABLE → 打印 ready | 本机/窗口/IRQ → ENABLE | 本机/窗口/广播对端 → ENABLE |
| TX 对端 | 不配置 UDP TX 对端 | 从收到的 PC UDP 源学习后配置 | 预置广播 MAC/IP、port 6000 |
| ARP | ENABLE 后由硬件处理 | 同一硬件 | 同一硬件 |

`eth_local_configure()` 写 MAC_HI=0x0245、MAC_LO=0x44525632、IP_ADDR=0xc0a8010a、
RX_PORT=5000。这些写入在 BIOS 打印 ready 前完成。`edrv32_eth_rx.v` 的 ARP 判断
先检查 ENABLE、ERROR、帧/FCS、本机/广播目的 MAC，再检查请求类型和目标 IP；
不依赖窗口、RX_NOTIFY3、IRQ_EN 或 UDP TX 对端。`edrv32_eth_tx.v` 的 ARP 分支
直接使用本机 MAC/IP 和请求携带的对端 MAC/IP，不使用 TX_DST_*。

卡 22 B3V 8bbf3021 的 `artifacts/b3v/eth_diag/result.md` 记录：初始延迟 1/1、四组
都能双向收发、显式绑定 192.168.1.2 后应用成功。该结果支持保留 PHY 延迟配置；
它不是 B3N BIOS 的在线 PHY 测量。仿真 MDIO 输入固定为 1，不能证明真实 PHY
地址、link、协商速率或 RGMII 采样相位正确。

### PC 工具两条路径

| 项目 | BIOS CLI / GUI 烧录页 | 应用网口工具 |
|---|---|---|
| 实现 | CLI `BiosTransfer`；GUI `BiosProgrammer` 继承同一实现 | `core/ethernet.py:EthernetTool` |
| 本机绑定 | 原来已经 `bind((local_ip, 0))`，默认 192.168.1.2；GUI 原来已有本机 IP 输入 | `self.local_ip` 显式绑定；可复用同 IP 的监听 socket，通常 6000 |
| 发送前确认 | 原来只等 BIOS 串口 ready，没有 ARP 成功判定 | 原来没有 ARP 成功判定；应用有 PC UDP peer/EDTM/模型完成等业务反馈 |
| 数据 / NOTIFY | 每个包最多 1464 B 数据；所有段后发 win3 offset0 描述块，仅最后包 NOTIFY | 每包 1024 B 数据；整个 blocks 最后一包 NOTIFY |
| 完成含义 | 原来 sent 仅是 sendto 提交字节，真正完成靠串口 Load/Run | TX sent 也不是板端确认；业务由板端回报 |

GUI 的应用监听 192.168.1.2:6000 与 BIOS 烧录的独立临时端口不是同一个 socket。
应用页设置和状态不能证明 BIOS 烧录实际选择了哪个源地址；烧录页的 local_ip
通过 engine/core/program 传入共享实现。原编码中 descriptor 最后发送和 NOTIFY
位置正确，无需改动。原有 FAIL bytes 后一次整份重发保持不变，未新增重试。

### 波特率时间线

原 BIOS：旧速率打印结果行 → `uart_drain()` 等 TX_EMPTY 且 !TX_BUSY →
`uart_set_baud()` → 立刻返回 bios() 打印新菜单。主机 CLI 要从原始串口缓冲区
拆出完整 LF，GUI 还需经 reader/_match_line，再调用 pyserial 波特率 setter。
因此 BIOS 的 drain 保证旧速率结果完整发出，却没有给主机设置串口的时间。
主机的切换点符合原协议，竞争发生在结果行到达后、新菜单发送前的空隙。

## 4. 根因

**已确认：** 源码和 fake 延迟模型均能复现结果行后过早发送新速率菜单导致
`wait_menu` 卡住。BIOS 原来先打印、drain、再切换，问题不是旧速率结果行顺序颠倒。
长时间零字节仍需板端原始串口复测，不能把全部异常字节都归于这一竞争。

**已确认：** BIOS 烧录没有 ARP 成功判定；UDP sendto 返回成功不能证明邻居解析
成功。ARP 不通时，进度仍可到满格并一直等没有收到数据的 BIOS，这解释了主机
为什么静默卡住。绑定本机 IP、descriptor 顺序、ENABLE 与 ready 的先后没有发现缺陷。

**尚未确认：** B3N 的 ARP 为什么不通。当前没有 BIOS 下的收发抓包、PHY 寄存器
或 ETH PERF 计数，不能区分 TUN/路由、PC 有线口出包、PHY 链路状态和实际板端收包。
BIOS 与应用共用复位和 MAC/IP 设置，不能凭现有现象认定 PHY 延迟或 PHYAD 错误。
代码对 BMSR 只取 bit2，全 1 的 MDIO 读数同样会打印 link up；因此日志中的 link up
本身不能排除无 MDIO 响应，这是需要真实 PHYID/BMSR 读数确认的可能性，未认定为板上根因。
没有据此修改 ETH 初始化，也没有增加 PHY 地址扫描、重试或回退。

## 5. 修复

- 按已确认 SoC v0.22 7.5(3a)，BIOS 改 BAUD_DIV 后以 CLINT 等 100 ms，随后打印
  原菜单。旧速率结果、drain、串口协议和提示文字保持原样。
- 共享 BIOS 主机工具在收到 ETH ready 后、提交任何镜像包前完成显式源地址的
  ARP 解析；失败关闭 socket、置 phase=error，CLI 抛出错误，GUI 显示错误。
  空源地址或 0.0.0.0 明确拒绝，不允许默认路由替代有线地址绑定。
- Windows 调用 `SendARP(dst, src, ...)`；Linux 在持有 CAP_NET_RAW 的进程中选取
  源 IPv4 所属接口，只发一次 ARP 请求，最多等 3 s 应答，无自建重试或备用路径。
  缺权限直接报错。Windows 解析返回值由操作系统决定，错误包含源/目标和错误码。
- ARP 检查证明二层可达，不是整份烧录确认；成功仍以 BIOS 的 Load/Run 为准。
  Linux 的原始 ARP 检查也不替代操作系统 UDP 路由选择。

**需要重新生成 ROM 并更新 FPGA 工程的 ROM 初始化文件。** 已生成
`build/fpga/ip_rom_boot.dat`（2048×64 bit）；文件属于 build 产物，不入库。
协调者应把下列命令和 ROM 更换步骤放进后续 Windows 任务卡，重新生成 bitstream，
仅更新 PC 工具不会给旧 bitstream 的 BIOS 增加 100 ms：

```sh
make -C sw PROGRAM=bootloader -j1
make -C sw PROGRAM=monitor -j1
python3 tools/fpga/mem_init.py build/sw/bootloader/rom.hex build/sw/monitor/sram.hex
```

## 6. 防回归

本次实现已 rebase 到 `22440f44`，没有 RTL 改动。

| 检查 | 结果 |
|---|---|
| bootloader `-Wall -Wextra -Werror` 构建 | 0 warning；text=8948 B，data/bss=0，≤16384 B |
| ROM 打包 | 命令成功，ip_rom_boot.dat=2048 行；ip_ram_sram.dat=8192 行 |
| BIOS C 边界测试 | 1 项通过 |
| tools/board 测试 | 17 项通过，含源地址绑定、拒绝 wildcard、SendARP 参数/失败、Linux 原始 ARP 收发、ARP 失败不提交镜像 |
| tools/debug_tool 全套 | 104 项通过，包含 13 项 BIOS programmer 测试；100 ms 菜单与 80 ms 主机延迟成功，1 ms 菜单重现丢失 |
| sc_bios_eth | UART、先 ARP 后 UDP 的完整 ETH、缺首 UDP 后整份重发三场景全部 PASS，均运行 DDR 程序并检查 SRAM 段 |
| ARP 定向 | 60 B 回复逐字节匹配；peer 模型检查 FCS/IFG；没有设置 UDP TX 对端仍正确应答 |
| 缺包路径 | 精确报告 win2=4 expect=380、win3=36 expect=36，完整重发后 PASS |
| SoC style / Verilator lint | 0 warning；Verilator 5.020（2024-01-01），构建 -j 1 |
| board_b1 load | 真实 115200→2 Mbaud、切换后的 100 ms 等待、非法段/入口和双段 ELF 自动运行 PASS；334 B/2 段；Verilator 与 B1 style 均 0 warning |

本机日志为 `build/bios-eth-{boot,monitor,board-tests,boot-tests,debug-tool-tests}.log`，
board_b1 为 `build/board_b1/{compile,case3}.log`。monitor 的上游 CoreMark 构建有既有
`core_list_join.c:376` 的 maybe-uninitialized 告警，未修改第三方代码；bootloader 0 告警。
board_b1 链接另有串行 LTO 提示，不是 RTL 或 C 源码告警。
SoC 定向仿真在用户授权的专用仿真环境完成，只保留本节结果总结，临时文件已清理，
未回传该环境文件或环境信息；本机复现命令将产生 `build/sc_bios_eth/*.log`。

原 sc_bios_eth 直接使用固定目的 MAC 发送 UDP，未发 ARP；现完整 ETH 场景先发
广播 ARP，并生成 `arp.bin` 复用 common checker 检查回复；未修改 common bench 或 RTL。
MDIO、真实 PHY、USB UART 和 Windows SendARP 的实际运行仍由第 7 节上板验证。

## 7. 同类排查与一次上板采集

应用工具 `ethernet.py`、`video.py`、`yolo.py` 未修改。PHY 复位、窗口初始化、
ARP/TX 对端依赖和 CLI/GUI 烧录入口均已对比，见第 3 节。

在同一 B3N、新 ROM bitstream 上按以下顺序采集，保留系统当前 TUN 状态，
不自动改路由、不自动重试。Windows 命令从仓库根目录运行，COM3 替换成实际端口：

1. 记录 `git rev-parse HEAD`、使用的 bitstream 路径和 ROM build commit；保存
   `Get-NetIPAddress -AddressFamily IPv4`、`route print -4`、`arp -a -N 192.168.1.2`，
   注明 Clash/TUN 是否开启，确认 192.168.1.2/24 属于有线网卡。
2. 只用 115200，保持按 KEY1 复位，运行新版 CLI：

   ```powershell
   py tools/board/uart_tool.py build/sw/board_npu/board_npu.elf --elf --eth --baud 115200 --local-ip 192.168.1.2 --port COM3 --log build/board/bios-eth-115200.raw
   arp -a -N 192.168.1.2
   Get-NetNeighbor -IPAddress 192.168.1.10
   ```

   保存完整报错、原始串口文件和邻居结果。ARP 失败时应 sent=0、明确错误；
   成功时应学到 02-45-44-52-56-32。不能把满进度条当成板端收到。
3. 若仍无法烧录，保持原始串口记录，手动重新进入 BIOS 菜单 2，另开终端运行：

   ```powershell
   py tools/board/eth_probe.py --local-ip 192.168.1.2 --listen 6000
   ```

   观察约 3 s 后 Ctrl-C，保存 TX/RX 原文以及此时 `arp -a -N 192.168.1.2`。
   **BIOS 不发送应用 UDP 回包，probe 无 RX 不能判定失败。** 此 probe 的默认包为
   win3 offset0 单字节且带 NOTIFY，可能导致 BIOS 打印 FAIL range 或 FAIL bytes；
   这种串口结果恰是包已到达的证据，probe 会触碰描述块，不能与正式烧录并行。
   此步骤后重新进入菜单 2 才能做新的烧录会话。
4. 若可抓包，选择有线网卡捕获 `arp or udp.port == 5000 or udp.port == 6000`，
   必须包含 step2 的 ready 至 ARP 错误/Load 结果：PC 有没有发出源 IP .2 的 ARP，
   板端有没有应答，UDP 有没有由 .2 发往 .10，以及最后 win3/NOTIFY 是否出现。
   这组观测区分“没有出有线口”“收到请求但没有板端应答”“ARP 通但 UDP 丢包”。
5. 新 ROM 下复位到 115200，另做一次 `--baud 2000000`，保存独立 raw 文件；应依次
   收到旧速率 Baud result、新速率菜单和 ETH ready。若仍乱码，用 921600 单独复测，
   记录 USB UART 型号和驱动版本；这属于人工诊断，工具不自动降速或回退。

BIOS 原始串口、BIOS 下 ARP/neighbor、probe 收发、网卡与路由、可选抓包一起回传，
即可进一步判断实际硬件/系统原因；目前不宣称已修复 B3N 上真实的 ARP 不通。
