from pathlib import Path
import json,subprocess
base=Path('/Users/shoemoney/Projects/OpenSkitch/docs/design/evidence/glass-pickers-2026-10-10')
checker=Path('/Users/shoemoney/Projects/OpenSkitch/tools/check-eye-dump.py')
for kind in ('glass','core','accessibility'):
 raw=Path('/tmp/gp-root-final-eye-'+kind);out=base/('candidate-'+kind)
 origin=json.loads((raw/'manifest.json').read_text());p=out/'manifest.json';packed=json.loads(p.read_text())
 index={(c['id'],c['slug'],c['appearance'],c['iconMode']):c for c in origin['captures']}
 for c in packed['captures']:
  original=index[(c['id'],c['slug'],c['appearance'],c['iconMode'])]
  for k,v in original.items():
   if k not in c:c[k]=v
 for k in ('injectedDisplayOptions','requested'):
  if k in origin:packed[k]=origin[k]
 packed.pop('displayOptions',None)
 p.write_text(json.dumps(packed,indent=1,ensure_ascii=False)+'\n')
 old=out/'checker-packed.log'
 if old.exists():old.rename(out/'checker-before-metadata-restoration.log')
 with (out/'checker-packed.log').open('w') as log:
  result=subprocess.run(['python3',str(checker),str(out),'--strict'],stdout=log,stderr=subprocess.STDOUT)
 print(kind,result.returncode,(out/'checker-packed.log').read_text()[-300:],flush=True)
 assert result.returncode==0
