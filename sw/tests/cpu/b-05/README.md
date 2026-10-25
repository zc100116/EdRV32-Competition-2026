# B-05

老 M 级访问异常与年轻 E/D 重定向竞争。

档位：`full`。

检查：oldest_fault 的 M 异常优先，mepc/mtval 正确，无年轻副作用；必须观测 M 异常、E 重定向、D 重定向同拍，否则本场景未覆盖。

B1 激励：scratch load 返回访问错误；I$ 全命中，观察 priority_branch/priority_jal 重叠。

Spike：仅冒烟（`SPIKE_SMOKE`），仅 B1 的检查见上述判据；该运行不能替代 B1 通过结果。

可执行配置约定、符号解析与构建见 [公共说明](../README.md)。
