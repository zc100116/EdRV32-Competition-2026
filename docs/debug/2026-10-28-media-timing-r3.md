# V-R8：媒体 clk_mem 时序路径寄存化

状态：RTL 和全部 Linux 检查已完成并提交；第 8.4 节三个需求边界尚未获答复，
本次 Dispatch 按未完成验收交付，不将超时视为批准。

## 1. 现象

输入基线为 `18a39be57ba1b142d5fc5466e41dfc293e39e214`，第三轮 PDS 报告见
`docs/reports/2026-10-28-timing-media-top-r3.md`；器件 PG2L200H-6，clk_mem 8 ns，
slow WNS +0.388 ns。VIN 的 APB abort 组合逻辑经过 PIX 的输出 READY，驱动
`advance_w`，PDS 报告该网络扇出 2358。其余待处理路径来自帧配置选择、FIFO 头保持、
事件与性能累加串联、GEO 源范围与地址计算串联、ETH 收包判定与复位判定。

本记录的 Linux 数字是结构和仿真结果；没有 Linux 布线余量结果。
最终是否达到 clk_mem 寄存器间 slack ≥1.0 ns 由 V-W5 的 PDS 复测判定。

## 2. 复现

最终实现与测量工具提交为 `fef837dec18d9564245a6b9315255a9083363d50`；回归结果见第 8 节。

工具：Verilator 5.020（Debian 5.020-1）；Yosys 0.70+219（git `5053d0e26`）。
先执行 `. ~/.local/opt/edrv32/env.sh`。风格及完整子系统 lint：

```sh
python3 tools/check/verilog_style.py rtl/media/pix rtl/media/vin rtl/media/geo rtl/media/disp rtl/eth
for module in pix vin geo disp eth; do
    tools/check/lint.sh -DSIM_MODE -Irtl/include --top-module "edrv32_$module" \
        -f "rtl/filelists/$module.f"
done
python3 verif/unit/pix_control/timing.py \
    --baseline 18a39be57ba1b142d5fc5466e41dfc293e39e214
```

`timing.py` 从指定 Git 提交读取原 PIX RTL，产物放在 `build/media-r3/timing/`。
使能统计使用 `proc; flatten; opt_expr; opt_clean; opt_dff; opt_clean`，刻意不运行
`opt_merge`，以统计 RTL 明确写出的复制寄存器。FF 的 EN 负载按 Q 位宽计数；
`loads` 额外计入直接组合输入引脚。没有把公共时钟和异步复位计入此数。
这是保守的 FF 位负载参考，不能等同于 PDS APM/CLM 打包后的 CE 引脚扇出。

PIX 算术级数使用 `synth -flatten -noabc; abc -lut 6`，filter/point2 黑盒，统计
寄存器 D 输入的最大 LUT6 深度。乘法器映射为通用 LUT，不能当作 PDS APM 的延迟。
每次一个测试目录，单作业、单仿真；回归原始日志在 `build/regress/`，本卡摘要在
`build/media-r3/`。完整命令和通过数见第 8 节。

## 3. 观察

基线全局推进使能的 PDS 扇出为 2358；本次 Linux 展开后的 PIX 推进寄存器最大
直接负载为 250，数据 EN 位负载为 248。无反压的双滤波最坏冲刷前后均为 `W+32`，
1280 像素宽时实测 1312 拍。完整矩阵及复现数字列于下文。

## 4. 根因

