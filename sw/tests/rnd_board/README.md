# RND 上板自检

B3R 顶层包含 CPU/DDR/RND/DISP/ETH；本程序使用 RND/DISP，ETH 连通检查由独立软件任务提供。

本程序在 DDR 应用区运行（`MEMORY=ddr_app`，CPU 入口 0x90000000），
用实际 RND 驱动绘制，再把 RGB565 L0 和非预乘 ARGB8888 L1 交给 DISP。
Linux 验收为编译和主机测试；未完成 SoC CRC 仿真，实际 HDMI 与 CRC 以上板检查为准。

## 构建及主机检查

仓库根目录执行：

```sh
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=rnd_board MEMORY=ddr_app
make -C sw/tests/rnd_board test
python3 sw/tests/rnd_board/expect.py
```

输出为 `build/sw/rnd_board/rnd_board.{elf,bin,dis,map}`。
`scenes.py` 是命令和源数据的唯一描述，构建时生成 `build/sw/rnd_board/scenes.h`；
生成物不入库。C 程序调用驱动的 v1/v2 编码函数，Python 用 `rnd_ref.py` 的编码器和
整数渲染器处理同一描述。主机测试将 C 的所有 64 B 命令与参考模型逐字节比较，
还覆盖提交/cache 调用顺序、轮询完成、错误详情、PLIC 11 回调、ABORT、两层寄存器及
日志 PASS/FAIL 判定。主机寄存器测试只映射内存字并记录 BSP 调用，不模拟 SoC/RTL。

程序保留原有 16 组及顺序，追加 v2 的 13 组，共打印 29 个 CRC。
MASK_RECT 按规格只允许 ARGB8888，协调者已确认不下发 RGB565 组。
每行 CRC 为该组完成后**整块目标 Surface**的 CRC32（IEEE，反射多项式 0xedb88320，
初值/末尾异或 0xffffffff），包含之前组留下的像素。两块 Surface 初值全零，
临时区和行外内存不计入 CRC。`rnd_wait()` 在 CPU 计算前通过 BSP 作废目标 cache。
每组另打印捕获的 `ERR_CODE` 和 `CUR_DESC`；错误时停止，不重试。

## BIOS 加载和运行

需要包含 DDR Load/Run 的 BIOS。当前工作分支的旧 BIOS 及 UART 工具可能尚未升级；
菜单只有 `1=Program SRAM` 时，先合入 SoC 规格 v0.17 7.5(3a) 对应的 BIOS/工具升级。
**不能用菜单 1 把这个 DDR 程序当作 SRAM 镜像下载。**

使用 `tools/board/uart_tool.py` 的 **ELF 加载并运行**功能，文件选择
`build/sw/rnd_board/rnd_board.elf`；具体命令行参数见
[`tools/board/README.md`](../../../tools/board/README.md) 的 ELF 加载用法。
工具应逐个加载 ELF 的非空 PT_LOAD 段，再以 ELF 入口运行，并保存串口日志。
可先通过 BIOS 菜单 4 将波特率从 115200 提至 921600 或 2000000。
本 Task 不修改 BIOS 或 UART 工具，不猜测尚未合入的参数名。

手动协议（协调者确认的 v0.17 7.5(3a)）：

1. 按住 KEY1 复位，出现 `BIOS menu: 1=Program SRAM 2=Load 3=Run 4=Baud`。
2. 对 ELF 每个文件长度非零的 PT_LOAD 段发送 `2` 和 Enter；看到 `UART load ready` 后，
   发送 **4 B 小端 CPU 目标地址 + 4 B 小端长度 + 该段数据**。
   地址使用 ELF 的 CPU 虚拟地址（0x90000000 起）。每段应出现
   `Load bytes: <n> at 0x<addr>` 和 `Load result: PASS`。
3. 发送 `3` 和 Enter；看到 `Run address:` 后，发送 `0x90000000` 和 Enter
   （一般情况下取 ELF 的入口）。BIOS 打印 `Run: 0x<addr>` 后跳转。
4. 保存从第一条 `RND` 到 `RND display ready` 的日志。若只需记录运行中的输出，
   当前工具可用 `python3 tools/board/uart_tool.py --port COM3 --log build/board/rnd.log`；
   下载和记录应使用同一串口会话，避免漏掉最前面的 CRC。

## 屏幕与上板检查清单

