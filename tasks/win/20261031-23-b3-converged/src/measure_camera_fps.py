from pathlib import Path
import urllib.request,json,time,re
O=Path(__file__).resolve().parents[1] / "artifacts/b3v/camera"
O.mkdir(parents=True,exist_ok=True)
def api(p,b=None):
 q=urllib.request.Request("http://127.0.0.1:8765/api/"+p,data=None if b is None else json.dumps(b).encode(),headers={"Content-Type":"application/json"});return json.load(urllib.request.urlopen(q,timeout=5))
def sample():
 before=api("buffer?since=0&limit=1")["lastSeq"]
 api("send",{"text":"status","ending":"cr"})
 time.sleep(1)
 data=api(f"buffer?since={before}&limit=5000")["entries"]
 fields={}
 for x in data:
  m=re.match(r"(VIN camera[01] frames|VIN CH0 overflow|Video skips \(current window\)|mtime): (\d+)",x["text"])
  if m:fields[m[1]]=int(m[2])
 return {"fields":fields,"entries":data}
a=sample();time.sleep(10);b=sample()
seconds=(b["fields"]["mtime"]-a["fields"]["mtime"])/100000000
result={"first":a,"second":b,"clock_sys_hz":100000000,"elapsed_s":seconds,"camera0_fps":(b["fields"]["VIN camera0 frames"]-a["fields"]["VIN camera0 frames"])/seconds,"camera1_fps":(b["fields"]["VIN camera1 frames"]-a["fields"]["VIN camera1 frames"])/seconds}
(O/"fps.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
(O/"status_samples.log").write_text("\n".join(f"[{x['ts']}] {x['text']}" for s in [a,b] for x in s["entries"]),encoding="utf-8")
print({k:v for k,v in result.items() if k not in ["first","second"]},flush=True)
