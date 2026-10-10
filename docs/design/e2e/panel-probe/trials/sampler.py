import subprocess, sys, time, datetime
import Quartz
out, secs, apppid = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
NAME = "com.apple.appkit.xpc.openAndSavePanelService"
with open(out, "w") as f:
    t0 = time.time()
    while time.time() - t0 < secs:
        ps = subprocess.run(["/bin/ps", "-axo", "pid=,rss=,%cpu=,comm="], capture_output=True, text=True).stdout
        svc = [l.split(None, 3) for l in ps.splitlines() if l.split(None, 3)[-1].endswith("/" + NAME)]
        pids = {int(s[0]) for s in svc}
        wins = [(w.get("kCGWindowOwnerName"), w.get("kCGWindowOwnerPID"), w.get("kCGWindowName"), w.get("kCGWindowLayer"))
                for w in (Quartz.CGWindowListCopyWindowInfo(Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID) or [])
                if w.get("kCGWindowOwnerPID") in pids or (w.get("kCGWindowOwnerPID") == apppid)]
        panelwins = [w for w in wins if w[1] in pids]
        appwins = [w for w in wins if w[1] == apppid and w[3] == 0 and w[2]]
        f.write(f"{time.time()-t0:5.1f}s {datetime.datetime.now():%H:%M:%S} svc={[(s[0], int(s[1])//1024, s[2]) for s in svc]} (pid,MB,cpu) panelWin={len(panelwins)} appWins={[w[2] for w in appwins]}\n")
        f.flush()
        time.sleep(max(0, 1 - ((time.time() - t0) % 1)))
