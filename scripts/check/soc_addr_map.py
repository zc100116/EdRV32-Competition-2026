#!/usr/bin/env python3
# ============================================================================
# soc_addr_map.py - EdRV32 competition SoC address-map single source generator.
#
# The machine-readable source of truth is rtl/include/soc_address_map.json.
# Generated outputs (do not edit by hand):
#   rtl/include/edrv32_soc_map.vh   - address/interrupt/APB-slot contract
#   rtl/include/edrv32_pma.vh       - PMA region attribute table
#   sw/hal/include/edrv32_soc_map.h - HAL C header
# Peripheral register offsets/bits are device ABI (hand-maintained in
# rtl/include/edrv32_periph_abi.vh) and intentionally not generated.
#
# Usage (run from anywhere; paths resolve from the script location):
#   python3 scripts/check/soc_addr_map.py generate   # (re)write outputs
#   python3 scripts/check/soc_addr_map.py check      # verify outputs match
# ============================================================================

import json
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))

JSON_PATH = os.path.join(ROOT, "rtl", "include", "soc_address_map.json")
VH_MAP_PATH = os.path.join(ROOT, "rtl", "include", "edrv32_soc_map.vh")
VH_PMA_PATH = os.path.join(ROOT, "rtl", "include", "edrv32_pma.vh")
H_MAP_PATH = os.path.join(ROOT, "sw", "hal", "include", "edrv32_soc_map.h")

GENERATED_NOTE = ("GENERATED FILE - do not edit by hand.  Source of truth: "
                  "rtl/include/soc_address_map.json (2026-09-19 Vision). "
                  "CPU PMA/access permission bits remain inherited from the "
                  "frozen CPU-REWRITE-SPEC-V1.0 contract.  Regenerate with:  "
                  "python scripts/check/soc_addr_map.py generate")


def load_map():
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def num(text):
    return int(text, 16) if isinstance(text, str) else int(text)


def hex32(value):
    """0x1234_ABCD style, always 8 digits with 4-digit underscore groups."""
    return "0x%04X_%04X" % ((value >> 16) & 0xFFFF, value & 0xFFFF)


def vh_base(value):
    return "32'h" + hex32(value)[2:]


def vh_size(value):
    return "32'd%d" % value


def attr_bits(cfg):
    return cfg["pma_attr_bits"]


def attr_vector(cfg, region):
    bits = attr_bits(cfg)
    vec = 0
    for name, bit in bits.items():
        if region["attr"].get(name):
            vec |= (1 << bit)
    width = max(bits.values()) + 1
    return "%d'b" % width + format(vec, "0%db" % width)


def region_by_name(cfg, name):
    for r in cfg["regions"]:
        if r["name"] == name:
            return r
    raise KeyError(name)


def slot_base(cfg, slot):
    return num(region_by_name(cfg, "PERIPH")["base"]) + (slot << 12)


def validate_map(cfg):
    """Validate the architectural names, ranges and alias contracts.

    The generated headers are consumed by RTL and software independently, so
    fail before generation if the JSON could create duplicate or unreachable
    symbols.  In particular, APB slots are the six-bit addr[17:12] field and
    PLIC source zero is architecturally reserved.
    """
    regions = cfg.get("regions", [])
    region_names = [r.get("name") for r in regions]
    if len(region_names) != len(set(region_names)):
        raise ValueError("region names must be unique")
    periph = region_by_name(cfg, "PERIPH")
    periph_base = num(periph["base"])
    periph_end = periph_base + num(periph["size"])

    apb_slots = cfg.get("apb_slots", [])
    apb_names = [s.get("name") for s in apb_slots]
    apb_indices = [s.get("slot") for s in apb_slots]
    if len(apb_names) != len(set(apb_names)):
        raise ValueError("APB peripheral names must be unique")
    if len(apb_indices) != len(set(apb_indices)):
        raise ValueError("APB slot numbers must be unique")
    for slot in apb_indices:
        if not isinstance(slot, int) or slot < 0 or slot >= 64:
            raise ValueError("APB slot %r is outside the six-bit 0..63 range" % slot)
        base = slot_base(cfg, slot)
        if base < periph_base or base + 0x1000 > periph_end:
            raise ValueError("APB slot %d is outside the PERIPH region" % slot)

    apb_formal_names = set(apb_names)
    for alias, target in cfg.get("apb_generic_aliases", {}).items():
        if target not in apb_formal_names:
            raise ValueError("APB alias %s targets missing peripheral %s" %
                             (alias, target))
        if alias in apb_formal_names:
            raise ValueError("APB alias %s conflicts with a formal peripheral" % alias)

    plic_num_sources = cfg.get("plic_num_sources")
    if not isinstance(plic_num_sources, int) or plic_num_sources <= 1:
        raise ValueError("plic_num_sources must be an integer greater than one")
    plic_sources = cfg.get("plic_sources", [])
    plic_names = [s.get("name") for s in plic_sources]
    plic_ids = [s.get("id") for s in plic_sources]
    if len(plic_names) != len(set(plic_names)):
        raise ValueError("PLIC source names must be unique")
    if len(plic_ids) != len(set(plic_ids)):
        raise ValueError("PLIC source IDs must be unique")
    for source_id in plic_ids:
        if (not isinstance(source_id, int) or source_id <= 0 or
                source_id >= plic_num_sources):
            raise ValueError("PLIC source ID %r must be nonzero and below %d" %
                             (source_id, plic_num_sources))

    plic_formal_names = set(plic_names)
    for alias, target in cfg.get("plic_generic_aliases", {}).items():
        if target not in plic_formal_names:
            raise ValueError("PLIC alias %s targets missing source %s" %
                             (alias, target))
        if alias in plic_formal_names:
            raise ValueError("PLIC alias %s conflicts with a formal source" % alias)