| 原路径组 | 根因信号与组合链 | 最终处理 | 增加的拍数 |
|---|---|---|---|
| VIN/stim → PIX kernel CE，50+26 个端点 | `abort_all_w` → VIN READY → PIX `advance_w`，全局扇出 2358 | 两槽输出缓冲计算下周期可用容量；103 份推进寄存器直接驱动各局部数据 CE，READY 只到这些寄存器的 D 输入 | 流水总延迟 +0，级数重新分配见第 5 节 |
| VIN/stim/width/ch0_ctrl → `u_regs/perf_r`，4+2+1 | 配置/帧事件、错误事件求和与 32 位累加串联 | `perf_event_r`、`cfg_errors_r` 先寄存，generate 中各计数器固定索引、独立累加器 | PERF +1 |
| VIN/stim → 写 FIFO 头 CE，20 | 原 `abort_all_w` 进入 FIFO 消费/保持逻辑，组合 `head_load_w` 控制 288 位头 | APB abort/soft-reset 合并后寄存为 `abort_all_r`；VIN 本地读控制器提前预留两个头槽，`fifo_capture0_r/1_r` 直接使能头寄存器 | abort +1；FIFO 读出 +1 |
| VIN width/valid/sof → PIX 帧配置、行 RAM，2+2+2+1 | 外部 SOF 直接选择 `point_cfg_w`，外部 valid/ready 直接参与内部 `accept_w` | 输入槽锁存中心化 RGB888、对比度、偏置和标签；帧配置在外部 SOF 握手时锁存；内部 accept 只由该槽 valid 和推进寄存器决定 | 输入槽 +1，同时吸收原 point1 操作数级，总延迟 +0 |
| PIX `frame_cfg_r` → kernel，6+2 | 整帧操作码直接扇出到四个 kernel 内所有运算 | 各 kernel 内三个颜色组及 spatial/result 分别复制操作码寄存器 | 配置分发 +1；第一拍数据到达前已稳定，像素延迟 +0 |
| ETH RX count → ARP IP、写 metadata，3+4 | 帧尾 action 判定直接作为远端数据寄存器/队列 CE | `packet_o`、`arp_o` 寄存；同拍锁存对应 metadata/MAC/IP；零长度包也由寄存的 packet 标志持有 BUSY | 接收决定/metadata +1；ARP 转发抵消额外 pending 跳转 |
| VIN ch0_ctrl → pack，9 | 首拍 admission、源选择、abort、overflow 串到打包 CE | `pack_valid_r`、`pack_data_r`、`pack_word_r` 锁存；完成 beat 的 FIFO 写使能也先寄存，接受末字时即预留 FIFO 项 | pack/FIFO 写入 +1；叠加读头 +1，共 +2 到 DMA 数据通道 |
| DISP meta → perf1_base，1 | CDC gray 解码、计数相减、停机判定与清基准 CE 串联 | 三路 CDC 计数先采样；`soft_clear_o` 再寄存；urgent/delayed-request 事件寄存后计数 | 计数采样 +1、停机清零 +1；本地 PERF3/4 +1 |
| GEO writer active → perf，1 | AXI 写握手门控 16 项串行像素计数，再到性能累加/CE | 四个独立 4 像素分组先寄存，握手同时寄存；随后平衡求和，再进入 regs 的像素事件寄存器；其他事件也先寄存 | PERF1 +2；其余 PERF +1 |
| GEO tile Y → read addr，1 | 两次角点加法、halo、裁剪、地址加法串联 | 源范围计算拆成局部角点和、第二个和、裁剪、输出宽高四个寄存阶段；地址模块接口不变 | 每块 bounds 设置 +4；像素流水吞吐不变 |
| ETH TX frame_state → regs，4 | frame_state 解码进入全局 BUSY，再到寄存器清零逻辑 | `frame_busy_r` 与状态转移同拍更新；仅 regs 内部使用寄存后的 `clear_regs_r`，parser 的原 SOFT_RST 命令边界保留 | BUSY +0；寄存器内部清零 +1，标准 APB 读回语义不变 |

## 5. 修复

### 5.1 无反压的输入到输出延迟

所有单位为 clk_mem 拍；首拍从输入 SOF 握手量到输出 SOF 握手。

| 配置与尺寸 | 基线首拍 / EOF 冲刷 | 本次首拍 / EOF 冲刷 |
|---|---:|---:|
| 全旁路，8×3 | 12 / 12 | 12 / 12 |
| 一个 3×3 级，4 像素宽 | 24 / 24 | 24 / 24 |
| 两个 3×3 级，4 像素宽 | 36 / 36 | 36 / 36 |
| 两个 3×3 级，16 像素宽 | 48 / 48 | 48 / 48 |
| 高斯 + Sobel，1280×5 | 1312 / 1312 | 1312 / 1312 |