HDMI 为 1280×720 黑底，L0 图案在 y=96..191，L1 图案在 y=384..479，
阴影向外扩 7 像素。两排从左到右顺序相同：

| 组 | 应看到的内容/覆盖 |
|---|---|
| fill | 圆角矩形、水平和竖直渐变、正负步长、半透明交叠 |
| border | 完整圆角边框与只选部分边的内框 |
| glyph | 四块掩码着色，A8/A4/A2/A1（测试纹理，不是文字） |
| blit | 六块源图：RGB565、ARGB8888、I8/I4/I2/I1；四种混合、翻转、缩放、重着色、颜色键、裁剪 |
| copy | 渐变块内向右/左/下/上的重叠搬运 |
| box_shadow | 带圆角、向四边柔化的彩色阴影 |
| blur | 彩色竖条经过区域模糊，边缘变柔和 |
| tilemap | 四块瓦片地图，8/16 像素瓦片、翻转、RGB565/ARGB8888/I8/I4 |

v2 排追加在 RGB565 y=240..351、ARGB8888 y=544..655；每列左边 x=40+172×列号。
原有两排不变，v2 下列各列在两个目标上相同；RGB565 的 MASK_RECT 列留黑。

| 列/组（后缀为目标格式） | 应看到的内容/覆盖 |
|---|---|
| 0 triangle | 两个由青色/粉色三角形拼成的方块；共享斜边无缝，左右分别开/关 AA，含边组合 011/100 |
| 1 line | 青色斜粗线和橙色水平粗线，各自两端圆头、AA 边缘 |
| 2 arc | 青色跨三个象限的 270° 粗圆弧，右下象限缺口、两个圆头 |
| 3 mask_rect | 仅 ARGB8888：两块 alpha/颜色渐变圆角遮罩，左侧清除外部，右侧保留外部 |
| 4 affine_blit | 六块旋转缩放纹理：三列 RGB565/ARGB8888/I4，上排最近邻、下排双线性 |
| 5 round_clip | RGB565/ARGB8888 两块纹理，独立目标圆角裁切 |
| 6 cutout | 粉色圆角柔阴影，背景区域被挖空，偏移的外侧阴影可见 |

检查清单：

- 保存全部 29 条 `RND <组名> crc=0x<8位>`，每条 `RND ERR_CODE` 必须为 0。
- 最后出现 `RND display ready`，四排图案完整；L1 外保持透明，可见黑色 L0。
- 运行下方日志比对，29 组逐行 PASS，最终 PASS、退出码 0。
- 若失败，保留实际 CRC、ERR_CODE/CUR_DESC、UART 日志及屏幕照片；本程序不自动恢复。
- 复位后重新加载运行，CRC 应相同；画完后程序不再写扫描中的 Surface（SoC R3）。

```sh
python3 sw/tests/rnd_board/expect.py > build/sw/rnd_board/expected.log
python3 sw/tests/rnd_board/expect.py build/board/rnd.log
```

未收到的组、任一 CRC 不符或非零 ERR_CODE 均输出 FAIL 并返回 1。
期望日志也可传给第二条命令检查工具链路，但那不构成上板证据。

## 验证记录

- 日期：2026-10-31；源码：基线 `6f71e73c` 加本提交（`git log -1 -- sw/tests/rnd_board`）。
- `make -C sw PROGRAM=rnd_board MEMORY=ddr_app -j 1`：通过，0 warning。
- `make -C sw/tests/rnd_board test`：108 条 C 命令与参考编码逐字节相同，
  驱动/cache/寄存器和全部 29 组日志 PASS/FAIL 测试通过。
- `python3 sw/tests/rnd_board/expect.py`：生成 29 组期望 CRC，原 16 组及顺序不变。
- 按协调者调整后的验收要求，不做 SoC CRC 仿真；已停止试跑、清理临时构建，
  不提交新增仿真目录，也不宣称 SoC CRC 已通过。
- 主机试跑环境：用户提供的仿真主机（环境不记录）；原始主机文件不回传。
- MASK_RECT 依 rnd-spec v0.3 2.6 及协调者确认只测 ARGB8888；其他六项各测两种目标。
- B3R 上板验收以 `expect.py build/board/rnd.log` 对 29 组 CRC 全部 PASS 为准，
  HDMI 画面按上述逐组清单核对；本次未执行实际板卡验收。