# ---------------------------------------------------------------------------
# edrv32_soc_map.vh
# ---------------------------------------------------------------------------

def gen_vh_map(cfg):
    L = []
    w = L.append
    w("// " + "=" * 76)
    w("// File        : edrv32_soc_map.vh")
    w("// Author      : Edward ZC")
    w("// Description : Competition SoC address, interrupt and APB slot contract")
    w("//               for RTL, verification and software.")
    w("//               GENERATED FILE - do not edit by hand.  Source of truth:")
    w("//               rtl/include/soc_address_map.json (2026-09-19 Vision).")
    w("//               CPU PMA/access permissions inherit the frozen CPU-")
    w("//               REWRITE-SPEC-V1.0 contract.")
    w("//               Regenerate with:")
    w("//               python scripts/check/soc_addr_map.py generate")
    w("// Notes       : Peripheral register offsets/bits are device ABI and live")
    w("//               in edrv32_periph_abi.vh (hand-maintained), included at")
    w("//               the end of this file.  64 APB slots decode addr[17:12];")
    w("//               each slot is 4 KiB.  Reserved slots are address-only.")
    w("// " + "=" * 76)
    w("`ifndef EDRV32_SOC_MAP_VH")
    w("`define EDRV32_SOC_MAP_VH")
    w("")
    w("// " + "-" * 76)
    w("// Region base addresses and exact sizes (design section 6.5.1).")
    w("// " + "-" * 76)
    rwidth = max(len(r["name"]) for r in cfg["regions"]) + 5
    for r in cfg["regions"]:
        w("`define SOC_%-*s %s   // %s" % (rwidth, r["name"] + "_BASE", vh_base(num(r["base"])), r["note"]))
        w("`define SOC_%-*s %s" % (rwidth, r["name"] + "_SIZE", vh_size(num(r["size"]))))
    w("")
    w("// " + "-" * 76)
    w("// APB peripheral slot bases within the 0x4 region.  Each slot is 4 KiB,")
    w("// sub-decoded by addr[17:12].  Reserved slots are address-only and")
    w("// produce no RTL (design section 6.5.1).")
    w("// " + "-" * 76)
    swidth = max(len(s["name"]) for s in cfg["apb_slots"]) + 5
    for s in cfg["apb_slots"]:
        base = vh_base(slot_base(cfg, s["slot"]))
        mark = " (reserved)" if s["reserved"] else ""
        w("`define SOC_%-*s %s   // slot 0x%02X - %s%s"
          % (swidth, s["name"] + "_BASE", base, s["slot"], s["note"], mark))
    w("")
    w("// Generic aliases resolve to instance 0.")
    for alias, target in sorted(cfg["apb_generic_aliases"].items()):
        w("`define SOC_%s_BASE   `SOC_%s_BASE" % (alias, target))
    w("")
    w("// " + "-" * 76)
    w("// Address decode fields.")
    w("//   - Coarse decode: addr[31:28] (high nibble) -> region.")
    w("//   - Peripheral sub-decode: addr[17:12] (6 bits -> 64 slots) within")
    w("//     the 0x4 region.")
    w("// " + "-" * 76)
    dec = cfg["decode"]
    w("`define SOC_NIB_MSB     %d" % dec["nib_msb"])
    w("`define SOC_NIB_LSB     %d" % dec["nib_lsb"])
    w("")
    for r in cfg["regions"]:
        if "nib" not in r:
            continue
        macro = r.get("nib_macro", r["name"])
        w("`define SOC_NIB_%-8s 4'h%X" % (macro, int(r["nib"], 16)))
    w("")
    w("`define SOC_PSEL_MSB    %d" % dec["psel_msb"])
    w("`define SOC_PSEL_LSB    %d" % dec["psel_lsb"])
    w("")
    w("// Frozen APB slot codes (design section 6.5.1).")
    for s in cfg["apb_slots"]:
        w("`define SOC_PSEL_%-12s 6'h%02X          // 0x%02X%s"
          % (s["name"], s["slot"], s["slot"], " (reserved)" if s["reserved"] else ""))
    w("")
    w("// Generic aliases resolve to instance 0.")
    for alias, target in sorted(cfg["apb_generic_aliases"].items()):
        w("`define SOC_PSEL_%-8s `SOC_PSEL_%s" % (alias, target))
    w("")
    w("// " + "-" * 76)
    w("// PLIC interrupt source numbering (design section 6.5.1).  Source 0")
    w("// reserved.  Register offsets live in edrv32_periph_abi.vh.")
    w("// " + "-" * 76)
    for src in cfg["plic_sources"]:
        w("`define PLIC_SRC_%-8s 32'd%d" % (src["name"], src["id"]))
    w("`define PLIC_NUM_SOURCES  32'd%-8d // total source count (incl. reserved source 0)"
      % cfg["plic_num_sources"])
    w("")
    w("// Backward-compatible aliases")
    for alias, target in sorted(cfg["plic_generic_aliases"].items()):
        w("`define PLIC_SRC_%-8s `PLIC_SRC_%s" % (alias, target))
    w("")
    w("// Peripheral register ABI (offsets/bit fields, hand-maintained).")
    w("`include \"edrv32_periph_abi.vh\"")
    w("")
    w("`endif // EDRV32_SOC_MAP_VH")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------------------
