# 抓取测试软件验收（2026-11-16）

- 源码：本报告所在提交；基线 `1e564654`（`zc100116/b3`），T-GRAB-TEST。
- 构建时 ELF 内的 `BUILD_COMMIT` 为基线 `1e564654`；编译输入含本报告同提交的工作树改动。
- 工具：xPack RISC-V GCC 15.2.0、主机 GCC 13.3.0；C11、`-Wall -Wextra -Werror`。
- 本次为软件/原生 LVGL 验证；未访问仿真虚拟机、未运行 SoC 仿真、未上板。

| ELF | 文件字节 | text / data / bss 字节 |
|---|---:|---|
| `build/sw/showcase/showcase.elf` | 29593700 | 29405388 / 12580 / 50654292 |
| `build/sw/showcase-cpupost/showcase.elf` | 29593556 | 29405832 / 12596 / 50653844 |

- 串行构建：`make -C sw -j2 PROGRAM=showcase`、`make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu`：PASS，0 警告。
- 默认构建后为光标配色改动补编：`make -C sw -j2 PROGRAM=showcase -o FORCE`：PASS。
- `make -C sw/tests/showcase grab`：PASS，覆盖 A 迟滞/两帧防抖、B/D 几何、C 映射/三帧类别防抖、最近选物、平滑跟随、重力、途中再抓、丢手十帧、不可见保持。
- `make -C sw/tests/showcase/vision test runtime`：PASS；包含原有各页及新增 grab 的模型切换、21 点、镜像切换/恢复、串口字段检查。
- 日志：`build/logs/grab-{build-default,build-default-final,build-cpu,test,vision,shot}.log`；`git diff --check`、debug_tool Python 语法及 EDSC APP=12 接受/13 拒绝测试通过（`grab-protocol.log`）。
- 截图：`assets/demo-grab.png`；`make -C sw/apps/showcase/sim -j2 grab-shot`，D 模式拿起/拖动 3 号球，光标及关键点可见。
- 使用已有 `task-demo-pages/build/npu/demo_pages_test/gesture.{expected,rgb565}` 夹具复制到本工作树相同 build 路径；以平移关键点模拟拿起，再回到照片原坐标；夹具重建入口为 `make -C sw/tests/showcase/vision models`。

四种模式：L 为腕到中指根的距离；所有物体 r=50，地面 y=650。
- A：拇指尖/食指尖距离除 L，抓 `<0.25`、放 `>0.40`，参数 ±0.05，放阈值恒加 0.15；抓取点为两指中点。
- B：拇指尖到其余四指尖平均距离除 L，抓 `<0.35`、放 `>0.55`，参数 ±0.05，放阈值恒加 0.20；抓取点为五指尖均值。
- C：既有三帧防抖类别，fist/grip/grabbing 抓、no_gesture 保持、其余放；无参数，抓取点为 P0/P5/P9/P13/P17 均值。
- D：两指各在同一物体 r+m 内且相对中心点积 <0，m=25 px、每次 ±5 px；指距 >2r+2m+40 放；抓取点为两指中点。
- A/B/D 连续两帧切换；所需点可见度 <0.5 保持；抓取点一阶 0.5 平滑；拿起保留偏移；重力 3000 px/s²，33 ms LVGL 定时器独立推进；拿着时丢手十帧放下。

串口（沿用既有计时单位 ms；A/B 的 d 两位小数，C 英文类别，D 指距 px）：
```text
grab fps=… shown=… disp=… npu=… wait=… decode=… kpt=… gui=… e2e=… hands=… mode=A|B|C|D param=… d=… state=open|grab held=-1|0..5 picks=… drops=… mirror=0|1 idle=…%
grab_evt ms=… mode=… state=grab|release d=… obj=-1|0..5 x=… y=…
grab param mode=… value=…
```

