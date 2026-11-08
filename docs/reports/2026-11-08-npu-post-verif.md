# NPU 后处理独立模块验证准备（2026-11-08）

- 依据：npu-spec v0.10、npu-testplan v0.6；未阅读被测 RTL。
- 提交：本报告所属 `npu: add independent postprocessing block verification`；工具依赖 fc0d2823（本分支引入为 61c7056e）。
- 环境：Linux host、Python 3.12.3、Verilator 5.020；默认 clk_npu=180MHz/clk_mem=125MHz，无 FPGA 测量。
- S：TL-05；PP-01–09、PP-13；F：PP-10–12；P：PP-P-01/02，均有 test.yaml/files.f。
- TL-05 已通过：真实固定网络 68 描述符、六标签、普通字13/14/15、三表共1536个u32逐项一致。
- 主机自检 6 项通过：DFL/舍入/位宽、24B字段和故障拒绝、阈值/tie、5040条容量、12600拍/II检查器、TL字段及查表故障拒绝。
- 公共 yolo_post_ref 生成完整候选/EDDT，与独立整数实现交叉比对；禁写cls参考只来自离线输入。
- 公共端口testbench已编译，最终 Verilator -Wall lint 与 SV 风格检查均0告警；所有编译固定 -j 1。
- 已备好：真实写回交错的六个identity CONV、R/W/B停顿、SLVERR/DECERR、ABORT/恢复、完成栅栏、模式/双帧与流量检查。
- PP-P-01 准备37/5040×三档内存及EN=0对照，输出核心/装表在途/尾部/DONE周期与流量CSV；尚无实测性能数字。
- PP-P-02 按协调者答复交付12600拍激励和5040条入队/II/延迟检查器；内部端口适配等待RTL worker接口报告，未适配运行会明确报错。
- DUT功能仿真未执行；PP-01–13及PP-P-01的功能、错误、ABORT、真实帧与性能结果均待协调者另开联调任务。
- 原始数据：build/npu/post/tl05、post_selftest、post_selftest_full、post/pp-p-02；编译日志：build/npu/post_sim/compile.log。

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/npu/post/selftest.py
python3 verif/block/npu/post/run.py --test TL-05
python3 verif/block/npu/check_style.py
flock /tmp/edrv32-sim.lock python3 verif/block/npu/post/run.py --test PP-01 --compile-only
flock /tmp/edrv32-sim.lock python3 verif/block/npu/post/run.py --test PP-01 --lint-only
python3 verif/block/npu/post/run.py --test PP-P-02 --prepare-only
flock /tmp/edrv32-sim.lock python3 verif/block/npu/post/run.py --test PP-05
```
联调时替换 `--test` 为相应编号；真实帧PP-10/11先按post/README.md生成完整网络ref_out.hex。
