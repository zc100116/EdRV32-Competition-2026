# RND v2 RN-17 不透明度舍入差异

## 1. 现象

46dba507 的 RN-17 共16帧，15帧通过，benchmark-12-opa-containers 为 FAIL：
full max=1 LSB，edge max=5 LSB，21240/921600=2.304688% 像素超过1 LSB，原阈值1%。
新增旋转、弧、widgets帧通过；原阈值和参考模型均未修改。

## 2. 复现

`python3 tools/s3/rn17.py`；锁定的 LVGL 子模块80ca777，主机确定性时钟，无随机种子。
日志 `build/rnd2/rn17-after-cutout.log`，帧图及描述符 `build/s3/lvgl/benchmark-12-opa-containers-*`。
这是主机C/Python比较，不使用RTL仿真器。

## 3. 观察

| 同场景诊断，仅修改build目录脚本中的执行 | >1 LSB像素比例 | full max |
|---|---:|---:|
| v0.3描述符及8位over | 2.304688% | 1 |
| 省略BOX_SHADOW命令 | 2.433485% | 1 |
| BOX_SHADOW半径约乘2/3 | 2.302734% | 1 |
| 前景按RGB565预量化，OPA按5位权重近似 | 2.130425% | 1 |
| 前景丢弃低位，OPA按5位权重近似 | 1.845269% | 0 |
| RGB565 over替换为LVGL原生混合，其余命令不变 | 0.515082% | 0 |

最后一项：`m=(sa+4)>>3`，先P565前景，再逐565通道计算
`floor((F*m+D*(32-m))/32)`；仅诊断，不改仓库参考模型。
诊断命令为 `python3 build/rnd2/rn17-opa-nativeblend.py --no-build`。

## 4. 根因

LVGL `src/misc/lv_color.c:316`、`src/draw/sw/blend/lv_draw_sw_blend_to_rgb565.c:1610`
使用上述5位权重和RGB565通道向下取整；rnd-spec 2.2使用E565、8位d()舍入和P565。
半透明图元叠加累积差异，既有8位over精度与原生5位量化不相同。
阴影还需按LVGL `src/draw/sw/lv_draw_sw_box_shadow.c:77` 将背景cutout内缩1像素；
该翻译修正使失败比例从2.434570%降到2.304688%，未单独解决舍入差异。

## 5. 修复

驱动已对齐cutout内缩；2026-10-31协调者裁定保持v0.3，不增加FLAGS[15]兼容位。
参考模型、RTL混合、RN-17阈值和测试不设例外；本帧如实保留FAIL。

## 6. 防回归

RN-17保留opa容器帧和1%阈值；主机MASK_RECT原生alpha独立16用例通过，带外最大0/255。
后续若用户选择兼容模式，另开规格和独立验证任务。

## 7. 同类排查

旋转、弧、widgets与opa-layer帧通过；没有以软件降级规避G1–G4认领。
无阴影、半径改变及只改驱动颜色/OPA的诊断均未通过，不能据此修改阴影硬件公式。
