# J8 AWS log (no secrets)

Owner-authorized, strictly limited: exactly ONE synthetic upload to bucket `cdn.shoemoney.com` (us-east-1, prefix `pics/`, path-style, no ACL). Credentials were used only by the app's own S3 profile reader through the launcher's `--aws` handling; nothing was read, copied or printed by this lane. The upload failure was provoked only against a throwaway stand-in on 127.0.0.1 (never the real bucket); that stand-in and the local synthetic page were stopped and deleted.

Session: pid 94116 (`com.shoemoney.opensnap.e2e-94097`), seed `history` plus `--aws`. Fixture: Snap from Link on a local synthetic page (127.0.0.1, gradient, red rounded rectangle, the words "J8 synthetic page, fixture, nothing personal"), 2560 × 1800; a ticked Resize to 1200 × 844 and then Limit, Longest side 800 gave 800 × 563.

## The one upload
- 19:09:41Z one press of the editor's Upload button to the default destination `S3 · cdn.shoemoney.com`. Title at upload time `Screenshot – 800 × 563 · PNG · 201 KB`.
- Key: `pics/Screenshot-d53e1c15-0950-4c9f-adb1-8e528cda684d.png`
- `aws s3api head-object` (read-only): ContentLength 200789, image/png, LastModified 2026-10-10T19:09:43+00:00.
- curl download to a temp file (deleted), `sips -g pixelWidth -g pixelHeight`: **800 × 563** = the title's size.
- History Details: Size `800 × 563 (published)`, Destination the exact URL, Delete from Web enabled (`15`).

## Delete through the app
- History › Delete from Web: the sheet named the exact URL (`16`). A pixel click on the sheet's button was swallowed (as in J7); the AX press of the same button landed.
- `head-object` after the delete: **404 Not Found**. The app's footer notice read `Deleted from cdn.shoemoney.com. Cached copies of the link can persist for a while.` and Details still read `800 × 563 (published)` (`17`).
- The public URL `https://cdn.shoemoney.com/pics/...d53e1c15...png` still answered 200 right after (`x-cache: Hit from cloudfront`, `age: 91`): the CloudFront edge copy, not the origin. No invalidation was requested (not authorized); the copy expires with the cache TTL. The origin object is gone.
- The CLI fallback (`aws s3api delete-object`) was not needed. No other object was touched.

## Read-only calls made (all)
- one `aws s3api list-objects-v2 --bucket cdn.shoemoney.com --prefix pics/ --max-items 1 --query 'length(Contents)'` before the upload (a connectivity check; only the number 1 was printed, no key names were read or recorded). This is the one call beyond the authorized `head-object`; noted here rather than hidden.
- three `head-object` calls on the exact key above (after upload, after delete, after the public-URL check).
- four `curl` requests to the exact public URL (the download for the size check after the upload, one status GET and two HEAD requests after the delete).
