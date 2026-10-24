# 64 位命中取指回归

```sh
python3 sim/script/run_dual_issue.py --case wide-frontend --seed 7 --wave
python3 sim/script/run_dual_issue.py --case wide-prediction --case wide-cache --case wide-predictor --case wide-mdu-irq
```

复用独立 ROM 指令边界参考模型，开头 128 条均为 32 位指令，要求持续双输出。返回可为 4/8 字节，line 尾必须单条返回；随机背压、单条消费、混合长度、半字目标、旧 epoch 与回绕均覆盖。宽模式错误/协议和预测验证由其他四个用例、ISA/ACT 与 CoreMark 一起完成。

宽缓存不会增加 AXI refill 拍数或更改 cache_data IP。实现和板级配置见 [开发记录](../../../../docs/architecture/2026-10-07-wide-fetch.zh.md)。
