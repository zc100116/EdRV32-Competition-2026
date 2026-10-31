# 地址和引擎寄存器头文件

从仓库根目录执行：

```sh
python3 tools/gen/soc_map.py
python3 tools/gen/regs.py
```

`soc_map.py` 从 `rtl/include/soc_address_map.json` 生成 SoC 基址和地址属性。
`regs.py` 从 `rtl/include/regs/*.json` 生成
`sw/bsp/include/regs/<模块>_regs.h`，只使用 Python 标准库，无命令行参数。
输入文件按文件名排序，文件内按描述顺序输出；重复执行得到相同内容，不含时间戳。
JSON 和生成的 C 头文件一起入库，修改描述后重新生成，不手改头文件。

覆盖 VIN、PIX、GEO、DISP、NPU、ETH、MEM_XBAR 的公共与私有寄存器；
另含 NPU 描述符、ETH 发送描述符和 ETH 应用头的字段表。
规格依据为各模块第 4 节、SoC 第 7.1 节，描述符和应用头另见 NPU 4.1、ETH 2.6/2.3。
MEM_XBAR 端口复位值另引用 SoC 6.4.5。

## JSON 格式

每个文件含 `module`、`spec`、`note`、`registers`、`layouts`。
`spec` 是规格文件和章节，寄存器与字段也逐项注明来源。
`note` 记录表中补充说明与命名约定。

寄存器条目：

| 键 | 含义 |
|---|---|
| `name` | 寄存器名；`CHn_*`、`WINn_*` 用 `CH_*`、`WIN_*`，下标放入维度 |
| `offset` | 十六进制字节偏移字符串，重复寄存器填写下标为 0 的偏移 |
| `access` | 规格中的 RO、RW、WO 或 RW1C；未使用寄存器仍保留公共布局的访问类型 |
| `reset` | 整数、`null`，或按端口下标排列的整数/`null` 数组 |
| `reset_status` | `unspecified` 表示规格未给复位值，`not_applicable` 表示 WO 的破折号 |
| `dimensions` | 按顺序列出 `index`、`count`、`stride`（字节）；所有下标从 0 起 |
| `fields` | 位域表，每项含 `name`、`lsb`、`width`、`spec` |

重复寄存器偏移为 `offset + Σ(stride × index)`，如 VIN 通道与槽有两个维度。
只为规格明确给出的位范围生成位域；不从取值范围、地址对齐推定位宽。
没有单独位域名的范围以 `VALUE` 命名，同一寄存器有多个未命名范围时用
`VALUE_<高位>_<低位>` 或 `VALUE_<位号>` 区分；这些是工具命名约定。
公共位名保留 SoC 7.1 的定义，具体引擎可能不使用其中某些位，行为以模块规格为准。

`layouts` 中每个字段表含 `name`、`size`（字节）、`byte_order`、`spec`、`fields`；
每个字段含 `name`、`offset`（字节偏移字符串）、`lsb`、`width`、`spec`。
描述符的位位置相对于该字段所在的 32 位字，字偏移乘 4 得到字节偏移。
ETH 应用头的位位置相对于相应字段；多字节 OFFSET 按网络字节序编码。
保留或忽略的区域在 `note` 中说明，不为它们编造字段名。

## C 接口

公共前缀为 `EDRV32_<模块>_`：

- `<寄存器>_OFFSET`：字节偏移；重复寄存器为带下标参数的宏。
- `<寄存器>_<下标名>_COUNT`：该维度的条目数。
- `<寄存器>_RESET`：规格给出的统一复位值。
- `<寄存器>_RESET_<端口号>`：按端口给出的复位值；`null` 不产生复位宏。
- `<寄存器>_<位域>_POS`、`_WIDTH`、`_MASK`：位位置、宽度、已经移位的掩码。
- `<字段表>_SIZE`、`<字段表>_<字段>_OFFSET`：记录大小和字段的字节偏移；
  另有对应的 `_POS`、`_WIDTH`、`_MASK`。

例如使用已有 BSP include 路径即可包含头文件，`sw/Makefile` 已提供该路径：

```c
#include "soc_map.h"
#include "regs/vin_regs.h"
#include "regs/npu_regs.h"

/* CH2 槽 1 的 Surface 地址寄存器。 */
uintptr_t address = EDRV32_VIN_BASE + EDRV32_VIN_CH_SURF_BASE_OFFSET(2, 1);

/* 位域值先移位再掩码；描述符字段 OFFSET 已是字节单位。 */
uint32_t shape = (height << EDRV32_NPU_DESC_IN_H_POS) & EDRV32_NPU_DESC_IN_H_MASK;
```

示例中的 `uintptr_t`、`uint32_t` 由调用方包含 `<stdint.h>` 提供；头文件本身只定义常量。
生成宏不执行 MMIO 读写或字节序转换。

## 编译检查与重复生成

`sw/tests/regs_check/main.c` 同时包含全部生成头文件和 `soc_map.h`，
每个模块选取五个寄存器，以 `_Static_assert` 对照带章节注释的规格数字；
另检查描述符、应用头的字节偏移和位域。

```sh
. ~/.local/opt/edrv32/env.sh
python3 tools/gen/regs.py
mkdir -p build/sw/regs_check
riscv-none-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -std=c11 \
    -Wall -Wextra -Werror -Isw/bsp/include \
    -c sw/tests/regs_check/main.c -o build/sw/regs_check/regs_check.o
```

也可使用统一构建入口 `make -C sw PROGRAM=regs_check`。
在已提交描述及生成头文件的工作树中验证重复生成：

```sh
python3 tools/gen/regs.py
git diff --exit-code -- sw/bsp/include/regs
python3 tools/gen/regs.py
git diff --exit-code -- sw/bsp/include/regs
```
