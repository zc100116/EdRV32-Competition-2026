# 双指令前端仿真复现

本阶段实现 IF2 和 ALIGN 的双指令接收、解压和消费。整核仍使用单发射 DECODE、执行和提交。默认 `FRONTEND_DUAL_WINDOW=0` 保持单发射基线；新配置以参数值 1 单独验证。

需要 Python 3 和 Icarus Verilog。推荐在虚拟机中从项目根目录运行：

```sh
python3 sim/script/run_dual_issue.py --suite all
```

默认包含 38 项已有回归，以及七种新配置用例。两个随机前端用例各使用种子 `1`、`7`、`20261006`，合计 49 次测试运行。

只运行新配置，或复现单个种子并保存波形：

```sh
python3 sim/script/run_dual_issue.py --suite frontend
python3 sim/script/run_dual_issue.py --case dual-frontend --seed 7 --wave
python3 sim/script/run_dual_issue.py --case dual-align --seed 20261006 --wave
```

工具不在 PATH 时，可以通过 `--iverilog`、`--vvp` 指定可执行文件。`--output` 指定结果目录；默认按 UTC 时间保存到 `sim/build/dual-issue/`，每次运行保留独立目录。

每项运行保存编译命令、运行命令、种子、源码和头文件 SHA256、工具版本、编译日志及运行日志。失败不会被当作 PASS；超时和非零退出码写入 manifest。两个新前端 scoreboard 支持 VCD；已有测试是否输出波形取决于其自身实现。

| 用例 | 核对内容 |
| --- | --- |
| `dual-align` | 四种长度组合、独立预测元数据、不完整 A/B、单条/双条消费、四项容量、B 单独 ready、错误、非法压缩编码、kill 和复位 |
| `dual-frontend` | IF2 与 ALIGN 联接，独立 ROM 指令流核对，无丢失或重复，连续双压缩指令、混合跨块指令、3/4 半字捕获、背压、迟到旧 epoch 响应和 epoch 回绕 |
| `if2-dual-prediction` | 新配置下复用预测回归，覆盖上下半字和跨块预测、直接跳转、BHT 方向与重复 redirect 抑制 |
| `core-dual-frontend` | 新前端与原标量后端的 Load、ALU、Store 和控制流整核检查 |
| `core-dual-csr-trap` | 新配置下 CSR 与同步异常 |
| `core-dual-irq-fencei` | 新配置下中断、fence.i 和恢复 |
| `core-dual-mdu-raw-irq` | 缓存核中新配置的乘法依赖、中断及精确提交边界 |

两个前端随机测试使用固定算法的 LFSR，不依赖模拟器的随机函数实现。参考模型核对已接受指令的完整 payload；集成测试按独立 ROM 指令表核对输出顺序。测试代码和依赖与 RTL 同版本保存，生成的二进制、日志和波形保留在 build 目录，不纳入源码提交。

根 `.gitignore` 显式列出需要版本管理的 CPU 仿真输入。新增 case 时同步增加其目录、filelist、testbench 和必要模型的白名单，并加入 runner 的回归集合；不要只在 build 目录生成一个临时测试。

本阶段不会因 B 槽 ready 而越过被阻塞的 A，也不会在已满容量上组合复用下游当周期释放的空间。四项寄存容量允许在已有两项时同时接收两项和消费两项。
