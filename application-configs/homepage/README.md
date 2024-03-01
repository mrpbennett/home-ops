# Catppuccin Homer dashboard

My custom [homer dasboard](https://github.com/bastienwirtz/homer) inspired by
the [catppuccin](https://github.com/catppuccin) Macchiato palette

![catppuccin](./../../imgs/homer.png)

## Activating theme

- Create a file called `custom.css` in `www/assets/custom.css` and copy the
  contents of [`catppuccin.css`](./config/catppuccin.css).
- Copy [`romb.png`](./config/images/romb.png) to `www/assets/romb.png`.
- Put these lines into `www/assets/config.yml` and save the file:

```yaml
stylesheet:
  - 'assets/custom.css'
```

## Install Homer using Docker

```bash
docker run -d \
  --name=homer-dashboard \
  -p 8082:8080 \
  -v /home/paul/.config/homer:/www/assets \
  --restart=unless-stopped \
  b4bz/homer:latest
```

## Install Homer Using Docker Compose

```yaml
version: '3'
services:
  homer:
    image: b4bz/homer
    container_name: homer
    volumes:
      - /Users/paul/Developer/homelab/applications/homer:/www/assets
    ports:
      - 8082:8080
    restart:
    user: '$(id -u):$(id -g)' # default
    environment:
      - INIT_ASSETS=1 # default
```

- [Editing your config.yml](https://github.com/bastienwirtz/homer/blob/main/docs/tips-and-tricks.md#remotely-edit-your-config-with-code-server)
- [Editing config via ssh](https://youtu.be/9iTPm45EmxM?t=284)

## Issues

https://github.com/bastienwirtz/homer/issues/531
