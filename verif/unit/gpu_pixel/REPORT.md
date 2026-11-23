# R-4b 验证结果

实现提交：`gpu: pixel operations and on-chip render target`。
定位提交：`git log -1 --format=%H -- rtl/gpu/edrv32_gpu_pixel.v`。
环境：用户提供的仿真主机（环境不记录）。

- pixel：PASS，5408 组配置、5667 个四像素字、12844 个通过测试的像素。
- 模板：8 函数 × 6 操作 × sfail/zfail/zpass，读掩码 00/55/ff，写掩码 00/a5/ff。
- 模板边界：原值 0/127/128/255；ref 0/127/255，饱和递增/递减和反转。
- 深度：LEQUAL/ALWAYS、相等边界、写入开关；颜色写入开关、透明 mask、最终 alpha=0。
- 混合：10×10 因子配对 × 5 方程 × 3 常数 alpha，d()、饱和、E565/P565。
- RMW：最近前驱未就绪/已就绪/已提交；连续 48 次同字运算仅一次 RAM 读取。
- 地址：两种行宽、负 X 偏移、任意 Y 偏移、行/段/尾部边界。
- 背压：入口阻塞 234 拍；无背压连续 160 拍提交，4 像素/拍。
- target：PASS，547337 次读响应、20 次 CLEAR；全部 28800 个地址及两种形状。
- CLEAR：8 组清除开关、部分 lane、完整/空交集、未清字段保留。
- 读口：pixel/RESOLVE 顺序与背压保持、五拍响应、采样拍提交旁路。
- 存储：14×9 个 2048×18 包装加 3 个 512×72 包装，129 个 DRM 实例。
- RTL 风格与 `--lint-only -Wall`：0 告警。
- 仿真主机新增的测试台声明初始化告警已通过改为 initial 初始化消除。
- 测试台 lint 配置仅豁免自身的过程式 BFM 赋值、未使用端口和复位观察；RTL 无豁免。
- PDS/IP 生成与物理时序未在本任务运行。

复现（仿真命令在仿真主机执行）：

```sh
python3 tools/regress.py full --path verif/unit/gpu_pixel -j 1
python3 tools/regress.py full --path verif/unit/gpu_target -j 1
python3 tools/check/verilog_style.py rtl/gpu/edrv32_gpu_pixel*.v rtl/gpu/edrv32_gpu_target*.v rtl/tech/edrv32_ram_gpu_target*.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include --top-module edrv32_gpu_pixel rtl/gpu/edrv32_gpu_pixel*.v
verilator --lint-only -Wall -DSIM_MODE -Irtl/include --top-module edrv32_gpu_target rtl/gpu/edrv32_gpu_target*.v rtl/tech/edrv32_ram_gpu_target*.v
```

端口摘要（流均 valid/ready；低 lane 位于低位）：

- pixel 输入：render_state(tex256/pixel256/target256/wide1)，shaded(x16/y16/mask4/depth64/color96/alpha32)。
- pixel 目标口：target_read(addr16)，target_old(data160)，target_write(addr16/data160)。
- pixel 控制：clk/rst_n、finish/stop、unit_done、perf_pixel_count[2:0]。
- target 输入：clear(command256/target256/wide1)，与 pixel 对接的上述三个目标流。
- target RESOLVE：resolve_read(addr16)，resolve_color(data64)，顺序响应。
- target 控制：clk/rst_n、finish/stop、unit_done，完成包含物理 RAM 写入。
- 两种 tech 包装：clk、wr_en/wr_addr/wr_data、rd_en/rd_addr/rd_data；读延迟均 2 拍。

I-1 完成协议修复：pixel/target 在 finish=0 时清除旧 unit_done（微结构 4.2）。
原 target 在上游尚未送来首个读写时仍保留上一命令的 done，GT-01 因而提前退休 DRAW_TRI。
两个单测均增加“空命令完成→finish 拉低→无输入/配置等待 8 拍”的检查，防止旧 done 泄漏。
上述两条 full 回归重新实跑，均为 1 PASS、0 FAIL；RTL 风格和 GPU 顶层 lint 仍为 0 告警。
修复提交定位：`git log -1 --format=%H -- rtl/gpu/edrv32_gpu_target.v`。
