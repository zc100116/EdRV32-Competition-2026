# F CPU125 cache容量核实与更正

用户要求检查实际IP后，核实对象为卡51/52沿用的G:/codex_project/EdRV32-FPGA/EdRV32-B3F-RND1S-CPU125，不只检查当前仓库RTL或软件页面。

## 结论

**I-cache=32KiB，D-cache=32KiB；均2路、512组、每行32B。** 两者合计64KiB数据容量。常说的cache容量不包含Tag及状态位存储。

| IP | 实际IDF及生成Verilog参数 | 硬件实例 |
|---|---|---|
| ip_ram_icache_data | WR/RD_ADDR_WIDTH=11，WR/RD_DATA_WIDTH=64，即2048×64bit=16KiB | I-cache u_data0、u_data1，两份=32KiB |
| ip_ram_dcache_data | WR/RD_ADDR_WIDTH=11，WR/RD_DATA_WIDTH=64，即2048×64bit=16KiB；8字节写使能 | D-cache u_data0、u_data1，两份=32KiB |
| ip_ram_icache_tag | 地址9位、数据18位，即512×18 | 两份，对应两路 |
| ip_ram_dcache_tag | 地址9位、数据20位，即512×20 | 两份，对应两路 |

容量也可按512组×2路×32字节=32768字节计算。

## 已综合结果交叉证据

工程synthesize/edrv32_fpga_board_full_top_syn.vm中的edrv32_icache和edrv32_dcache，均有u_data0、u_data1，I-cache读地址使用ic_req_addr_i[13:3]、写地址使用addr_r[13:5]加两位beat，Tag索引addr_r[13:5]；D-cache数据RAM也是完整11位读写地址。不是IP生成容量较大但只接低地址的情况。

同目录edrv32_fpga_board_full_top.snr：I/D-cache各9个DRM；每个cache的两路data各4DRM、两路tag各0.5DRM，与上述实际实现一致。

## 为什么串口打印8192

旧BIOS/monitor初始化软件基线92b38fd2的sw/boot/info.h：

```c
#define SYSTEM_ICACHE_BYTES 8192u
#define SYSTEM_DCACHE_BYTES 8192u
```

sw/boot/info.c仅用这两个常量打印I-cache bytes、D-cache bytes，未从硬件探测容量。因此卡51串口8192记录本身是真实输出，但不能作为cache实际大小。

当前b3已将这两个软件常量改为32768，showcase v2页面“各32KiB”与实际硬件相符；旧比特流的初始化软件仍会打印旧值。SYSCTRL_CLK_SYS_HZ是另一项运行时读取，不应与固定cache容量打印混为一谈。

## 更正范围

Codex此前根据旧串口打印推断实际为8KiB，并说卡52页面32KiB有误，这一判断错误，现明确撤回。卡52的user_steps.md已更正。请Claude阅读卡51报告中“I/D-cache各8192B”时理解为旧软件打印值，不要据此将硬件或新页面改回8KiB。本次没有修改RTL、IP、比特流或页面。
