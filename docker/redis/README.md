# Run Redis Stack on Docker

How to install Redis Stack using Docker

To get started with Redis Stack using Docker, you first need to select a Docker image:

- `redis/redis-stack` contains both Redis Stack server and Redis Insight. This container is best for local development because you can use the embedded Redis Insight to visualize your data.

- `redis/redis-stack-server` provides Redis Stack server only. This container is best for production deployment.

## Getting started

**redis/redis-stack**

To start a Redis Stack container using the redis-stack image, run the following command in your terminal:

[_compose.yaml_](compose.yaml)

The docker run command above also exposes Redis Insight on port `8001`. You can use Redis Insight by pointing your browser to `localhost:8001`.

[https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/docker/](https://redis.io/docs/latest/operate/oss_and_stack/install/install-stack/docker/)
