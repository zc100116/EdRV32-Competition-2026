from pathlib import Path
import urllib.request,json,subprocess,time,datetime
R=Path(__file__).resolve().parents[4]
O=R/"tasks/win/20261031-22-b3-rnv/artifacts/b3v/eth_diag"
O.mkdir(parents=True,exist_ok=True)
def api(path,body=None):
    req=urllib.request.Request("http://127.0.0.1:8765/api/"+path,data=None if body is None else json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req,timeout=5))
initial=api("buffer?since=0&limit=5000")
entries=initial["entries"]
last=initial["lastSeq"]
def stamp():return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
def collect():
    global last
    d=api(f"buffer?since={last}&limit=5000")
    entries.extend(d["entries"]);last=d["lastSeq"]
    return d["entries"]
def save():
    (O/"serial_entries.json").write_text(json.dumps(entries,ensure_ascii=False),encoding="utf-8")
    (O/"uart.log").write_text("\n".join(f"[{x['ts']}][{x['dir'].upper()}] {x['text']}" for x in entries)+"\n",encoding="utf-8")
    (O/"rx_text.log").write_text("\n".join(x["text"] for x in entries if x["dir"]=="rx")+"\n",encoding="utf-8")
(O/"initial_gui_ethernet.json").write_text(json.dumps(api("ethernet/status"),ensure_ascii=False),encoding="utf-8")
api("ethernet/receive/stop",{})
probe_log=(O/"eth_probe.log").open("w",encoding="utf-8")
probe=subprocess.Popen(["C:/Python314/python.exe","-u",str(R/"tools/board/eth_probe.py"),"--local-ip","192.168.1.2"],cwd=R,stdout=probe_log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
phases=[]
try:
    for combo in range(4):
        collect()
        start_seq=last
        phase={"combination_requested":combo,"start":stamp(),"startSeq":start_seq}
        print("Testing delay combination",combo,phase["start"],flush=True)
        api("send",{"text":"d","ending":"cr"})
        deadline=time.monotonic()+25
        link=False
        while time.monotonic()<deadline:
            new=collect()
            if any("link=1 speed=1000" in x["text"] for x in new):link=True;break
            if probe.poll() is not None:raise RuntimeError("eth_probe exited; see eth_probe.log")
            time.sleep(.5)
        phase["link1000_observed"]=link
        begin=last
        phase["observationStartSeq"]=begin;phase["observationStart"]=stamp()
        with (O/f"ping_combo{combo}.txt").open("w",encoding="utf-8") as log:
            ping=subprocess.Popen(["ping","-S","192.168.1.2","-n","3","-w","1000","192.168.1.10"],stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
            end=time.monotonic()+10
            while time.monotonic()<end:
                collect()
                if probe.poll() is not None:raise RuntimeError("eth_probe exited; see eth_probe.log")
                time.sleep(.5)
            ping.wait(timeout=10)
        collect();phase["endSeq"]=last;phase["end"]=stamp()
        with (O/f"arp_combo{combo}.txt").open("w",encoding="utf-8") as log:subprocess.run(["arp","-a","-N","192.168.1.2"],stdout=log,stderr=subprocess.STDOUT,check=True,creationflags=subprocess.CREATE_NO_WINDOW)
        phases.append(phase);save()
        (O/"phases.json").write_text(json.dumps(phases,ensure_ascii=False,indent=2),encoding="utf-8")
        print("Completed combination",combo,"link1000",link,flush=True)
finally:
    probe.terminate();probe.wait(timeout=10);probe_log.close();collect();save()
print("Four delay combinations recorded",flush=True)
