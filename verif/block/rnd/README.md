# RND v1 精简验证

对应 `docs/spec/rnd-spec.md` v0.5 和 `docs/testplan/rnd-testplan.md` v0.3。
仅 FILL、BORDER、GLYPH、BLIT、COPY；BLIT 为正常混合、RGB565/ARGB8888/I8。
Python 整数参考独立实现 alpha、渐变、圆角、字形解包、翻转/缩放、调色板及重叠 COPY。

```sh
. ~/.local/opt/edrv32/env.sh
python3 verif/block/rnd/rnd_ref.py --selftest
flock /tmp/edrv32-sim.lock python3 tools/regress.py smoke --path verif/block/rnd -j 1
```

`run.py` 的 `SMOKE_CASES` 覆盖保留的 RN-01–10、14–16、20，另检查
0x06–0x0D、I4/I2/I1、MODE=1–7 的非法命令错误 3。
存储模型支持 AXI 随机背压、读写错误；逐字节比较目标、源、命令和外围区域。
不运行 full/perf；最终画面与布线结果由 B3R 上板验证。
