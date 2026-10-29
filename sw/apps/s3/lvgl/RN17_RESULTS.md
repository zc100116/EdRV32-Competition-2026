# RN-17 定稿容差主机结果

日期：2026-10-29。集成基线 `34a49ee`；本次被测 C 实现 `4053b9a`，主机工具 `80e54f5`。
判据来自用户确认的 `docs/testplan/rnd-testplan.md` 第 6 节（`ef191bf`），
LVGL v9.6.0 子模块仍为 `80ca777e37a2b176770726a02e07a6fb79ef0b39`。
没有修改绘制算法、edge mask 分类、规格或 testplan。

## 当前判定和输出

两边原始 RGB565 像素直接拆成 R5/G6/B5 后逐通道相减，单位为相应通道的最低位：

- 全覆盖区（两边覆盖率均255）的每个通道差≤1 LSB。
- 全帧中任一通道差>1 LSB 的像素数≤全帧的1%，含等号。
- 边缘（任一覆盖率不为255，以及 BOX_SHADOW 区域）没有单像素上限。

`rn17_compare.c:s3_compare_pixels` 共用逐像素统计；`s3_compare_passes` 共用判定。
板上 UART 和 Python runner 都调用这两个 C 实现，Python 不复制判定公式。
原有 8 位通道统计字段及旧判定已删除。
每帧统计 full_max_lsb、edge_max_lsb、>1 LSB 像素数和比例、五档分布、PASS/FAIL。
五档是像素最大 R5/G6/B5 通道差为0、1、2、3–4、≥5 LSB的计数。

## 11 帧重跑结果

每帧921600像素，`RND/SW` 是混合渲染中实际认领/未认领的任务数，不含纯 SW 参考重画。

**11 帧全部 PASS，runner 返回0。** 全覆盖区最大差均为1 LSB，
超过1 LSB的像素比例最大为0.464844%（4284/921600，containers场景）。

frame|full max LSB|edge max LSB|>1 LSB pixels|>1 LSB %|RND/SW tasks|bins|result
---|---:|---:|---:|---:|---:|---|---
widgets-16|1|8|1736|0.188368|62/0|[881741, 38123, 922, 792, 22]|PASS
widgets-176|1|8|1736|0.188368|62/0|[881741, 38123, 922, 792, 22]|PASS
widgets-656|1|8|1761|0.191081|62/0|[881274, 38565, 947, 792, 22]|PASS
benchmark-00-empty|1|1|0|0.000000|5/0|[912999, 8601, 0, 0, 0]|PASS
benchmark-02-rectangle|1|2|151|0.016385|6/0|[912234, 9215, 151, 0, 0]|PASS
benchmark-04-rgb-images|1|2|151|0.016385|26/0|[912187, 9262, 151, 0, 0]|PASS
benchmark-05-argb-images|1|2|886|0.096137|26/0|[902040, 18674, 886, 0, 0]|PASS
benchmark-06-rotated-images|1|2|151|0.016385|5/10|[912090, 9359, 151, 0, 0]|PASS
benchmark-07-labels|1|2|1720|0.186632|40/0|[893756, 26124, 1720, 0, 0]|PASS
benchmark-10-containers|1|6|4284|0.464844|78/0|[895654, 21662, 1643, 2523, 118]|PASS
benchmark-13-opa-layer|1|4|2642|0.286675|278/0|[672306, 246652, 2538, 104, 0]|PASS

实际 `rnd_ref` 执行总量：{'batches': 668, 'commands': 2891, 'pixels': 21168044}。

## 命令与验证

所有生成物都在本 worktree 自己的 `build/` 中，没有复用其他 worktree 的编译/链接产物。
主机 GCC 13.3.0、Python 3.12.3；目标 xPack riscv-none-elf-gcc 15.2.0。
C11 `-O2 -Wall -Wextra -Werror -ffreestanding -fno-builtin`，无第三方告警豁免。
主机/板上使用同一 lv_conf、DIRECT RGB565 1280×720 双缓冲、batch=32。

```sh
python3 tools/s3/lvgl_host.py > build/s3/lvgl/build-lsb.log 2>&1
python3 tools/s3/rn17.py --no-build > build/s3/lvgl/rn17-lsb.log 2>&1
. ~/.local/opt/edrv32/env.sh
make -C sw PROGRAM=s3 MEMORY=ddr_app -j1 > build/s3/lvgl/s3-build-lsb.log 2>&1
PYTHONPYCACHEPREFIX=build/s3/pycache python3 -m py_compile tools/s3/rn17.py
git diff --check
```

