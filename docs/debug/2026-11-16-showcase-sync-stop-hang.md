# Showcase 同步页停止等待不结束

## 1. 现象

卡 93（`01352c691`）协作式版本退出抓取后首页停在“正在停止”，GUI 占用降为 0。
卡 92 和卡 93 的其他退出曾正常完成，说明故障依赖中断与任务的交错。
板上原始线索：`tasks/win/20261116-93-sched-ab/artifacts/uart/A.log`。

## 2. 复现

代码基线：`49a910c77`，开始工作前已 rebase 到 `origin/zc100116/b3`。
主机定向用例：`sw/tests/showcase/vision/runtime_test.c::sync_stop_pending_test`。
命令：`flock /tmp/edrv32-sw-build.lock make -C sw/tests/showcase/vision runtime`。
无随机种子、无 RTL 仿真器；GCC 13.3.0 / UBSan 主机 C 测试调用生产 vision 状态机，
模拟 DISP 锁存和释放。修复后固件代码提交为 `208b78c46`。

## 3. 观察

1. FRAME 中断锁存旧地址，并在 `irq_flags[ENGINE_DISP]` 留下待处理事件。
2. GUI 提交新 L0 NEXT_BASE，立刻给新缓冲增加 REF_DISPLAY，记录 `v.submitted`。
   无 L1 重绘时不会等待 SWITCH1，因而可在 L0 首次锁存前处理返回输入。
3. 返回首页使会话进入 STOPPING；`leave()` 停采集、释放结果，保留显示引用。
4. application task 消费第 1 步的 FRAME，`display_step()` 在新地址尚未锁存时关闭 L0。
5. 下次 FRAME 释放旧的已扫描地址；新的未扫描地址没有对应 SWITCH，REF_DISPLAY 长期保留。
6. DISP 仍扫描首页 L1，STATUS.IDLE 不成立；`vision_service()` 始终等待 `v.display_owned`。

## 4. 根因

`vision.c::display_step()` 的 STOPPING 分支在 `v.submitted` 尚未锁存时关闭 L0。
根据 DISP 规格 2.4 第 4 条，SWITCH 只释放上一帧实际读取过的层地址。
软件把 NEXT_BASE 的预留引用当作已扫描引用，却取消了该地址首次扫描的机会。
CUR_BASE 在层关闭时保持旧值（DISP 4.2），所以单独比较地址还不足以确认重新提交已锁存。
这是代码和主机时序可确认的竞争；卡 93 没有寄存器跟踪，无法证明板上那一次恰好采用此交错。

## 5. 修复

提交时记录 FRAME 序号；后续 FRAME 且 CUR_BASE 匹配才确认提交已经锁存。
STOPPING 保留 L0 使能，直到待提交地址锁存后再关闭，之后由 SWITCH/REL_BASE 释放引用。
不增加超时、自动重试或强制清除已扫描引用；DISP IDLE 的既有释放契约保留。
另修复同步页主动暂停的页面定时器在离开同步会话后未恢复的问题；GUI 归还定时器控制权，
框架定时器不受影响。否则首页状态文字可能一直保留退出时的内容。

## 6. 防回归

修复前用例在 `assert(display_enabled)` 失败：停止消费旧 FRAME 时已经错误关闭 L0。
日志：`build/sw/tests/showcase/smooth-before.log`；原生产代码为 `49a910c77`。
修复后的 `smooth-stop-after.log` 全部通过，含 FACE/GRAB、已有/未有扫描、暂停退出和旧 CUR_BASE。
`smooth-stop-sync.log` 的 GUI 定时器恢复和全应用 session 矩阵通过；覆盖 RUNNING、PAUSED、
STOPPING 中的新请求替换、同应用重入及返回 NONE。最终 rebase 后的结果见报告。

## 7. 同类排查

贴纸和抓取（包括使用 GRAB 后端的体感游戏）共用提交与停止路径。
普通相机、姿态、手势、涂鸦、安全帽和图像页也经过 `display_step()`。
暂停保持 L0 扫描，不撤销提交；停止期间新请求由 `session_open()` 排队，旧资源释放后才 start。
指针返回的 action 1000 和按键 KEY_BACK 都进入 `ui_back()`，随后 `ui_open()` 请求 NONE。
新体感页返回首页页签仍走同一路径；无需修改 `shell.c`。
