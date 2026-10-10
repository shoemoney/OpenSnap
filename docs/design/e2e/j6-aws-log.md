# J6 AWS log (no secrets)

Owner-authorized, strictly limited: at most two synthetic uploads, one with Original size ticked, one unticked, to bucket `cdn.shoemoney.com` (us-east-1, prefix `pics/`). Credentials were used only by the app's own S3 profile reader through the launcher's `--aws` handling; nothing was read, copied or printed by this lane.

Session 2: pid 69609, seed `history` plus `--aws`. Fixture: Snap from Link on a local synthetic page (127.0.0.1) → 2560 × 1800 snap, one red arrow drawn, Resize to 1200 × 844.

## Upload 1: Original size ticked
- 15:46:07Z upload via the editor's Upload button (one press) to the default destination `S3 · cdn.shoemoney.com`. Title at upload time: `Screenshot – 2560 × 1800 · PNG · 4 MB`.
- Key: `pics/Screenshot-69515236-a12e-4c61-89b4-5cdf0108e723.png`
- `aws s3api head-object` (read-only): ContentLength 4041263, ContentType image/png, LastModified 2026-10-10T15:46:07+00:00.
- Downloaded with curl to a temp file; `sips -g pixelWidth -g pixelHeight`: **2560 × 1800** = the title's size. The Resize to 1200 × 844 applied before the upload did not change the object (Original size ticked).
- History Details for the new Shared entry: Size `2,560 × 1,800`, Destination `https://cdn.s…108e723.png`; Delete from Web enabled.
- Destination edits in the app (config only, no network): Name changed to "S3 renamed by J6" → Delete from Web stayed enabled on the already selected entry (not reselected, so this may only be the unrefreshed state; with upload 2 the rename was repeated and the entry reselected: enabled); Key prefix temporarily changed `pics` → `pics-j6x` → after reselecting the entry the button is disabled with help text "…the default destination is no longer the server, bucket or folder it was published to. Make that destination the default again to delete it." Prefix then restored to `pics`.
- After the prefix was restored to exactly `pics` (verified in the Edit sheet: us-east-1 / cdn.shoemoney.com / pics) and the entry reselected, Delete from Web stayed disabled with the same "no longer the server, bucket or folder" reason. The app therefore refused to delete upload 1 (FAIL, see F-J6 findings).
- 15:49:25Z deleted ONLY that exact key with `aws s3api delete-object --bucket cdn.shoemoney.com --key pics/Screenshot-69515236-a12e-4c61-89b4-5cdf0108e723.png`; `head-object` afterwards: 404 Not Found.

## Upload 2: Original size unticked
- 15:50:05Z one press of the editor's Upload button; title at upload time `Screenshot – 674 × 474 · PNG · 217 KB`.
- Key: `pics/Screenshot-220d5557-110c-4c3c-9df3-07f84323ca7c.png`
- `head-object`: ContentLength 217022, image/png, LastModified 2026-10-10T15:50:05+00:00.
- curl download + `sips`: **674 × 474** = the title's (fitted) size.
- After renaming the destination again ("S3 renamed again") and reselecting the entry, Delete from Web was enabled; its sheet named the exact URL, Cancel focused.
- 15:51:19Z History › Delete from Web (the app): `head-object` at 15:51:27Z → 404 Not Found. History footer: "Deleted from cdn.shoemoney.com. Cached copies of the link can persist for a while."; the entry's Delete from Web, Copy Link and Open Link became disabled.
- Public URLs of both objects still answered 200 20 s after the deletes (CloudFront cache, as in J4); the app's notice says so.

## Summary
| # | Original size | Title | Object pixels (sips) | History Details size | Deleted by | After |
|---|---|---|---|---|---|---|
| 1 | ticked | 2560 × 1800 | 2560 × 1800 | 2,560 × 1,800 | `aws s3api delete-object` on that exact key (the app refused: button disabled after a location edit and exact restore) | head-object 404 |
| 2 | unticked | 674 × 474 | 674 × 474 | 674 × 474 | the app, History › Delete from Web | head-object 404 |

Two uploads in total, nothing else listed, modified or deleted; temp downloads removed.