原最坏双滤波冲刷已经达到 `W+32`，因此不能把输入槽和输出缓冲各直接多串行一拍。
最终输入槽兼作 point1 的原操作数级；point1 内仍是乘法 → 偏置 → 饱和 → Gamma
四级。point2 的 RGB565 选择结果由两槽输出缓冲锁存，该缓冲兼作原 point2 末级。
point1（含输入槽）仍为 5 级，point2（含输出缓冲）仍为 5 级；两个 3×3 级未增级。

输出 FIFO 有两个槽。每次根据本拍 push/pop 后的容量，把下一拍推进状态写进全部
局部使能寄存器；READY 突然拉低时，第二槽容纳最后一次已安排的推进。输出 READY
一直为 1 时，输入及输出都维持每拍一个双像素字。FIFO 满后的恢复也能逐拍输出。

输入未收 EOF 的新 SOF 仍先拒收并触发丢弃（pix-spec 2.8）；外部端口的 SOF 拒收
门控不进入内部 accept/point 配置/行 RAM/推进 CE。丢弃后可同拍清旧流水并将新 SOF
存入输入槽；有挂起的 SOFT_RST 时，先清零后再接受新 SOF。

### 5.2 point1 各级最大 LUT6 深度

| 级或寄存器 | 基线 | 本次 |
|---|---:|---:|
| 中心化数据操作数（本次为 input_data_r） | 1 | 1 |
| 对比度操作数 | 1 | 1 |
| 偏置操作数 | 2 | 2 |
| 乘法结果 | 7 | 7 |
| 偏置加法结果 | 5 | 5 |
| 饱和选择结果 | 1 | 1 |
| Gamma / 旁路末级 | 7 | 7 |
| frame_cfg_r 的 D 输入 | 7 | 2 |

没有把饱和逻辑和 Gamma 查表合并成更长的末级。输入级组合深度没有超过原操作数级，
乘法结果的通用 LUT 深度也保持一致；物理 APM 映射和余量仍须由 PDS 检查。

### 5.3 推进使能和帧配置复制

`reg ... /* synthesis syn_preserve=1 */;` 写法已由协调者明确授权，依据
`docs/guides/pds-floorplan.md` 中的厂商 RTL 例子。该文档并未证明其 Compile/ADS
防合并语义，因此 V-W5 必须核对综合后保留数量。未使用未经确认的 FDC 属性。

使用属性的推进寄存器：`advance_input_r`（1）、`advance_point1_r[6:0]`（7）、
`advance_point2_r[2:0]`（3）、`advance_filter1_r[3:0]`（4）、
`advance_filter2_r[3:0]`（4），四个 `advance_kernel10/11/20/21_r[20:0]`
各 21，共 103 份。帧配置复制属性仅加在各 kernel 的 `op_color_r`（每颜色组一份）、
`op_spatial_r`、`op_result_r`，四个 kernel 合计 20 组 × 3 位。

即使 PDS 合并等价复制，推进的源仍是寄存器 Q，不会恢复原来的外部组合 READY 路径。
每份完整负载列表由 `timing.py` 输出，按相同值归并如下（FF 位 EN / 总直接负载）：

| 复制寄存器 | 每份 EN 位 / 总负载 |
|---|---:|
| input | 70 / 74 |
| point1[0]；[1–6] | 127 / 129；45 / 45 |
| point2[0]；[1–2] | 248 / 250；95 / 95 |
| 每个 filter[0]；[1]；[2]；[3] | 0 / 35；209 / 209；0 / 9；75 / 75 |
| 每个 kernel[0]；[1] | 216 / 216；168 / 168 |
| 每个 kernel[2–10] | 95 / 95 |
| 每个 kernel[11,13,15]；[12,14,16] | 89 / 89；162 / 162 |
| 每个 kernel[17]；[18–19]；[20] | 128 / 128；80 / 80；24 / 24 |

EN=0 的 filter 分组通过局部 request/capture-valid 控制使能，直接组合负载数列在右侧。
这些局部组合 CE 自身也没有超过 256 位。四个 kernel 同一编号的值相同。

