"""Export MEDIA r4 timing from the existing routed database."""
from pathlib import Path
import importlib.util
from concurrent.futures import ThreadPoolExecutor

REPO=Path(__file__).resolve().parents[4]
BUILD=REPO/"build/win/20261029-01-media-r4"
path=REPO/"tasks/win/20261028-04-media-cpu-probes/src/export_timing.py"
spec=importlib.util.spec_from_file_location("previous_export",path)
export=importlib.util.module_from_spec(spec)
spec.loader.exec_module(export)
export.BUILD=BUILD

if __name__=="__main__":
    db=REPO.parent/"EdRV32-FPGA/EdRV32-MEDIA/place_route/edrv32_fpga_media_top_pnr.adf"
    jobs=[("media_top200",db,"-max_path 200 -input_pins TRUE"),
          ("media_near",db,"-delay_type max -max_path 100000 -slack_greater_than 0 -slack_less_than 1 -input_pins TRUE"),
          ("media_violating",db,"-delay_type max -max_path 100000 -slack_less_than 0 -input_pins FALSE"),
          ("media_disp",db,"-delay_type max -max_path 200 -to {u_disp/*} -input_pins TRUE")]
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(export.export,jobs))
