# AUD 模块级测试

依据 `aud-spec.md` v0.1 和 `aud-testplan.md` v0.1，独立实现 AT-01–AT-09。
测试只观察 `edrv32_aud` 的 APB、AXI256 和 I2S 端口。

- AT-01：256 个已知立体声样本，包括正负极值和左右不等的样本。
- AT-02：1536 B 环形缓冲、十次分段发布，覆盖四次回绕、4 KiB 拆分和短读。
- AT-03：LOW 阈值跨越、RW1C 清除、持续低水位不重复置位、再次跨越。
- AT-04：空缓冲输出零、八帧对应八次欠载、补充样本后恢复。
- AT-05：带在途读取关闭、排空事务、丢弃 FIFO、关闭期间零输出和计数不变、重开。
- AT-06：成功前缀保持顺序、SLVERR、ERROR/ERR_CODE、继续发布后 DMA 仍停止、最终零输出。
- AT-07：关闭和空 FIFO 的 urgent，以及 FIFO 剩余 64/63 帧的阈值行为。
- AT-08：公共和私有寄存器复位值、TYPE、对齐屏蔽、使能时配置写忽略。
- AT-09：随机 AXI 延迟、80 轮随机等待和按水位随机补数；比对所有已发布样本且无欠载。

`edrv32_aud_memory.sv` 在 AR 和每个 R 拍之间独立插入随机延迟，支持单事务
SLVERR 注入；复用 `edrv32_axi256_if` 和 `edrv32_axi256_checker`。
现有存储模型没有所需的随机延迟控制，因此这里实现只读模型。
镜像以相对环形偏移存储样本；软件发布 WR_PTR 时按顺序生成期望队列。
I2S 模型逐位检查 dummy、有效位和零填充，检查数据/LRCK 只在 BCLK 下降沿改变，
以及 BCLK 每两个 clk_aud 周期翻转、LRCK 每 128 个 clk_aud 周期翻转。
初次填充前允许零输出；第一个非零样本开始后逐帧比对，队列耗尽后只接受零。

AT-06 按协调者确认的判据：出错事务数据是否进入 FIFO 不作规定；成功前缀仍逐样本
比对，之后等待超过 FIFO 深度，再检查持续输出零。AT-05 在 ENABLE 跨域和当前帧
完成期间暂停内容比对，随后检查关闭期零输出，并使用新的样本序列检查重开。

回归只在用户提供的仿真主机运行：

```sh
python3 tools/regress.py smoke --path verif/block/aud -j 1
python3 tools/regress.py full --path verif/block/aud -j 1
```

`test.yaml` 的 `plusargs: +AT=N` 选择测试；AT-01–08 为 smoke，AT-09 为 full。
`lint.vlt` 仅豁免行为模型的阻塞赋值、共用检查器的整数 ID 临时变量未使用高位、
以及测试环境同步采样异步复位的告警；不关闭 RTL 的告警。
本机 lint 命令使用 `tools.regress.expand_files` 展开测试文件列表：

```sh
python3 - <<'PY'
import subprocess
from pathlib import Path
from tools.regress import expand_files
subprocess.run(['verilator', '--lint-only', '--timing', '-Wall', '+define+SIM_MODE',
                '--timescale', '1ns/1ps', '--top-module', 'edrv32_aud_tb',
                *expand_files(Path('verif/block/aud/files.f'))], check=True)
PY
```

结果见 [results.md](results.md)。
