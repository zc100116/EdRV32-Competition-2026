# ip_ram_sram

| 项 | 内容 |
|---|---|
| IP 类型 | IP Compiler → Memory → DRM（块 RAM）单口 RAM（Single Port） |
| 模块名 | `ip_ram_sram` |
| 包装模块 | `rtl/tech/edrv32_ram_sram.v` |
| 使用者 | 片上 SRAM（64 KiB，系统子系统规格 2.2） |
| 器件 | PG2L200H |

## 选项

| 选项 | 取值 |
|---|---|
| 数据位宽 | 64 |
| 深度 | 8192（地址 13 位，共 64 KiB） |
| 字节写使能 | 勾选，8 位 |
| 时钟使能（端口使能） | 勾选。使能为 0 的周期不读不写，读数据输出保持 |
| 输出寄存器 | 不勾选（读延迟 1） |
| 写时读出 | 写周期的读数据不使用，取任意模式 |
| 初始化文件 | 使能（`INIT_EN=true`），HEX（`INIT_FORMAT=HEX`），选择 `build/fpga/ip_ram_sram.dat`；每行 16 个 HEX 字符，地址 0 起共 8192 行 |
| 复位 | IP 强制带高有效 `rst`，只作用于读出通路；包装模块接 `1'b0` |

## 初始化文件生成

```sh
make -C sw PROGRAM=bootloader
make -C sw PROGRAM=monitor
python3 tools/fpga/mem_init.py build/sw/bootloader/rom.hex build/sw/monitor/sram.hex
```

输入为 `make` 生成的字节镜像，转换后按小端排列为 64 位字，未用地址补零。
选择上表的 `.dat` 文件，不直接选择字节 `rom.hex`/`sram.hex`。
格式依据：厂商 `SOC系统设计/doc/fpga/pago_200/2_Demo/2_6_ram_rom_fifo/2_6_ram_rom_fifo/3_6_ram_rom_fifo/`
下 `rom_test/rom_test/ipcore/rom_test/init_param_hex_exmp.dat`、
`init_param_bin_exmp.dat` 和 `rom_test.idf`（实际 HEX 初始化选项）；
完整路径和已选文件说明见 [README 初始化文件](README.md#初始化文件)。
Windows B1 任务卡实测导入、地址顺序及启动输出。

## 实际端口（PDS 2022.2-SP6.1 生成，任务 20261025-01 回传）

| 端口 | 方向 | 位宽 | 包装模块连接 |
|---|---|---|---|
| `clk` | in | 1 | `clk_i` |
| `clk_en` | in | 1 | `en_i` |
| `rst` | in | 1 | `1'b0`（高有效） |
| `addr` | in | 13 | `addr_i` |
| `wr_data` | in | 64 | `wr_data_i` |
| `wr_en` | in | 1 | `|wr_en_i`（任一字节写即为写周期） |
| `wr_byte_en` | in | 8 | `wr_en_i` |
| `rd_data` | out | 64 | `rd_data_o` |

## 生成后需要回传的信息

PDS 生成的端口名由 IP 决定，不能手动改名。生成后请在 Windows 任务卡的 `result.md` 中记录：
1. 生成的模块名（必须为上面的模块名，在 IP Compiler 中填写实例名/模块名时设置）；
2. 生成文件中模块的实际端口列表（名称、方向、位宽）；
3. 各选项的最终取值截图（PNG，放 `artifacts/`）。

重新生成后端口与上表不一致时，由协调者统一修改包装模块的 FPGA 分支，不要改生成的文件。
