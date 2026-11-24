# 升级候选不足导致长录像崩溃

## 1. 现象
基线8e7d2e950，seed20261124的现有海岸录像，在尝试12升13级时崩溃。
Linux完整构建和短定向用例通过，但headless与纯模拟都收到SIGILL。

## 2. 复现
环境：Linux x86-64，GCC13.3，C11；输入为assets/replays/coast.txt（10800帧）。
在基线提交构建并运行：
```sh
make -C sw/apps/ember_isles linux test -j1
build/ember_isles/sim-replay sw/apps/ember_isles/assets/replays/coast.txt
```
基线纯模拟退出132；同输入的headless也崩溃。
调试日志：build/g2/e4-{pc,sim-only,sim-sanitize,before-pool}.log。

## 3. 观察
ASan/UBSan将故障定位到基线sim.c:1492的取模。
仅在临时副本中打印抽取参数，实际第6984帧：
```text
CHOICE frame=6984 level=12 slot=2 count=0 total=0
```
前两项已抽完，第三项没有普通候选；不是GPU或平台指令集问题。
临时副本build/g2/e4-before-pool.c来自git show 8e7d2e950，仅插入观测输出。

## 4. 根因
upgrade_offer固定抽三次；移除每次选中的条目后，未处理普通候选不足三项的规则。
两个武器仍可升级，铭文与遗物槽已满时只剩两项，第三次执行random % 0。
GDD第6节4ca15ec09已经定义资源补位，当前升级流程尚未接入。

## 5. 修复
先按权重抽取至多三项现有普通候选，再以资源补位填满剩余位置；补位不重复。
upgrade_fillers.csv保存回复30%生命、金币40、灯油30（内部3000）的初值和中文说明。
选择种类5表示资源补位，UI读取该表；治疗走原治疗结算，灯油遵守0–100上限。
补位不改变永久属性；普通候选足够时抽取流程和随机数调用数保持一致。
满槽替换、商店和10/20/30级稀有保底仍属于E5，不在本修复中冒充完成。

## 6. 防回归
新增普通候选分别为0、1、2项的定向情形，检验三选一完整和补位不重复。
分别选择三种补位，验证资源量及属性数组保持不变。
e4_verify.py共8087条断言通过；日志build/g2/e4-upgrade-fillers.log。
修复版ASan/UBSan运行满10800帧，没有运行时检查异常。
该旧录像在新内容中停于升级界面，旧工具因胜利断言退出1，不能作为通关通过。
实际日志build/g2/e4-sim-fixed.log；唯一FAIL为demo must clear five waves。

## 7. 同类排查
当前CSV固定分类池：传说遗物8、普通遗物8、稀有铭文9，检查了另三处分类抽取。
没有将不完整的商店、替换流程或完整两模式通关计为已验证。

## 8. 状态
该修复由首次新增data/upgrade_fillers.csv的提交标识，可复现查询：
```sh
git log --diff-filter=A --format=%h -- sw/apps/ember_isles/data/upgrade_fillers.csv
```
四目标重建和PC/Spike摘要比对结果记录在report-c1.md；完整E4仍待四项玩法答复。
