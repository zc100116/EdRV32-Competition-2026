# board_npu：B3N 上板功能测试

B3N 顶层包含 CPU/DDR/NPU/ETH；本程序检查 NPU，ETH 连通检查由独立软件任务提供。

依据 `docs/design/2026-10-30-board-npu-test.md` 第 4 节、NPU v0.5 第 2–5、7 节，
运行 A 寄存器检查、15 个 B 小用例、C YOLOv8n 整网和 20 个 D 连续整网，共 39 项。
程序使用 `sw/bsp/ld/ddr.ld`，从 `0x80000000` 执行；由 BIOS 的 `1=UART load`
加载 ELF 的 PT_LOAD 段，再跳转入口。保持 BIOS 切换后的 2 Mbaud 串口设置。

## 生成数据与构建

先按 `docs/guides/env-setup.md` 安装工具链、Python 环境和 COCO128/YOLOv8n 权重。
在仓库根目录执行：

```sh
. ~/.local/opt/edrv32/env.sh
git submodule update --init third_party/ultralytics
export PYTHONPATH="$PWD/third_party/ultralytics"
~/.local/opt/edrv32-py/bin/python tools/npu/board_cases.py
make -C sw PROGRAM=board_npu -j 1
riscv-none-elf-readelf -SW -lW build/sw/board_npu/board_npu.elf
```

也可直接运行上述 make：`program.mk` 自动调用生成器。
生成器使用当前 Python 解释器调用原 `gen_case.py`、`compile_yolo.py`，
整网输入固定为
`~/.local/share/edrv32/npu/coco128/images/train2017/000000000009.jpg`。
编译器复用 `build/npu/quantized/{model.bin,quantization.json}`；干净 build 首次运行时
按 `tools/npu/README.md` 标定 96 张图，此后不重新标定。BLAS/OMP 使用单线程。

所有生成物位于 `build/sw/board_npu/data/`：各用例的公共 hex 镜像、
`ref_out.hex`、`cases.bin`、只读目标文件 `cases.o`、C 接口 `board_data.h`。
`objcopy` 将原始二进制转成 `.rodata.board_cases`，由标准 `ddr.ld` 合入 `.rodata`。
每次生成后从 `cases.bin` 重新装载实际打包的描述符、模型和输入，
在板上物理地址下运行独立参考模型，逐字节比较打包的期望输出；B 和 C 全部自检。
数据、参考结果及 ELF 不入库。

## 小用例与模块级测试对照

参数直接取自 `verif/block/npu/cases.py:recipes()`；与模块级 `prepare.py` 相同，
除 OP-12 seed00 使用 seed 0 外，其余均使用 seed 1。
OP-05 的 LUT、OP-09 的全负输入也调用模块级相同的 `patch_case()`。

| 板上项（前缀 B-） | 对应 OP 变体 | 覆盖 |
|---|---|---|
| OP-01-c16_32 | OP-01 / c16_32 | 8×4，1×1 S1，Cin16/Cout32 |
| OP-01-c48_96 | OP-01 / c48_96 | 8×4，1×1 S1，三输入平面/三输出块 |
| OP-02-w12 | OP-02 / w12 | 12×6，3×3 S1 |
| OP-03-h5 | OP-03 / h5 | 12×5，3×3 S2，奇数高度 |
| OP-04-c4_cout32_lut0_res0 | OP-04 同名 | 8×4，C4 首层，3×3 S2 |
| OP-04-c4_cout16_lut1_res1 | OP-04 同名 | C4 + HALF_TAIL + LUT + 融合残差 |
| OP-05-lut1 | OP-05 / lut1 | 非恒等 LUT 激活 |
| OP-06-work | OP-06 / work | WORK 残差源 |
| OP-06-output | OP-06 / output | OUTPUT 残差源 |
| OP-07-cout80 | OP-07 / cout80 | Cin48，3×3，第三输出块半块 |
| OP-09-negative_c48 | OP-09 同名 | 20×12，三平面，全负 5×5 POOL |
| OP-10-w2 | OP-10 / w2 | 2×3，Cin32，2× UPSAMPLE |
| OP-10-w40 | OP-10 / w40 | 40×3，UPSAMPLE 最大输入宽度 |
| OP-11-concat | OP-11 / concat | 三层链，零拷贝拼接 |
| OP-12-seed00 | OP-12 / seed00 | 固定 seed 0 的随机多层链 |

