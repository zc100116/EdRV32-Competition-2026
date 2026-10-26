# PDS IP 实际端口与配置

工程：`G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`。
PDS / IP Compiler：2022.2-SP6.1，build 138931。
7 个 IP 的 `.idf` 均已核对为 PG2L200H、-6、FBB676。
生成日志均为 `Done: 0 error(s), 0 warning(s)`，未执行 IP 独立综合。

## 四种 Cache RAM

实际模块名和宽度：

| 模块 | 写/读地址位宽 | 写/读数据位宽 | 物理深度 | wr_byte_en |
|---|---|---|---|---|
| ip_ram_icache_tag | 9 / 9 | 20 / 20 | 512 | 无 |
| ip_ram_dcache_tag | 9 / 9 | 20 / 20 | 512 | 无 |
| ip_ram_icache_data | 9 / 9 | 64 / 64 | 512 | 无 |
| ip_ram_dcache_data | 9 / 9 | 64 / 64 | 512 | in，8 位 |

上述四个模块的共同端口如下，位宽按上表取值：

| 实际端口 | 方向 | 位宽 | 包装模块连接 |
|---|---|---|---|
| wr_clk | in | 1 | clk_i |
| wr_en | in | 1 | wr_en_i |
| wr_addr | in | 9 | Tag 为 {2'b00, wr_addr_i}；Data 为 wr_addr_i |
| wr_data | in | 20 或 64 | wr_data_i |
| wr_rst | in | 1 | 1'b0 |
| rd_clk | in | 1 | clk_i |
| rd_clk_en | in | 1 | rd_en_i |
| rd_addr | in | 9 | Tag 为 {2'b00, rd_addr_i}；Data 为 rd_addr_i |
| rd_data | out | 20 或 64 | rd_data_o |
| rd_rst | in | 1 | 1'b0 |

D-cache Data 另外具有 `wr_byte_en[7:0]` 输入，接 `wr_byte_en_i`。

共同配置：`WR_CLK_EN=0`、`RD_CLK_EN=1`、`OUTPUT_REG=0`、
`RD_OCE_EN=0`、`FAB_REG=0`、`RESET_TYPE="ASYNC"`、`INIT_EN=0`。
两个 Tag 为 `CAS_MODE="18K"`，两个 Data 为 `CAS_MODE="36K"`。
D-cache Data 为 `WR_BYTE_EN=1`、`BYTE_SIZE=8`、`BE_WIDTH=8`；其余不启用字节写使能。

### Tag 深度调整

原 128 深度、7 位地址触发厂商 `04030101` 参数诊断。
2026-10-26 用户转达 VPS Claude 确认：两个 Tag IP 改用 512 深度，包装模块地址高位补零。
当前实际 IP 读写地址均为 9 位，包装模块仍对外提供 7 位逻辑地址，只使用物理地址 0–127；
其行为模型仍为 128×20。当前 ModelSim 检查未再出现原地址宽度诊断。

## ip_rom_boot

| 实际端口 | 方向 | 位宽 | 包装模块连接 |
|---|---|---|---|
| clk | in | 1 | clk_i |
| clk_en | in | 1 | en_i |
| rst | in | 1 | 1'b0 |
| addr | in | 11 | addr_i |
| rd_data | out | 64 | rd_data_o |

物理容量 2048×64；`CAS_MODE="36K"`、`CLK_EN=1`、`OUTPUT_REG=0`、
`RD_OCE_EN=0`、`FAB_REG=0`、`RESET_TYPE="ASYNC"`。
`INIT_EN=1`、`INIT_FILE="NONE"`、`INIT_FORMAT="BIN"`，实际未加载外部初始化文件。
生成的 `rtl/ip_rom_boot_init_param.v` 中初始化参数为零。

## ip_ram_sram

| 实际端口 | 方向 | 位宽 | 包装模块连接 |
|---|---|---|---|
| clk | in | 1 | clk_i |
| clk_en | in | 1 | en_i |
| rst | in | 1 | 1'b0 |
| addr | in | 15 | addr_i |
| wr_data | in | 64 | wr_data_i |
| rd_data | out | 64 | rd_data_o |
| wr_en | in | 1 | reduction OR：\|wr_en_i |
| wr_byte_en | in | 8 | wr_en_i |

单口，32768×64；`CAS_MODE="36K"`、`WR_BYTE_EN=1`、`BYTE_SIZE=8`、
`BE_WIDTH=8`、`CLK_EN=1`、`OUTPUT_REG=0`、`RD_OCE_EN=0`、`FAB_REG=0`、
`RESET_TYPE="ASYNC"`、`WRITE_MODE="NORMAL_WRITE"`、`INIT_EN=0`。
有任意字节需要写入时总写使能为 1，各字节仍独立受原 8 位使能控制；全零时是读操作。

## ip_mul_s33x33

| 实际端口 | 方向 | 位宽 | 包装模块连接 |
|---|---|---|---|
| clk | in | 1 | clk_i |
| ce | in | 1 | enable_i |
| rst | in | 1 | 1'b0 |
| a | in | 33 | operand_a_i |
| b | in | 33 | operand_b_i |
| p | out | 66 | product_o |

当前实际配置（已重新生成，取代此前内部流水级 1、3 的记录）：
`A_SIGNED=1`、`B_SIGNED=1`、`ASYNC_RST=1`、`ADVANCED_BOOL=1`、
`PIPE_STATUS=2`、`XYREG=0`、`MREG=1`、`PREG=0`、`INREG=0`、`OUTREG=0`、
`CPO_REG=14'b00000000000010`。
本机 ModelSim 定向检查确认两次使能上升沿的延迟、CE 暂停保持和所测有符号极值乘积正确，
`PASS multiplier checks=23`。尚未取得 PDS 综合报告中的 APM 占用数字。

## 复位与初始化

全部已生成 IP 的复位均为高有效，按用户转达的确认统一接 `1'b0`。
存储 IP 的端口复位作用于读出通路，不清空整个存储阵列；关闭额外输出寄存器不代表复位完全无作用。
存储数据不复位，Cache 的 valid/dirty/LRU 等控制状态仍按仓库设计正常复位。

ROM、SRAM 生成目录提供 `init_param_hex_exmp.dat`、`init_param_bin_exmp.dat`。
HEX 示例为每行一个 64 位字（16 个十六进制数字），横向数据、纵向地址；实际使用时删除示例注释。
这是生成器示例格式，尚未验证外部初始化文件加载，也未确认转换脚本所需的完整格式契约。

## 检查范围

复现入口：`src/check_ip_wrappers.do`，依赖上述本机工程和 PDS 安装路径。
Cache 检查复用仓库 `verif/unit/cache_ram/tb.sv`，仅在 build 中生成带厂商 GRS 实例的测试顶层。
乘法器、SRAM 检查源保存在任务 `src/`；厂商源码、生成 IP 和完整日志均未入库。

ModelSim 编译 0 error / 0 warning；Cache、乘法器、SRAM 定向检查均 PASS。
最终检查中 Cache 优化时有一条厂商 `GTP_DRM36K_E1.v:746` 的 `vopt-2250` 警告：
`Function "mem_read_a" has no return value assignment.` 未屏蔽、未修改厂商模型。
重复使用本地工作库时，vlib 另有库已存在的提示。上述检查不是完整系统回归或完整 IP 等价性证明。
