# Setting up Home Assistant

Setting up Home Assistant via a Docker container

```docker
docker run -d \
  --name homeassistant \
  --privileged \
  --restart=unless-stopped \
  --device /dev/ttyUSB0:/dev/ttyUSB0 \
  --network=host \
  -e TZ=Europe/London \
  -v /Users/paul/Desktop/homelab/ha:/config \
  -p 8123:8123 \
  ghcr.io/home-assistant/home-assistant:stable
```

This will now be avaiable at `<host>:8123`

## links

[https://www.homeautomationguy.io/home-assistant-tips/installing-docker-home-assistant-and-portainer-on-ubuntu-linux/](https://www.homeautomationguy.io/home-assistant-tips/installing-docker-home-assistant-and-portainer-on-ubuntu-linux/)