# edrv32_pma.vh
# ---------------------------------------------------------------------------

def gen_vh_pma(cfg):
    L = []
    w = L.append
    w("// " + "=" * 76)
    w("// File        : edrv32_pma.vh")
    w("// Author      : Edward ZC")
    w("// Description : Competition physical-memory-attribute (PMA) table.  "
      + GENERATED_NOTE)
    w("// Notes       : Every PMA consumer (cache wrapper and future memory")
    w("//               targets) must use this table, never inline bounds.")
    w("//               Per-region PMA_ATTR_*/PMA_SIZE_* macros are the only")
    w("//               encodings.  Region bounds follow edrv32_soc_map.vh.")
    w("// " + "=" * 76)
    w("`ifndef EDRV32_PMA_VH")
    w("`define EDRV32_PMA_VH")
    w("")
    w("`include \"edrv32_soc_map.vh\"")
    w("")
    w("// " + "-" * 76)
    w("// PMA attribute bits per region.")
    bits = attr_bits(cfg)
    desc = {"cacheable": "cacheable (SRAM/DDR canonical)",
            "executable": "instruction fetch allowed",
            "readable": "data load allowed",
            "writable": "data store allowed",
            "idempotent": "idempotent (re-reads stable, safe to probe)",
            "device": "ordered device/MMIO access",
            "tcm_only": "access requires the TCM profile to be enabled",
            "retained": "retains contents across non-POR reset"}
    w("`define PMA_ATTR_WIDTH       %d" % (max(bits.values()) + 1))
    for name, bit in sorted(bits.items(), key=lambda kv: kv[1]):
        w("//   bit%-2d %-11s: %s" % (bit, name.upper(), desc.get(name, name)))
    w("// " + "-" * 76)
    for name, bit in sorted(bits.items(), key=lambda kv: kv[1]):
        w("`define PMA_ATTR_%-11s %d'b%s" % (name.upper(),
                                             max(bits.values()) + 1,
                                             format(1 << bit, "0%db" % (max(bits.values()) + 1))))
    w("")
    w("// Accesses outside every region and accesses to a disabled TCM never")
    w("// reach the fabric.  MEM1 converts them into precise access faults.")
    w("`define PMA_HOLE_FAULT_NO_REQUEST          1'b1")
    w("`define PMA_TCM_DISABLED_FAULT_NO_REQUEST  1'b1")
    w("`define PMA_REGION_COUNT                   %d" % len(cfg["regions"]))
    w("")
    w("// " + "-" * 76)
    w("// Region attributes (frozen competition contract, design section 6.5.1).")
    w("// " + "-" * 76)
    for r in cfg["regions"]:
        w("`define PMA_ATTR_%-11s %s" % (r["name"], attr_vector(cfg, r)))
    w("")
    w("// " + "-" * 76)
    w("// Region sizes (single source; identical values to SOC_*_SIZE).")
    w("// " + "-" * 76)
    for r in cfg["regions"]:
        w("`define PMA_SIZE_%-11s %s" % (r["name"], vh_size(num(r["size"]))))
    w("")
    w("// " + "-" * 76)
    w("// Region table: (name, base, size, attributes) - packed form for table")
    w("// consumers and for reference-model parsers.")
    w("// " + "-" * 76)
    for r in cfg["regions"]:
        w("`define PMA_REGION_%-11s \"%s\",%s`SOC_%s_BASE,%s`PMA_SIZE_%s,%s`PMA_ATTR_%s"
          % (r["name"], r["name"], " " * max(1, 10 - len(r["name"])),
             r["name"], " " * max(1, 10 - len(r["name"])),
             r["name"], " " * max(1, 10 - len(r["name"])), r["name"]))
    w("")
    w("`endif // EDRV32_PMA_VH")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------------------
