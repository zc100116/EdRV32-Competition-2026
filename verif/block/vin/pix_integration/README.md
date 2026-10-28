# VI-18 VIN + 真实 PIX

依据 `vin-testplan.md` v0.2 VI-18。独立 testbench 不改变 VI-01–17；
使用真实 VIN 和 `-f ../../../../rtl/filelists/pix.f` 的 PIX。

```sh
. ~/.local/opt/edrv32/env.sh
make smoke REGRESS_ARGS='-j 1 --path verif/block/vin/pix_integration'
```

`run.py` 用 `verif/block/pix/pix_ref.py` 生成四帧 64×16 输入和期望值；
SV 摄像头模型和内存源使用这些输入，AXI RAM 中的结果逐像素比对。
同一配置为高斯 → Sobel → 二值化 → 反色。

先验证摄像头帧（ENABLE 后先丢两帧），再验证内存源帧（源 stride 160 字节），
最后在 PIX BUSY、输入至少 96 字而未收到 EOF 时写 VIN ABORT。
检查中止帧无完成/EOF，AXI 事务排空，下一摄像头帧复用同一槽并逐像素正确，
PIX PERF3 从 0 变 1。所有观察均为公开端口/寄存器或测试 RAM 状态。

生成物在 `build/vin_pix/`；`compile.log`、`run.log` 为详细日志。
