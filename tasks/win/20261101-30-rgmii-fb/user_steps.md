# 卡30用户步骤

## A：先跑厂商基线

1. 打开工作副本G:/codex_project/EdRV32-FPGA/EdRV32-ETH-VENDOR/ethernet_test.pds，原件不改。
2. 工程目标已标PG2L200H-6/FBB676；在此工程重新生成ref_clock，参数保持125MHz→125MHz、30度、50%、内部CLKOUTF反馈、输入/输出No Buffer，保留lock，不启用rst。
3. 用户已要求将顶层DEST_IP改为192.168.1.2，工作副本已改；GUI重新执行综合、Device Map、布局布线、时序、bitstream；出现错误保留原文。
4. 下载厂商bitstream后通知Codex；届时配置/确认PC192.168.1.2/24、UDP8080，采集约60秒ARP/ping/UDP。不要使用SoC的192.168.1.10:5000与监听6000配置。

## B：A完成后改B3V

仅重新生成B3V中的ip_pll_eth，ROM/SRAM及其他IP沿用卡29。

| 项 | 配置 |
|---|---|
| 模块名 | ip_pll_eth |
| 输入 | CLKIN1，125.000MHz，No Buffer |
| Feedback Clock Mode | External Feedback |
| Feedback from | CLKOUT0 |
| 输出 | 仅CLKOUT0，125.000MHz，0度，占空比50% |
| 输出Buffer | No Buffer，板级RTL已有GTP_CLKBUFG |
| reset | RST_INNER_EN=false，不生成reset端口 |
| lock | 保留，LOCK_MODE=0 |
| 其他 | 不开第二输入、动态切换、APB、SSC、动态相移、gate及互补输出 |
| 生成端口 | clkin1、clkfb、clkout0、lock |

保存GUI反馈模式、源、相位、分频截图。生成后通知Codex检查，不要使用旧的无clkfb端口IP开始编译。

在PDS Tcl Console执行以下命令，路径按现有FPGA工程位置计算：

```tcl
cd G:/codex_project/EdRV32-FPGA/EdRV32-B3V
source ../../EdRV32-Competition-2026/fpga/scripts/import_board_vision_top.tcl
```

导入脚本以项目目录为基准计算../../EdRV32-Competition-2026，include使用相同工程相对路径与tab结尾格式。之后GUI跑完整流程；任何IP/约束错误停下，不自行改写。

上板先5轮PHY复位，再断电重下bitstream再5轮，最后demo_vision的ETH输出60秒。串口保持115200。
