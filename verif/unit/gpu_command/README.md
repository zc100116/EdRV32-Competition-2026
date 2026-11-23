# GPU 前端单元验证与集成端口

依据 gpu-spec v0.2、GPU 微结构设计记录 4.2/4.5/4.9；环境：用户提供的仿真主机（环境不记录）。

| 模块 | 端口摘要 |
|---|---|
| `regs` | APB4；start/abort/soft_rst 脉冲；enable/desc_base/desc_count/wide；busy/done/error/err_code；object_cfg 与 object_result；PERF 事件、IRQ |
| `command` | 7 路独立 read_req；command_read_data；matrix 回传；unpack/pack 启动；geometry_cfg；raster/quad/texture/pixel 四路 render_state；geometry/raster/quad/object 四路 draw；clear/resolve；palette_prepare/prepared；每单元 finish/done；stop、DMA start/idle/error |
| `read_dma` | command/matrix/vertex/quad/object/texture/palette 七路 read_req/data/done；AXI256 AR/R；start/stop、idle/error、read_wait |
| `write_dma` | object/hit/free/resolve 四路 write_req/data/done；AXI256 AW/W/B；start/stop、idle/error |
| `resolve` | resolve_command/target/wide；target resolve_read/color；Surface write_req/data/done；finish/stop/done、busy 事件 |
| `unpack` | 当前命令；matrix/vertex/quad/texture/palette 五路 read_data；matrix512、vertex128、quad_record128、texture_load、palette_load；stop/done |
| `list_pack` | 当前 OBJ_STEP、列表配置；object_update/event；object/hit/free 三路 write_req/data/done；finish/stop/done |

- DRAW_TRI 只向 raster 发扫描状态；DRAW_QUAD/OBJ_STEP 只向 quad 发扫描状态，测试分别计数并对 quad 独立反压。
- 命令 FIFO 为 32 项；每次预取至多 16 条，并先保留整个区间所需 FIFO 空间，避免命令返回阻塞当前绘制所需的读 DMA。
- `command.dma_start_o` 接两个 DMA 的 `start_i`，清本次运行的 AXI 错误粘滞位。
- `command.object_cfg_request_o` 接 regs 快照请求；`object_cfg_done_i` 是配置流实际握手脉冲。快照同时供 object 与 list_pack，顶层须保证两者均已取到快照。
- `command.pack_valid/command` 启动 list_pack，其 `finish_i` 接 object 的 `unit_done`；`pack_done_i` 返回 command。
- texture 的 `unit_done` 在单元内部合并纹理 RAM 的全部装入写提交；TEX_LOAD 的 texture finish 等 unpack 完成，PAL_LOAD 以末项写握手为准。
- object 的读数据直接接 object；其他数据客户接 unpack。command 负责生成所有读区间，unpack 负责拆包。
- `object_publish` 后的 object_result 实际握手反馈 `object_published_i`，该握手才退休 OBJ_STEP。
- RESOLVE 的 `resolve_target` 是启动时 SET_TARGET 快照；目标读坐标减 TGT_X0/Y0，Surface 地址使用原屏幕坐标。
- finish 从 1 降至 0 开始新命令；配置流在 finish=0 保持一拍后才能握手。stop 时 DMA 已接收区间继续完成。

## 存储包装

| 包装 | 配置 | 实例 |
|---|---|---|
| `edrv32_ram_gpu_read_pool` | 分布式 64×256、读延迟 1 拍 | read_dma ×1 |
| `edrv32_ram_gpu_write_pool` | 分布式 32×256、读延迟 1 拍 | write_dma ×1、command FIFO ×1 |
| `edrv32_ram_gpu_resolve_line` | DRM 512×72、有效 320×64、读延迟 1 拍 | resolve ×3 |

创建说明见 `fpga/ip/ip_{lutram_gpu_read_pool,lutram_gpu_write_pool,ram_gpu_resolve_line}.md`。

## 复现

在仿真主机同步工作树后，对下列每个目录分别执行：

```sh
python3 tools/regress.py smoke --path verif/unit/gpu_regs -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_command -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_read_dma -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_write_dma -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_resolve -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_unpack -j 1
python3 tools/regress.py smoke --path verif/unit/gpu_list_pack -j 1
```

SET_TEX 的 108 种宽高/格式组合均核对完整 9 级物理占用，并测试容量内/越界相邻 32 B 偏移。

单元测试自检 payload、状态和完成顺序；DMA 覆盖背压、4 KiB、16 beat、4读/2写在途上限、keep/WSTRB、错误与 ABORT；RESOLVE 覆盖逐像素公式、边界、两种目标形状、偏移、跨度及全条 AA 周期预算。

## 验证结果
实现 commit：`48136be87acb141fcfa99a97eb3cd8d5b62d6833`。
七项自检 7/7 PASS；10 个 RTL 文件风格检查和七模块 Verilator `--lint-only -Wall` 均为 0 告警。
读/写在途峰值 4/2；640×180 全条 AA 为 34375 周期；主机仿真进程和构建目录已清理。
周期属于单元目标/写完成模型，DDR 端到端性能和 PDS 时序留给独立集成验证。

4.12 状态路由补充：`gpu: command sends render_state to quad for quad draws`；
`python3 tools/regress.py smoke --path verif/unit/gpu_command -j 1` 实测 1 PASS、0 FAIL。
新增检查：DRAW_TRI 的 raster 快照 1 次，DRAW_QUAD/OBJ_STEP 的 quad 快照合计 2 次；
quad 独立反压时快照保持；command 风格检查和 `--lint-only -Wall` 为 0 告警。

装入完成补充：TEX_LOAD/PAL_LOAD 的 finish 均等待 unpack 最后一项输出握手。
单测额外设置 5 拍 unpack 输出尾延迟，覆盖 DMA 已空闲但仍有待输出项的窗口，并检查 finish 保持低。
该补充的同一单元回归为 1 PASS、0 FAIL；command 风格和 RTL lint 均为 0 告警。
