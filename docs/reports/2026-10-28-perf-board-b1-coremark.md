# B1 上板 CoreMark 正式成绩（第二次上板）

| 项 | 内容 |
|---|---|
| commit | RTL 与约束 `346c171`（与第一次相同）；软件构建 `207b05a`（GCC 15.2.0，rv32im_zicsr_zifencei） |
| 任务卡 | `tasks/win/20261028-07-media-r3-b1/` B 部分，结果提交 `ec77019`、`eee2bcc` |
| 工具 / 器件 | PDS 2022.2-SP6.1（build 138931），ADS；PG2L200H-6 FBB676 |
| 配置 | clk_sys 100 MHz（PLL）；CPU 双发射 rv32im，I$/D$ 各 8 KiB；程序和数据在片上 SRAM |
| 原始数据 | `tasks/win/20261028-07-media-r3-b1/artifacts/b1/uart/`（`b1_o2.log`、`b1_tuned.log`、`b1_uart_download.log`、`hpm_*.txt`、`b1_periph.log`、`b1_sysinfo.log`） |
| 上一次 | `docs/reports/2026-10-28-board-b1.md` |

## 时序和资源

重新生成 ROM/SRAM IP（新初始化内容）后，clk_sys slow WNS +0.674 ns、fast +4.046 ns，0 违例；PnR 资源 LUT 14648、FF 8334、分布式 RAM 151、APM 4、DRM36K 当量 26，均与第一次相同。

## CoreMark（5000 次迭代）

O2 版本从 SRAM 初始化内容启动；tuned 版本按住 KEY1 复位后经 UART 下载（`monitor_tuned.wire` 31896 字节，`Boot mode: UART download`）。

| 编译选项 | 计时周期 | 运行秒数 | CoreMark | CoreMark/MHz | 指令数 | IPC | CRC | RTL 仿真 CoreMark/MHz | 板上 / 仿真 |
|---|---:|---:|---:|---:|---:|---:|---|---:|---:|
| O2 | 1,387,629,692 | 13.88 | 360.326 | **3.603** | 1,441,025,033 | 1.038 | PASS | 3.592456 | +0.29% |
| tuned | 1,159,978,150 | 11.60 | 431.042 | **4.310** | 1,239,834,691 | 1.068 | PASS | 4.290770 | +0.45% |

两次运行均超过 10 秒，监控程序打印 `Score status: duration >= 10 s`。tuned 选项：`-O3 -funroll-all-loops -finline-limit=600 -falign-functions=4 -falign-jumps=4 -falign-loops=4`，比 O2 高 19.6%。HPM 分两轮采集，两轮周期数相差 335（tuned）。

tuned 的 HPM（`hpm_tuned.txt`）：双发射比例 0.272，load-use 停顿比例 0.078，前端空比例 0.080，分支预测错误率 0.161，I$ MPKI 1.083，D$ 缺失 1 次。

## 外设和系统信息

| 测试 | 结果 |
|---|---|
| 按键（10 s 内按下并松开 KEY1） | 第一次 `NOT PRESSED within wait`（未操作）；第二次按下 3748 ms、松开 4003 ms，PASS |
| LED | 本次没有目视记录 |
| CLINT 定时器中断 | 请求 4096 周期，实际 4143，PASS |
| I2C 扫描 | 两端口 0 个设备（未接设备） |
| 系统信息 | PASS |
