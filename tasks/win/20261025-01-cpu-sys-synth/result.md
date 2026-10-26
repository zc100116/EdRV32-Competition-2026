# 20261025-01-cpu-sys-synth 结果

| 项 | 内容 |
|---|---|
| 输入基线 | f6d6b256aaad2f268f04c0d4536a44f6dba69359 |
| 本次 RTL / 检查源 commit | cb547cbe3bb6b2e4783800191cb57281aa6998f1 |
| PDS 版本 | 2022.2-SP6.1，build 138931 |
| ModelSim | SE-64 2020.4 |
| 器件 | PG2L200H-6 FBB676（工程及 7 个 IP 的 .idf 已核对） |
| 完成情况 | 阶段回传：7 个 IP 全部生成，包装模块适配及本机定向检查完成；顶层综合、布局布线和 RVC_EN=0 对照尚未执行 |

## 用户确认与 IP 端口差异

2026-10-26 用户授权 Windows Codex 修改包装模块，并转达 VPS Claude 确认：
其余包装模块复位统一接 `1'b0`、使能接实际端口；两个 Tag IP 用 512 深度，地址高位补零；
SRAM 使用单口；Windows 不要求运行 Verilator，结果推送后由 VPS Linux 执行 lint 和仿真回归。
因此本次不按原任务卡“端口不同就停止且不修改 RTL”处理，而是按上述用户确认适配并阶段回传。

| IP | 差异 | 本次实现 |
|---|---|---|
| ip_rom_boot | en → clk_en，必带 rst | en_i 接 clk_en，rst 接 0 |
| ip_ram_icache_tag、ip_ram_dcache_tag | rd_en → rd_clk_en；必带读写复位；物理深度变为 512 | 复位接 0，读写地址均为 {2'b00, 原7位地址} |
| ip_ram_icache_data、ip_ram_dcache_data | rd_en → rd_clk_en，必带读写复位 | 重接读使能，复位接 0；D-cache 字节使能保留 |
| ip_ram_sram | clk_en；1 位 wr_en 加 8 位 wr_byte_en；必带 rst | clk_en 接 en_i，wr_en 接原8位写使能的 OR，wr_byte_en 接原8位写使能，rst 接 0 |
| ip_mul_s33x33 | 必带 rst，厂商内部流水配置不同于原创建说明 | rst 接 0；实际流水延迟和 CE 行为通过本机定向检查 |

修改了上述 7 个 `rtl/tech/` 包装模块的 FPGA 分支。对外接口与行为模型保持不变，
未修改厂商生成文件、规格或共享 IP 创建说明。
实际端口、参数、初始化格式见 `artifacts/ip_ports.md`。

Tag 原 7 位地址的 `04030101` 诊断在两个 IP 重生成为 9 位地址后未再出现。
逻辑 Tag 容量仍为 128×20，仅使用物理 IP 的前 128 项。

## 本次验证

RTL 与检查源 commit：`cb547cbe3bb6b2e4783800191cb57281aa6998f1`。
生成 IP 来自上述本机工程，不入库。

1. 风格检查：7 个包装模块，0 告警。

   ```powershell
   python tools/check/verilog_style.py rtl/tech/edrv32_ram_icache_tag.v rtl/tech/edrv32_ram_icache_data.v rtl/tech/edrv32_ram_dcache_tag.v rtl/tech/edrv32_ram_dcache_data.v rtl/tech/edrv32_rom_boot.v rtl/tech/edrv32_ram_sram.v rtl/tech/edrv32_mul_s33x33.v
   ```

2. 实际生成 IP 的 ModelSim 编译、加载及定向检查：通过。

   ```powershell
   & G:/Program/modeltech64_2020.4/win64/vsim.exe -c -do 'do G:/codex_project/EdRV32-Competition-2026/tasks/win/20261025-01-cpu-sys-synth/src/check_ip_wrappers.do'
   ```

   - vlog 编译：Errors 0，Warnings 0。
   - Cache：`PASS cache_ram`；检查读出、同址读旧数据、字节写使能及读禁用保持。
   - 乘法器：`PASS multiplier checks=23`；检查两次使能上升沿延迟、CE 暂停保持、有符号极值。
   - SRAM：`PASS SRAM checks=7`；检查首尾地址、按字节写入、禁用端口时不写入且输出保持。
   - ROM：实际端口编译与加载；外部初始化内容未验证。
   - 最终检查中 Cache 优化时有一条厂商 `GTP_DRM36K_E1.v:746` 的 `vopt-2250` 警告：
     `Function "mem_read_a" has no return value assignment.` 未屏蔽，未修改厂商模型。
     重复运行时 vlib 另提示本地工作库已存在。不能把全部流程描述成“零告警”。

3. 此前现有 ROM 行为模型单元仿真：`PASS memory checks=20`。
   当前 FPGA 连接变更不修改该行为模型。

按用户确认，Verilator lint 和完整仿真回归交给 VPS Linux；本阶段不声称完整回归或完整 IP 等价性通过。

## 引脚

| 端口 | 引脚 | 出处 |
|---|---|---|
| clk_i | 未取得 | 待用户提供对应板卡的厂商 demo 约束文件 |
| rst_n_i | 未取得 | 同上 |
| uart_rx_i | 未取得 | 同上 |
| uart_tx_o | 未取得 | 同上 |
| key_n_i | 未取得 | 同上 |
| led_o[3:0] | 未取得 | 同上 |

## 时序（RVC_EN=1）

| 时钟 | WNS | TNS | WHS | THS | Fmax（推算） |
|---|---|---|---|---|---|
| clk_sys | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |

最差路径前 5 条：未取得，尚未运行顶层综合和布局布线。

## 资源（RVC_EN=1）

| LUT | FF | DRM | APM | 分布式 RAM | IO | PLL |
|---|---|---|---|---|---|---|
| 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |

按层次（主要模块）：未取得。乘法器实际 APM 占用亦尚未取得。

## RVC_EN=0 对照

| 项 | RVC_EN=1 | RVC_EN=0 |
|---|---|---|
| WNS / Fmax | 未取得 | 未取得 |
| LUT / FF | 未取得 | 未取得 |

顶层参数默认值未修改，仍为 RVC_EN=1。

## 完整报告在 Windows 本地的路径

- 工程：`G:\codex_project\EdRV32-FPGA\EdRV32\EdRV32.pds`。
- ModelSim 日志：`G:\codex_project\EdRV32-Competition-2026\build\win\20261025-01-cpu-sys-synth\check_ip_wrappers.log`。
- PDS 综合、布局布线报告尚未生成。

## 后续工作

- VPS Claude：执行 Linux lint / 回归，审阅包装适配；据实际端口和物理 Tag 深度更新 IP 创建说明。
- Windows：取得厂商 demo 引脚约束后，编写导入 Tcl、150 MHz 约束，执行综合和布局布线，收集任务卡全部时序/资源产物及 RVC_EN=0 对照。
- 配置截图尚未归档；ROM/SRAM 外部初始化文件格式尚未实测加载。

## 备注

原 Git SSH 22 端口在认证前被关闭；本仓库 origin 已切换到
`ssh://git@ssh.github.com:443/zc100116/EdRV32-Competition-2026.git`，fetch 已成功。
本机提交身份仅在当前仓库配置，沿用现有提交作者 `zc100116`。
本阶段仅提交源码、可复现检查源和精简报告；不提交 PDS 工程、厂商 IP、完整日志或 bitstream。
