# ip_ram_gpu2_sdp72

| 项 | 固定取值 |
|---|---|
| 依据 | gpu-v2-spec §2.4/§2.6；G-P04；M-8 §10.2/10.4 |
| 器件 | PG2L200H；速度等级沿用工程 |
| 创建入口 | PDS IP Compiler → Memory → DRM → Simple Dual Port RAM |
| Component/Module Name | `ip_ram_gpu2_sdp72` |
| 包装 | `rtl/tech/edrv32_ram_gpu2_sdp72.v`，一个 IP 一种包装，所有同几何实例复用 |
| 使用者/实例数 | RF 6、常量 4；DRM scratch 144（LUTRAM 版本无此 144） |
| Write/Read Data Width | 72 / 72 |
| Write/Read Depth | 512 / 512 |
| Write/Read Address Width | 9 / 9 |
| Memory Resource | DRM；不要选 Distributed RAM |
| Clock | Common clock，同步上升沿；wr_clk/rd_clk 都接 clk_gpu |
| Write Enable | 开启整字写使能；Byte Write Enable 关闭 |
| Read Clock Enable | 开启；rd_clk_en=0 时保持内部读寄存器 |
| Output Register | **关闭**；RAM 本身同步读 1 拍，业务模块另有外部捕获 1 拍 |
| Read-during-write / Write Mode | Read First / Old Data，同一上升沿同址返回写入前整字 |
| Reset | 不复位内容/数据；生成 wr_rst/rd_rst 接 0 |
| Initialization | None，无初始化文件；内容和数据输出上电未定义 |

生成后期望端口如下，名称必须与包装一致：

| 端口 | 方向/位宽 |
|---|---|
| wr_clk、rd_clk、wr_rst、rd_rst、wr_en、rd_clk_en | input 1 |
| wr_addr、rd_addr | input 9 |
| wr_data | input 72 |
| rd_data | output 72 |

在 IP Compiler 中逐项设置后点 Generate，把生成目录加入探针工程；不要把生成文件提交到仓库。
导入 `import_probe_gpu2_banks_top.tcl`（DRM）或
`import_probe_gpu2_banks_lutram_top.tcl`（LUTRAM）前生成所需两种 DRM IP。
每实例预期一颗 DRM，实际以 PDS 报告为准；未启用的高位不另建更小 IP。
SDP72 的 RF/常量用两片拼128，scratch 两片拼92；SDP36 五片拼180，低160有效。

Windows 回传配置截图、真实模块端口和层次资源；在 ModelSim 上用 G-P04 同一 trace
核对 1 拍 RAM + 1 拍外捕获、连续每拍读写、读禁止保持、同址 Old Data。
若 GUI 不提供 Old Data 或实际碰撞语义不同，明确记录失败并交协调者修改契约/包装；
不得把未验证的跨端口碰撞写成已通过，也不得手改生成 IP。
