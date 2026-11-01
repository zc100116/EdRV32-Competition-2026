# S3 菜单启动 WIDGETS 时访问已删除卡片

## 1. 现象

卡 23 B3R 从 BIOS 加载 S3 后，按键选中 WIDGETS 启动，出现
`lv_obj_get_display: No screen found`、NULL display 警告，随后
`mcause=7 mepc=0x900663bc`（卡 23 ELF 的 `lv_event_send.part.0`）。
主机使用真实菜单并通过 LVGL keypad 移动焦点后，重现同组警告。

## 2. 复现

复现基线：`7826ec1b`（其 `menu.c` 与卡 23 构建基线 `506f07e4` 一致）；LVGL 子模块：`80ca777e37a2b176770726a02e07a6fb79ef0b39`。
工具：Ubuntu GCC 13.3.0、Python 3.12.3、xPack RISC-V GCC 15.2.0；
板级配置、LVGL 内建 24 MiB 堆，
无随机种子，无 RTL 仿真器。复现入口与本修复一起提交。

```sh
flock /tmp/edrv32-sim.lock python3 tools/s3/widgets_check.py
```

主机构建复用 `lvgl_host.py` 的源文件组和 `lv_conf.h`，额外链接真实 `menu.c`
及已有 `layers_check.c`（调用生产 `layers.c` 的 `lvgl_scene`）。
全部 C 源使用 `-fsanitize=address,undefined -fno-omit-frame-pointer`；
RND 描述符经 `draw_rnd`、`rnd.c` 和 RN-17 的 `rnd_ref.py` 路径实际执行。
CPython 进程预加载 libasan；禁用的是 Python 进程退出时的 LeakSanitizer，
ASan 地址检查与 UBSan 保持开启，首个错误立即退出。

修复前在基线 `menu.c` 上加入本次入口并恢复两行性能统计配置，
命令退出 1；修复后执行同一命令。修复版本为本记录所在提交。
本地日志：`build/widgets-before.log`、`build/widgets-after.log`（生成物不入库）。

## 3. 观察

主机虚拟时间 192 ms：初始菜单完成 1 帧；KEY2 按下完成 1 帧，释放后启动
WIDGETS。此前参考模型已执行 73 批、915 条命令、3,970,067 个目标像素。
警告发生于 WIDGETS 创建之前的菜单清理，随后 UBSan 报：

```text
lv_display.c:1096: member access within null pointer of type 'struct lv_display_t'
lv_display_send_event -> lv_obj_refresh_style -> lv_obj_set_style_border_width
-> select_card (menu.c:31) -> card_event (menu.c:39)
-> lv_event_send -> focus_next_core -> lv_group_refocus -> lv_group_remove_obj
-> lv_obj_destructor -> lv_obj_clean -> s3_lvgl_stop_demo
-> begin_demo -> s3_lvgl_start_widgets
```

地址检查未先报堆释放，是因为保留了板级 LVGL 内建分配器；其内存池内部释放
不等于宿主 `free`。UBSan 在后续空 display 解引用处终止，不能据此声称已检测到
宿主 malloc 的 use-after-free。

## 4. 根因

基线 `sw/apps/s3/menu.c:39` 的 `card_event` 在 `LV_EVENT_FOCUSED` 中调用
`select_card`，后者在第 26–31 行通过整个 `cards[]` 设置样式。
`cards[]` 保存菜单对象的裸指针，菜单清理时并未逐项改变这些指针。

LVGL `lv_obj_clean` 顺序删除子对象。选中第二张卡片时，第一张卡片先被释放；
第二张卡片析构调用 `lv_group_remove_obj`（`lv_obj.c:1535`），
后者自动重聚焦并同步发送下一张卡片的 FOCUSED 事件
（`lv_group.c:190–196`）。回调再次遍历已经包含已释放对象的 `cards[]`，
样式写入已销毁对象，并通过失效对象关系进入 display/event 路径。
这条已确认的软件生命周期错误能够在没有 RTL、cache 或板级 DMA 的主机上重现。
板上最终 fault 指令与主机 UBSan 停止点不同，二者出现相同前置警告；
板上修复效果仍需重新下载验证。

## 5. 修复

