# G-2.7 音乐音效交付测量

结论：混音器、事件路由、素材链接和技术测试完成；听感验收未完成，不能判定质量通过。
代码 commit：与本报告同一提交；用 `git log -1 --format=%H -- sw/apps/ember_isles/docs/report-audio-c1.md` 定位。
依据：GDD v2.0 2.3、5f；tech v2.0 3–5、7；aud-spec v0.2 2.1；G-2.7 Task。
工具：GCC 13.3.0、Zig 0.17.0、xPack GCC 15.2.0、Spike 1.1.1-dev、ffmpeg 7.0.2-static。

三关暂定：海岸 A Night Of Dizzy Spells；密林 Arpanauts；火山口 Chibi Ninja。
作者 Eric Skiff，专辑 Resistor Anthems；原始页明确 CC BY 4.0，2026-11-24 实际核验。
音乐映射：`assets/music/stages.csv`；换对应只改 CSV，重新转换即可，不改 C 代码。
音效原始来源：Kenney 本人 Starter-Kit-FPS / Starter-Kit-3D-Platformer 固定提交。
两个原始 README 实际核验 sound effects 为 CC0；具体文件和版本见 `assets/CREDITS.md`。
未尝试再次下载此前失败的 Kenney 网站 ZIP / OGA；未使用第三方镜像。
九个原始 OGG 共 94820 B，三个原始 MP3 共 9637915 B；源文件原样入库，仅重命名 MP3。
旧 night_coast 乐谱删除；没有商业游戏素材，没有低质量短蜂鸣占位替代音乐。

全部录音离线重采样为 48 kHz 立体声，CPU 整数解码、四音效声部混音，输出 PCM16。
音乐峰值归一为 10000，音效为 4000；mu-law 解码音乐实测峰值均 9852。
音乐结尾与开头作 1 秒等增益重叠，去掉开头 1 秒，循环保留完整录音其余部分。
这不是原生无缝乐段；淡化听感和节拍一致性待用户确认，不据波形宣称试听通过。
升级和胜利由 coin 采样升调分层，格挡由 coin 降八度；其余为实际素材采样。
内部 13 个音效覆盖射击、命中、死亡、冲刺、火种、爆炸、升级、选择、受伤、胜利、拾取、格挡、元素命中。
事件 PICKUP=10、WEAPON_CHANGE=11 映射拾取/选择；各拾取子类型共享拾取音色。
主线程队列保留 kind / damage_type / outcome；闪避不启动声部，格挡启动铃声。
`ember_audio_volume(unsigned percent)` 已生效：0–100 主音量，默认 100，重置保留设置。
`ember_audio_stage(unsigned stage)` 已生效：0/1/2，下次 mix 开始切换曲目。
主音量和关卡请求为原子访问；sim 不调用音频，本次不改 sim、胜负或随机流。

| 项目 | 海岸 | 密林 | 火山口 |
|---|---:|---:|---:|
| 循环采样帧 | 5431445 | 9393698 | 5872810 |
| 音乐编码 B | 10862890 | 18787396 | 11745620 |
| 量化 SNR dB | 37.13 | 36.88 | 37.08 |
| 试听 WAV B（完整循环+2秒） | 22109824 | 37958836 | 23875284 |
| 每800帧音乐 instret | 29889 | 29889 | 29889 |
| 每800帧四音效 instret | 90977 | 90977 | 90977 |

13 种四声部组合均测一次/关；CPI1.3 为音乐 38855.7、四音效 118270.1 周期。
台架测混音函数，不含事件排队、IRQ、MMIO，也不代表整机实时性或板上 CPI 已验证。
合并音频二进制 42069944 B，独立 Spike ELF 42079972 B（text 42072260/data 76/bss 7360）。
使用 assembler incbin 链接，不生成巨型音乐 C 数组；本机单模块编译峰值 RSS 45184 KiB、0.21 秒。
音乐/音效重置、跨任意块（1/8/257/800/1024）、三个完整循环逐采样相等。
测试覆盖13音效结束回归音乐、闪避静音、格挡/元素/拾取/换武器路由、0/50/100%音量。
40秒四声部重叠运行无超30000采样；三次200ms前端间隔播放28800帧，AUD欠载0。
Linux测试、Windows模块交叉编译、RV32台架编译为 C11 -Wall -Wextra -Werror，零告警。
纯C改动；tools/check 的两个入口仅检查 Verilog，不适用；本次 git diff --check 通过。

复现（仓库根目录；只串行执行；生成 WAV 约84 MB）：
```sh
export PATH="$HOME/.local/opt/video/bin:$PATH"
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/ember_isles assets -j1
make -C sw/apps/ember_isles "$PWD/build/ember_isles/audio-test" "$PWD/build/ember_isles/audio-ring-test" -j1
mkdir -p outputs/ember_isles/audio
build/ember_isles/audio-test && build/ember_isles/audio-ring-test
~/.local/opt/zig-0.17.0/zig cc -target x86_64-windows-gnu -std=c11 -O2 -Wall -Wextra -Werror -Isw/apps/ember_isles/src/audio -Ibuild/ember_isles/generated -c sw/apps/ember_isles/src/audio/audio.c -o build/ember_isles/audio-g27-win.o
riscv-none-elf-gcc -std=c11 -O2 -Wall -Wextra -Werror -march=rv32im_zicsr_zicntr -mabi=ilp32 -Isw/apps/ember_isles/src/audio -Ibuild/ember_isles/generated -nostartfiles -Tsw/apps/ember_isles/src/audio/tests/audio_bench.ld sw/apps/ember_isles/src/audio/audio.c sw/apps/ember_isles/src/audio/tests/audio_bench.c -lc -lgcc -o build/ember_isles/audio-bench.elf
spike --isa=rv32im_zicsr_zicntr --priv=m --pmpregions=0 --no-dm --disable-dtb -m0x80000000:0x40000000 --pc=0x80000000 build/ember_isles/audio-bench.elf
```
原始日志：`build/g2/audio-{final-build,test,ring-test,bench,compile-memory}.log`；转换日志 `audio-research/conversion.log`。
试听：`outputs/ember_isles/audio/stage-{0,1,2}.wav`、`cue-{00..12}.wav` 和 CREDITS.txt（不入库）。
未完成：用户听感/选曲/场景匹配/循环节拍确认；E5中文设置与换关调用由PM集成；完整Windows/板上运行未测。
集成：PM已在 5d84a7a1c 迁移 Spike 事件调用、788c765d6 补齐流程测试音频桩；本任务未改这两文件。