范围外的共同项是 `rtl/common/edrv32_dma2d_wr.v:119`：固定 256 位 data + 32 位
strb 的接收使能在此保守统计中为 288；已经向协调者提问是否接受为“约 256”的固定总线
项，本卡未修改公共 DMA。VIN 新头寄存器同为 288 位，但由 `fifo_capture0/1_r` 直接使能。

### 5.4 修复后的边界

- APB 顶层端口、地址、寄存器位域、valid/ready 流和 AXI 事务规则不变。
- 完整帧像素内容、像素次序、边界标记、寄存器计数含义不变；允许的事件计数寄存延迟
  为 1–2 拍，空闲后要结清。停止计数以原事件周期采样，不按延迟后的 BUSY 多计周期。
- 所有新增数据寄存器不复位；valid、槽指针、预留数量、事件标志等控制状态复位。
- 没有新增 RTL 文件、filelist 项、参数、错误检测、回退实现或测试门禁。

## 6. 防回归

单元测试保留全部原自检，并随内部端口连接适配局部推进位宽。
`pix_control` 增加 SOF 首拍和 EOF 冲刷实测输出。GEO bounds 单元按 done 后检查新的
源范围结果，不再在没有发起新运算时假定结果组合跟随输入。事件计数单元在允许的
固定流水延迟后读取最终值。

VIN 通道单元增加恰好填满 512 项后、下一拍立即到达单字新帧的情形：下一帧只溢出
一次，前一帧末 beat 仍逐字正确，槽分配回退及随后新帧恢复都正确。测试没有靠空拍
回避寄存写级中仍有最后一个完整 beat 的边界。

`verif/unit/eth_priority` 复用独立 ETH 端口环境，在首个 UDP 帧启动后延迟
0、1001、1002 拍发送 ARP 请求，检查下一帧次序、内容、FCS、计数和没有重复应答。
1002 拍是临界值：基线 `18a39be` 通过；首次寄存版本 `371cf61` 在 TX frame=1
期望 60 字节 ARP 帧体，实际得到 1074 字节 UDP 帧体；转发修复后通过。
原因是 RX 的决定寄存器之后再串联 top 的 pending 寄存器，TX 空闲第一拍可能先取 UDP。
现在把 RX 的已寄存事件及其已寄存负载直接交给 TX 仲裁，空闲时同拍消费优先，忙时才
转存 pending；避免重复发送。原始复现位于
`build/media-r3/eth_priority/delay-1002/{original,registered,forwarded}.log`。
延迟 1003 拍时三个版本都已错过首个 UDP 边界，不属于这组“下一帧必须 ARP”的期望，
因此固定回归只选上面的三个合法边界/控制场景。

本卡没有修改 `verif/block/`，也没有新增 filelist 条目。新的 unit test.yaml 指向已有
ETH 端口环境的 files.f。独立模块级测试用于验证协议、计数、吞吐、复位和反压。

## 7. 同类排查

- PIX 输入/输出停顿事件先寄存，PERF1/2 +1；丢弃事件复用 `discard_r`，PERF3 +1。
  输出 EOF 的 IRQ 和 DONE_COUNT 保留握手当拍更新。SOFT_RST 清空脉冲寄存，增加 1 拍，
  挂起期间继续拒收新帧。
- GEO 描述符原动态半字选择使能在 Yosys 中覆盖 512 位；改为两个明确的 256 位 beat
  接收使能。bilinear 的舍入寄存器只保存实际使用的高 8 位，省去三个颜色组共 48 个
  无用的推进位；Yosys 的 GEO `advance_w` 为 211 个 EN 位 / 220 个直接负载，
  没有增加像素级延迟。
- ETH 全部 PERF 事件先寄存，PERF9/10 的 DOORBELL 同时清掉前一命令的事件。
  WINn_BYTES、PEER、NOTIFY 更新维持原有写响应完成边界。
- VIN 的 FIFO 容量计数包含已接受、还在寄存写级中的完整 beat；该 beat 的寄存写入
  不被下一帧的溢出撤销。ABORT 后它仍属于已接受数据，正常提交到内部 RAM 再排空。
  不会丢失末 beat 或留下虚假的占用计数。


