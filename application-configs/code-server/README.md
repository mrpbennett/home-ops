# Setting up Code Server

- [Github repo](https://github.com/coder/code-server)
- [Docker info](https://hub.docker.com/r/codercom/code-server)

```bash
docker run -it --name code-server -p 8083:8080 --restart unless-stopped \
-v "$PWD:/home/coder/project" \
-v "$PWD/etc/ntfy:/home/coder/project/ntfy" \
-u "0:0" \
codercom/code-server:latest
```

```yaml
version: '3.8'
services:
  code-server:
    image: codercom/code-server:latest
    container_name: code-server
    restart: unless-stopped
    ports:
      - '8080:8080'
    volumes:
      - '$PWD:/home/coder/project'
    user: '0:0'
```

## Adding directories

It's pretty easy to add a new directory to code server. This is great for adding
something like Kubernetes manifests, rather than editing them in VIM. I love
VIM, however I have spent so much more time in VSC.

You will need to add another volume into your Docker run command, like so:

```bash
-v '/home/paul/homelab/kube-manifests':'/home/coder/kube-manifests':'rw' \
```

The path on the left is the directory you want to bring into code-server. To add
it into code-server you will need to map it to the following path `/home/coder/`
after the path you will need to give it read and write access with the following
`:'rw'`.

Now you can add and edit those kube manifest files with easy.
