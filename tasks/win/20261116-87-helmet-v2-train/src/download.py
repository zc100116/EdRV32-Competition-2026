"""download.py — T-HELMET-V2 step 1, coordinator-approved author mirror.

Download six CrowdHuman files to the server only. Clock domain: not applicable.
Source change from Google Drive was approved through orchestration ask.
"""

import sys
import urllib.request
from datetime import datetime
from pathlib import Path


root = Path(sys.argv[1])
for name in ["annotation_train.odgt", "annotation_val.odgt", "CrowdHuman_train01.zip",
             "CrowdHuman_train02.zip", "CrowdHuman_train03.zip", "CrowdHuman_val.zip"]:
    print(datetime.now().isoformat(), name, flush=True)
    urllib.request.urlretrieve(
        "https://huggingface.co/datasets/sshao0516/CrowdHuman/resolve/main/" + name,
        root / name)
    print(datetime.now().isoformat(), "done", name, flush=True)
