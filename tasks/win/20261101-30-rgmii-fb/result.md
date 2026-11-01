# 卡30结果（A已完成，B待执行）

- 分支win/20261101-30-rgmii-fb，任务输入921ca8fc。
- A采用仓库外厂商工程副本，目标PG2L200H-6/FBB676，ref_clock重新生成、参数保持内部反馈125MHz/30度。
- PC添加192.168.1.105被Windows权限拒绝；用户明确要求仅改例程PC目的地址为192.168.1.2，并重新实现/下载。该授权覆盖卡中A阶段RTL不改的原要求；未改RGMII/PLL/FDC或资料包原件。

## A通信结果

ARP成功，板端MAC a0:b1:c2:d3:e1:e1；ping5/5，0丢包、<1ms。UDP采集60.075920s，PC发60包、收到60条板端固定20字节消息，60条内容均一致，异常0。不是UDP echo，不能将收发数相同解释为逐包回环全部成功或完整UDP丢包率为0。

完整测试方法、差异说明、PC输出、每包记录、PLL/缓冲站点与时序原文见 [A结果](artifacts/vendor/result.md)。原厂报告All Constraints Met，但厂商FDC没有RGMII输入/输出延迟约束，结论受覆盖范围限制。没有pcap。

## B

尚未重新生成B3V的ip_pll_eth；需External Feedback、Feedback from CLKOUT0、125MHz/0度，并确认clkfb端口。后续实现、双工艺角RX详细路径、10次PHY复位和60秒视频仍待完成，不宣称整卡完成。
