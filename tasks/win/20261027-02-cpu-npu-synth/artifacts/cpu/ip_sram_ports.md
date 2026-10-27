# CPU SRAM 实际端口与配置

来源：`G:/codex_project/EdRV32-FPGA/EdRV32/ipcore/ip_ram_sram/ip_ram_sram.idf`。

容量 8192×64，字地址 13 位，64 KiB；单口 RAM，读延迟 1 拍，输出寄存器关闭。

| 端口 | 方向 | 位宽 |
|---|---|---|
| `wr_data` | input | 64 |
| `addr` | input | 13 |
| `wr_en` | input | 1 |
| `wr_byte_en` | input | 8 |
| `clk` | input | 1 |
| `clk_en` | input | 1 |
| `rst` | input | 1 |
| `rd_data` | output | 64 |

实际配置：

```text
FAB_REG=false
INIT_FORMAT=BIN
BE_WIDTH=8
RESET_TYPE=ASYNC
RD_OCE_EN=false
RST_VAL_EN=false
POWER_OPT=false
RST_VAL=0
INIT_EN=false
WR_BYTE_EN=true
BYTE_SIZE=8
WRITE_MODE=NORMAL_WRITE
ADDR_STROBE_EN=false
ADDR_WIDTH=13
DATA_WIDTH=64
INIT_FILE=NONE
OUTPUT_REG=false
CLK_EN=true
CAS_MODE_SEL=AUTO
CAS_MODE=36K
CLK_OR_POL_INV=false
```

包装模块连接：wr_en=|wr_en_i、wr_byte_en=wr_en_i、clk_en=en_i、rst=0。
最终 PnR PRR 的 u_sys_subsys/u_sram 行报告 16 DRM，u_rom 行报告 4 DRM。
