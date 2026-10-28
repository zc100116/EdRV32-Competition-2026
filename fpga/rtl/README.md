板级顶层和板级适配 RTL（PLL/DDR IP 的例化、DDR 适配器、TMDS 串化、RGMII IO）
`edrv32_fpga_media_top.v`：VIN/DISP/PIX/GEO/ETH 合并 PDS 测量顶层，分域串行激励和寄存 XOR 观察，不上板。

`edrv32_fpga_board_b1_top.v`：B1 上板顶层，27 MHz PLL → 100 MHz CPU/cache/系统子系统，UART、启动按键与 LED。