`menu.c` 抽出 `style_card`；焦点、失焦和点击事件只修改
`lv_event_get_current_target(event)` 指向的存活卡片。
新增 DEFOCUSED 回调恢复旧焦点样式，FOCUSED 回调记录选中项并高亮自身。
板上按键的 `s3_menu_input` 仍只在菜单存活期间调用 `select_card`，
保持其原有导航顺序，不额外移动 LVGL 焦点。
没有增加空指针检查、对象有效性探测、重试或兜底。

恢复 `lv_conf.h` 的 `LV_USE_PERF_MONITOR=1` 和
`LV_USE_PERF_MONITOR_LOG_MODE=0`，使 benchmark 恢复软件帧率统计。
未修改 RTL、规格、寄存器头或 cache 操作。

## 6. 防回归

新增 `tools/s3/widgets_check.py`：真实菜单经 KEY2 的按下/释放进入 WIDGETS，
回菜单启动 BENCHMARK 的全部 16 个原生场景及结束回调，
再经生产 LAYERS 半透明容器、返回菜单、重新选择 WIDGETS。
每条 RND 命令均实际执行参考模型，输出帧数、批数、命令数、像素数及 opcode 统计。

sanitizer 检查通过：步进中实际刷新 60 帧（另有 LAYERS 强制刷新），
2,814 批、18,442 条命令、103,553,634 个目标像素，ASan/UBSan 均无报告，
无 LVGL 警告。直接 WIDGETS 刷新 2 帧，LAYERS 后 WIDGETS 刷新 1 帧；
全部 16 个 benchmark 场景及结束回调完成，LAYER 认领 9、未认领 0。
opcode 数量：FILL 678、BORDER 255、GLYPH 16,638、BLIT 600、COPY 54、
BOX_SHADOW 134、ARC 56、AFFINE_BLIT 27。主机虚拟时钟的 FPS 不作为板上性能测量。

原有回归在 rebase 到 `026b87ef` 后运行；该提交对 S3 公共代码仅增加
`virtual_input.c` 状态的 volatile 限定，未改菜单及渲染路径。

```sh
flock /tmp/edrv32-sim.lock python3 tools/s3/rn17.py
flock /tmp/edrv32-sim.lock python3 sw/apps/s3/host/layers_check.py
flock /tmp/edrv32-sim.lock make -C sw PROGRAM=s3 MEMORY=ddr_app -j1
```

- RN-17：512 个源文件 C11/Werror 构建通过；原生 MASK_RECT 16 例通过，
  带外 alpha 最大差 0/255；图像比较 15/16，命令退出 1。
  唯一失败仍为 `benchmark-12-opa-containers`：20,752/921,600 = 2.251736%，
  full max=1、edge max=5 LSB；其余 15 帧通过。参考模型执行 776 批、
  3,899 条命令、32,684,843 个目标像素。
- 该 opacity 失败是既有基线，见
  [2026-10-31 不透明度调试记录](2026-10-31-rnd-v2-rn17-opacity.md)；
  本次普通 RN-17 库没有链接菜单，未修改该帧阈值、混合规格或模型。
  协调者本次通过 Orca ask 明确接受 15/16 既有基线并要求如实记录。
- LAYERS：24,000 次参数提交通过，原生 LVGL 50% 容器经参考模型通过，
  LAYER 认领 9、未认领 0。
- S3 DDR 构建：通过，0 warning，生成 `build/sw/s3/s3.elf`。
- `git diff --check` 通过；新 C 源均使用 `-Wall -Wextra -Werror`；
  未改 RTL，不涉及 Verilog 风格检查或 lint。

日志：`build/rn17.log`、`build/layers-check.log`、`build/s3-build.log`；
比较数字与帧图位于 `build/s3/lvgl/`，均为不入库的生成物。

## 7. 同类排查

`menu.c` 中所有焦点/点击事件均进入同一回调，已移除其跨卡片访问；
仅菜单显示和板上菜单输入仍遍历 `cards[]`。
`begin_demo`、`s3_menu_show`、LAYERS 的 `lvgl_scene` 均会清理当前屏幕，
因此复现覆盖直接进入 demo、demo 返回菜单及 LAYERS 后重新进入 demo。
原 RN-17 直接创建 demo，结束后使用简化主机菜单，不包含生产菜单的卡片事件，
此前不能覆盖该释放期间的重入路径。
