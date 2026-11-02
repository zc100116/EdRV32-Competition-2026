# B3VN CPU L1 脏区优化（T-VN-OVERLAY）
- commit：本报告所属提交（`git log -1 --format=%H -- docs/reports/2026-11-02-vn-overlay.md`）。
- 改前基线：`3c254cdaf6ca192962c2f66b88217d01212f4aef`；软件主机验证，无器件/时序约束。
- 工具：主机 GCC 13.3.0、UBSan；xPack RISC-V GCC 15.2.0，RV32IM_Zicsr、C11、-Os。
- 每框记录四条 1 像素边和标签条（容量 5×DEMO_MAX_BOXES）；字形包含在标签条内。
- 清除与绘制后均逐矩形逐行调用 BSP cache_clean；竖边每行只覆盖一个 cache 行。
- 保留原 BORDER/FILL/GLYPH 顺序、CLIP 与空 RECT 语义；不改 overlay.c 或其他场景。
- `make -C sw/apps/demo test` 全部 PASS，C 编译 0 warning，UBSan 无错误。
- 移动框后与首次绘制的透明缓冲逐像素一致；两槽清空后 CPU/DISP 可见数据全部为零。
- 原有逐像素参考覆盖重叠、单像素、右/下裁剪、边界折叠和槽位独立；clean 桩检查不跨行。
- 条件：3 个 600×400 框，标签均 person 0.875；每帧右移 20、下移 10，包含清旧和画新。
| 每稳态帧 | 改前 | 改后 |
|---|---:|---:|
| 清除像素 store | 724608 | 10608 |
| 绘制像素 store（含重复角点/重叠/字形） | 11235 | 11235 |
| 总像素 store | 735843 | 21843 |
| cache_clean 调用 | 12 | 4908 |
- 主机测试按矩形面积/字形位数统计 store；build/sw/vn-overlay/{before,after}.c 临时逐 store 计数复核一致。
- ELF size：text=47244、data=0、bss=10316，总计 57560 B；原始 SRAM .bin=47244 B。
- 反汇编 demo_overlay_ids 只有 ret；无 RND 符号或 0x41004xxx 槽引用，通用 engine 表也不含 RND。
- 镜像已复制到 `tasks/win/20261102-38-b3vn-b3r/src/demo_vnpu.bin`，与卡 21 同为 objcopy 原始二进制。
- 原始日志：`build/sw/vn-overlay/host-test.log`、`build/sw/vn-overlay/build.log`；未跑仿真/实板，未测帧耗时。
- 复现：`. ~/.local/opt/edrv32/env.sh; make -C sw/apps/demo test; make -C sw PROGRAM=demo_vnpu`。
- size：`riscv-none-elf-size build/sw/demo_vnpu/demo_vnpu.elf; wc -c build/sw/demo_vnpu/demo_vnpu.bin`。
- 反汇编：`rg -n 'RND|41004' build/sw/demo_vnpu/demo_vnpu.dis` 无匹配；`git diff --check` 通过。
