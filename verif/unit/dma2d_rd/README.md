# V-D1：DMA2D 单元验证与资源参考

日期：2026-10-27。RTL 和 testbench 的测量版本：`70ed3134f974eff014934798e341cdbea5aef4c6`。
依据 dma2d-spec v0.1、dma2d-testplan v0.1、SoC spec v0.8 的 4.2/7.1。
本报告放在任务归属目录；没有修改 docs、共享 RTL、共享 checker 或 tools。

## 实现与验证

两个模块按行、16 beat 上限和 4 KiB 边界贪心拆分；ID 固定为 0。
读方向保留行标记，写方向传递字节使能；在同拍响应回收 credit，
使 OUTSTANDING=1 时无阻塞的连续突发也保持每拍一个 beat。
ABORT 排空已提交事务；W 被反压时的负载寄存器不复位。
错误只累计非 OKAY 响应，在 done 同周期报告。

工具：Verilator 5.020（Debian 5.020-1）；Yosys 0.70+219，
git sha1 5053d0e26，Clang 21.1.8。
所有 Verilator 构建均使用 `-j 1`，本 worker 的仿真串行执行。

以下命令均从仓库根目录执行，先 `. ~/.local/opt/edrv32/env.sh`：

| 命令 | 结果 |
|---|---|
| `python3 tools/check/verilog_style.py rtl/common/edrv32_dma2d_rd.v rtl/common/edrv32_dma2d_wr.v` | 2 files，0 warnings |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/dma2d_rd'` | 1 PASS，0 FAIL |
| `make smoke REGRESS_ARGS='-j 1 --path verif/unit/dma2d_wr'` | 1 PASS，0 FAIL |
| `make full REGRESS_ARGS='-j 1 --path verif/unit/dma2d_rd'` | 4 PASS，0 FAIL |
| `make full REGRESS_ARGS='-j 1 --path verif/unit/dma2d_wr'` | 4 PASS，0 FAIL |

两个模块分别在 OUTSTANDING=1、4、8 下以 `-Wall` 做 lint，均为 0 告警：

```sh
for dma_direction in rd wr; do
    for dma_limit in 1 4 8; do
        verilator --lint-only -Wall -DSIM_MODE -Irtl/include \
            --top-module edrv32_dma2d_$dma_direction -GOUTSTANDING=$dma_limit \
            rtl/common/edrv32_dma2d_$dma_direction.v
    done
done
```

原始日志：`build/dma2d/style.log`、`build/dma2d/lint_{rd,wr}_{1,4,8}.log`；
回归日志：`build/regress/{smoke,full}/unit/dma2d_{rd,wr}/` 下每个配置的
`verilator/compile.log` 和 `verilator/run.log`。

## 档位和覆盖

根目录 test.yaml 是 smoke：DM-01、DM-02（读）/DM-03（写）、DM-05、DM-06、DM-07。
full 增加 full_1、full_4、full_8，分别设 OUTSTANDING=1/4/8，
以 `+FULL` 加入 DM-04、DM-08、DM-09；根 smoke 配置也由 full 入口执行。
每个 smoke 执行 93 个描述符，每个 full_N 执行 1101 个描述符。
full_4 和根 smoke 在同一次 full 命令中复用编译产物。

- DM-01：4 个边界偏移 × 7 个宽度 × 3 个高度的全部 84 个组合；
  另测 width=65535、height=4095 的合法边界。
  期望突发列表由 testbench 按字节地址和行长度独立计算。
- DM-02/03：读逐字节比较并检查 sol/eol/eof；写比较独立生成的 data/strb，
  再逐字节比较实际和期望存储，包括未使能字节和 stride 间隙。
- DM-04：逐拍统计 AR 至 RLAST / AW 至 B；随机延迟下不超过实例上限，
  并通过冻结响应确定性地打满 1/4/8 个 outstanding。
- DM-05：width=5120、height=8，无阻塞，检查首 beat 后每拍连续且跨突发行无空拍；
  对 1/4/8 三个配置均执行。
- DM-06：下一拍完成、done 单周期、完成前 desc_ready=0；写等待最终 B。
- DM-07：SLVERR、DECERR 分别注入首/中/末突发；同拍检查 done/err，继续比对数据。
- DM-08：地址 VALID 被反压、数据已传一部分、R 或 W 被反压、outstanding 打满时中止；
  AXI checker 检查已展示负载稳定性，写补零 beat 逐个检查 strb=0，排空后重启描述符。
- DM-09：每个 full_N 各 1000 个随机合法描述符，随机地址/宽度/高度/stride 和两端反压。
  随机初始种子为 `32'h1a2b3c4d + OUTSTANDING`。

两个 testbench 都复用 `verif/common/edrv32_axi256_checker.sv` 和对应 interface，
检查 VALID 稳定、ID/顺序、对齐、4 KiB、WLAST/RLAST。

## 已提出并确认的 ask

本次只发出一条 ask，包含两项：

1. ABORT 与已展示但未握手的 AR/AW/W 稳定性冲突。
   协调者确认已置 VALID 的 AR/AW 视为已提交，保持到握手后 drain；
   已置 VALID 的 W 保持原 data/strb 到握手，其余 beat 才 strb=0。
   协调者负责补入规格；本分支未修改 docs。
2. tools/synth/yosys_synth.py 仅列出 CPU 类顶层。
   协调者确认在 build/synth 生成相同 synth -noabc / abc -lut 6 流程的 DMA 脚本，
   不修改共享 tools/synth。

没有未回答的 ask，也没有等待超时后自行决定的规格事项。

## Yosys LUT6 / FF 参考

OUTSTANDING=4，单模块，FPGA_MODE，flatten；
沿用 tools/synth/yosys_synth.py 的 generic LUT6 流程。
这是通用 LUT6 映射参考，未指定 FPGA 器件或速度等级，没有时钟约束，
不能替代 PG2L200H 的 PDS 资源或时序实测。
此前无这两个模块的基线。

| 模块 | LUT6 (`$lut`) | FF | RAM/DRM 单元 |
|---|---:|---:|---:|
| edrv32_dma2d_rd | 393 | 165 | 0 |
| edrv32_dma2d_wr | 664 | 436 | 0 |

FF 统计：rd = 15 DFF + 42 带复位 DFFE + 108 无复位 DFFE；
wr = 16 DFF + 24 带复位 DFFE + 396 无复位 DFFE。
写方向的 generic LUT6 数高于规格第 7 节待定的 600 LUT 参考目标；
PDS 实际资源和时序仍需后续实测确认。

下面完整复现脚本的流程；与本次 build/synth/dma2d_{rd,wr}/netlist.ys 内容相同：

```sh
for dma_direction in rd wr; do
    mkdir -p build/synth/dma2d_$dma_direction
    cat > build/synth/dma2d_$dma_direction/netlist.ys <<EOF
read_verilog -D FPGA_MODE -Irtl/include rtl/common/edrv32_dma2d_$dma_direction.v
chparam -set OUTSTANDING 4 edrv32_dma2d_$dma_direction
hierarchy -top edrv32_dma2d_$dma_direction
synth -top edrv32_dma2d_$dma_direction -flatten -noabc
abc -lut 6 -dress
opt_clean
write_json build/synth/dma2d_$dma_direction/netlist.json
stat
EOF
    yosys -Q -T -l build/synth/dma2d_$dma_direction/netlist.log \
        -s build/synth/dma2d_$dma_direction/netlist.ys
done
```

原始综合脚本、日志和映射网表位于 `build/synth/dma2d_rd/` 与 `build/synth/dma2d_wr/`。
