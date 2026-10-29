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

## A2：圆角 FILL / BORDER 差异归因

### 结论与参数核对

**归类：rnd-spec 2.3 与 LVGL v9.6 软件圆角光栅算法的固有差异，未发现绘制单元换算错误。**
本次不修改 `draw_rnd.c`、参考模型、LVGL、规格或容差，前面的 RN-17 表保留原始结果。
被分析实现仍是 `e45a150` 及其上述父提交。

通过一个只观察 `evaluate_cb`、不改变任务偏好的临时 draw unit，重新运行真正 widgets 的
16 ms SW 帧，取得如下原始 LVGL task 参数；再解码该帧已保留的 descriptors。
编号是 `widgets-16.commands.bin` 中从 0 起的 64 B 命令序号。

| 命令 | LVGL area（含端点） | 原始 radius | LVGL 有效 radius | RND X0/Y0/X1/Y1 | RND RADIUS | OPA / COLOR |
|---|---|---:|---:|---|---:|---|
| FILL #139 | (751,217)–(988,256) | 13 | min(13,40>>1)=13 | 751/217/988/256 | 13 | 255 / 0x2196f3 |
| FILL #252 | (674,421)–(696,443) | 32767 (`LV_RADIUS_CIRCLE`) | 23>>1=11 | 674/421/696/443 | 11 | 255 / 0x2196f3 |
| FILL #281 | (1227,667)–(1267,707) | 32767 (`LV_RADIUS_CIRCLE`) | 41>>1=20 | 1227/667/1267/707 | 20 | 255 / 0x2196f3 |
| BORDER #184 | (42,411)–(319,454) | 10 | min(10,44>>1)=10 | 42/411/319/454 | 10 | 255 / 0xe0e0e0 |

三个 FILL 的 `FLAGS=0`，无渐变。它们的 RND CLIP 分别是
(747,213)–(992,260)、(650,366)–(1259,498)、(1227,667)–(1267,707)，均覆盖下表分析点。
目标 layer 的 `buf_area` 原点为 (0,0)，RGB565、跨距 2560 B，坐标没有额外平移或缩放。
LVGL `lv_area_get_width/height`、本绘制单元和 RND 都采用 `x2-x1+1 / y2-y1+1`。
`draw_rnd.c:radius()` 与 `lv_draw_sw_fill.c` 的 `rout=min(radius,short_side>>1)` 相同；
不是 `LV_RADIUS_CIRCLE` 漏截断、四舍五入成 12/21 或含端点偏一。

### RND 公式手算与实际像素

令 `i=x-X0`、`j=y-Y0`，下表使用上半部分；底边使用对称的 `jd=H-1-j`。
在这些位置 RND 左边界更近，因此 `room=16(i+1)-e`，右边取镜像的同一个值。

| 命令 / j | dy | 根号内 `256r²-dy²` | isqrt | e | i / room / RND cov | LVGL SW cov |
|---|---:|---:|---:|---:|---|---|
| #139 / 0 | 200 | 3264 | 57 | 151 | 10 / 25 / 255 | 192 |
| #139 / 1 | 184 | 9408 | 96 | 112 | 6 / 0 / 0 | 48 |
| #139 / 1 | 184 | 9408 | 96 | 112 | 7 / 16 / 255 | 192 |
| #252 / 0 | 168 | 2752 | 52 | 124 | 8 / 20 / 255 | 176 |
| #281 / 0 | 312 | 5056 | 71 | 249 | 14 / -9 / 0 | 48 |
| #281 / 0 | 312 | 5056 | 71 | 249 | 16 / 23 / 255 | 176 |
| #281 / 0 | 312 | 5056 | 71 | 249 | 17 / 39 / 255 | 192 |

例如 #139 的首行：`dy=16*13-8=200`，
`e=208-isqrt(43264-40000)=208-57=151`，
(761,217) 的 `i=10`，`room=176-151=25≥16`，因此 cov=255。
(757,218) 的 `i=6,j=1`，`e=208-isqrt(43264-33856)=112`，
`room=112-112=0`，因此 cov=0。`rnd_ref.coverage` 对这些点逐项返回相同整数。

OPA=255，所以本例 RND 的最终源 alpha 就是 cov；再由 2.2 over 和 P565 得到像素。
SW mask 则取自未修改 LVGL 的 `lv_draw_sw_mask_radius_init/apply`。
下表的两组 RGB 是原始完整 widgets PPM 中的实际读数，并非另造命令得到的画面。