- 主机510个C源编译并链接共享库：PASS，0告警；`build-lsb.log`。
- `python3 tools/s3/rn17.py --no-build`：返回0，11帧全部PASS；`rn17-lsb.log`。
- 完整 `make -C sw PROGRAM=s3 MEMORY=ddr_app -j1`：返回0，0 warning、0 error；
  本worktree的 `build/sw/s3/s3.elf` 和 `.map`，完整日志 `s3-build-lsb.log`。
- 共用C判定的定向边界检查：PASS；1 LSB的R/G/B均允许，全覆盖区2 LSB拒绝，
  单个边缘63 LSB在100像素中允许，两个>1 LSB边缘像素在100像素中拒绝，验证1%含等号；
  C11 `-Wall -Wextra -Werror` 编译的临时检查在 `build/s3/lvgl/lsb-check.c` / `.log`。
- 两次benchmark退出后菜单保持不变的检查：PASS；真正benchmark结束回调已执行。
- Python语法与 `git diff --check`：PASS。

完整ELF为RISC-V ELF32，入口 `0x90000000`；`riscv-none-elf-size` 给出
text=1119908、data=1408、bss=53206592，共54327908字节（不含运行期栈）。

真正板上 RN-17、边缘目视检查和benchmark FPS仍待上板；host时钟人工推进的FPS不是硬件性能。

runner 执行真实 widgets 三帧和 benchmark 八场景，由真实 LVGL 任务生成原始64 B描述符和源数据，
交仓库 `rnd_ref.execute` 执行并写回目标内存；没有用 SW 替代 RND。
CPU idle 文本由 Linux sysmon 采样，重复运行时该文字及少量涉及像素的计数可能改变；
每一对 SW/RND 比较期间时间和 UI 内容均冻结。
`build/s3/lvgl/` 保留22张 `*-sw.ppm` / `*-rnd.ppm`、11份 `*.commands.bin`、
当前 `rn17-results.md` 和 `rn17-lsb.log`。所有生成物不入库。

## 旧初值的历史说明

定稿前曾按展开后的8位通道统计，11帧均超出当时开发初值；
随后的 A2 核对确认圆角坐标/半径换算正确，差异来自两套覆盖率算法。
用户据此确认现在的 RGB565 LSB 判据；旧判据结果表已删除，详细旧数据保留在 git 历史中，
不作为当前验收标准。下面仅保留 A2 的参数、像素与算法推导依据。

## A2 历史说明：圆角 FILL / BORDER 差异归因

### 结论与参数核对

**归类：rnd-spec 2.3 与 LVGL v9.6 软件圆角光栅算法的固有差异，未发现绘制单元换算错误。**
A2 当时未修改 `draw_rnd.c`、参考模型、LVGL 或规格；被分析实现为 `e45a150`
及其父提交（集成为 `34a49ee`）。下述 RGB 读数/8 位上界仅保存历史归因依据，
不再用于容差判定；现行判定及唯一的逐帧统计表是前面的 LSB 表。

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

历史上，纯连续颜色的粗估说明 8 位差48不构成算法上界：#252 的覆盖率差79，
蓝/白的红通道反差222，仅 `222*79/255≈68.78`，就已超过48，尚未计量化；
当时观察到的展开通道差66与这个量级一致；这项归因是用户最终改用 LSB 容差的依据之一。

### A2 当时的验证和复现

只重新生成 widgets 16 ms 的 SW task 参数，未重跑无关 benchmark、完整 RN-17 或目标构建。
临时 C probe 用 `-std=c11 -Wall -Wextra -Werror -O2` 链接现有
`build/s3/lvgl/lvgl_rn17.so`，0 告警；观察 unit 只提供 evaluate 日志，dispatch 始终 IDLE。
输出与 mask/bound 的临时计算程序在 `build/s3/lvgl/corner/`，均非产品代码。
A2 未修改当时的样本；A3 已重跑样本，并以定稿 LSB 统计替换旧判据结果表。

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

A2 的 `git diff --check` PASS；仅追加归因，没有改绘制单元或为不存在的换算 bug 添加回归用例。
