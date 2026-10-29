# RN-17 主机结果与 B3-3b A 交接

日期：2026-10-29。被测实现提交：`76e0513`（工具）、`146b4fd`（服务/绘制单元）、
`546be8a`（公共 API/配置）；本文件另行提交，不改变被测代码。
LVGL v9.6.0 原始子模块 `80ca777e37a2b176770726a02e07a6fb79ef0b39`。

**初始容差结果：11 帧全部 FAIL，容差没有修改。**
这份交付实现了真实 LVGL → RND 命令 → Python 参考模型的比对与板上 CPU 比对入口；
不能把“比对已实现/执行完成”称为“RN-17 初值通过”。
原始判据仍为全覆盖区通道差≤3、边缘≤48、>3 像素≤全帧 1%，由协调者处理 testplan 待定项 1。

## 条件和命令

- 主机：Ubuntu GCC 13.3.0，Python 3.12.3；1280×720 RGB565，DIRECT 双缓冲。
- 目标编译：xPack riscv-none-elf-gcc 15.2.0，RV32IM_Zicsr / ilp32。
- 主机/目标同一 `lv_conf.h`、单 SW unit、无 OS、静态 24 MiB 堆、batch=32。
- C11 `-O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin`；第三方告警豁免：无。
- 所有构建/执行串行，无 SoC 仿真，无 RTL 读取/修改。

```sh
python3 tools/s3/lvgl_host.py > build/s3/lvgl/build.log 2>&1
python3 tools/s3/rn17.py --no-build > build/s3/lvgl/rn17.log 2>&1
. ~/.local/opt/edrv32/env.sh
python3 tools/s3/lvgl_target.py > build/s3/lvgl/target-build.log 2>&1
PYTHONPYCACHEPREFIX=build/s3/pycache python3 -m py_compile \
    tools/s3/lvgl_assets.py tools/s3/lvgl_host.py tools/s3/lvgl_target.py tools/s3/rn17.py
git diff --check
```

主机：510 个 C 源文件编译并 `--no-undefined` 链接共享库，PASS，0 告警。
RV32：509 个源文件编译和可重定位链接，PASS，0 告警；不再有 libc/math 未解析符号。
剩余引用是 libgcc、BSP cache、RND encoder/physical、共享 S3 平台，以及最终链接
`--wrap=lv_draw_sw_blend` 的 `__real_` 引用，均属于约定的集成依赖。
Python 语法检查和 `git diff --check` 均 PASS。
RN-17 runner 正确返回 1，表示容差超限；它仍完成全部帧，生成完整差异分布。

## 实际 LVGL 帧的结果

`RND/SW` 是该帧混合渲染中的任务数，不包含前一次纯 SW 参考重画。
bins 是每像素最大通道差的五档计数：0–3、4–8、9–16、17–48、49–255。
所有帧均为 921600 像素；RGB565 按规格展开到 8 位通道再比较。
边缘分类为协调者确认的 SW 非255 AA mask / RND 非255 coverage 并集，
BOX_SHADOW 模糊网格整体计入边缘，主机和板上共用同一 C 代码。

| frame | max R | max G | max B | full max | edge max | >3 pixels | >3 % | RND/SW | bins | 结果 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| widgets-16 | 66 | 32 | 25 | 9 | 66 | 39859 | 4.324978 | 62/0 | 881741,37250,2279,314,16 | FAIL |
| widgets-176 | 66 | 32 | 25 | 9 | 66 | 39859 | 4.324978 | 62/0 | 881741,37250,2279,314,16 | FAIL |
| widgets-656 | 66 | 32 | 25 | 9 | 66 | 40331 | 4.376194 | 62/0 | 881269,37686,2314,315,16 | FAIL |
| benchmark-00-empty | 9 | 4 | 9 | 9 | 9 | 8607 | 0.933919 | 5/0 | 912993,1448,7159,0,0 | FAIL |
| benchmark-02-rectangle | 9 | 8 | 9 | 4 | 9 | 9366 | 1.016276 | 6/0 | 912234,9141,225,0,0 | FAIL |
| benchmark-04-rgb-images | 9 | 8 | 9 | 4 | 9 | 9413 | 1.021376 | 26/0 | 912187,9177,236,0,0 | FAIL |
| benchmark-05-argb-images | 16 | 9 | 16 | 4 | 16 | 19182 | 2.081380 | 26/0 | 902418,15507,3675,0,0 | FAIL |
| benchmark-06-rotated-images | 9 | 8 | 9 | 4 | 9 | 9029 | 0.979709 | 5/10 | 912571,8770,259,0,0 | FAIL |
| benchmark-07-labels | 16 | 9 | 9 | 4 | 16 | 27415 | 2.974718 | 40/0 | 894185,21239,6176,0,0 | FAIL |
| benchmark-10-containers | 49 | 24 | 25 | 4 | 49 | 25946 | 2.815321 | 78/0 | 895654,20653,4879,356,58 | FAIL |
| benchmark-13-opa-layer | 33 | 12 | 17 | 4 | 33 | 248301 | 26.942383 | 278/0 | 673299,233576,13616,1109,0 | FAIL |