| 命令 | 像素（左右/上下镜像同值） | RND cov / SW cov | SW RGB | rnd_ref RGB | 最大通道差 |
|---|---|---|---|---|---:|
| #139 | (761,217)、(978,217) | 255 / 192 | 82,174,247 | 33,150,247 | 49 |
| #139 | (757,218)、(982,218) | 0 / 48 | 206,235,247 | 255,255,255 | 49 |
| #139 | (758,218)、(981,218) | 255 / 192 | 82,174,247 | 33,150,247 | 49 |
| #252 | (682,421)、(688,421)、(682,443)、(688,443) | 255 / 176 | 99,182,247 | 33,150,247 | 66 |
| #281 | (1241,667)、(1253,667) | 0 / 48 | 206,235,247 | 255,255,255 | 49 |
| #281 | (1243,667)、(1251,667) | 255 / 176 | 99,182,247 | 33,150,247 | 66 |
| #281 | (1244,667)、(1250,667) | 255 / 192 | 82,174,247 | 33,150,247 | 49 |

原任务重点的 10 个点来自 #139 和 #252；另 6 个 #281 点也复现相同覆盖率机制。
#281 更靠下的像素会受后续 sysmon 图层影响，不能直接把单图元的完整对称性当成最终 PPM 对称性。

### 两种公式的差别

RND 2.3 在一行的 **y 像素中心**取一次圆的横截面：
`x_edge=r-sqrt(r²-(r-j-0.5)²)`，向内量化为 Q4 的 e，
再对这条横截面做 x 方向覆盖率。每侧每行最多一个部分覆盖像素。
这不等于在整个像素方格上积分圆形面积。

LVGL `lv_draw_sw_mask.c:circ_calc_aa4` 则以 `radius*4` 运行 midpoint/Bresenham 圆：
初态 `x=4r,y=0,tmp=1-4r`，每次按 `tmp<=0` 与否更新 x/y 和判别式。
每组推进四个 y 子像素；将四个 `x>>2` 和 `x&3` 汇成 16 倍的 opacity，
跨列时拆成多个像素，最后镜像另一个八分圆。它近似像素方格的二维面积，
同一行允许连续多个部分覆盖像素；不是给相同半径简单加/减半个像素。

读取实际 circle cache / mask，#139 的 `r=13,j=0` 左侧得到：

| i | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---:|---:|---:|---:|---:|---:|
| LVGL cov | 0 | 32 | 112 | 192 | 240 | 255 |
| RND cov | 0 | 0 | 144 | 255 | 255 | 255 |

该行 LVGL 的 `cir_y=12,x_start=1,aa_len=5`，缓存 opacity 为
`[0,32,112,192,240]`，按 `cir_x_left=r-x_start-1=11` 反向放入左侧像素。
#252 首行在 i=8、#281 首行在 i=16 都是 SW=176、RND=255。
此外 #139 的 (i=10,j=0) 要降低 RND 覆盖，而 (i=6,j=1) 要提高 RND 覆盖；
统一增加或减少半径不能同时消除这两个方向相反的偏差。

### BORDER 同类排查

#184 的 LVGL `width=2,side=0xF`，编码 `W9=0x000f0002`，四边位映射正确。
两边都得到内矩形 (44,413)–(317,452)、内半径 `max(10-2,0)=8`。
widgets 中其余六条非零半径 BORDER（#154/#205/#218/#228/#229/#279）也都是
`radius=10,width=2,side=0xF,opa=255`，原始 task 参数与编码字段一致。
两个 radius=0 的 BORDER 中，#3 的 LVGL BOTTOM=1 正确映成 RND BOTTOM=2。

圆角外/内 mask 的组合机制相同，但各自圆的光栅覆盖率不同。
以 #184 的 (49,411)，即外矩形 `i=7,j=0` 为例：
RND `dy=152,isqrt(2496)=49,e=111,room=128-111=17`，外 cov=255；
该行在内矩形上方，内 cov=0，所以边框 cov=255。LVGL 外 mask=160、内 mask=0，
组合后 cov=160。该点及其左右/上下镜像的最终 PPM 为
SW=(239,235,239)，RND=(231,227,231)，最大差8。
不是 BORDER 半径、宽度或内矩形换算错误。

### 上界估计的范围