## 8. 最终验收与提交

全部规定的 Linux 风格、lint、单元、模块和性能检查已通过；另有第 8.4 节的需求澄清尚未收到答复。

### 8.1 性能测量

GEO GE-12：1280×720、45°，固定读延迟 40 拍，P5 模型读写合计 1.2 GB/s；seed 1。
原始日志：`build/media-r3/baseline-geo-perf-run.log` 与
`build/regress/perf/block/geo/perf/verilator/run.log`。

| 档位 | 基线 PERF0 / 帧时间 | 本次 PERF0 / 帧时间 | 规格上限 |
|---|---:|---:|---:|
| s=1 | 1203605 / 9.628840 ms | 1209097 / 9.672776 ms | 16.7 ms |
| s=2 | 2453345 / 19.626760 ms | 2458837 / 19.670696 ms | 33 ms |

两档实际执行均增加 5492 拍（43.936 µs）。PERF4 分别 7→11、929→933；
PERF5 分别 238748→244236、1487566→1493054。bounds 设置的 +4 拍改变了执行和等待
周期，PERF 仍按真实事件计数；事件流水没有人为补偿或伪造原计数值。
关于 Task 的“最终计数相同”是否允许实际周期/停顿事件数量随流水设置延迟变化，
已向协调者提问，等待明确这一区别；帧数、像素数、包数、字节数等仍严格按独立参考核对。

ETH ET-14：固定 R/B 延迟 40 拍、无反压，RX 连续 2 MiB、TX 单描述符 1 MiB。
原始日志：`build/media-r3/baseline-eth-perf-run.log` 与
`build/regress/perf/block/eth/perf/verilator/run.log`。

| 项 | 基线 | 本次 | 规格 |
|---|---:|---:|---:|
| RX | 116.556207 MB/s，17992624 ns | 116.556051 MB/s，17992648 ns | ≥100 MB/s |
| TX | 116.418931 MB/s，9006920 ns | 116.418931 MB/s，9006920 ns | ≥100 MB/s |
| 发送期间 ARP 应答开始延迟 | 104.010400 ns | 104.010400 ns | ≤10000 ns |


### 8.2 回归结果与命令

风格：40 个 RTL 文件，0 告警。完整 PIX/VIN/GEO/DISP/ETH 顶层各执行
`tools/check/lint.sh`，全部 0 告警；没有通过新增 lint 屏蔽绕过 RTL 告警。
所有仿真都 `-j 1`，没有使用 `--parallel`，同时只运行一个仿真。

| 单元测试目录族 | smoke 通过项 | full 通过项 |
|---|---:|---:|
| pix_* | 4 | 4 |
| vin_* | 6 | 6 |
| geo_* | 6 | 6 |
| disp_* | 6 | 6 |
| eth_*（含新 priority） | 7 | 8（含 eth_tx/fast） |
| 合计 | 29 | 30 |

| 独立模块测试 | smoke | full / perf |
|---|---|---|
| PIX | selftest；12 场景 | 25 场景 |
| VIN | selftest；VI-01–08、11、14、15；VI-18 真实 PIX 集成 | VI-01–17（含 720p、VI-17 十个种子）；VI-18 真实 PIX 集成 |
| GEO | selftest；53 场景 | 33 场景；GE-12 两档 perf |
| DISP | 12 场景 | 17 场景 |
| ETH | selftest；22 场景 | 10 个随机种子；ET-14 三项 perf |

模块 full 子目录执行追加的 full 场景；同一最终 RTL 的 smoke 已单独完成，
两者合起来覆盖完整 full 计划。最后的 ARP 转发修复后重新跑了全部 ETH 单元两档、
ETH 模块 smoke/full/perf；其他子系统 RTL 未受该修改影响。

