# J4 AWS live check (F-J2-002): Delete from Web on the app's own S3 upload

Owner-authorised and limited to one synthetic object. No credential, key or secret value was read, printed, copied or logged: the launcher points the isolated app at `~/.aws/credentials` in place (`--aws`), and the `aws` CLI used the same default profile for read-only `head-object` only.

| Time (UTC) | Step | Result |
|---|---|---|
| 11:49 | `sh tools/e2e-session.sh start --seed history --aws` (pid 70107, id `com.shoemoney.opensnap.e2e-70088`) | Settings › Upload shows one destination, **S3 · cdn.shoemoney.com**, Default (`64-…jpg`) |
| 11:49 | Drew one red ellipse on the blank 800 × 600 canvas (nothing personal) | `65-…jpg` |
| 11:49:49 | Clicked Upload once (AX press on the bottom-bar button) | "Uploading Untitled…" with ✕ (`66-…jpg`), then "Link copied · cdn.shoemo…4c6433.png" with Open and Copy icons (`67-…jpg`) |
| 11:50 | Link read from the clipboard (text) | `https://cdn.shoemoney.com/pics/Untitled-cabc17a5-98e9-469c-b429-094ff54c6433.png` |
| 11:50 | `aws s3api head-object --bucket cdn.shoemoney.com --key pics/Untitled-cabc17a5-98e9-469c-b429-094ff54c6433.png` | **exists**: 29,751 bytes, `image/png`, LastModified 11:49:56Z. `curl -sI` the public URL: HTTP/2 200 |
| 11:50 | History: new **Untitled · Shared** tile (`68-…jpg`); selected it | Delete from Web icon **enabled**; Destination shows `https://cdn.s…54c6433.png` (middle-cut, `69-…jpg`) |
| 11:50 | Clicked Delete from Web in History | Confirm sheet **on the History window** naming the exact URL (`70-…jpg`) |
| 11:50 | Confirmed "Delete from Web" | Copy Link, Open Link and Delete from Web icons went disabled, History entry kept (`71-…jpg`) |
| 11:50:56 | `aws s3api head-object` again | **404 Not Found** |
| 11:51 | `curl -sI` the public URL | still HTTP/2 200, `x-cache: Hit from cloudfront`, `age: 69`, still 200 after 20 s more |

**Verdict F-J2-002: PASS.** The app deleted its own S3 object through the app (signed DELETE); the origin returns 404. The fallback `aws s3api delete-object` was **not needed and not run**. No other object was listed, modified or deleted; no IAM or infrastructure was created.

**Observation (not an app defect, noted as F-J4-003):** the public URL keeps answering 200 from the CloudFront edge cache after the origin object is gone. The app cannot invalidate the CDN; the confirm text says "This removes the published image" and the History footer gives no after-delete notice, so the owner may believe the link is dead while it is still cached.

Session stop: `sh tools/e2e-session.sh stop` printed "RESULT stores unchanged, session removed" for pid 70107 (and for the earlier pid 62733). Clipboard: held no text before the run; reset to empty text afterwards.
