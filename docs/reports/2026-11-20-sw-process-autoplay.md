# 图像处理自动演示与现场反馈修正

- 基线：`f5124a3cb`；自动演示：`c76a98c8b`；最终验收源码：`dda25aab0`。
- 依据：现场演示设计 L12；参数取值经协调者 ask 确认。
- 顶栏自动演示开关、场景 6 自动打开、19 步各 3000 ms 循环、大号步骤标签。
- 50 ms LVGL 定时器驱动；旋转 0→360°（映射现有有符号角度），缩放 50→200→50%。
- 各步独立默认值；亮度/对比度 48/320，Gamma 1.8（处理页倒数指数，可提亮暗部），平移 160/80。
- 组合为 S1 高斯、S2 Sobel、旋转 30°；关闭/离页恢复快照，手动编辑保留当前参数并停止。
- 全部参数通过 `ui_data_process_set` 下发；未改变 PIX/GEO 帧边界接口。
- 单独修复提交 `443a39448`：L9 在无 PIX 识别页也重算 LUT，造成 256 切片启动等待，首帧 NPU 断言失败。
- 经协调者确认，无 PIX、识别档位 0、识别 Gamma=1.0 不计算/上传 LUT，保持 bank；非恒等 Gamma 仍切换空闲 bank。
- 新主机测试覆盖 19 步顺序、2999/3000 ms 边界、循环、动画中间值、关闭/离页恢复、滑块/开关/默认操作接管和定时器。
- 工具：RISC-V GCC 15.2.0、主机 GCC 13.3.0、仓库锁定 LVGL 9.6.0；主机与 RV32 配置，无板上性能测量。
- `. ~/.local/opt/edrv32/env.sh; make -C sw -j1 PROGRAM=showcase`：通过，0 告警；`build/process-autoplay/build-acceptance.log`。
- `make -C sw/tests/showcase -j1 live`：通过，含新增实际 LVGL 自动演示测试；`build/process-autoplay/live.log`。
- `make -C sw/tests/showcase/vision -j1 runtime`：修复后通过，原 NPU/bank 断言保留；`build/process-autoplay/runtime-regression.log`。
- `make -C sw/apps/showcase/sim -j1 pages-shots live-shots`：通过；`build/process-autoplay/shots.log`。
- 三张 1280×720 截图：`outputs/process-autoplay/{sobel,rotation,combined}.png`，不入库。
- 完整 `test live tower` 及更新后的构建、截图最终结果见 L13 追加记录。

## L13 追加验收

- 依据协调者派发的设计记录 `df8da1fb0` L13.1–4；各项独立提交。
- `dda25aab0`：每帧保留实际 BC 和已上传 Gamma 表，按最小满足值逆映射百分位与均值；Gamma 用更新后 BC 的输入均值计算。
- 保留一半平滑；候选变化低于对比度 16、亮度 8、Gamma 0.1 时不更新；逆映射只查实际 LUT。
- 固定输入经 RGB565 量化闭环 30 次：最终 BC=495/92、Gamma=0.8，最后 10 次完全相同，无持续振荡。
- `188d47872`：四种动物计数连续保持 1 s 后更新，稳定少于盘点数持续 3 s 报警，恢复后解除；盘点、看板、采样均用稳定值。
- 经 ask 确认：走失复用红横幅和 `farm event=missing`，板端不新增发声；人员仍为 0.5 s 触发、1 s 解除。
- `f9f589cbe`：分段 NONE 和空下拉明确编码 `value=-1`，多段 EDSC 测试覆盖未选、选择和再次未选。
- 最终 `make -C sw -j1 PROGRAM=showcase`：通过，0 告警；`build/process-autoplay/build-l13.log`。
- 最终 `make -C sw/tests/showcase -j1 test live tower`：全部通过，0 告警；`build/process-autoplay/tests-l13.log`。
- 最终 `make -C sw/apps/showcase/sim -j1 pages-shots live-shots`：通过，0 告警；`build/process-autoplay/shots-l13.log`。
- 另跑 `make -C sw/tests/showcase -j1 farm` 和 `make -C sw/apps/showcase/sim -j1 farm-shots`：均通过；日志 `farm-l13.log`、`farm-shots-final.log` 位于同一日志目录。
