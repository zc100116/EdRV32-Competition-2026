# T-GAMES-MORE 软件原型（2026-11-16）

代码提交：本报告所在提交（`git log -1 --format=%H -- docs/reports/2026-11-16-games-more-sw.md`）。
基线：弹弓原型 e84a54c8b；rv32im / GCC 15.2.0，目标卡 75 硬件后处理。
入口：首页顶栏「体感游戏」→ 5 张卡片；点击、按键或光标停留握拳 1 s 进入。
游戏内返回回大厅，厅内返回回首页；页面始终为 15 / PAGE_GRAB，不重启会话。

| 游戏 | 参数初值（集中在对应 `.h` 的 enum） |
|---|---|
| 公共 | 30 Hz，Q8 像素；模式 C 平滑光标；握拳停留/重开 30 步；默认关关键点 |
| 大厅 | 5 张 350×170 卡片；停留中须保持同一卡片、有效手、fist 类别 |
| 弹弓 | 沿用原型：5 发，拉距 180 px，重力 900 px/s²，木箱 100 / 气球 50 |
| 石头剪刀布 | 倒数 3 s，18 步/0.6 s 投票，结果显示 45 步；5 局、先赢 3 局结束 |
| 石头剪刀布 | fist=石、peace=剪、palm/four=布；无票不计局；票数相同按石/剪/布顺序 |
| 石头剪刀布 | 有效平局计入 5 局；胜 100、平 25；3 胜三星、2 胜二星；LFSR 种子来自 mtime |
| 打地鼠 | 45 s；洞心 x=360/640/920，y=330/500；命中半径 70 px；仅放→抓边沿 |
| 打地鼠 | 每 15 步尝试随机洞；可见 27–42 步，随时间缩短；普通/金色/炸弹=80/10/10% |
| 打地鼠 | 普通 +10、金色 +30、炸弹 −20；命中 9 步动画；100/250 分二/三星 |
| 切图形 | 60 s / 漏 3 个 / 切到炸弹结束；每 45 步抛 1–3 个，最多 9 个 |
| 切图形 | 半径 36 px；轨迹最近 6 点；按实际推理帧 ms 检测线段，严格 >800 px/s |
| 切图形 | 新位置权重 3/4（独立于抓取页）；重力 450 px/s²；切中 +10；半块 24 步淡出 |
| 切图形 | 4 种宝石，炸弹概率 1/10；100/250 分二/三星 |
| 接物篮 | 60 s；篮宽 150 px，y=600；横速上限 900 px/s；x 限于篮宽内可见区域 |
| 接物篮 | 每 18 步一个，最多 6 个；下落 150 px/s 起，每 6 s 加 30 px/s |
| 接物篮 | 水果 +10、炸弹 −30（1/8 概率），闪烁 12 步；100/250 分二/三星 |

| 素材目录 | 精灵清单、尺寸 | ARGB8888 合计字节 |
|---|---|---|
| sling | 原 9 张（见原型报告） | 216,688 |
| rps | 双方各 3 手势 120×120，胜/负标记各 64×64 | 378,368 |
| mole | 洞 150×70，普通/命中/金色各 100×100，炸弹 88×88，特效 90×90 | 225,376 |
| slice | 4 整体 72×72+8 半块 36×72，炸弹/切效 72×72，拖尾点 20×20 | 208,960 |
| catch | 篮子 150×76，4 水果+炸弹各 60×60 | 117,600 |

共 1,146,992 字节，不含小型描述符，小于 4 MB；全部原创 imagegen，透明 RGBA8 非隔行 PNG。
各素材目录 README 记录完整提示词与裁边/缩放/半块裁切命令；生成中间文件使用 build 后删除。

验收（先 `. ~/.local/opt/edrv32/env.sh`；两种构建经 flock 串行）：
- `make -C sw/tests/showcase games sling grab`：PASS。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`：PASS。
- `flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`：PASS。
日志：`build/games-tests.log`、`build/games-hw-build.log`、`build/games-cpu-build.log`。
硬件版 ELF：`build/sw/showcase/showcase.elf`；CPU 版：`build/sw/showcase-cpupost/showcase.elf`。

局部刷新：静态洞/平台/靶和卡片不主动失效；运动图像只刷旧新矩形并集，拖尾按线段区域失效。
游戏切换/重开才重建场景；公共计时器、性能窗和光标保持；绘制 fps 按 LVGL 刷新完成计数。
性能窗复用识别 fps、端到端 ms、CPU idle 字段；图片不旋转，半块是预裁切的独立精灵。
新游戏状态和物理不使用浮点，原有关键点 float 仅在视觉接口转整数；板上效果待协调者验证。


## R2：卡 90 反馈修订

代码：本节所在提交；基线 `3cd55f195`，GCC 15.2.0 / rv32im_zicsr，未做板测。
入口改为首页第 15 张应用卡，硬件要求 VIN+NPU+RND；游戏返回大厅，大厅返回首页。
安全区常量集中于 `game_math.h`：x=200–1080、y=120–600；大厅卡片 280×170。
洞心与命中区域原已在安全区；弹弓叉口 x=400，180 px 圆形拉距再限制于安全区。
接物篮中心 x=200–1080、y=600，水果出发 x 同范围；手势重开区限于中央结果面板。
打地鼠、切图形、接物篮新增开始面板，速度按钮可点选或握拳停留 30 步选择并开始。
三游戏独立保留本次运行的选择，默认慢；动作速率为慢/中/快=0.5/0.75/1。
经协调者确认：慢档间隔/停留时间 ×2，中档 ×4/3（整数步取整）；局时不缩放。
切图形以 Q8 时间步缩放速度/重力积分，保留抛物线高度；接物篮缩放水果下落速度。
切图形门限严格 >350 px/s，命中半径 36+24=60 px；连续丢手 ≤2 帧保留轨迹。
移动圆用前后目标位置与光标构成相对线段，检测同一插值时刻的最小距离。
UART `game name=hall/sling/rps/mole/slice/catch` 每秒记录 draw_fps、cursor、lost、cls。
开局/自然结束/退出记录 event、speed、score、dur_ms；固定速率两游戏标为快。
切图形另每秒记录 segments、fast_segments、hits、near_misses；近失为未命中且距离 <90 px。
主机 `make -C sw/tests/showcase games sling grab`：PASS，含新判定、速率、保留选择、串口事件。
`flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase`：PASS。
`flock /tmp/edrv32-sw-build.lock make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`：PASS。
日志：`build/games-r2-tests.log`、`build/games-r2-hw-build.log`、`build/games-r2-cpu-build.log`。
仅软件验证；四周失灵的具体原因、实际命中体验和绘制帧率仍需上板数据确认。
