# Destinations (form, S3-compatible)

- Surface: Destinations (form, S3-compatible)
- Suite: accessibility-audit-tests
- Build: 723e65bb
- Nodes: 37

```
[0] scroll area
[1]   Connection
[1]   Name:
[1]   Name, empty, edit text
[1]   Protocol:
[1]   S3-compatible, Protocol, pop up button
[1]     hint: AWS S3, Cloudflare R2, Backblaze B2, DigitalOcean Spaces, Wasabi, MinIO
[1]   Endpoint:
[1]   Endpoint, empty, edit text
[1]   Region:
[1]   Region, us-east-1, edit text
[1]   Bucket:
[1]   Bucket, empty, edit text
[1]   Key prefix:
[1]   Key prefix, empty, edit text
[1]   Public base URL:
[1]   Public base URL, empty, edit text
[1]   
[1]   Make uploads public-read, unchecked, checkbox
[1]   Credentials
[1]   Source:
[1]   AWS credentials profile, Source, pop up button
[1]     hint: AWS credentials profile
[1]   AWS profile:
[1]   AWS profile, empty, edit text
[1]   Path-style S3 over system curl, for AWS, Cloudflare R2, Backblaze B2, DigitalOcean Spaces, Wasabi and MinIO. Public base URL maps to the key prefix; the uploaded file is downloaded from it to verify the exact bytes. Leave public-read off when the bucket disables ACLs.
[1]   0, scroll bar
[2]     button, dimmed
[2]     button, dimmed
[2]     button, dimmed
[2]     button, dimmed
[0] Test lists the bucket with these credentials. It never uploads.
[1]   Test lists the bucket with these credentials. It never uploads.
[0] Test connection, group
[1]   Test, button
[0] Cancel or save, group
[1]   Cancel, button
[1]   Save, button
```
