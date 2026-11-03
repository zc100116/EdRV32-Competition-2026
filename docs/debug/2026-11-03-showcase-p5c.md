# P5c：刷新、识别流水和换图失联

## 现象与复现
- 基线 7b48ccaf；现场证据 5122515a 的卡 54 `r2_*`。
- request 8 在 21:08:50.933 完成；随后 request 10 缓存为接收中，STATE/HELLO 消失，CPU 仍输出。
- 工具随后 IMAGE_INFO 超时，`pending` 不释放，继续发送报“同类命令正在等待设备完成”。
- 主机复现：`make -C sw/tests/showcase test` 的 `vision/network_test.c`，模型在 IDLE 检查后制造 RX BUSY，忽略 DOORBELL。

## 根因与修复
- ETH 的 BUSY 包含 RX DDR 写事务（`rtl/eth/edrv32_eth.v:198`）。
- `board_eth_send` 检查 IDLE 后到 DOORBELL 之间，RX 可转为 BUSY；按 eth-spec 4.1，DOORBELL 被忽略。
- 软件已置 `tx_active`，此后 DONE_COUNT 不增长，图片 TX 等待及所有 STATE/HELLO 发送一起卡住。
- 通信服务保留原描述符表；观察到 IDLE 后再次独立读取 DONE_COUNT，仍未增长才重新敲 DOORBELL。
- 这是规格定义的忽略命令处理，没有超时或重试上限；CPU 行增加累计 `rering=`。
- 时序核对：tx.v:455–461 同沿撤销 active、置 descriptor_done；regs.v:166–167 下一拍更新 DONE_COUNT。
- STATUS 的 APB 读之后，下一笔 DONE_COUNT 读至少间隔 setup/access，保证看到更新，避免重复发送。
- regs.v:569 生成 start_o，tx.v:386 下一 clk_mem 置 active；早于软件下一次 STATUS APB 读。
- 取消后的原始图片槽在 CH2 完成后已不被 NPU/TX读取，释放 JOB/READY 引用；DISP 引用仍由 SWITCH 释放。
- 工具 command_wait 超时释放 pending；迟到的该序号 ACK 与后续命令分开处理。
- 现场没有门铃/寄存器采样；以上是代码与主机确认的竞态，解释现场失联，仍需上板复测。

## 刷新与识别
- LV_DEF_REFR_PERIOD 从 34 改成 16 ms，刷新到期后由异步 L1 SWITCH1 释放双缓冲，连续绘制最快跟随 60 Hz。
- 保留定时器调度及 WFI；flush_pending 时不执行绘制、也不预约空转任务；无新增每帧轮询。
- 新 POST 缓冲物理地址 0x05100000，725760 B；RND COPY 用 ARGB8888 1260×144、stride 5040。
- 同步 showcase_rnd_run 在合作调度内独占 RND，与 GUI run_batch 不会重叠；目标完成后失效缓存。
- DONE/COPY 后马上使用最新匹配 VIN 帧启动 N+1；N 帧的元数据、OUTPUT 和后处理各自保留。
- 暂停/停止不再启动下一帧，排空已在途帧；图片单张也读取相同 POST 缓冲。
- vision 行保留原字段，新增 period（相邻启动间隔）与 copy（同步 COPY 完整耗时），单位 ms。
- 工具上传改为等比居中补黑；显示结果按同一整数尺寸和偏移反变换并裁剪；参考输入使用同一图。

## 防回归与验收
- 主机覆盖 N+1 NPU / N 后处理重叠、不同类别与帧号不串帧、暂停/停止排空。
- 联合测试覆盖识别中取消、发送中取消、取消后立即 INFO+BEGIN、无取消直接 INFO；每种都注入被忽略的门铃，验证 STATE/HELLO 和后续图片。
- 工具测试覆盖超时命令释放与迟到 ACK、横图/竖图/16:9 补边、框反变换、真实参考模型比对。
- `make -C sw PROGRAM=showcase -j 1`：通过，0 warning。
- `make -C sw/tests/showcase test`：通过。
- `make -C sw/apps/showcase/sim shots win`：通过。
- `QT_QPA_PLATFORM=offscreen ~/.local/opt/edrv32-py/bin/python -m unittest discover -s tools/debug_tool/tests`：137 项通过。
- 上板尚未测量：记录 vision fps/period/copy/e2e 和 rering；目标约 24 fps、period 接近 NPU+COPY，Single rectangle 接近 60 fps。
- benchmark 必须保留 16 场景的 fps，尤其 Empty screen、Single rectangle，与第 2 轮 28 fps 对比；不以 render_ms 推算 fps。

## 追加界面改动（10.5）
- 三个媒体页增加“隐藏界面”；隐藏顶栏、底栏和控制区，保留检测框与 sys 层光标。
- 浮窗只临时 suppress，保留开关状态；板载/虚拟按键先恢复并屏蔽本次按下，鼠标接收层消费恢复点击。
- 实时类别按过滤后全帧统计，数量降序、类别 ID 升序取前五；不足五类显示“—”，空条宽为 0。
- 浮窗直接显示 ui_system_t.cpu，无新增统计；ui_vision_t 仅追加 category_id[5] / category_used。
- 新增截图：`build/sim/shots/vision-hidden.png`、`vision-categories.png`、`overlay-cpu.png`。
- 主机 filter 覆盖排序/截断/白名单；shots 覆盖三页第一次 Esc 和鼠标点击只恢复、第二次才执行返回。
