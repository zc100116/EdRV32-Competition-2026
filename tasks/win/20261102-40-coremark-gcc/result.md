# 卡40：CoreMark编译器和编译选项对比结果

| 项 | 内容 |
|---|---|
| 代码输入 | 5aeb2c1a9522f605ff8d4c1247bf17c3c448dfb1（卡40八个程序已交付） |
| 程序构建源码 | 23cc1643bfd02fe80fcf6dd17af6b3063805148c，依src/variants.md |
| bitstream | 用户确认：卡34 B1-ILA；本次8组共用 |
| 器件 / 时钟 | PG2L200H-6 FBB676；日志CLK_SYS_HZ=100000000 |
| 串口 | COM7，115200，8N1 |
| 测试方式 | 每组KEY1+复位进入BIOS，加载SRAM monitor，地址/入口0x10000000；各跑5000次、两轮HPM |
| 结论 | 8/8 CoreMark PASS；16/16轮CRC result PASS；8组Score status均duration >= 10 s，无需8000重跑 |

## 分数和第1轮HPM

以下分数直接抄录串口显示，未重算CoreMark/MHz精度。

|变体|Compiler version|Iterations|Iterations/Sec|CoreMark/MHz|Score status|CRC / CoreMark|第1轮cycles / instructions|
|---|---|---:|---:|---:|---|---|---|
|g15-o2|GCC 15.2.0|5000|360.326|3.603|≥10s|PASS / PASS|1387629662 / 1441025033|
|g15-tuned|GCC 15.2.0|5000|435.438|4.354|≥10s|PASS / PASS|1148269092 / 1239834691|
|g15-peer|GCC 15.2.0|5000|390.162|3.901|≥10s|PASS / PASS|1281515693 / 1367429982|
|g15-combo|GCC 15.2.0|5000|424.627|4.246|≥10s|PASS / PASS|1177502301 / 1237199692|
|g16-o2|GCC 16.1.0|5000|357.562|3.575|≥10s|PASS / PASS|1398357428 / 1424251847|
|g16-tuned|GCC 16.1.0|5000|422.505|4.225|≥10s|PASS / PASS|1183415430 / 1244278640|
|g16-peer|GCC 16.1.0|5000|388.339|3.883|≥10s|PASS / PASS|1287533338 / 1351024982|
|g16-combo|GCC 16.1.0|5000|427.193|4.271|≥10s|PASS / PASS|1170429108 / 1238266827|

## 比较

本轮最高为GCC15.2 tuned，4.354 CoreMark/MHz、435.438 Iterations/Sec；GCC16.1中最高为combo，4.271 CoreMark/MHz。对方条件g16-peer为3.883 CoreMark/MHz，本机本轮未超过我们tuned方案。该结论限于本卡的同一硬件及8组各一次跑分，没有重复测量，不作为统计稳定性结论。

## 第2轮HPM和日志定位

|变体|第2轮cycles|第2轮instructions|串口seq区间|
|---|---:|---:|---|
|g15-o2|1387628281|1441025033|1–101|
|g15-tuned|1148266737|1239834691|102–201|
|g15-peer|1281513567|1367429982|202–301|
|g15-combo|1177500004|1237199692|402–501|
|g16-o2|1398356012|1424251847|302–401|
|g16-tuned|1183413092|1244278640|502–601|
|g16-peer|1287531098|1351024982|602–701|
|g16-combo|1170427310|1238266827|702–801|

## 编译条件和校验记录

完整编译选项见src/variants.md，各程序实际输出的Compiler version/Compiler flags原文均在对应artifacts/uart/<变体>.log中。变体按每组跑分末尾程序打印的编译器及选项归类：实际测试顺序是g15-o2、g15-tuned、g15-peer、g16-o2、g15-combo、g16-tuned、g16-peer、g16-combo，表格按任务卡顺序排列。

每轮CRC seed=0x0000e9f5、list=0x0000e714、matrix=0x00001fd7、state=0x00008e3a、final=0x0000bd59；seed/list/matrix/state和总体校验均PASS。日志保留每轮计数、全部HPM事件行及两轮CRC，没有仅保留最终分数。

## 问题与偏离

- 每次复位BIOS启动横幅都打印其固有Build commit d5d16c34和GCC15.2；这是加载前的启动镜像信息，不能用它给随后加载的程序归类。实际跑分程序在每组结尾打印Compiler version/Compiler flags，已依此区分GCC15.2/16.1。未通过BIOS横幅冒充确认下载镜像的构建版本。
- 原始完整会话为artifacts/uart/session.log；每变体日志同时包含其加载前BIOS与加载结果，方便区分。导出自工具API缓冲，保留时间、方向和seq；这是工具解码后的文本日志，不声称为原始字节流.raw。
- 没有修改源码、重新构建软件或运行PDS/仿真；没有影响正在运行的布局布线。任务要求的八组结果均已取得。