对上述三个 FILL 的全部像素及 #184 的完整外/内 mask，比较原始 LVGL mask 与
`rnd_ref.coverage` / RND BORDER 公式，得到如下覆盖率差的**有限域精确最大值**。
同一形状对任意常量前景 RGB888、任意背景 RGB565、OPA=255 的单次正常混合，
可以逐通道枚举得到 RGB565 展开后的界；它不是任意半径、任意后续图层的全帧保证。

| 图元 | 最大 cov 差 | 蓝色 0x2196f3 / 白背景的最大通道差 | 任意颜色的 R/B 上界 | 任意颜色的 G 上界 |
|---|---:|---:|---:|---:|
| #139，238×40，r13 | 63 | 49 | 66 | 65 |
| #252，23×23，r11 | 79 | 66 | 83 | 81 |
| #281，41×41，r20 | 79 | 66 | 83 | 81 |
| #184 BORDER，278×44，r10/w2 | 95 | 82（假设蓝色边框） | 99 | 97 |

这里的任意颜色界同时包含已知 RGB565 mix 舍入差异，仅为界的计算，不处理该类差异。
计算方法是令 n=5（R/B）或6（G），`E_n` 为通道展开，F8 遍历0..255、Bn 遍历0..2^n-1，
并遍历该形状真实 mask 中出现的每一对 `(aR,aS)`：

```
Rn = d(aR*F8 + (255-aR)*E_n(Bn)) >> (8-n)
m  = (aS+4) >> 3
Sn = Bn + floor(((F8>>(8-n))-Bn)*m/32)
bound = max(abs(E_n(Rn)-E_n(Sn)))
```

纯连续颜色的粗估也说明 48 不构成算法上界：#252 的覆盖率差79，
蓝/白的红通道反差222，仅 `222*79/255≈68.78`，就已超过48，尚未计量化；
本次实际 RGB565 差66与这个量级一致。不能把“圆角 AA 允许48”当作由现有两套公式保证的性质。

### 本次验证和复现

只重新生成 widgets 16 ms 的 SW task 参数，未重跑无关 benchmark、完整 RN-17 或目标构建。
临时 C probe 用 `-std=c11 -Wall -Wextra -Werror -O2` 链接现有
`build/s3/lvgl/lvgl_rn17.so`，0 告警；观察 unit 只提供 evaluate 日志，dispatch 始终 IDLE。
输出与 mask/bound 的临时计算程序在 `build/s3/lvgl/corner/`，均非产品代码。
原始 PPM、descriptor 与 RN-17 差异表没有覆盖或变更。

下面的独立片段可以直接重现关键 SW mask 和 RND 整数计算；前提是按前文命令建立同配置
host library。48 是这个 x86_64 host ABI 下 `lv_draw_sw_mask_radius_param_t` 的大小，
由已检查的 LVGL private header 中 dsc/cfg/circle 成员布局得到。

```sh
python3 - <<'PY'
import ctypes as C
from math import isqrt
lib = C.CDLL('build/s3/lvgl/lvgl_rn17.so')
lib.lv_init()
class Area(C.Structure):
    _fields_ = [(k, C.c_int32) for k in ('x1', 'y1', 'x2', 'y2')]
lib.lv_draw_sw_mask_radius_init.argtypes = [C.c_void_p, C.POINTER(Area),
                                          C.c_int32, C.c_bool]
lib.lv_draw_sw_mask_apply.argtypes = [C.POINTER(C.c_void_p), C.POINTER(C.c_uint8),
                                    C.c_int32, C.c_int32, C.c_int32]
lib.lv_draw_sw_mask_free_param.argtypes = [C.c_void_p]
for w, h, r in ((238,40,13), (23,23,11), (41,41,20)):
    p = C.create_string_buffer(48)
    a = Area(0, 0, w-1, h-1)
    lib.lv_draw_sw_mask_radius_init(p, C.byref(a), r, False)
    for j in (0, 1):
        sw = (C.c_uint8*w)(*([255]*w))
        masks = (C.c_void_p*2)(C.addressof(p), None)
        lib.lv_draw_sw_mask_apply(masks, sw, 0, j, w)
        e = 16*r-isqrt(256*r*r-(16*(r-j)-8)**2)
        rnd = [min(255, max(0, 16*(16*(i+1)-e))) for i in range(r+1)]
        print(w, h, r, j, 'SW', list(sw)[:r+1], 'RND', rnd)
    lib.lv_draw_sw_mask_free_param(p)
PY
```

`git diff --check` PASS。本次仅追加本节，不需要改绘制单元或为不存在的换算 bug 添加回归用例。
