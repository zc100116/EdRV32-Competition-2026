# NPU AXI256 存储模型单元测试

依据 `docs/testplan/npu-testplan.md` 2.3，用现有
`edrv32_axi256_master` 驱动，`edrv32_axi256_checker` 全程开启。
三目录 `zero/`、`latency/`、`bw/` 分别覆盖首拍延迟和连续/限带宽传输；
每档都检查 WSTRB、B 首次拉高前不可见/拉高后可见、RREADY/BREADY 反压、
读写各自的在途窗口和返回顺序、突发内部地址命中的 SLVERR、非命中 OKAY、
plusarg hex 装载、读写拍数和首请求到末响应的周期统计。

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/unit/npu_axi256_mem'
```

模型使用 `edrv32_axi256_if`（本地 ID 1 位），提供 `peek`、`poke`、`load_hex`
后门和 `elapsed_cycles()`。未装载/未写入字节读 0，复位只清事务和统计，不清存储。
BVALID 首次拉高时提交整笔写，即使 BREADY 为 0 也已可见；在途信用直到 B 握手释放。

| plusarg | 默认 | 含义 |
|---|---|---|
| MEM_MODE | zero | zero / latency / bw |
| MEM_LAT | 94 | latency/bw 的 AR 握手到首个 R 可握手边沿周期数 |
| MEM_B_DELAY | 1 | 最后 W 握手到 BVALID 拉高的周期数 |
| MEM_OUTST | 8 | 读、写各自的最大在途笔数 |
| MEM_BW_MBPS | 1400 | 读写共享的数据带宽，十进制 MB/s |
| MEM_MHZ | 125 | clk_mem MHz，带宽令牌换算使用 |
| MEM_RERR_FIRST / MEM_RERR_LAST | 不注入 | 读错误字节地址闭区间，十六进制 |
| MEM_WERR_FIRST / MEM_WERR_LAST | 不注入 | 写错误字节地址闭区间，十六进制 |
| MEM_MODEL_HEX / MEM_DESC_HEX / MEM_INPUT_HEX | 不装载 | 绝对 beat 地址镜像路径 |
| MEM_WORK_HEX / MEM_OUTPUT_HEX / MEM_STATE_HEX | 不装载 | 绝对 beat 地址镜像路径 |

`bw` 每 clk_mem 周期增加 MEM_BW_MBPS 个令牌，一个 beat 消耗
`32 × MEM_MHZ`，桶容量两个 beat；读在 RVALID 首次拉高时扣除，写在 W 握手时扣除。
R 反压时不重复消费令牌，已有 RVALID 的数据和标志保持。
统计 `read_beats` 统计 R 握手、`write_beats` 统计 W 握手；`elapsed_cycles()`
包括首请求和末响应两个边沿，空测试为 0。

`lint.vlt` 只豁免验证行为代码的 BLKSEQ，以及现有公共 master/checker 中的
未使用打包字段；模型和本测试的其他 lint 告警均为错误。
`image.hex` 是手写的两拍装载激励，右侧字节对应最低 DDR 地址。
