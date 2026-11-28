# ip_rom_gpu2_sfu

| 项 | 固定设置 |
|---|---|
| 依据 | gpu-v2-spec §2.4；GP-A2 协调者确认：M-6 64bit打包改为M-7 §9.1的TDP36几何 |
| 器件 | PG2L200H，工程速度等级 |
| 入口 | PDS IP Compiler → Memory → DRM → True Dual Port RAM（带初始化，两个独立只读端口） |
| Module / Component Name | `ip_rom_gpu2_sfu` |
| 数据宽度 / 深度 / 地址位宽 | A、B均32 /1024 /10；物理1024×36，一颗DRM |
| 时钟 | 两口接 clk_gpu，同步上升沿；各自独立clock enable |
| Address / Input Register | 不启用额外地址/输入流水寄存器 |
| Read latency / Output Register | 阵列读1拍，关闭额外输出寄存器；禁读时保持输出 |
| Reset / Write enable | a_rst/b_rst接0；两口a_wr_en/b_wr_en接0，wr_data接32位0，运行时只读 |
| Initialization | 运行下述脚本生成 `build/gpu2_sfu/rom.hex`，HEX纯数据格式，1024行，每行8位十六进制 |
| 包装 / 使用者 | `rtl/tech/edrv32_rom_gpu2_sfu.v`；SFU A口，setup B口 |

```sh
python3 -B tools/gpu2/gen_sfu_rom.py
```

地址：RCP64在0..63；RSQ64在64..127；LOG49在128..176；INV49在177..225；
EXP64在226..289；290..1023补0。每项都是M-6公式得到的FP32最近偶数位模式。
将生成文件复制到本地PDS工程，选择HEX初始化文件；不提交生成文件或IP生成目录。
SFU发射周期先读LOG，下一周期读INV；其余操作只读一次，均在原4拍前端内完成。
B口仅访问0..63，可在SFU读LOG/INV时连续每拍读取RCP，不复制种子ROM。
期望端口 `a_clk/a_clk_en/a_addr[9:0]/a_rd_data[31:0]` 和同名 `b_*`，另有各口rst、wr_en、wr_data[31:0]，均接0；
固定采用真双口RAM预初始化只读模式，确认两个独立32bit读口实际共用一颗DRM，
将端口列表、配置截图和资源报告回传；不得以512×72 SDP冒充两个独立读口。
Windows ModelSim用同一rom.hex验证1拍读、独立使能/保持及并发地址；PDS核实真实1DRM。