# sw/hal/include/edrv32_soc_map.h
# ---------------------------------------------------------------------------

def gen_h_map(cfg):
    L = []
    w = L.append
    w("// " + "=" * 76)
    w("// File        : edrv32_soc_map.h")
    w("// Author      : Edward ZC")
    w("// Description : Competition SoC address/interrupt contract for software.")
    w("//               " + GENERATED_NOTE)
    w("// Notes       : Values mirror rtl/include/edrv32_soc_map.vh.  Reserved")
    w("//               APB slots are address-only.  Device register offsets")
    w("//               belong to the HAL driver headers, not this file.")
    w("// " + "=" * 76)
    w("#ifndef EDRV32_SOC_MAP_H")
    w("#define EDRV32_SOC_MAP_H")
    w("")
    w("// Region base addresses and exact sizes (design section 6.5.1).")
    for r in cfg["regions"]:
        w("#define SOC_%s_BASE    0x%08Xu  // %s" % (r["name"], num(r["base"]), r["note"]))
        w("#define SOC_%s_SIZE    0x%08Xu" % (r["name"], num(r["size"])))
    w("")
    w("// APB peripheral slot bases within the 0x4 region (4 KiB per slot).")
    for s in cfg["apb_slots"]:
        mark = " (reserved)" if s["reserved"] else ""
        w("#define SOC_%s_BASE      0x%08Xu  // slot 0x%02X%s"
          % (s["name"], slot_base(cfg, s["slot"]), s["slot"], mark))
    w("")
    w("// Generic aliases resolve to instance 0.")
    for alias, target in sorted(cfg["apb_generic_aliases"].items()):
        w("#define SOC_%s_BASE   SOC_%s_BASE" % (alias, target))
    w("")
    w("// PLIC interrupt source numbering (source 0 reserved).")
    for src in cfg["plic_sources"]:
        w("#define PLIC_SRC_%-8s %du" % (src["name"], src["id"]))
    w("#define PLIC_NUM_SOURCES  %du" % cfg["plic_num_sources"])
    w("")
    for alias, target in sorted(cfg["plic_generic_aliases"].items()):
        w("#define PLIC_SRC_%-8s PLIC_SRC_%s" % (alias, target))
    w("")
    w("#endif // EDRV32_SOC_MAP_H")
    return "\n".join(L) + "\n"


OUTPUTS = (
    (VH_MAP_PATH, gen_vh_map),
    (VH_PMA_PATH, gen_vh_pma),
    (H_MAP_PATH, gen_h_map),
)


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    cfg = load_map()
    validate_map(cfg)
    if mode == "generate":
        for path, gen in OUTPUTS:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(gen(cfg))
            print("wrote %s" % os.path.relpath(path, ROOT))
        return 0
    if mode == "check":
        ok = True
        for path, gen in OUTPUTS:
            expected = gen(cfg)
            try:
                with open(path, "r", encoding="utf-8") as f:
                    actual = f.read()
            except FileNotFoundError:
                print("MISSING %s" % os.path.relpath(path, ROOT))
                ok = False
                continue
            if actual != expected:
                print("MISMATCH %s (regenerate with: python scripts/check/soc_addr_map.py generate)"
                      % os.path.relpath(path, ROOT))
                ok = False
            else:
                print("OK %s" % os.path.relpath(path, ROOT))
        return 0 if ok else 1
    print("usage: soc_addr_map.py generate|check", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
