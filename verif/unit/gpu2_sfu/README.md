# GPU v2 SFU numerical pieces — integration pending

依据 gpu-v2-spec v0.1 §2.4、VT06、M-6。当前目录验证三个数值前端阶段和两个最终
缩放阶段；独立十拍 MUL/FMA 核复用已验证的 GPU v2 标量数据通路，综合时裁掉 DP
乘积旁路。**当前还没有 SFU ROM/II4 预约引擎集成模块或 FPGA SFU 探针顶层，不能
把本目录 PASS 记为 G-P02 完成。**

`tools/gpu2/sfu.py` 为标准库整数 FP32 逐操作参考；表由原始 M-6 libm 公式生成。
`tools/gpu2/corpus.py` 复用 M5 原14变体×128组（包括末32组 G 类定向）及 M6 的
四函数、近1、窄域/广域 pow 语料，共398760次调用；M5 的 underflow 调用全部保留。
M6 直接函数采用原种子20261127。smoke 选每函数原20000例的前128例，共512例；
full 保留全部原始调用，包括重复和 underflow；整数参考与原 M-6 返回逐位匹配。

前端公开数值字段、表地址、scale/sign、特殊值开发初值按每输入逐位检查；不读内部信号。
最终缩放以整数二进制幂与 RNE 检查2000余条 smoke /100000条 full，覆盖渐进下溢。
原 M6 `EXP2` 在 `-1/64<x<0` 时的残差通常不是 FP32：第一预约槽必须用
`FMA(x, ln2, ln2/64)`，不能先把 `x+1/64` 舍入。定向原料 `bb77b4d6` 的结果为
`3f7f5488`；多一次残差舍入会变为 `3f7f5486`。这不增加预约槽或 APM。

```sh
python3 tools/regress.py smoke --path verif/unit/gpu2_sfu -j 1
python3 tools/regress.py full --path verif/unit/gpu2_sfu -j 1
python3 -B tools/gpu2/corpus.py
python3 -B -m tools.gpu2.sfu
```

最后一条仅证明512个混合 II4 请求的3131个算术预约无冲突，尚不是 RTL 预约测试。
待协调：M6 的64bit LOG+INV与 setup 独立读口怎样映射单 DRM；推荐1024×36 TDP、
32bit表项分地址，在原四拍前端依次读 LOG/INV，保持 setup 独立端口与原总延迟。
