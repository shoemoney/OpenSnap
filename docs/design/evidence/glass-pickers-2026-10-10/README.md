# OpenSnap glass choices evidence

Canonical tested source: `21b8d68e10543b097cb6a902103e9c56eeb76be5`, tree `047c1a0ce65c3806633926740afea20c8eaffc4d`.

- `root-before`: synthetic baseline at `57ec799`.
- `candidate-glass`, `candidate-core`, `candidate-accessibility`: final packed captures and exact retained glass/display metadata. Raw gate logs are in `verification/21b8d68`. Packed strict checks pass too. Logs named `checker-before-metadata-restoration.log` are superseded packaging failures, not product failures.
- `native/03d267b`: actual external review source, raw action replies and window-root dumps, portable assertion client, cleanup proof and matching-product subtree identities.
- `opened-image-review.json`: representative files actually opened by root and review limits.
- `gallery-runtime.json`: desktop/phone gallery checks.
- Older verification records and failed pre-final suite logs remain historical, clearly separated from final gates.

No Pro fonts are included. The sf harness mode strips Pro; embedded official Font Awesome Free vectors resolve before SF fallback. Capture images are packed to at most 1280px width. Their metrics describe actual app points; Stored pixels in the gallery refers to the packed image resolution.

Regenerate the standalone offline gallery from this repository with:

```sh
rtk proxy python3 docs/design/evidence/glass-pickers-2026-10-10/gallery-builder.py
```

`gallery-data.json` uses repository-relative image paths. The generator also writes a lean private HTML for T3 preview. Runtime checks use `gallery-runtime-check.js`. No app is launched by gallery generation.
