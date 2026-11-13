# COPY 单次对齐回归

对应 rnd-spec 2.6、5.2、5.3 和 T-SLIM1-MEDIA M2。

```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/unit/rnd_copy -j 1
flock /tmp/edrv32-sim.lock python3 verif/block/rnd/run.py copy
```

单元测试用完整源快照生成字节期望值，检查全部 32×32 源/目的偏移组合、
64 组最大 4096 像素行（包括 513 个原始 beat）、同行与跨行重叠、反向行序、
跨 4 KiB 行、读/写背压、连续输出每拍一 beat，以及读中/写中取消后重启。
模块级 copy 档检查两种格式的六种复制/重叠方向、4 KiB 和最大行宽、
命令/源读/写事务中的 ABORT，并检查父模块排空在途 AXI 事务。
