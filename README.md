# OpenIOT Web App (for OpenIOT devices)

OpenIOT WebApp provides device controls, configuration, logs, template import and
export, filesystem access, and OTA updates.

## Proxmox installation

The [WebApp installer](webapp_lxc.sh) creates a ready-to-use container and guides you
through its settings and root password.

Default container resources:

| Resource | Allocation |
|---|---|
| CPU | 1 core |
| RAM | 256 MB |
| Disk | 2 GB |

Open your Proxmox node's **Shell** as root and run:

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/DeDaMrAzR/OpenIOTwebapp/main/webapp_lxc.sh)"
```

After setup, copy the displayed URL into your device's **Configure WebApp** setting,
then use **Launch WebApp**.

## NAS/server hosting

Run the container on a Docker-compatible NAS or server. The default host port is
6468; the container's internal port is 8080. Opening the server URL shows setup
instructions. Launch the application from your device's **Launch WebApp** button.

After building and starting the container, set **Config → Configure WebApp** on the
device to a short URL such as `http://nas:6468/`, then use **Launch WebApp**. Use a
hostname or address reachable from the browser. Reload an already open WebApp after
updating.

No persistent data volume is required for the container.

### Build, update, and rollback

In a NAS/server shell, create a local `.env` beside `compose.yaml`, choosing a
distinct image tag for each build:

```dotenv
WEBAPP_VERSION=local-001
WEBAPP_PORT=6468
NGINX_IMAGE=nginx:alpine
```

From this directory:

```sh
docker compose build --pull
docker compose up -d --no-build
```

These commands build and run a local `openiot-webapp` image. Building may require
internet access to download the nginx base image.

To update, retain the previous image, apply the intended source changes, set a new
`WEBAPP_VERSION` such as `local-002`, then repeat the build and start commands. Check
the WebApp through the device before removing the previous image. To roll back, set
`WEBAPP_VERSION` back to the retained tag and run `docker compose up -d --no-build`.
Do not rebuild that previous tag or prune its image while it is your rollback copy.

### Internet access

Template import, demo configurations, and firmware release checks require internet
access. The OTA release list currently points to
[upstream OpenBeken firmware](https://github.com/openshwprojects/OpenBK7231T_App/releases).

## Source attribution

Originally created by [btsimonh](https://github.com/btsimonh), with subsequent work
by the [OpenBekenIOT/webapp contributors](https://github.com/OpenBekenIOT/webapp/graphs/contributors).
See [ATTRIBUTION.md](ATTRIBUTION.md) for the upstream source and retained
third-party notices.

## License

OpenIOT-authored contributions and modifications are licensed under
[Creative Commons Attribution 4.0 International (CC BY 4.0)](LICENSE.md).
This does not relicense inherited application code or bundled third-party libraries;
their existing notices and applicable upstream terms remain in effect.
