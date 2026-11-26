# 棱炉地宫

原创机械地宫肉鸽 GPU demo：9 房单层、三种敌人、两阶段 Boss、点射/霰弹/旋转弧刃、
清房三选一、宝箱和付费治疗祭坛。金币靠近自动吸取，击中有停顿、震动、白闪、
击退、飘字、碎片、枪口火和弹壳；翻滚前8/12 tick无敌。死亡/通关后确认重开。
没有存档或局外成长。原生640×360、两个640×180条带，DISP放大到720p。

## 按键

板上bit0/bit1左右转向，自动向前；bit2短按翻滚，长按0.5秒打开控制菜单；bit3返回
开机菜单。门口允许上下左右换房。ETH/PC上下可直接纵向移动，左右转向；X/VI_B
立即翻滚，Z/Enter/VI_A短按也可翻滚，按住并配方向键手动瞄准；松开恢复自动瞄准。
四键也能在任意方向走动，不依赖ETH。三选一暂停战斗，左右选择、确认领取。
控制菜单左右选择、确认应用：正常/压测、负载、武器、AA、继续、重开。
Esc/VI_START/VI_ESC返回开机菜单。默认目标是一局5～10分钟，实际时长随操作而变。

每次进场使用下一个确定性种子，初始`0x00264b42`，HUD显示该局种子；种子递推
`seed = seed*1664525+1013904223`。重新启动程序可复现首局，状态测试覆盖1024局
地图的连通、唯一坐标与固定种子复现。地图生成只保留9房连通性，格子相邻可能
形成额外通路；房号8的Boss不保证是最远叶节点，这是与最初设计的简化差异。

## 预算与渲染

CPU执行AI、弹体运动和碰撞；GPU用DRAW_QUAD绘制瓦片/实体、DRAW_TRI绘制旋转
武器、刀光弧带及三份拖尾，OBJ_STEP（STEP=0）批量绘制弹体，避免占用quad表。
这里没有把8个硬件碰撞目标当作任意敌人数，也没有宣称硬件负责CPU战斗判定。
正常房约6～13敌；压测敌/弹目标32/512、64/2048、128/8192，粒子池512。
压测不因帧慢自动减量；低帧率和真实计数如实显示。

复用共享185792B纹理RAM布局（192KiB上限）：主图集65536、场景图集65536、
五个10944B的RGB565 mip槽。肉鸽实际使用前两个图集131072B；其余mip槽保持
公共布局并同批装入，不参与场景采样。独立源图是actors.png，32px实体、64px Boss
源（GPU放大到96px）、64px旋转弧刃；字体为94字Fusion Pixel子集。
进入场景TEX_LOAD一次185792B，之后每帧0B；PAL_LOAD仅换场景。CPU战斗状态
约0.32MiB，弹体GPU表最多8192×32B，复用公共命令、顶点、quad和Surface。
预算初估见DESIGN.md，板端CPU/GPU耗时和60fps目标尚未实测；PC GPU周期为0时
显示0us，含义是模型没有该计数。FPS是实际墙钟帧间隔；连续包是180个60Hz游戏tick，
参考模型执行时间不作为板端性能。

## 复现

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw/apps/gpu_test board linux windows -j1
make -C sw/apps/gpu_test_rogue state-test -j1
python3 sw/apps/gpu_test_rogue/tools/capture.py rogue
```

截图与CSV在`outputs/gpu-test-games-20261126/`：rogue-combat、rogue-slash、rogue-boss、
rogue-choice、rogue-minimap、rogue-stress（.png/.csv）；rogue-3s.zip包含180个连续帧。
命名shot设置真实游戏状态后仍由同一GPU命令路径渲染；未拿概念图代替截图。
`capture.py`使用独立进程各自初始化，截图不是同一帧改名。只做C/PC验证，不跑RTL/SoC。
