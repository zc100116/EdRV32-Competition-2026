# AUD A-1r 验证结果

结论：5 项单元测试全部 PASS；RTL lint 和风格检查均为 0 告警。
提交：本报告与实现同一提交，可用 `git log -1 --format=%H -- rtl/media/aud` 定位。
环境：用户提供的仿真主机（环境不记录）。
规定的环境脚本在主机上不存在，改用主机已安装的工具。

| 测试 | 结果与关键数字 |
|---|---|
| aud_i2s | PASS；2324 个音频时钟，4 帧样本、2 次欠载；逐位检查时钟、左右声道、填零和关闭行为 |
| aud_dma | PASS；8 次突发、568 个有序样本、1 次错误；覆盖 4 KiB 和不足 512 B 的环尾拆分、回绕、停顿与错误排空 |
| aud_regs | PASS；setup 本地寄存、字节写、地址掩码、LOW 边沿、W1C、错误码、欠载计数、软复位 |
| aud_fifo | PASS；1536 个样本，3 次满空循环及计数器回绕；检查保守水位 |
| aud_control | PASS；在途关闭、快速重新开启、FIFO 排空、RD_PTR 清零与基址重启 |

在完成任务规定的工作树同步后，于仿真主机执行：

```sh
python3 tools/regress.py smoke --path verif/unit/aud_i2s -j 1
python3 tools/regress.py smoke --path verif/unit/aud_dma -j 1
python3 tools/regress.py smoke --path verif/unit/aud_regs -j 1
python3 tools/regress.py smoke --path verif/unit/aud_fifo -j 1
python3 tools/regress.py smoke --path verif/unit/aud_control -j 1
```

本机静态检查：

```sh
python3 tools/check/verilog_style.py rtl/media/aud
cd rtl/filelists
verilator --lint-only -Wall +define+SIM_MODE --top-module edrv32_aud -f aud.f
```

顶层 `edrv32_aud` 端口遵循 AUD 规格第 3 节：

- 输入：`clk_mem_i/rst_mem_n_i`、`clk_aud_i/rst_aud_n_i`。
- APB：输入地址 12 位、写数据 32 位、字节使能 4 位与控制；输出读数据 32 位、ready、slverr。
- AXI256 只读：AR 输出 addr[31:0]、len[3:0]、id、valid，输入 ready；R 输入 data[255:0]、resp[1:0]、id、last、valid，输出 ready。
- 输出：`urgent_o`、`irq_o`、`aud_bclk_o`、`aud_lrck_o`、`aud_sdata_o`，均 1 位。

使用协调者提供的 `edrv32_ram_aud_fifo`，没有新增 IP 包装。
CDC 读计数和清空完成后的 RD_PTR 清零按协调者确认的方案实现。
仿真进程已结束，任务专用构建目录已清理。
AT-01–AT-09 由独立验证及联调任务执行，本任务未读写其验证目录。
