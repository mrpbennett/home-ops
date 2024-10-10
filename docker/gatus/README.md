# Gatus

First create a directory on the Docker host

```bash
mkdir gatus/config
```

This will be mapped to your volume like

```yaml
volumes:
  - /home/sysadm/gatus:/config
```
