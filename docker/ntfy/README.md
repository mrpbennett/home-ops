The ntfy image is available for amd64, armv6, armv7 and arm64. It should be pretty straight forward to use.

The server exposes its web UI and the API on port `80`, so you need to expose that in Docker. To use the persistent message cache, you also need to map a volume to `/var/cache/ntfy`. To change other settings, you should map `/etc/ntfy`, so you can edit `/etc/ntfy/server.yaml`.
