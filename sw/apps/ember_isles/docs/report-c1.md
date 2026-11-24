# C 第一版集成报告（进行中）

状态：E3系统与平台已集成，Windows帧率待实测；经协调者确认E4并行进行，E5/ART3/新音频未完成。
集成908da6ff7，GPU/PC性能dc323266c；规格gdd/tech v2.0，蓄力4a5df57c0、内容8b7645861。
本报告为工作中记录，不能作为完整 C 第一版验收通过的依据。
旧ART2（2d4e370a7）用户否决；b4efbe59f新样张画风已认可，按AI生图+网格规范化+人工修整生产。
E3模拟551ca8366/ef9fb9725；平台f33181ace/a20fe0023/10f5e5b12/7591a2056。
E3返工13879d601：致命冻结铁命中碎裂，死亡计数一次；补闪避/格挡结果事件。
纯真伤不误报格挡；正式测试覆盖致命/非致命碎裂及玩家和敌人的结果事件。
集成908da6ff7：PC纹理256KiB；菜单鼠标转换为录像里的方向/确认键。
旧plat_keys保持兼容；plat_game_keys返回16位键位图；菜单指针640×360。
弓/火铳/大剑及爆核蓄力交E4实现；E3先保留J持续普攻，E4尚未验收。

四目标构建与五组测试通过，构建0 warning/0 error：
```sh
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/ember_isles all test -j1
```
日志：build/g2/e3-integrated-build.log；GCC13.3/Zig0.17/xPack15.2，C11/Wall/Wextra/Werror。
Windows仅交叉编译，未实机运行；板上仅构建，FPGA移植不在本包。
可执行文件：outputs/ember_isles/ember_isles.exe（E3占位画面，非完整发行版）。

录像：assets/replays/coast.txt，seed20261124，10800帧；第9947帧清第5波。
PC/Spike每60帧180组摘要一致；双实例逐帧全状态一致；230击杀/260生命/14级。
原始数据：build/g2/g22b-{pc-summary,baseline-summary,spike}.log。
按最终模拟13879d601的Spike日志汇总（每帧10800行）：
| 分项 | 平均instret | 最大instret | 最大周期估计(CPI1.3) |
|---|---:|---:|---:|
| 模拟 | 66808.30 | 108007 | 140409.10 |
| 表现准备 | 167506.17 | 255791 | 332528.30 |
| 音频 | 61437.28 | 129298 | 168087.40 |
| 同帧合计 | 295751.74 | 477568 | 620838.40 |
音频峰值超15万周期分项预算12.06%；表现不含GPU/MMIO提交，CPI仍待上板测量。

03平台实测：10800帧墙钟mean/p95/p99/max=9.956/16.557/23.173/62.689ms。
510/10800帧超16.667ms（4.722%），共享主机调度包含在内，不能宣称稳定60Hz。
繁忙600帧：GPU84.29%、DISP12.58%、模拟0.70%、表现准备0.59%、音频0.34%。
详见report-e3-platform.md；build/ember-perf/e3-before/{profile.log,frames.csv,replay.log}。
08性能优化dc323266c：最近邻缓存复用、调色板延迟展开、并行只读共享、DISP行循环优化。
同10800帧CPU均值8.717→6.937ms（−20.42%），CPU p99 16.919→14.890ms。
墙钟均值10.463→9.460ms，但p99 28.377ms、894帧超16.667ms，不能宣称稳定60Hz。
08按failed结算；接受等价优化，E3帧率由用户Windows实测判定，详见report-e3-performance.md。
优化前后180组STATE及10800行PERF一致；不改模拟，不重复Spike。
GPU逐位：121个GT与43863次自测通过，沿用C API不支持的AXI错误注入跳过项。
GPU功能模型周期PERF仍为0，GPU时钟预算未测定；不能据墙钟推算硬件周期。

当前纹理布局65600B/硬件196608B，低于预算131008B；PC容量262144B。
提交对象槽峰值8000，存活粒子140，敌人19，模拟弹33；未验证1500/3000/8000存活目标。
以上是五波海岸测量，不冒充未来两模式三关的各关容量统计。
| 产物 | text B | data B | bss B |
|---|---:|---:|---:|
| Linux | 239175 | 11388 | 4507016 |
| Windows | 431210 | 528 | 0 |
| board | 206832 | 1752 | 67865564 |
| Spike | 237496 | 1744 | 9025592 |
BSS包括固定实体/录像池，board还包括64MiB平台DMA池；Windows列仅照录GNU size输出。
以上为GNU size口径，不是进程运行时内存；PC列为dc323266c，最终内容/图集变化后须重测。

E3截图：outputs/ember_isles/e3/{combat,upgrade,weapon-swap}.png，1280×720。
E3视频：outputs/ember_isles/e3/systems-30s.mp4，30秒/30fps，录像前1800模拟帧每2帧采样。
视频无音轨，仅展示系统；占位素材、旧英文HUD与旧键位标签仍待E5/美术替换。
捕获：908da6ff7，build/g2/e3-capture.log；帧PNG在build/g2/e3-frames/，音频欠载0。
编码：ffmpeg7.0.2-static，libx264，-threads 1 -crf20 -pix_fmt yuv420p。

tech7自评：帧率未达标；美术/完整动作/大招全屏/中文图标界面未达标；规模未测。
已有火花/闪白/击退/爆散/飘字仅E2占位表现，不算ART-3通过；灯火状态未完整可视化。
旧音乐与十音效仍在，音频质量未通过；新音乐待制作、授权写CREDITS。
尚缺：E4全部条目实际效果、两模式三关/局外/经济、完整回放与各关统计。
尚缺：ART-3全套、完整音频、每个后续里程碑截图视频和最终Windows试玩；新方向已确认。
当前exe含dc323266c优化；另存ember_isles-e3-optimized.exe，区别于用户此前下载的908da6ff7版。
当前：04内容与06a海岸两角色素材并行；新体型44px、8向、96+96KiB预算尚待生产实测。
后续：06b真实GPU海岸验证交用户，再扩三关；完整ART3/音频及两模式三关未完成。
录像配置快照/相对动作计时契约已确认待后续接入；E3 Windows帧率仍待frame-times.txt。

中文字体准备：Fusion Pixel 12px zh_Hans 2026.11.10，OFL及上游许可原文随assets/fonts保留。
font_convert.py按当前CSV/UI提取690字形，位图16560B，C结构22080B；额外提供原生U+2212减号。
命令：python3 sw/apps/ember_isles/tools/font_convert.py；C11/Wall/Wextra/Werror头文件编译及字形检查通过。
CPU预览：outputs/ember_isles/font-cpu-preview.png；尚未接入GPU界面，不算中文HUD完成。
