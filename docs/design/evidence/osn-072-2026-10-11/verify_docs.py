import json,base64,re,sys
from pathlib import Path
old=Path(sys.argv[1])/"History"; new=Path(sys.argv[2])/"History"
oi=json.load(open(old/"index.json"))["entries"]; ni={e["id"]:e for e in json.load(open(new/"index.json"))["entries"]}
assert len(oi)==len(ni)==58
bad=[];els=0;panned=[]
for k,e in enumerate(oi):
    st=json.loads(base64.b64decode(re.search(r'redux:state="([^"]+)"',(old/e["nativeFile"]).read_text()).group(1)))
    raw=json.loads(base64.b64decode(st["rawCanvasData"]))        # the old editable canvas JSON
    n=ni[e["id"]]; nd=json.loads((new/n["nativeFile"]).read_bytes())
    dd=nd.pop("drawingDefaults",None)
    raw_cmp=dict(raw); nd_cmp=dict(nd)
    raw_cmp["format"]=nd_cmp["format"]="X"                         # only the format id may change
    ok=raw_cmp==nd_cmp
    if st["document"]!=raw: panned.append(e["id"][:8])  # viewport-only copy differs: the file keeps the full pan source (by design)
    pv=(old/e["previewFile"]).read_bytes()==(new/n["previewFile"]).read_bytes()
    t=lambda d:[x.get("text") for x in d["elements"] if x.get("kind")=="text"]
    ok&= pv and t(raw)==t(nd) and len(raw["elements"])==len(nd["elements"])
    els+=len(nd["elements"])
    if k<3: print("SPOT",e["id"][:8],"elements",len(raw["elements"]),len(nd["elements"]),"texts",len(t(raw)),"preview-bytes-equal",pv,"canvas-json-equal-except-format-id",ok)
    if not ok: bad.append(e["id"])
print("panned documents whose full pan source was preserved:",panned)
print(f"checked 58 documents, {els} elements total, mismatches: {len(bad)}")
sys.exit(1 if bad else 0)
