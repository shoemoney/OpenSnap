# Destinations (form, FTPS)

- Surface: Destinations (form, FTPS)
- Suite: accessibility-audit-tests
- Build: dda6b216
- Nodes: 23

```
[0] scroll area
[1]   Connection
[1]   Name, empty, edit text
[1]   FTPS, Protocol, pop up button
[1]     hint: FTP with TLS required
[1]   Endpoint URL, empty, edit text
[1]   Remote folder, empty, edit text
[1]   Public base URL, empty, edit text
[1]   Credentials
[1]   Username, empty, edit text
[1]   Password, secure edit text
[1]   FTPS: ftp:// starts explicit TLS and ftps:// implicit TLS; TLS is required either way. Folders must exist. Public base URL maps to the upload folder; only the file name is appended.
[1]   0, scroll bar
[2]     button, dimmed
[2]     button, dimmed
[2]     button, dimmed
[2]     button, dimmed
[0] Test logs in over TLS and lists the folder. It never uploads.
[0] Test connection, group
[1]   Test, button
[0] Cancel or save, group
[1]   Cancel, button
[1]   Save, button
```
