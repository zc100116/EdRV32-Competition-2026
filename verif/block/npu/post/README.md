# NPU post block verification

依据 npu-spec v0.10 / testplan v0.6；只使用顶层 APB/AXI，未读 DUT RTL。
`fixtures.py` 按 §4.1/4.3 手工编码六个 identity CONV，输入为指定的真实固定形状
C64 box / C80 cls，所以不借助未公开的内部端口即可产生真实写回交错和 HALF_TAIL。
`oracle.py` 独立实现整数 max/tie、两阈值、DFL、未裁剪 Q8、24 B 小端记录。
测试按最终 C16 plane 的 beat 次序给出期望 enqueue order，完整比较 raw box/debug cls
和候选（包括尾拍补零）；禁写 cls 只检查无事务，不读取其空洞。

| 测试 | 档位 | 用例/检查 |
|---|---|---|
| TL-05 | S | 68 描述符、六标签、普通字13/14/15、三张逐项查表 |
| PP-01 | S | 三 head 两阈值等号两侧、−128/127/128、零候选、复位/SOFT_RST |
| PP-02/03 | S | tie 0/15/16/63/64/79、row/plane/pair/C32/half-tail/head 切换 |
| PP-04/05 | S | 全等/首末峰/峰差255/三stride、1–5条打包/零填充 |
| PP-06 | S | 零/非零，延迟 raw B/gather R/candidate B 的完成栅栏 |
| PP-07/08/09 | S | 固定种子随机R/W/B停顿、三阶段×两种错误、三阶段ABORT及恢复 |
| PP-10/11/12 | F | 真实帧/0/5040、raw/debug 三模式、全容量停顿 |
| PP-13 | S | 不同 INPUT/OUTPUT/POST 的双帧与旧候选区保持 |
| PP-P-01 | P | 37/5040×zero/latency/bw，EN=0 对照与debug EN=1，CSV |
| PP-P-02 | P | 12600 beat 激励、II=1/标签/5040入队检查器；接口适配待联调 |

环境：先 `. ~/.local/opt/edrv32/env.sh`；所有生成物在 `build/npu/`。

```sh
python3 verif/block/npu/post/selftest.py
python3 verif/block/npu/check_style.py
flock /tmp/edrv32-sim.lock python3 verif/block/npu/post/run.py --test PP-01 --compile-only
flock /tmp/edrv32-sim.lock python3 verif/block/npu/post/run.py --test PP-01 --prepare-only
flock /tmp/edrv32-sim.lock python3 verif/block/npu/post/run.py --test PP-05
flock /tmp/edrv32-sim.lock python3 tools/regress.py --path verif/block/npu/pp_05 --parallel 1
python3 verif/block/npu/post/run.py --test PP-P-02 --prepare-only
```

编译内部固定 `-j 1 -Wall`。TL-05 默认用仓库内离线快照重新编译真实固定网络到 `build/npu/post/tl05`；
也可用 `--network` 指定已有的 `mem_*.hex`、`regs.txt`。PP-10/11 的默认目录
`build/npu/yolo` 还须有整网参考的
`ref_out.hex`（包含完整 raw cls）。可先运行现有
`python3 verif/block/npu/run.py --test NET-01 --prepare-only` 生成这些公开交换产物。
已引入协调者授权的 tools 提交 fc0d2823；TL-05 已在本机通过。

PP-P-01 的 `performance.csv` 记录核心、装表在途等待、最后raw B到首gather和最后
候选B、DONE、读写字节及320拍预算。debug模式令最后raw B包含cls，便于从公开口
确定核心结束；装表等待按有未完成装表读事务的clk_npu周期计数，可能与核心重叠。
EN=0对照含同样raw写入，核心差值含装表开销。200MHz预算仅参照，不设性能上限。

协调者已确认：PP-P-02 本次只交激励/比对器和骨架；待 RTL worker 的接口报告后
联调接入 `stream.Acceptance`，不读实现。`accept(cycle, beat)` 在每个支路接收沿调用，
`enqueue(anchor)` 记录双入队，`finish(first_enqueue_cycle)` 输出拍数、流水延迟、63us参照。
未接入时直接运行 PP-P-02 明确失败；prepare-only 生成 stream.txt/anchors.txt。
本次只完成主机自检和编译；RTL功能/错误/ABORT/性能数值统一留给协调者另开联调。
