# C 第一版集成报告（进行中）

结论：完整C版未完成；E4已提交但未验收，E5、完整ART3和新音频仍缺。
游戏代码b871ee706；规格gdd/tech v2.0；字体准备0d8c859ec。
E3模拟13879d601，平台10f5e5b12，GPU等价性能优化dc323266c。
E4员工提交见report-e4.md；PM修复c99be1151、8e7d2e950、b871ee706。
E4四项玩法待答：沙漏消费时机、中性减速、影步朝向窗口、灯匠维修强化叠加。
另待冻结混伤元素提高的份额算法及伤害数字颜色口径；未自行改动。

四目标及五组系统测试通过，GCC13.3/Zig0.17/xPack15.2，C11/Wall/Wextra/Werror。
```sh
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/ember_isles all test -j1
python3 sw/apps/ember_isles/tools/e4_verify.py
```
日志build/g2/e4-fillers-build.log：warning/error均0；E4共8087条断言通过。
原194项覆盖加3种资源补位，表由工具生成到build/ember_isles/e4-coverage.csv，不入库。
Windows与board仅构建，未实机运行；FPGA移植不在本包。

长录像发现第6984帧、12升13级时第三次抽取空升级池，导致除零/SIGILL。
已按GDD6补位：回复30%生命、金币40、灯油30，初值在upgrade_fillers.csv。
选择kind5、中文说明、0/1/2普通候选及资源/属性回归已实现；不是完整满槽替换流程。
调试记录docs/debug/2026-11-24-upgrade-pool-exhaustion.md；基线8e7d2e950。
修复版ASan/UBSan运行满10800输入帧无异常；旧工具因胜利断言返回1。
旧E3输入在新内容中停于升级界面，不能作为E4通关证据，E5必须重录。

跨平台样本：b871ee706、seed20261124、10800输入帧、9264战斗tick。
PC/Spike每60帧180组字段摘要完全相同；两端END,10800,2,5（升级界面/第5波）。
原始日志build/g2/e4-fixed-{pc,spike}.log；汇总e4-cross-summary.txt；PC音频欠载0。
复现（在本报告提交构建，游戏逻辑与样本相同）：
```sh
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt > build/g2/e4-fixed-pc.log
spike --isa=rv32im_zicsr_zicntr --priv=m --pmpregions=0 --no-dm --disable-dtb \
  -m0x80000000:0x40000000 --pc=0x80000000 build/ember_isles/ember_isles-spike.elf > build/g2/e4-fixed-spike.log
python3 sw/apps/ember_isles/tools/compare_replay.py build/g2/e4-fixed-pc.log build/g2/e4-fixed-spike.log
```
Spike实测每帧10800行；表现仅CPU准备，不含GPU/MMIO提交；CPI1.3为估计。
| 分项 | 平均instret | 最大instret | 最大周期估计 |
|---|---:|---:|---:|
| 模拟 | 97395.74 | 274860 | 357318.0 |
| 表现准备 | 157598.15 | 235403 | 306023.9 |
| 旧音频 | 58888.03 | 129535 | 168395.5 |
| 同帧合计 | 313881.91 | 623059 | 809976.7 |
音频峰值超过15万周期分项预算12.26%；总计不是各分项峰值相加。
功能模型GPU周期PERF仍为0，硬件GPU时钟预算未测，不能据PC墙钟推算。

PC稳定60帧未验收，本报告未取得用户Windows实测frame-times.txt。
E3优化同10800帧CPU均值8.717→6.937ms，CPU p99 16.919→14.890ms。
共享Linux墙钟均值9.460ms、p99 28.377ms，894帧超16.667ms；详report-e3-performance.md。
GPU逐位等价优化曾通过121个GT和43863次自测，沿用C API不支持的AXI注入跳过项。
新E4尚未做稳定帧率验收；旧占位图集65600B，不冒充三关量产纹理统计。

| b871ee706产物 | text B | data B | bss B |
|---|---:|---:|---:|
| Linux | 369789 | 73204 | 5275944 |
| Windows | 578526 | 528 | 0 |
| board | 325692 | 1752 | 68635548 |
| Spike | 356540 | 1744 | 9794252 |
GNU size口径，text含只读数据，不是进程运行时内存；Windows BSS照录工具输出。
board BSS含64MiB平台DMA池；新中文字体未链接入这些产物，最终素材后须重测。

旧ART2被用户否决；b4efbe59f新样张画风确认，采用AI生图+网格规范化+人工修整。
06a以failed结算，b20b77328；仅守火人检查点与容量试样，不是完整海岸包。
I8精确部件基础163840B、爆核196608B，分别超98304B常驻半区65536B、98304B。
I4比较为69632B、81920B；加其他项预留估算仍超，完整常驻/场景包未实测。
每帧41–91个4x4小quad的测量不是最终语义共骨架方案；还有36姿势尺寸告警待核对。
检视outputs/ember_isles/art3-coast-assets/index.html；I4比较keeper-i4-comparison.html。
待协调者决定I8共骨架重构或I4例外；提案build/g2/subtasks/06a2-art3-semantic-parts.md。

中文字体：0d8c859ec保存Fusion Pixel 12px原始BDF/OFL及上游许可，显式补U+2212减号。
初次CPU子集690字形/22080B；当前工具按CSV与UI重生成，GPU界面缓存尚未接入。
CPU字体预览outputs/ember_isles/font-cpu-preview.png，不算中文HUD完成。
音乐候选4首Eric Skiff（原页CC BY4.0），音效候选11个Kenney官方仓库OGG（CC0）。
原始来源/许可/文件已保存build/g2/audio-research/，未试听验收或链接进游戏。
30秒试听outputs/ember_isles/audio-candidates/candidate-{1,2,3,4}.wav及CREDITS.txt。
07音频任务已备好，等待协调者代派；最终授权与字体统一汇入assets/CREDITS.md。

E3截图及视频outputs/ember_isles/e3/；E4四图outputs/ember_isles/e4/frame*.png。
E4 content-30s.mp4：实际GPU路径，640×360、15fps、450帧、30秒，3864621B，无音轨。
E3/E4视频均沿用旧占位美术/HUD，不是ART3质量通过；各关实体/粒子峰值尚未测全。
tech7自评：稳定帧率、量产美术/完整动作/VFX、中文图标界面、规模及声音均未达最终验收。
outputs/ember_isles/ember_isles.exe仍为此前E3优化版；最终两模式三关Windows发行版尚未生成。
下一步：答复E4玩法、派07、决定容量工艺，再完成06b实际海岸、05模式及06c其余素材。
