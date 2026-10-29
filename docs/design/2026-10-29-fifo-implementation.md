# FIFO 实现方式：RAM IP + 自写控制器

| 项 | 内容 |
|---|---|
| 日期 | 2026-10-29 |
| 状态 | 已决定（用户 2026-10-29：保持现状） |
| 关联 | CLAUDE.md 5.3、8；SoC 规格 v0.16 5.2；`rtl/common/README.md`；`vision-plan.md` V-P1、V-P2；`disp-spec.md` v0.3 2.5、4.1 |

## 1. 背景和问题

DDR 相关引擎中容量较大的 FIFO 现在由两部分组成：
- 存储体：PDS 生成的简单双口 DRM（`ip_ram_vin_wfifo`、`ip_ram_disp_scan`、`ip_ram_eth_fifo` 等），经 `rtl/tech/` 包装；
- 控制器：`rtl/common/edrv32_sync_fifo_ram.v`、`edrv32_async_fifo_ram.v`，负责指针、空满、格雷码指针同步和首字直接可见的预取输出。

深度 2–8 的小 FIFO（AXI 异步桥等）用寄存器实现（`edrv32_async_fifo`）。

用户提出：PDS IP Compiler 本身提供基于 DRM 的同步和异步 FIFO IP。这种做法当初在 V-P1/V-P2 中直接采用，没有和 FIFO IP 做过比较，本记录补上。

## 2. 约束

- 主力仿真为 Linux 上的 Verilator；加密 IP 只能在 Windows 的 ModelSim 上仿真（CLAUDE.md 4、8）。
- 跨时钟域只能用 `rtl/common/` 中登记的原语，格雷码总线约束写在 `fpga/constraints/`（CLAUDE.md 5.3，SoC 5.2）。
- DISP 发读请求前的空位判断依赖"写入计数减去同步过来的读出计数"，以及"同步延迟只会让水位偏高"这条性质；STATUS.BUSY 也用这两个计数（disp-spec 2.5、4.1）。

## 3. 可选方案

| | A. RAM IP + 自写控制器（现状） | B. PDS FIFO IP |
|---|---|---|
| 行为模型 | 只复刻 RAM：读延迟 1 拍、读使能为 0 时保持 | 每种宽度、深度、时钟组合各一个 IP，模型要复刻它的空满标志延迟、读延迟和水位输出时序，每个都要做 ModelSim 等价性测试 |
| 验证 | 控制器是 RTL，在 Verilator 中完整验证（`verif/unit/edrv32_*fifo*`） | IP 内部逻辑只能在 ModelSim 中看 |
| 跨时钟域 | 用登记过的原语，格雷码约束由我们控制 | 跨域在加密块内部，要修改 5.3 的规则和约束写法 |
| 计数语义 | 写入、读出计数可以直接使用，满足 DISP 2.5 的论证 | IP 的水位输出有它自己的延迟定义，要重新论证 |
| 额外逻辑 | 每个 FIFO 几十个 LUT/FF（**估算**） | 由 IP 提供；仓库没有 PDS FIFO IP 手册，资源和能力未核实 |
| 已有进展 | 模块级验证通过，media r4 时序已收敛（+0.592 ns @ 135 MHz） | 需要重新生成 IP、做等价性测试、重新收敛时序 |

## 4. 决策

保持方案 A（用户 2026-10-29）。以后新增的 FIFO（包括 B3 的 DISP L1 扫描 FIFO）也按这种方式实现。

## 5. 影响

无需修改规格、RTL 或测试。

## 6. 状态

已决定。
