# 《余烬群岛》E1/E2 交付测量

代码 commit：`16f6fc83d`；依据：GDD v1.0.1、tech v1.0及协调者确认的 E2 范围。
工具：GCC 13.3.0、Zig 0.17.0、xPack GCC 15.2.0、Spike 1.1.1-dev；全部 C11、O2、Wall/Wextra/Werror。
结论：E1 底座、守火人、海岸五波、4 武器、3 敌人、2 词缀、6 遗物、4 铭文和升级三选一已集成。
包括有界岛/礁石/超时收缩、经验拾取、标签联动、对象粒子/飘字/闪白/震动、HUD/SELECT及菜单暂停/返回。
E2 不含祭坛、商人、金币、祝福和可破坏物；未实现 E3–E5。

Linux、Windows、board、spike 四构建通过，构建日志 0 warning、0 error。
Windows 为 PE32+ x86-64；board、spike 为 RV32 ELF；Windows 与板上均未运行。
录像 `assets/replays/coast.txt`：seed=20261124，10800 帧/180 秒；第 10195 帧胜利。
最终：第 5 波清场、230 击杀、179/260 生命、14 级；13 次升级并确认，冲刺/火种/终极各 39/40/6 次。
PC 与 Spike 均输出 `END,10800,3,5`；每 60 帧的全部字段摘要共 180 组逐项相同。
主机模拟双实例全状态比较、游戏流程、音频跨块确定性/十音效和音频环测试通过。
全录像 AUD underruns=0；三次 200 ms 前端间隔测试播放 28800 采样，underruns=0。

| 分项 | 平均 instret | 最大 instret | CPI1.3 平均周期 | CPI1.3 最大周期 | tech 预算周期 |
|---|---:|---:|---:|---:|---:|
| 模拟 | 69694.26 | 125335 | 90602.54 | 162935.50 | 1200000 |
| 表现准备 | 174969.22 | 281299 | 227459.99 | 365688.70 | 500000 |
| 音频 | 62962.14 | 131524 | 81850.79 | 170981.20 | 150000 |
| 三项合计 | 307625.62 | 530316 | 399913.31 | 689410.80 | 1850000 |

平均指令占比：模拟 22.66%、表现准备 56.88%、音频 20.47%；合计最大值来自同一实际帧。
音频峰值第 9643 帧，超分项预算 14.0%；瓶颈为 800 采样的合成/叠加音效与噪声更新，未增加降级路径。
Spike 测真实模拟、gfx_prepare 和混音；不执行 GPU、DISP、AUD MMIO 提交或硬件对象推进。
因此表现准备计数包含粒子累积存活扫描的保守上界；不据此宣称“表现加提交”完整预算达标。
周期是 CPI=1.3 的估算，需上板修正；模拟峰值及三项总峰值低于预算，音频峰值仍需后续优化。
GPU PERF 最大值：顶点 324、三角形 108、四边形 1348、通过像素 646071；周期计数为 0。
功能模型不模拟周期，GPU 一帧 70% 预算本次未测定；录像峰值 28 敌人/35 模拟弹，未做满载压测。
纹理 65600 B，调色板 11264 B，合计 76864 B < 196608 B；两张 imagegen 原图及提示词保留于 assets/art/。
原创海岸音乐一首（三声部，20 秒循环）和十音效；32 采样控制率，噪声使用独立 xorshift 流。

从仓库根目录复现四产物、测试及完整验收：
```sh
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/ember_isles all test -j1
mkdir -p build/ember_isles/frames
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt \
  --dump 172,749,8283,9500 --out build/ember_isles/frames > build/ember_isles/pc.log
python3 sw/apps/ember_isles/tools/measure.py > build/ember_isles/measure.txt
```

四张 PNG 均为 1280×720：
- 第 1 波：`build/ember_isles/frames/frame00172.png`
- 升级三选一：`build/ember_isles/frames/frame00749.png`
- 精英波（第 5 波）：`build/ember_isles/frames/frame08283.png`
- 第 5 波战斗：`build/ember_isles/frames/frame09500.png`

原始证据：`build/ember_isles/{build-all.log,pc.log,spike.log,measure.txt,sim-stats.txt}`。
模拟单独复现：`build/ember_isles/sim-replay sw/apps/ember_isles/assets/replays/coast.txt`。
核心/表结构：`f99c2b056`；模拟：`8b4cff9fd`；录像/检查：`9a1e54552`；图形/UI：`3aeb6803c`。
音频：`cf6300d2a`、`d5d6829d4`；平台/构建：`e495660ac`、`6edf31c88`。
表驱动/HUD：`6b86401c1`；规格对齐：`d46c176ac`；音频 IRQ：`8e9bdb32c`；稀有度：`16f6fc83d`。