真实模型执行总计：668 个 batch、2881 条命令、21164490 个目标像素。
选帧导出 2874 条原始命令：FILL=178、BORDER=85、GLYPH=2431、BLIT=138、BOX_SHADOW=42；
另外 7 条来自帧间 DIRECT 脏区 COPY。每条均交给 `rnd_ref.execute`，不是手写模型场景。
旋转图像场景的 10 个 IMAGE 任务未被认领，与该帧 `RN-17 type=6 unclaimed=10` 一致。

产物在 `build/s3/lvgl/`：22 张 `*-sw.ppm` / `*-rnd.ppm`，11 份各帧
`*.commands.bin`，`rn17-results.md`，`rn17.log`。
源数据是实际 LVGL 解码/字体 staging 和目标字节，由 host callback 直接传给 Python 模型；
重新运行上述 runner 可重新取得，不另造源图或命令。
CPU idle 文本由 Linux sysmon 采样，重复运行时该文字及其涉及的少量像素计数可能改变；
每一对 SW/RND 比较期间时间和 UI 内容均冻结。

## 观察、限制和独立检查

源码中可以确认两组算法差异：

- LVGL `src/draw/sw/blend/lv_draw_sw_blend_private.h` 的 RGB565 mix 把 opacity
  化成 `mix5=(mix+4)>>3`，在 RGB565 通道内混合；RND 2.2 是展开 RGB888 后按 /255 四舍五入，
  最后截成 RGB565。两者并非逐位相同，单个 RGB565 LSB 展开就是 R/B 8–9、G 4–5。
- LVGL `lv_draw_sw_box_shadow.c` 的 `SHADOW_ENHANCE=1` 将半宽盒滤波再重复一次，
  RND BOX_SHADOW 是规格定义的一组水平/竖直盒滤波和 Q4 圆角覆盖率。

这些是已检查源码的差异，不代表已经逐任务归因了表中所有差异；
本轮没有改 SW 参考、硬件算法、容差，也没有为了通过初值而禁用正常认领。
需要进一步逐任务归因或容差定稿时，可从保留的 PPM/命令及该实现继续。

真实 benchmark 的 16 个场景及平均 FPS 打印路径已执行；人工推进 host tick 下输出为 0，
这只验证结束回调，不是硬件性能值。两个“benchmark → stop → menu → 越过场景期限”
检查均 PASS，菜单中心像素保持不变。host 的 Surface 重叠检查未报错。

目标片段 `riscv-none-elf-size build/s3/lvgl-rv32/lvgl.o`：

| text（含常量） | data | bss | 合计 |
|---:|---:|---:|---:|
| 1761060 | 1405 | 38436764 | 40199229 B |

这是未最终放置、未执行应用级 `--gc-sections` 的可重定位片段；
不代表最终 ELF，也不含共享 S3/game/stack 的布局。
主静态对象逐项大小、对齐、DDR CPU/物理窗口、cache 交接和 perf 估算输入见 `README.md`。
最终绝对地址/应用 DDR 总量由项目经理在完整 S3 map 中记录。

未验项：真实板上 RN-17、RND 中断和 DISP SWITCH/FRAME、KEY/UART、
真实 benchmark FPS、最终 S3 DDR ELF/主界面 PPM；前五项需要上板，最终集成由 C/项目经理负责。
本员工没有运行完整 SoC 仿真，没有修改归属外文件。