```sh
for tier in smoke full; do
    for directory in verif/unit/pix_* verif/unit/vin_* verif/unit/geo_* verif/unit/disp_* verif/unit/eth_*; do
        python3 tools/regress.py "$tier" -j 1 --path "$directory"
    done
done
for module in pix vin geo disp eth; do
    python3 tools/regress.py smoke -j 1 --path "verif/block/$module"
    python3 tools/regress.py full -j 1 --path "verif/block/$module/full"
done
python3 tools/regress.py smoke -j 1 --path verif/block/vin/pix_integration
python3 tools/regress.py full -j 1 --path verif/block/vin/pix_integration
python3 tools/regress.py perf -j 1 --path verif/block/geo
python3 tools/regress.py perf -j 1 --path verif/block/eth
```

摘要日志：`build/media-r3/unit-*-{smoke,full}.log`、
`build/media-r3/block-*-{smoke,full}.log`、`vi18-{smoke,full}.log`、
`geo-perf.log`、`eth-perf.log`、`structure.log`。各仿真的编译及原始输出在
`build/regress/<tier>/{unit,block}/.../verilator/`；端口环境另保留 `build/{pix,geo,disp,eth}/`。

### 8.3 提交与文件

已在分支 `zc100116/task-media-timing-r3` 按模块提交：

| 提交 | 内容 |
|---|---|
| `dd73421` | PIX 寄存推进、操作数输入级、输出缓冲、操作码复制及结构测量 |
| `0d3a7d5` | VIN 寄存 abort/pack、FIFO 预留和头捕获、事件计数 |
| `e946e72` | GEO 分段 bounds、分组像素事件、计数、局部使能 |
| `371cf61` | ETH 寄存收包决定、计数、帧活动和寄存器清零 |
| `6fec697` | DISP CDC 计数采样、停机清零和事件寄存 |
| `ca82223` | ETH ARP 临界周期转发及端口回归 |
| `fef837d` | PIX 结构工具禁止向源目录写 Python 缓存 |

修改仅限本卡归属：

- PIX：全部六个 `rtl/media/pix/*.v`；`pix_control`、`pix_filter`、`pix_kernel`、
  `pix_point` 的 `tb.sv`；`verif/unit/pix_control/timing.py`。
- VIN：`edrv32_vin.v`、`edrv32_vin_ch.v`、`edrv32_vin_regs.v`；`vin_ch/tb.sv`。
- GEO：`edrv32_geo.v`、`edrv32_geo_bounds.v`、`edrv32_geo_bilinear.v`、
  `edrv32_geo_regs.v`；`geo_math/tb.sv`、`geo_regs/tb.sv`。
- DISP：`edrv32_disp_regs.v`；`disp_regs/tb.sv`。
- ETH：`edrv32_eth.v`、`edrv32_eth_rx.v`、`edrv32_eth_tx.v`、`edrv32_eth_regs.v`；
  `eth_regs/tb.sv`；`eth_priority/run.py`、`eth_priority/test.yaml`。
- 本调试记录。

### 8.4 待协调者确认

以下问题已经通过本 Dispatch 的 ask 记录，已按返回的 message ID 多次恢复等待，
尚未收到答复；没有把超时视为同意：

1. `msg_dd1513d9834c`：PIX 内部推进完全寄存，但外部 `pix_in_ready_o` 保留
   pix-spec 2.8 所要求的新 SOF 拒收门控。否则会先误握手再丢弃，改变原协议。
2. `msg_1719acbf3b13`：范围外公共 DMA 的固定 256+32 位使能，在保守 FF 位统计中为
   288；是否接受为“约 256”的固定总线项，或另行扩大公共 DMA 修改范围。
3. `msg_59eb0e01b8ac`：确认“计数相同”指保持真实事件且不丢计/多计流水尾周期，
   允许固定设置延迟导致实际执行、等待或停顿周期数量改变；GE-12 的实测差异见 8.1。

V-W5 还须检查 103 份推进寄存器、20 组操作码复制是否在 Compile/ADS/map 后保留，
各份实际 CE 扇出，以及 8 ns 下全部 clk_mem 寄存器间路径是否达到 ≥1.0 ns。

上述三个问题在最终交付前再次按原 message ID 查询，仍为 pending；因此本次 worker_done
使用 `outcome=failed`，失败原因是需求边界未确认，不是 lint 或仿真失败。
