# 临时 CPU 后处理构建（2026-11-14）

- 测量源码：`19008a4a` 加本报告所在提交；ELF 内 BUILD_COMMIT 为构建时 HEAD `19008a4a`。
- 目标：卡 68 R2（PG2L200H，NPU 180 MHz）；这里只做软件构建和主机测试，未上板。
- 工具：xPack riscv-none-elf-gcc 15.2.0，C11，`-Wall -Wextra -Werror -O2`。

| 选项 | ELF | 文件字节数 |
|---|---|---:|
| hw（默认） | `build/sw/showcase/showcase.elf` | 13484156 |
| cpu | `build/sw/showcase-cpupost/showcase.elf` | 13492268 |

- `make -C sw PROGRAM=showcase`：PASS；默认 post.c/vision.c 汇编与 `19008a4a` 相同。
- `make -C sw PROGRAM=showcase SHOWCASE_POST=cpu`：PASS；ELF 无 npu_post_* 符号，后处理不访问 POST 寄存器。
- `make -C sw/tests/showcase/vision cpu`：PASS；空帧、密集并列和固定种子稠密/稀疏帧对参考的结果、候选和计数完全一致。
- `make -C sw/tests/showcase/vision test`、`make -C sw/tests/showcase/pipeline test`：PASS。
- 日志：`build/sw/showcase-cpupost/{hw-build,cpu-build,cpu-post-test,hw-post-test,pipeline-test}.log`。

- 卡 68 软件基线 `48b84d67` 与当前的 `yolo_tables.c`、离线模型快照完全相同。
- 原模型 3242752 B；当前编译器保留全部原字节，仅追加 6144 B 的 exp/probability 表，合计 3248896 B。
- 68 个 64 B 描述符仅索引 52/55/58/61/64/67 的 word 13/14 增加 post_kind/head_id/LUT 偏移；卡 68 R2 NPU（`b5be940c`）不读取这些字段。
- OUTPUT 仍为 725760 B；三头 box/cls 偏移依次为 `0/0x3c000`、`0x87000/0x96000`、`0xa8c00/0xac800`，C16 布局不变。
- CPU 构建原始输出双缓冲为 `0x05000000/0x05200000`；沿用候选缓冲所有权，phase 0 每次最多 8 anchor 且不跨行。
- 上传仍是 EDNM v1：描述符在 +0x1000、模型在 +0x100000；无需换模型或修改调试工具。
- 上板使用本 CPU ELF 内嵌模型即可；重新上传用当前 `build/npu/software_model/{mem_desc.hex,mem_model.hex,regs.txt}`（源快照 `tasks/win/20261029-09-b3-software/src/npu/`）。
- 调试工具使用 `19008a4a` 的 `tools/debug_tool`（含流水线 UI 和候选回传协议）；CPU 解码后、排序前回传候选，兼容当前比较工具。
- 未运行 SoC 仿真、未访问仿真虚拟机；卡 75 验收后删除此临时选项。
