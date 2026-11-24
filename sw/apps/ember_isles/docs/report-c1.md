# C 第一版集成报告（进行中）

结论：E4机制已集成待协调者确认；E5、完整ART3、稳定60Hz及听感尚未验收。
E4b实现a741f9701、验证068a1dbfe、报告606b757a9；音频f65ca0776。
PM集成5d84a7a1c、788c765d6、868d16170；字体准备0d8c859ec、许可6603e730f。
E3模拟13879d601，平台10f5e5b12，GPU等价性能优化dc323266c。
规格gdd/tech v2.0，新增口径3fe7d291d、流式装载64e52d15b/8ee40659b。
六项E4裁定全部定向覆盖：元素提高、颜色、中性减速、沙漏、影步、维修。
混伤例旧112→新125；颜色取防御/独立减伤后、护盾前最大实际份额。

四目标构建及五组系统测试通过，GCC13.3/Zig0.17/xPack15.2，C11/Wall/Wextra/Werror。
```sh
. ~/.local/opt/edrv32/env.sh
export PATH="$HOME/.local/opt/video/bin:$PATH"
make -C sw/apps/ember_isles all test -j1
python3 sw/apps/ember_isles/tools/e4_verify.py
```
Linux/Spike日志build/ember_isles/e4b-{linux-test,final-build,final-unit}.log。
PM补Windows/board：build/g2/e4b-windows-board.log；上述日志warning/error均0。
E4共8132条断言，197定义覆盖；e4b-content.log、e4b-coverage.csv在build/ember_isles。
CSV独立调参恢复通过，e4b-table.log；不是运行时读CSV。Windows/board未实机运行。

PM修复b871ee706：第6984帧第三次抽取空升级池导致除零/SIGILL。
按GDD6补位回复30%生命/金币40/灯油30，初值upgrade_fillers.csv；不是完整满槽替换。
0/1/2候选与资源效果回归通过；修复版ASan/UBSan满10800输入帧无异常。
调试记录docs/debug/2026-11-24-upgrade-pool-exhaustion.md；故障基线8e7d2e950。
PICKUP/WEAPON_CHANGE具名事件在core.h；独立subtype，不复用伤害字段、不改随机流。

跨平台样本：a741f9701模拟+f65ca0776音频+5d84a7a1c入口，seed20261124。
10800输入帧/9264战斗tick，每60帧180组字段摘要完全相同；END,10800,2,5。
终点是第5波升级界面，不是通关；旧/新摘要HP246、击杀175、伤害17335均相同。
原始build/ember_isles/e4b-{pc,spike}.log；汇总e4b-cross-summary.txt，PC音频欠载0。
```sh
build/ember_isles/ember_isles --replay sw/apps/ember_isles/assets/replays/coast.txt > build/ember_isles/e4b-pc.log
spike --isa=rv32im_zicsr_zicntr --priv=m --pmpregions=0 --no-dm --disable-dtb \
  -m0x80000000:0x40000000 --pc=0x80000000 build/ember_isles/ember_isles-spike.elf > build/ember_isles/e4b-spike.log
python3 sw/apps/ember_isles/tools/compare_replay.py build/ember_isles/e4b-pc.log build/ember_isles/e4b-spike.log
```
Spike每帧10800行；表现仅CPU准备，不含GPU/MMIO提交；CPI1.3为估计。
| 分项 | 平均instret | 最大instret | 最大周期估计 |
|---|---:|---:|---:|
| 模拟 | 98204.16 | 311978 | 405571.4 |
| 表现准备 | 157598.76 | 235403 | 306023.9 |
| 音频 | 70507.30 | 92604 | 120385.2 |
| 同帧合计 | 326310.22 | 629765 | 818694.5 |
音频峰值较旧129535降至92604指令，现低于15万估计周期；合计不是各项峰值相加。
功能模型GPU周期PERF为0，硬件GPU预算未测，不能据PC墙钟推算。

PC稳定60帧未验收，未取得用户Windows实测frame-times.txt。
E3优化CPU均值8.717→6.937ms，CPU p99 16.919→14.890ms。
共享Linux墙钟均值9.460ms、p99 28.377ms，894帧超16.667ms；详report-e3-performance.md。
GPU优化曾通过121个GT和43863次自测，沿用C API不支持的AXI注入跳过项。
新E4未重测稳定帧率；旧占位图集65600B，不冒充三关量产纹理统计。

| E4b+音频产物 | text B | data B | bss B |
|---|---:|---:|---:|
| Linux | 42436189 | 73336 | 5344136 |
| Windows | 574770 | 42070472 | 0 |
| board | 42391568 | 1752 | 68705244 |
| Spike | 42422368 | 1752 | 9856324 |
GNU size口径；PE把音频列入data，不能与ELF分段直接类比，也不是运行时内存。
board BSS含64MiB平台DMA池；中文字体尚未链接。音频进一步压缩按协调者裁定留E6。

旧ART2被用户否决；b4efbe59f画风确认，采用AI生图+网格规范化+人工修整。
06a检查点b20b77328只含守火人与容量试样；I8整套裁边224KiB，旧96KiB常驻方案作废。
tech5b改DDR保存I8帧、TEX_LOAD+LRU缓存：固定48/场景64/动画约80KiB，装载32KiB每帧初值待测。
普通敌人按种类/动作/朝向共享动画时钟，角色/宠物/头目/Boss独立；不删角色动作。
06a-2 ctx_be6c0bcc23e7续作海岸整包；06b测可见独立帧字节、装载峰值和实际帧时。
中文字体保留Fusion Pixel BDF/OFL/上游许可，显式补U+2212；CPU690字形/22080B，GPU缓存未接。
预览outputs/ember_isles/font-cpu-preview.png不是中文HUD完成；总许可assets/CREDITS.md。

音频三首Eric Skiff CC BY4.0音乐+九个Kenney CC0原始OGG；来源、加工均写CREDITS。
链接mu-law 42069944B；独立台架音乐29889/四音效90977 instret，环形测试欠载0。
volume/stage/result接口已实现；E5设置/换关待接。用户明天试听，曲目/场景/循环节拍未验收。
完整试听outputs/ember_isles/audio/stage-{0,1,2}.wav、cue-{00..12}.wav；详report-audio-c1.md。

E3媒体outputs/ember_isles/e3/；E4新截图outputs/ember_isles/e4/frame{00120,00570,01020,01695}.png。
E4新capture日志build/g2/e4b-capture{,-build}.log，8独立角色片段/1800tick/实际GPU路径。
content-30s.mp4为H264、640×360、15fps、450帧、30秒、3332001B，无音轨；非正常完整模式录像。
截图可见旧英文HUD/键名与占位美术；tech7的中文界面、比例动画/VFX和最终画面质量均未通过。
各关实体/粒子峰值、两模式三关通关及开局快照录像待E5；不把素材预览当GPU游戏录像。
outputs/ember_isles/ember_isles.exe仍是先前E3版；完整C版未生成，现E4b构建在build/。
下一步：E4确认、完成海岸素材与06b真GPU检视，再做05模式和06c其余两关素材。
