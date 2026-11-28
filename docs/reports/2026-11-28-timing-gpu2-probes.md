# GPU v2 算术与存储探针布局布线（卡 112）

- 源码：`35ec01496`；结果分支 `win/20261128-112-gpu2-probes`（`107d25118`），原始报告在该分支 `tasks/win/20261128-112-gpu2-probes/artifacts/`。
- 工具：PDS 2022.2-SP6.1 build 138931，PG2L200H-6 FBB676，默认 P&R；单时钟 `clk_i` 4.545 ns（220 MHz）；Slow Corner。

| 探针 | WNS / TNS ns | Fmax MHz | LUT / FF | DRM / APM / 分布式 RAM | CLMA / CLMS |
|---|---:|---:|---:|---:|---:|
| fp32（vec4+DP） | −4.078 / −2673.0 | 116.0 | 8241 / 5045 | 0 / 8 / 80 | 2046 / 732 |
| sfu | −2.712 / −579.8 | 137.8 | 4546 / 3862 | 15 / 4 / 60 | 1237 / 343 |
| setup（N48/49×33/60） | −4.188 / −1115.5 | 114.5 | 1337 / 1362 | 0 / 6 / 0 | 386 / 96 |
| banks（DRM 映射） | +0.444 / 0 | 243.8 | 1589 / 15362 | 159 / 0 / 0 | 3266 / 808 |
| banks_lutram | +0.698 / 0 | 259.9 | 4901 / 21986 | 15 / 0 / 3312 | 3517 / 1617 |

关键段（Slow Corner setup 裕量）：

| 段 | 裕量 ns | PDS 逻辑级 |
|---|---:|---:|
| fp32 APM 尾积 → `tap_s6_increment_r` | −4.078 | 15 |
| fp32 DP 第一级 `product_o → s1_small_r` | −3.703 | 15 |
| fp32 DP 舍入 `s2_sum_r → result_o` | −3.285 | 14 |
| fp32 DP 对齐加法 `s1_small_r → s2_sum_r` | +2.701 | 6 |
| sfu 请求 → 种子 ROM 地址 | −2.712 | 14 |
| sfu scratch DRM 读出 → `s1_a_exp_r` | −2.342 | 10 |
| sfu `s6_c_r → s7_forward_r` | +1.772 | — |
| setup N48 首拍 `mantissa_r → truncated_r` | −4.188 | 27 |
| APM 原语级联（三探针） | +2.73 | — |
| banks DRM 读出 → 捕获 / LUTRAM 版 | +0.444 / +1.422 | 0 |

DRM 同址读写（ModelSim SE-64 2020.4，厂商 GTP_DRM 模型，`src/check_drm_collision.do`）：sdp72/sdp36 同沿读旧字、下次读新字；sfu scratch 包装转发新字；PASS。

与上一版本对比：本卡为 GPU v2 首次 PDS 测量，无同口径前版。
