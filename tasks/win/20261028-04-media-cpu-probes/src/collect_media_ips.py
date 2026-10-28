"""Record generated MEDIA IP settings and wrapper connections, without editing IP/RTL."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET


REPO = Path(__file__).resolve().parents[4]
TASK = REPO / "tasks/win/20261028-04-media-cpu-probes"
IP_ROOT = REPO.parent / "EdRV32-FPGA/EdRV32-MEDIA/ipcore"
OUT = TASK / "artifacts/media/ip"
NAMES = ("ip_ram_vin_wfifo", "ip_ram_disp_scan", "ip_ram_pix_line",
         "ip_ram_geo_src", "ip_ram_eth_buf", "ip_ram_eth_fifo")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    summary = ["# MEDIA 生成 IP 配置与端口", "",
               f"来源：`{IP_ROOT.as_posix()}`。直接读取 .idf、生成顶层 .v 和 generate.log。",
               "未修改生成文件、RTL包装或IP配置；未做IP仿真。DRM数量来自已完成的MEDIA PnR层次报告。", "",
               "| IP | 写深度×位宽 | 读深度×位宽 | 输出寄存器 | 读使能 | 包装端口集合 | DRM块数 |",
               "|---|---|---|---|---|---|---|"]
    for name in NAMES:
        prr = (IP_ROOT.parent / "place_route/edrv32_fpga_media_top.prr").read_text(encoding="utf-8")
        resource_row = next(line for line in prr.splitlines() if "U_ipm2l_sdpram_" + name in line)
        blocks = float(resource_row.split("|")[6].strip())
        drm_count = "1 DRM18K" if blocks == 0.5 else f"{blocks:g} DRM36K"
        folder = IP_ROOT / name
        xml = ET.parse(folder / f"{name}.idf").getroot()
        params = {p.findtext("name"): p.findtext("value")
                  for p in xml.findall("param_list/param")}
        generated = (folder / f"{name}.v").read_text(encoding="utf-8")
        header = re.search(r"module\s+" + name + r"\s*\((.*?)\);", generated, re.S)[1]
        ports = re.findall(r"\b\w+\b", re.sub(r"//[^\n]*", "", header))
        wrapper_path = REPO / "rtl/tech" / f"edrv32_{name[3:]}.v"
        wrapper = wrapper_path.read_text(encoding="utf-8")
        inst = re.search(r"\b" + name + r"\s+u_ip\s*\((.*?)\);", wrapper, re.S)[1]
        connections = re.findall(r"\.(\w+)\s*\(([^)]+)\)", inst)
        matched = set(ports) == {p for p, signal in connections}
        write_shape = f"{2**int(params['WR_ADDR_WIDTH'])}×{params['WR_DATA_WIDTH']}"
        read_shape = f"{2**int(params['RD_ADDR_WIDTH'])}×{params['RD_DATA_WIDTH']}"
        summary.append(f"| {name} | {write_shape} | {read_shape} | {params['OUTPUT_REG']} | "
                       f"{params['RD_CLK_EN']} | {'一致' if matched else '不一致'} | {drm_count} /实例 |")
        lines = [f"IP: {name}", f"IDF: {(folder / (name + '.idf')).as_posix()}",
                 f"Type: {xml.findtext('header/display_name')}",
                 f"Device: {xml.findtext('header/device')}, "
                 f"{xml.findtext('header/package')}, {xml.findtext('header/speedgrade')}",
                 f"Wrapper: {wrapper_path.as_posix()}",
                 f"Write: depth x width = {write_shape}; address width={params['WR_ADDR_WIDTH']}",
                 f"Read: depth x width = {read_shape}; address width={params['RD_ADDR_WIDTH']}",
                 f"Port names match wrapper: {matched}", "", "Actual port declarations:"]
        lines += [line.strip() for line in generated.splitlines()
                  if re.match(r"^\s*(input|output)\s", line)]
        lines += ["", "Wrapper connections:"] + [f".{p}({s})" for p, s in connections]
        lines += ["", "Actual IDF settings:"] + [f"{k}={v}" for k, v in sorted(params.items())]
        log = (folder / "generate.log").read_text(encoding="utf-8")
        lines += ["", "Generation log excerpt:"] + [line for line in log.splitlines()
                  if line.startswith(("IP Generator", "Instance:", "IP:", "Part:",
                                      "Synthesis is disabled", "Done:"))]
        lines += ["", f"Actual DRM block count: {drm_count} per instance; source: final MEDIA PRR hierarchy.",
                  "IP option screenshot: 未取得；当前没有选项截图文件，未操控桌面采集。"]
        (OUT / f"{name}.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    summary += ["", "共同设置：RD_CLK_EN=true、OUTPUT_REG=false、WR_BYTE_EN=false、INIT_EN=false、",
                "INIT_FILE=NONE、WR_CLK_EN=false、读写地址 strobe 均关闭；复位为 ASYNC，",
                "包装将 wr_rst/rd_rst 接 1'b0。DISP/ETH FIFO 的两个时钟端口独立连接。", "",
                "GEO：SAMEWIDTH_EN=false，写地址8位/数据128位，读地址11位/数据16位。",
                "生成 RTL 的 wr_data_mix_bus、地址移位和 rd_full_data 拼接关系",
                "按读地址低3位选择同一写项的连续16位，低位在低地址；",
                "这是静态连接关系推导，与包装的 r[10:3] / r[2:0] 定义一致，未运行 IP 仿真。", "",
                "DRM 模式：ETH FIFO 为18K，其余为36K；这是 CAS_MODE，不是已测得的块数。",
                "六份 generate.log 均为 Done: 0 error(s), 0 warning(s)，且 Synthesis is disabled。",
                "DRM块数已由PnR报告补充：整个MEDIA为8 DRM18K + 42 DRM36K。选项PNG截图未取得。", "",
                "6个 .idf 均位于上述 ipcore 目录；导入时沿用 MEDIA 工程中已有的 IP 引用。"]
    (OUT / "ip_summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print("Recorded six MEDIA IPs under", OUT)


if __name__ == "__main__":
    main()
