# ip_ram_gpu2_queue

| 项 | 固定设置 |
|---|---|
| 依据 | gpu-v2-spec §2.4，G-P01 变延迟算术返回背压 |
| 器件 | PG2L200H，工程速度等级 |
| 创建入口 | PDS IP Compiler → Memory → Distributed RAM → Simple Dual Port RAM |
| Component / Module Name | `ip_ram_gpu2_queue` |
| 宽度 / 深度 / 地址位宽 | 32 / 16 / 4，两端口相同 |
| 写口 | 上升沿同步写，整字 `wr_en`，无 byte enable |
| 读口 | 异步读，无输出寄存器、无时钟使能 |
| 初始化 / 复位 | 无；上电内容不确定，模块占用状态负责屏蔽未写内容 |
| 读写同址 | 不依赖；仅非空读首指针，写尾指针 |
| 使用者 | `edrv32_gpu2_fp32`，vec4 四份和 DP 一份，总计五份 |
| 包装 | `rtl/tech/edrv32_ram_gpu2_queue.v` |

期望端口（PDS 2022.2-SP6.1 实际模板，卡 112）：`wr_clk`、`rd_clk`、`rst`、`wr_en` 各1位，包装把两个时钟都接 `clk_i`、`rst` 接 0；`wr_addr`/`rd_addr` 各4位；
`wr_data` 输入32位，`rd_data` 输出32位。生成后文件留在本地 FPGA 工程，加入
探针工程；不得提交生成文件。每实例预期16个32bit LUTRAM原语分配额（合计80 LR），
实际 LUTRAM/LUT/FF 以 PDS 报告为准。数据队列用于任意下游合法背压；自由运行
算术管线不会因 ready 形成组合使能路径。总在途信用数16限制所有返回队列容量。