上板：卡 68 R2 使用 cpupost ELF；首页/调试工具 APP=12 进入，确认 L0 实时画面、6 个物体与关键点对齐。
逐一用板键切换 A→B→C→D、参数、关键点（默认关）、镜像（默认开）、物体复位；检查空手抓、最近选物、拖动、松手下落和途中再抓、遮手十帧放下。
确认镜像开写 0x3821=0x07、关/退出写 0x01，返回手势/其他页后模型和画面正常；采集每秒统计及即时事件/参数行，核对计数与约 30 fps 下落。

## R2：按卡 85 实测调整抓取与镜像切换

- 源码：本报告所在提交；基线及构建时 `BUILD_COMMIT` 为 `ce76bf65`（`zc100116/b3`），编译输入包含本提交的工作树改动。工具仍为 xPack RISC-V GCC 15.2.0、主机 GCC 13.3.0；未访问仿真虚拟机、未跑 SoC 仿真、未上板。
- 地面改为 y=520，六个物体中心为 x=290/430/570/710/850/990、y=470，半径仍为 50。
- C 改为 fist/grip 抓、palm/four 放，其他类别（包括 grabbing、no_gesture）保持；沿用已有三帧类别防抖。
- A/B 的 L 改为 P0 到 P5/P9/P13/P17 四个距离的平均。A/B/D 的 d 从首个有效帧初始化，后续按 `0.5×旧值+0.5×本帧值` 平滑；切换模式时重置平滑。抓取连续两帧、释放连续四帧；拿着物体时连续十五帧没有手才放下。串口字段与格式保持原样。
- 按协调者补充要求，镜像按钮只记录待处理值并请求 `PIPE_CONFIGURE`；进入抓取页也在配置点写镜像。切换时由既有流程停止采集、排空任务并等 VIN 空闲，再写 OV5640 寄存器，随后 `configure_capture` 重启；退出时在 VIN 停止后恢复非镜像。VIN 错误立即停止的行为未改。

| 验证命令 | 结果 | 日志 |
|---|---|---|
| `make -C sw -j2 PROGRAM=showcase` | PASS，0 编译告警 | `build/logs/grab-r2-build-default.log` |
| `make -C sw -j2 PROGRAM=showcase SHOWCASE_POST=cpu` | PASS，0 编译告警；在默认构建完成后运行 | `build/logs/grab-r2-build-cpu.log` |
| `make -C sw/tests/showcase grab` | PASS，C 保持类别、A/B 四指根尺度（含 P0=P9）、A/B/D 数值平滑、两帧抓/四帧放、十五帧连续丢手及原有物理行为 | `build/logs/grab-r2-test.log` |
| `make -C sw/tests/showcase/vision test runtime network` 的 `test`、`runtime` | PASS，包含镜像进入/双向切换/退出时序与原有页面、模型恢复；UBSan 无报错 | `build/logs/grab-r2-vision.log` |
| 同一命令的额外 `network` 目标 | FAIL，`network_test.c` 包含 `runtime_test.c` 后，既有 pose/hand/grab/demos 四个静态测试函数未被入口引用，触发 `-Werror=unused-function`；本次未改该入口或这些函数的声明关系 | `build/logs/grab-r2-vision.log` |

主机镜像测试人为保持 VIN 忙碌：按钮调用及停止后的等待阶段均无 SCCB 镜像写入，VIN 空闲后才发生写入，且写入时采集配置计数尚未增加；随后确认采集重配和重启，退出时同样等空闲才恢复。首次抓取单测因本工作树尚未初始化 LVGL 而未编译，初始化仓库锁定的子模块后上述单测通过；`git diff --check` 通过。实际抓取手感及板上镜像切换仍需复测。

| ELF | 文件字节 | text / data / bss 字节 |
|---|---:|---|
| `build/sw/showcase/showcase.elf` | 29593692 | 29405732 / 12588 / 50653972 |
| `build/sw/showcase-cpupost/showcase.elf` | 29593548 | 29406176 / 12604 / 50653460 |
