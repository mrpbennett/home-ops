# Docker host setup

My docker host will be managed via [Portainer](https://docs.portainer.io/start/install-ce/server/docker/linux) for ease of use.

The host will mainly be running home assistant and my docker registry.

## Install Portainer

First, create the volume that Portainer Server will use to store its database:

```bash
docker volume create portainer_data
```

Then, download and install the Portainer Server container:

```bash
docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
```
