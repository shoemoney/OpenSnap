from pathlib import Path
import json,re
p=Path(__file__).resolve().parent;read=lambda n:(p/(n+'.txt')).read_text()
all_dumps=[f for f in p.glob('*.txt') if f.name!='stop.txt']
assert all('parentOK=false' not in f.read_text() and 'AXUnknown' not in f.read_text() for f in all_dumps)
first=lambda n:read(n).split('\nAXWindow ',2)[1]
counts={
 'Toolbox rows':len(re.findall(r'^    AX(?:Button|CheckBox) ',first('06-toolbox'),re.M)),
 'Color preset radios':len(re.findall(r'^    AXRadioButton (?!Custom color)',first('01-color'),re.M)),
 'Capture key radios':len(re.findall(r'^    AXRadioButton ',first('15-all-keys'),re.M)),
 'Destination protocol radios':len(re.findall(r'^    AXRadioButton ',first('24-protocol'),re.M)),
 'Destination source radios':len(re.findall(r'^    AXRadioButton ',first('26-source'),re.M))}
assert counts=={'Toolbox rows':18,'Color preset radios':10,'Capture key radios':69,'Destination protocol radios':5,'Destination source radios':2},counts
checks={
 'Color chosen value':'AXRadioButton Blue value=1' in read('03-color-blue-value'),
 'Size choice applied':'AXSlider Drawing size value=12' in read('05-size-chosen'),
 'Zoom choice applied':'AXPopUpButton Canvas zoom value=75%' in read('09-zoom-chosen'),
 'Rejected draft retained':'AXPopUpButton Screen region key value=K' in read('18-key-dismiss-focus') and 'Error: Choose Command or Control' in read('18-key-dismiss-focus'),
 'Modifier arrows work':'AXCheckBox Screen region Option value=1' in read('20-modifier-arrows') and 'AXCheckBox Screen region Control value=1' in read('20-modifier-arrows'),
 'Keyboard opener regains focus':'AXPopUpButton Screen region key value=None enabled=1 children=0 focused=Optional(1)' in read('32-key-keyboard-focus-return'),
 'First Escape closes panel only':'AXSheet ' in read('27-source-escape') and '\nAXWindow Source ' not in read('27-source-escape'),
 'Sheet Return validates Save':'Error: Enter an AWS profile name' in read('28-destination-return'),
 'Sheet second Escape cancels':'AXSheet ' not in read('29-destination-cancel'),
 'History date chosen':'AXPopUpButton History date filter value=Yesterday' in read('37-history-date-chosen'),
 'History export chosen':'AXPopUpButton History drag export format value=JPG' in read('39-history-format-chosen'),
 'Resize arrows retain selection focus':'AXRadioButton Crop value=1 enabled=1 children=0 focused=Optional(1)' in read('42-resize-arrows'),
 'Resize Escape and Return close sheet':'AXSheet ' not in read('43-resize-cancel') and 'AXSheet ' not in read('46-resize-return-ok'),
 'Return from nonchosen focus leaves choice unchanged':'AXRadioGroup Size operation value=Resize' in read('45-resize-nonchosen-focus'),
 'Toolbar focus restored':'AXMenuButton Toolbox value= enabled=1 children=0 focused=Optional(1)' in read('52-toolbar-return-focus'),
 'Toolbar Tab continues':'AXButton Photos value= enabled=1 children=0 focused=Optional(1)' in read('53-toolbar-continued-tab')}
assert all(checks.values()),[k for k,v in checks.items() if not v]
actions=json.loads((p/'actions.json').read_text());assert all(a['exit']==0 for a in actions)
stop=(p/'stop.txt').read_text();assert 'RESULT stores unchanged, session removed' in stop and 'kills this session: 0' in stop
record={'sourceSha':'03d267b933566114dad26e765f7fc306b553e2f4','sourceTree':'e3e8d943ef748ae53411988c8a0d9371c467cf83','status':'pass','counts':counts,'checks':checks,'allActionResultsSuccess':True,'allParentChainsAgree':True,'noUnknownWrappers':True,'windowDumpCount':len(all_dumps),'method':'External window-root AXUIElement traversal and actions; window-scoped routed keys. Known Window > Focus Toolbar activated separately through only that app-owned menu branch. No physical HID or VoiceOver speech.','limits':['Physical pointer/hover and VoiceOver speech remain manual','Injected display settings are not live system-setting toggles','Routed Option-Command-T did not execute the menu command; the known-command activator did'],'session':'com.shoemoney.opensnap.e2e-20576','storesDigest':'dbde037ac2085108','watchdogKills':0}
(p/'summary.json').write_text(json.dumps(record,indent=2)+'\n');print('PASS final external-client assertions',counts)