A 检查 ID、空描述符列表完成（DONE_COUNT=1、IDLE）、SOFT_RST 后的全部已定义
寄存器复位值（含 16 个 PERF）。复位前令配置、ENABLE、IRQ_EN、DONE_COUNT、DONE
非零。B 比较 `check.txt` 的全部输出字节，包括平面填充。
C 的 68 条描述符为 63 CONV + 3 POOL + 2 UPSAMPLE；逐字节比较六个检测头的
全部 OUTPUT 区，共 725760 B。D 每次保留相同输入/模型和描述符，连续运行 20 帧，
对按 `check.txt` 顺序连接的 OUTPUT 计算 CRC32，与 C 实际输出的 CRC32 比较。
CRC32 为反射 IEEE 多项式 `0xedb88320`，初值和最终异或均为 `0xffffffff`。
每次 D 单独报告，通过计入 39 项；首个失败即结束。

NPU 运行基址均为公共用例原始基址加 `0x10000000`，避开 ELF：

| 用途 | NPU DDR 物理地址 | CPU 缓存别名 |
|---|---:|---:|
| 描述符 | 0x10080000 | 0x90080000 |
| MODEL | 0x10100000 | 0x90100000 |
| WORK | 0x11000000 | 0x91000000 |
| INPUT | 0x14000000 | 0x94000000 |
| OUTPUT | 0x15000000 | 0x95000000 |

描述符内部的选择器、相对偏移及跨距保持原值。每个用例先清零实际访问范围和填充，
再复制初始数据；启动前对这些范围调用 BSP `cache_clean()`，DONE 后、CPU 读输出前
调用 BSP `cache_invalidate()`（SoC 7.4）。D 不重新复制整网数据，也不清零中间特征图。
完成用轮询 IRQ_STAT.DONE/ERROR 判定；发生 ERROR 打印 CUR_DESC 和 ERR_CODE 后结束。

## 上板加载

Windows 仓库根目录执行（把 COM3 改为设备管理器中的端口）：

```sh
python tools/board/uart_tool.py build/sw/board_npu/board_npu.elf --elf \
    --baud 2000000 --port COM3 --log build/board/board_npu-uart.log
```

先运行命令，再按住 KEY1 并按复位键进入 BIOS。工具选择 `1=UART load`、从 115200
切换到 2000000、按会话描述块加载 ELF，完成后自动运行入口；结束后 Ctrl-C 停止日志采集。
Linux 使用同一完整命令，把 `python` 改为 `~/.local/opt/edrv32-py/bin/python`，
把 COM3 改为 `/dev/ttyUSB0`。串口依赖见 `tools/requirements.txt`。

## 串口输出

以下为格式示例，性能数字仅用于展示格式，须以上板实测为准：

```text
NPU A-ID PASS
NPU A-empty PASS
NPU A-reset PASS
NPU B-OP-01-c16_32 PASS PERF0=1200 MAC=32
...其余 14 个 B 项...
NPU C-YOLO PASS PERF0=7500000 MAC=6000000 ms/frame=41.667 fps=24.000 CRC32=12345678
NPU D-01 PASS CRC32=12345678 PERF0=7500000 MAC=6000000
...D-02 至 D-19...
NPU D-20 PASS CRC32=12345678 PERF0=7500000 MAC=6000000
NPU board: PASS 39/39
```

`PERF0` 是 NPU 总周期，`MAC` 是 MAC 有效拍（npu-spec 4 的计数器开发初值）。
`ms/frame = PERF0 × 1000 / 180000000`，`fps = 180000000 / PERF0`，打印三位小数。
180 MHz 固定值来自 npu-spec 第 7 节；SYSCTRL 只提供 clk_sys，不用它代替 clk_npu。
失败示例：

