# MEDIA 生成 IP 配置与端口

来源：`G:/codex_project/EdRV32-FPGA/EdRV32-MEDIA/ipcore`。直接读取 .idf、生成顶层 .v 和 generate.log。
未修改生成文件、RTL包装或IP配置；未做IP仿真。DRM数量来自已完成的MEDIA PnR层次报告。

| IP | 写深度×位宽 | 读深度×位宽 | 输出寄存器 | 读使能 | 包装端口集合 | DRM块数 |
|---|---|---|---|---|---|---|
| ip_ram_vin_wfifo | 512×288 | 512×288 | false | true | 一致 | 4 DRM36K /实例 |
| ip_ram_disp_scan | 512×256 | 512×256 | false | true | 一致 | 4 DRM36K /实例 |
| ip_ram_pix_line | 1024×48 | 1024×48 | false | true | 一致 | 2 DRM36K /实例 |
| ip_ram_geo_src | 256×128 | 2048×16 | false | true | 一致 | 2 DRM36K /实例 |
| ip_ram_eth_buf | 1024×32 | 1024×32 | false | true | 一致 | 1 DRM36K /实例 |
| ip_ram_eth_fifo | 512×10 | 512×10 | false | true | 一致 | 1 DRM18K /实例 |

共同设置：RD_CLK_EN=true、OUTPUT_REG=false、WR_BYTE_EN=false、INIT_EN=false、
INIT_FILE=NONE、WR_CLK_EN=false、读写地址 strobe 均关闭；复位为 ASYNC，
包装将 wr_rst/rd_rst 接 1'b0。DISP/ETH FIFO 的两个时钟端口独立连接。

GEO：SAMEWIDTH_EN=false，写地址8位/数据128位，读地址11位/数据16位。
生成 RTL 的 wr_data_mix_bus、地址移位和 rd_full_data 拼接关系
按读地址低3位选择同一写项的连续16位，低位在低地址；
这是静态连接关系推导，与包装的 r[10:3] / r[2:0] 定义一致，未运行 IP 仿真。

DRM 模式：ETH FIFO 为18K，其余为36K；这是 CAS_MODE，不是已测得的块数。
六份 generate.log 均为 Done: 0 error(s), 0 warning(s)，且 Synthesis is disabled。
DRM块数已由PnR报告补充：整个MEDIA为8 DRM18K + 42 DRM36K。选项PNG截图未取得。

6个 .idf 均位于上述 ipcore 目录；导入时沿用 MEDIA 工程中已有的 IP 引用。
