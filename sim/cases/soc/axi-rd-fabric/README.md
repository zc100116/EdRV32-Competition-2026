# AXI read fabric directed test

这个 case 同时覆盖 `axi_rd_fabric` 的两个参数分支：

- `u_single`：`M_MAX_OUTSTANDING=1`，对应当前 SoC 的配置；
- `u_multi`：`M_MAX_OUTSTANDING=3`，覆盖通用多 Outstanding 路由。

运行：

```sh
make case-sim CASE=soc/axi-rd-fabric WAVE=1
make case-wave CASE=soc/axi-rd-fabric
```

建议在波形中分别展开：

```text
tb_axi_rd_fabric.u_multi
tb_axi_rd_fabric.u_multi.dut
tb_axi_rd_fabric.u_single
tb_axi_rd_fabric.u_single.dut
```

两个环境都有一个 `stage` 信号，用来标记当前定向场景。

## u_multi.stage

| stage | 场景 |
|---:|---|
| 1 | 同周期 AR/R 的零延迟响应 |
| 2 | Outstanding 上限和释放后的重新准入 |
| 3 | 不同 Slave、不同 ID 的乱序返回 |
| 4 | R Burst 源锁定，禁止同一 Master 的响应交织 |
| 5 | `AXI_MON_ENABLE=0` 时监控输出保持为零 |

## u_single.stage

| stage | 场景 |
|---:|---|
| 1 | 复位和空闲输出 |
| 2 | AR 背压、字段转发和全局 ID 扩展 |
| 3 | 单 Outstanding 准入限制 |
| 4 | 错误 Slave、错误 RID 隔离 |
| 5 | R Burst、Master 背压、响应字段和监控计数 |
| 6 | 两个 Master 访问不同 Slave 的并行传输 |
| 7 | 两个 Master 竞争同一 Slave 的 Round-Robin 仲裁 |
| 8 | 普通地址边界和跨零地址区间 |
| 9 | 无命中、断连、重叠、空区间的完整 DECERR Burst |
| 10 | 读超时、错误上下文、粘滞状态和复位清除 |

testbench 不会在第一个检查失败时立即退出，而是记录所有失败，完成全部场景后
统一 `$fatal`。这样即使发现 RTL 问题，也能保留后续场景的波形。

`stage=10` 按模块注释声明的 fail-stop 语义检查：超时锁存后，旧事务仍可排空，
但该 Master 不得再发出新的 AR。这个检查针对的是接口契约，不会迁就当前实现。

当前 RTL 中 `mon_rd_maxwait_o` 实际按“已接受的 R beat 数”增长，而不是按
AR 到 RLAST 之间的时钟周期增长。case 会检查当前可观察行为，并在包含背压的
Burst 波形中保留这个差异，便于后续单独修正监控器。
