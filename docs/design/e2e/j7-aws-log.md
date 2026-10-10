# J7 AWS log (no secrets)

Owner-authorized, strictly limited: at most two synthetic uploads, one after a ticked Resize, one unticked, to bucket `cdn.shoemoney.com` (us-east-1, prefix `pics/`, path-style, no ACL). Credentials were used only by the app's own S3 profile reader through the launcher's `--aws` handling; nothing was read, copied or printed by this lane. Failures were provoked only against a throwaway stand-in server on 127.0.0.1 (never the real bucket).

Session 2: pid 35679, seed `history` plus `--aws`. Fixture: Snap from Link on a local synthetic page (127.0.0.1, gradient, red rounded rectangle, one arrow drawn) giving a 2560 × 1800 snap.

## Upload 1: Original size ticked, Resize to 1200 × 844
- 18:03:33Z one press of the editor's Upload button to the default destination `S3 · cdn.shoemoney.com`. Title at upload time `Screenshot – 1200 × 844 · PNG · 386 KB`. Before the upload, Edit › Copy Image left a TIFF of 1200 × 844 pixels on the pasteboard (readout).
- Key: `pics/Screenshot-bdca80a7-f0bb-48ac-8290-a43dafc6c576.png`
- `aws s3api head-object` (read-only): ContentLength 386274, image/png, LastModified 2026-10-10T18:03:33+00:00.
- curl download to a temp file, `sips -g pixelWidth -g pixelHeight`: **1200 × 844** = the title's size. (J6 with the same steps produced 2560 × 1800.)
- History Details: Size `1200 × 844`, Destination ends `…afc6c576.png`, Delete from Web enabled.

## Upload 2: Original size unticked
- Undo of the Resize (title back to 2560 × 1800), then Original size unticked: title `Screenshot – 1438 × 1011 · PNG · 742 KB`.
- 18:04:22Z one press of Upload.
- Key: `pics/Screenshot-a9330390-cafa-4e85-aec5-75a0b0a00efe.png`
- `head-object`: ContentLength 742170, image/png, LastModified 2026-10-10T18:04:22+00:00.
- curl + `sips`: **1438 × 1011** = the title's (fitted) size.

## Deletes through History › Delete from Web (finding 7)
- Destination edit in Settings › Upload › Edit… (config only, no network): Key prefix `pics` to `pics-j7x`, Save. With the upload 1 entry still selected, Delete from Web turned disabled at once with the reason "the default destination is no longer the server, bucket or folder it was published to…". Key prefix restored to `pics`, Save: the button turned enabled at once, no reselect, no list reload (J6 needed a reload).
- 18:08Z History › Delete from Web on upload 1: the sheet named the exact URL, Cancel focused; `head-object` at 18:08:06Z: 404 Not Found.
- 18:09Z the same for upload 2; `head-object` at 18:09:43Z: 404 Not Found. History footer both times: "Deleted from cdn.shoemoney.com. Cached copies of the link can persist for a while."
- The public URLs still answered 200 shortly after the deletes (CloudFront cache, as in J4 and J6); the app's notice says so.
- The CLI delete fallback was not needed.

## Summary
| # | Original size | Title | Object pixels (sips) | Deleted by | After |
|---|---|---|---|---|---|
| 1 | ticked, Resize 1200 × 844 | 1200 × 844 | 1200 × 844 | the app, History › Delete from Web | head-object 404 |
| 2 | unticked | 1438 × 1011 | 1438 × 1011 | the app, History › Delete from Web | head-object 404 |

Two uploads in total, nothing else listed, modified or deleted; temp downloads removed.