```text
NPU B-OP-01-c16_32 FAIL desc=0 addr=11020003 expected=0000007f actual=0000007e mismatches=2 PERF0=1200 MAC=32 passed=3
NPU board: FAIL 1/39
```

`desc` 从 0 编号；数据差异报告首个不一致的 DDR 物理字节地址、期望/实际字节和
整个用例的不一致字节总数。寄存器差异报告 APB 字节地址；NPU ERROR 报告 ERR_CODE
寄存器地址和值。GPIO bit4（LED0）亮表示通过，bit5（LED1）亮表示失败，
均高电平点亮，按 SoC 3.5 分配。结果保持到复位；不重试。

## 主机验证与 ELF 布局

```sh
. ~/.local/opt/edrv32/env.sh
~/.local/opt/edrv32-py/bin/python \
    -m unittest discover -s tools/npu/tests -p 'test_board_cases.py' -v
~/.local/opt/edrv32-py/bin/python \
    tools/npu/board_cases.py --out build/sw/board_npu/repeat-data
diff -r build/sw/board_npu/data build/sw/board_npu/repeat-data
```

最后的 diff 直接逐字节比较生成物，不存储哈希；两次均包含独立参考执行和打包自检。
只删除本程序输出目录后运行 make 可验证重新生成：

```sh
rm -rf build/sw/board_npu
make -C sw PROGRAM=board_npu -j 1
```

GCC 15.2.0、RV32IM/Zicsr/Zifencei、`-O2 -Wall -Wextra -Werror` 的本次构建：

| ELF 段/节 | CPU 地址 | 大小（字节） | UART 加载 |
|---|---:|---:|---|
| `.text` | 0x80000000 | 5460（0x1554） | 是 |
| `.rodata` | 0x80001554 | 5171952（0x4eeaf0） | 是 |
| `.data` | 0x804f0044 | 0 | 无内容 |
| `.tohost` | 0x804f0080 | 72（0x48） | NOLOAD，启动代码清零 |
| `.bss` | 0x804f00c8 | 4 | NOLOAD，启动代码清零 |

入口为 `0x80000000`；栈顶为标准 `ddr.ld` 的 `0xc0000000`，向低地址增长。
有效 PT_LOAD 共一段：VMA/LMA `0x80000000`，文件/内存大小均为
`0x4f0044` = **5177412 B**，覆盖 `.text` 和 `.rodata`。
另两个 PT_LOAD 的文件大小为 0，加载器跳过；BSS 的内存大小为 76 B。
原始测试数据为 **5168832 B**，位于只读节内的
`_binary_cases_bin_start = 0x80002084`，末尾为 `0x804eff44`。
UART 工具实际取出的 ELF 段已与 `cases.bin` 逐字节比较一致。
`uart_tool.py --elf --baud 2000000 --emit build/sw/board_npu/uart-wire.bin`
加上 ELF 路径可生成传输字节；本次为 5177445 B，含 BIOS 命令和地址/长度。
仅数据在 2 Mbaud、8N1 下的理论传输时间为 25.9 s；实际耗时以上板日志为准。

本次主机验证：3/3 单元测试、15/15 B 打包自检及 C 的 725760 B 输出比较通过；
两份独立生成目录 `diff -r` 无差异，编译 0 告警，`git diff --check` 通过。
未运行 RTL 仿真（本分支尚未合入 T-BN1 的 `verif/soc/board_npu`），未上板。
本改动没有 Verilog，风格检查扫描 0 文件、0 告警，Verilator lint 不适用。

## ETH 与 DDR 监控

启动时按 demo 网口约定初始化 ETH（192.168.1.10:5000）。调试工具选择 B3N，
点击“建立网口连接”，WIN3 更新对端并打印 PEER；DDR 页接收固定 100 Hz、
每批 16 条的 EDTM。原有 NPU 测试流程、结果和结束输出保持，结束后 CLINT 监控继续运行。
网口窗口与发送区沿用 demo 的 0x0a000000 / 0x0a100000 区域，与 NPU 测试存储分离。
