# V1-INT 暂停报告（2026-11-25）
状态：failed；用户试玩后要求暂停并讨论卡顿、打击手感、美术风格；未完成正式验收。
代码 WIP：`e32042392`（`wip: v1 integration paused`）；素材冻结：`17a80a639`。
首版范围：守火人、余烬剑/余火杖配对选择、海岸竞技场 10 波；不宣称完整 E5。
授权的模拟/核心提交：`790120cf0` 施法技能、`bdc601c6c` 敌人动作、`b87449af6` 命中来源。
另有 `554a734fd` 敌弹来源、`d978cadcc` 弹体进化快照、`7c3d063fd` 水柱 45 帧预警及新录像。
元数据不改变伤害；水柱时机是用户另行授权的机制变更，比较基线因此固定为 `7c3d063fd`。
I4/I8 原生紧凑帧、固定区、统一 LRU、动作/方向/手锚点、海岸角色/敌人/Boss 部件已接入代码。
中文 HUD、升级卡、商店/祭坛/裂隙/替换面板、标题/武器选择/音量/结算返回已接入；不开放扩展玩法入口。
拾取/换装使用真实事件；粒子由 GPU OBJ_STEP 推进，9 种发射器参数编译自 emitters.csv。
固定区配置 48 KiB；FPGA 流式 144 KiB、总 192 KiB；PC 流式 208 KiB、总 256 KiB。
流式页为 16 KiB，合法视图 128×128 I8 / 128×256 I4；同一物理 8 字节块按帧格式寻址。
当前编译包 PC 1646 帧（1598 I8 + 48 I4），FPGA 1404 帧（1356 I8 + 48 I4）；16 组素材色板。
17a80a639 源包 GPU 唯一参考模型回读：39,976,960 纹素通过；DDR 库 2,879,200 B。
混页模型单测在 806d51110 包验证 48 I4 + 48 I8，297,386 纹素及声明的色板变体一致。
CPU 字体 776 字形；GPU 热字形/普通与暴击数字共用 4 KiB，未上传整套字体。
普通数字含描边 7×12，暴击 11×20；140 个普通缓存槽加预驻留十个数字，描边/数字占独立位平面。
四主目标 Linux/Windows/board/Spike 最后均编译完成、0 warning；日志 `build/ember_isles/v1-final-build.log`。
组合命令在后续 linux-fpga 辅助构建时按暂停指令终止（exit 143）；之后没有启动新验收或媒体生成。
最后已运行的定向测试：E4 8138 断言；E5 内容/海岸、45 帧水柱、菜单流程通过。
GPU 粒子单测：9 发射器、66 对象均移动/减寿命，暂停不变；9 种武器分支配对通过固定区测试。
另测普通/暴击数字对象、8 种真实 I4 光环及双层叠画；这些测试早于最后地形合批/敌弹拖尾等收尾改动。
CPU 中文 UI：正常录像 25,920 帧，单界面字形峰值 106；22,100 种卡片组合非数字峰值 116/140。
上述定向结果不替代 WIP 最终运行；最后合批、卡片选中提示、动作分段等尚未完成组合回归。
已分发 Windows 预览：`outputs/ember_isles/v1/preview/`，对应 806d51110 素材及较早代码。
预览含独立 exe、8 行中文 README、总 CREDITS 与字体 OFL/上游许可证；素材/音频/字形内置。
预览真实 headless 冒烟 3934 帧：phase=2（升级）、wave=2，第一波残敌=0，音频 underruns=0；不是胜利证明。
CPU 新录像生成器完成 25,920 帧、phase=3、HP=216、击杀=695；这只是模拟结果，不是最终 GPU/Windows 通关验收。
以下为该预览的实测，波 2 仅部分；固定/缓存按块占用，可见为视口内提交的不同原生帧字节，含固定素材。
| 波 | 固定 B | 流缓存 B | 可见原生 B | 单帧 TEX_LOAD B | 粒子实存/视口提交 | 帧均值/p99/最大 ms |
|---|---:|---:|---:|---:|---:|---|
| 1 | 31792 | 185704 | 59656 | 58688 | 151/137 | 31.865/81.733/141.389 |
| 2（部分） | 32440 | 178592 | 64088 | 19136 | 354/354 | 36.668/82.411/124.074 |
波 1 包括冷装载；58,688 B 超出 tech5b 暂定 32 KiB，运行日志明确 ERROR 并列出 LOAD_ITEM，未自动降级。
预览已提交的角色方向掩码 0xff、友方弹体方向 0xffff；不能代替尚未生成的方向展示视频。
最后 WIP 增加了地形按页合批、敌弹拖尾、数字描边/暴击放大、灯光接缝修正等，效果与帧时间尚未重测。
tech7：实时稳定 60fps 未通过；GPU 一帧 70% 周期预算未测；最终 Spike gfx 分项 instret 未测。
tech7：原生像素素材/动作/中文卡片已接入，最终美术风格、动作节奏、双词缀可读性尚待评审。
tech7：闪白/模拟击退/数字已接；屏幕震动、短暂顿帧未实现；全屏级 U 表现未达标。
tech7：8000 是 GPU 池容量，实测预览粒子峰值 354；未验证 8000 同屏，不宣称规模指标通过。
声音沿用既有授权素材及混音协议；只桥接音量与 stage(0)，未代替用户试听验收。
未完成：17a80a639 两配置完整 10 波 GPU 通关、逐帧 STATE 对照、逐波装载数据、Spike 全帧 INST。
未完成：最终 Windows 分发、4 张正式截图与双词缀附加截图、约 30 秒真实游戏视频、最终性能及质量验收。
现有输出中断图片/开发日志均不能当正式媒体；没有生成素材拼接视频，也没有改 HP/伤害/无敌强行通关。
其他敌方即时地面效果未改：雾水母死亡雾 effect4、织网者 effect5、蛞蝓/熔渣虫 effect6、潮主漩涡 effect8、余烬王火雨 effect9。
潮主尾扫和黑潮范围伤害也保持即刻结算；除水柱外没有为它们增加预警；扩展敌人不是首版入口。
恢复工作后可复现（本次暂停后未执行这些完整验收命令）：
```sh
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/ember_isles -j1 all linux-fpga "$(pwd)/build/ember_isles/"{v1-accept,v1-accept-fpga,v1-particles-test,v1-ui-test}
python3 sw/apps/ember_isles/src/gfx2d/tests/cache_layout.py
python3 sw/apps/ember_isles/src/gfx2d/tests/reference_v1.py
build/ember_isles/v1-accept sw/apps/ember_isles/assets/replays/coast.txt outputs/ember_isles/v1/pc-coast coast
build/ember_isles/v1-accept-fpga sw/apps/ember_isles/assets/replays/coast.txt outputs/ember_isles/v1/fpga-coast coast
spike --isa=rv32im_zicsr_zicntr --priv=m --pmpregions=0 --no-dm --disable-dtb -m0x80000000:0x40000000 --pc=0x80000000 build/ember_isles/ember_isles-spike.elf
build/ember_isles/v1-accept sw/apps/ember_isles/assets/replays/coast.txt outputs/ember_isles/v1/media showcase
```
报告数字来源：`v1-preview-smoke.log`、`v1-quality-test.log`、`v1-ui-test.log`、`v1-i4-layout.log`、`v1-frozen-build.log`（均在 build/ember_isles）。
