# 人脸图片贴纸软件验证（2026-11-16）

- Commit：本报告所在提交；开发基线 `242b3fb7d`，集成基线 `e84a54c8b`（`zc100116/b3`）。
- 工具：xPack RISC-V GCC 15.2.0；主机 C11；Python 3 标准库。
- 范围：PAGE_FACE；L1 ARGB8888，RND 缩放/混合，预生成角度代替运行时旋转。
- 全部 C 跟踪/滤波/几何代码使用整数；像素、角度 Q8，alpha Q16。
- One Euro：min_cutoff=26/256 Hz，beta=197/65536，d_cutoff=1 Hz。
- 参数依据：在 37 ms 合成采样下，低静态截止压制独立关键点噪声；
  beta 随速度提高截止，同时满足 ≤1 px 抖动和 ≤3 帧滞后。
- 五点各自独立 ±3 px 噪声，LCG seed=23，600 帧，丢弃前 101 帧：
  滤波眼中点 x/y 峰峰值 226/256=0.883 px、190/256=0.742 px。
- 600 px/s、37 ms 采样、100 帧：最大滞后 16086/256=62.836 px，2.830 帧。
- 两脸交叉且检测顺序交替、最多三脸、连续两帧确认、丢失六帧保持和四帧淡出通过。
- 五档角度的中点外 3° 滞回、d/θ 锚点及缩放几何通过。
- 关联使用眼中点，0.8d 门限；上一帧运动预测的最近邻代价保持交叉轨迹身份。

| 套装/组合元素 | 基图 | 旋转画布×帧数 | ARGB 字节 | alpha 1–39 像素 |
|---|---|---|---:|---:|
| 桃桃猫耳/猫耳发箍 | 160×160 | 220×220×5 | 968000 | 547 |
| 软糖兔耳/兔耳发箍 | 160×160 | 220×220×5 | 968000 | 694 |
| 海盐墨镜/墨镜 | 160×160 | 220×220×5 | 968000 | 199 |
| 宝石皇冠/皇冠 | 160×160 | 220×220×5 | 968000 | 330 |
| 彩带派对/帽子彩带 | 160×160 | 220×220×5 | 968000 | 418 |
| 心动发箍/爱心发箍 | 160×160 | 220×220×5 | 968000 | 964 |

合计 5,808,000 字节；提示词、后处理命令和锚点参数见素材目录 README。
补充：边界连通低 alpha 底色清理保留一像素抗锯齿边缘，爱心发箍 5161→964，六图均≤1000。

```sh
. ~/.local/opt/edrv32/env.sh
flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase
flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu
make -C sw/tests/showcase sticker
```

原始日志：`build/showcase/sticker-{hw,cpu}-build.log`、`sticker-test.log`。
构建和测试：两版构建零告警，主机测试通过；未运行 SoC 仿真或上板。

底色补充验证：仅重跑硬件构建与 sticker（含 alpha 回归），日志 `sticker-alpha-{build,test}.log`。

## R3 同步显示与分部位贴纸（2026-11-16）

- Commit：本节所在提交；基线 `89e47fe49`（`zc100116/b3`）；工具同前。
- 仅 PAGE_FACE/PAGE_GRAB：CH0 不立即排队显示，引用随 NPU → post → 结果 → GUI 转移。
- GUI 取走后保留独立引用，更新结果不会释放正在绘制的画面；未取走的旧结果直接释放。
- 最后一块 flush 先暂存 L1，在 FRAME IRQ（本帧已锁存）中连续写 L0/L1 NEXT_BASE，
  两层下次锁存一起生效；相比立即提交增加一帧提交等待，实际 e2e 留待上板测量。
- PAGE_GRAB 的非 framework 页面 timer 在取结果后 ready，按经过 ticks 推进，不额外走模拟步；
  同步页在判断无重绘前调用 lv_refr_now，保证光标/贴纸失效区域先渲染。
- 无重绘时 GUI 尾部直接提交 L0；不要求 SWITCH1，L0 实际扫描时计 shown 和 e2e。
- 同一 revision 至多提交一次；同步页 L0 SWITCH 在 IRQ 内释放旧槽，避免 REL_BASE 被后帧覆盖。
- CH0 仍为 **4 槽、4×2 MiB**，每槽有效数据 1,843,200 B，DDR 表不变。
- 槽通常跨采集/推理/显示约 2–3 周期占用；多结果重叠时按 vin-spec 2.6 全忙 SKIP，
  不是溢出错误；硬件仅支持 4 槽（vin-spec 4.3），未改 RTL/规格或增加 DDR 区域。
- 暂停先停止并排空，已取走结果仍可完成同步上屏；退出释放 pending，扫描槽只由 SWITCH/IDLE 释放。
- One Euro：min_cutoff=26/256 Hz，**beta=1311/65536≈0.020004**，d_cutoff=1 Hz。
- 37 ms、600 px/s、100 帧：最大滞后 **4722/256=18.445 px，0.831 帧**（原 2.830 帧）。
- 独立五点 ±3 px 噪声、LCG seed=23、600 帧、舍弃前 101 帧：眼中点峰峰值
  **x=330/256=1.289 px、y=328/256=1.281 px**；提高 beta 以滞后优先，仍满足 ≤1.5 px。
- 五点分别滤波；眼中点/鼻尖/嘴角中点/同侧眼嘴中点锚点及嘴宽几何通过；最多三脸。
- 头饰五款沿用，眼部保留墨镜；新增素材及五角度 ARGB 数据如下（含左右胡须）：

| 新部位 | 新增 PNG | 基础尺寸 | 字节 |
|---|---|---|---:|
| 眼睛 | 爱心眼镜、星星眼、卡通大眼 | 112² | 1,422,960 |
| 鼻子 | 猫鼻、小丑鼻、小狗鼻 | 48² | 261,360 |
| 嘴巴 | 八字胡、红唇、吐舌头 | 96² | 1,045,440 |
| 脸颊 | 腮红、猫胡须（左右） | 64² | 464,640 |

- 新增 **3,194,400 B**；全部素材 **9,002,400 B <10 MB**；逐张 imagegen 提示词见素材 README。
- 五部位各含“无”，四预设猫咪/派对/酷/兔子，选择及调试开关保留；小图使用实际尺寸。
- 验收命令：`make -C sw/tests/showcase sticker grab`、`make -C sw/tests/showcase sync`；
  sync 同时跑生产 LVGL 挂钩与 vision runtime，覆盖仅提交一次、无重绘前进、跳帧及暂停/退出释放。
- 构建：经 `flock /tmp/edrv32-sw-build.lock` 串行执行 `make -C sw -j2 PROGRAM=showcase`
  与 `make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`。
- 结果：两版构建零告警，sticker/grab/sync 全通过；日志 `build/showcase/r3-{hw-build,cpu-build,final-tests}.log`。
- 未跑 SoC 仿真或上板；`sync` 还验证旧帧呈现与新帧提交共处一个 IRQ 时 e2e 时间戳不串帧。
