# T-P5-RUNTIME 验收摘要

基线：a30c3ee3；实现提交由同次 worker_done 给出。
依据：2026-11-03-showcase-p5-replan §3、§6、§8，及协调者补充的 IMAGE_STEP 规则。

- 新增硬件无关 session / protocol / input / STATE 编码模块。
- 错误范围经协调者确认：参数/消息长度/状态错误只回 ACK(3)/DONE(error)，不停止当前应用。
- 硬件不支持、已接受 BULK 的解析错误才使会话 FAILED，排空资源后可重试。
- 主循环只读后端会话，不再读取 UI 页面或游戏全局变量。
- STOPPING 等待 VIN、PIX、GEO、当前 NPU 和 L0 REL_BASE；游戏和 CoreMark 完成保留 app。
- 视觉应用各自保留结果/图片元数据，共享管线以显式状态管理启动、运行、暂停和停止。
- 图片使用 IMAGE_INFO → BULK_BEGIN，EDDT request 与 BULK seq 对应；取消不打断 NPU。
- 取消后立即上传下一张的测试覆盖旧结果丢弃、旧 OUTPUT 保留、新请求排队。
- PROCESS 独立启用位、参数保留、选择性默认值；ACK 等到新配置的采集帧完成。
- HELLO、ACK、STATE、APP、IMAGE_STEP、DETECT、CANCEL 接入板端；STATE 每秒及变化时广播。
- PROCESS/DETECT 在任意状态保存；对应应用 RUNNING 时等下一帧 ACK，否则保存后立即 ACK。
- showcase 删除 UART 虚拟输入解析/源文件/专属测试，独立 NES 的库没有修改。
- 输入所有者变更屏蔽所有仍按住的键；300 ms 无帧释放虚拟键鼠。
- LVGL 报告当前键自己的按下/松开，四个板载键映射 NEXT/PREV/ENTER/ESC。
- 后处理先 invalidate OUTPUT，再使用 cached OUTPUT 和 workspace，保持原来的小片执行。

验证：

- `make -C sw/tests/showcase test`：全部通过，C11 `-Wall -Wextra -Werror`。
- session：6×6，RUNNING / PAUSED 切换、STOPPING 再次请求、恢复、FAILED 重试、自然完成。
- protocol：v3 各命令回复/边界错误、异步 ACK、取消 DONE/ACK 独立 seq、状态广播。
- STATE：逐字节核对 56 B，含有符号参数、类别、request、frame 和保留位。
- input / GUI：游戏 Esc 一次、持键屏蔽、300 ms 释放、当前键释放后才报告下一键。
- vision：UBSan；空/密集/固定种子数据与 yolo_post_process 的结果、工作区、操作计数全相同。
- 21 个任务归属内 C 对象用 showcase Makefile 单独交叉构建：0 warning / error。
- `make -C sw PROGRAM=showcase -j 1`：停在旧 `ui/page_process.c` 接口错误，符合并行任务约束。
- `git diff --check`：通过；没有 RTL 变更，Verilog lint 不适用。
- 原始日志：build/sw/tests/showcase/{acceptance,board-objects,board-build}.log。

卡 54 必须实测（本任务没有 FPGA 实测数字）：

- 先过六应用运行/暂停/停止切换矩阵、Esc 逐级返回和断网 300 ms 释放。
- 每张图片的 EDDT request / BULK seq 一致，取消后不得显示旧结果。
- 相同模型、图片、门槛对比 demo_npu：后处理 decode+sort+nms ≤35 ms。
- 记录 vision 的 fps / npu / wait / decode / sort / nms / post_span / gui / e2e 和三任务 CPU%。
- GUI 完成口径：新结果被 ui_data_vision 首次取走后的第一次 L1 SWITCH，协调者已确认。
- 核对 视觉切片 ≤2 ms（既有独占步骤除外）、输入到 LVGL ≤16.7 ms、上传完成到 DONE ≤300 ms。
- 记录 DDR 各端口带宽、NPU/RND 忙时和连续 15 分钟识别结果。

待协调者合并 UI/TOOL 分支后执行 ELF 集成构建及卡 54。
