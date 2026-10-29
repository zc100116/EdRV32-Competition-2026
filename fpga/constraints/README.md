约束文件（.fdc：时钟、引脚、跨时钟域例外）
`edrv32_fpga_media_top.fdc`：媒体测量双 125 MHz 时钟、异步时钟组、串行激励 false path 与引脚约束。

`edrv32_fpga_board_b1_top.fdc`：B1 板钟 27 MHz、PLL 100 MHz 和 UART/按键/LED 引脚约束。


B2：`edrv32_fpga_board_b2_top.fdc` 使用 Mini Base 的 27 MHz 和 125 MHz 差分参考，
显式约束 sys/npu/pix/serial、DDR PHY 和 Ethernet 派生时钟。SoC 5.2 X1–X10
采用域间异步例外；pix/serial、ETH MAC/TXC 及 DDR PHY 内部关系保留。
全部 137 个物理引脚与 `fpga/rtl/README.md` 的逐位表对应，含 I2C、MDIO 和 DDR
双向引脚；两路摄像头 PWDN 按协调者确认不引出。Windows PDS 需核对 IP 实际层级。
