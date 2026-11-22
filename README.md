# OpenIOT Web App (for OpenIOT devices)

This copy contains the device control application, including template import and export. The supported-device database and catalog have been removed.

## NAS/server hosting

The container serves static WebApp assets on internal port 8080, exposed on host port
6468 by default. No Node build or application
backend is required for the OpenIOT launch path. The browser still opens the device's
`/app`; the device loads `startup.js` from this server. The hosted root page provides
setup instructions rather than a standalone device control page.

After building and starting the container, set **Config → Configure WebApp** on the
device to a short URL such as `http://nas:6468/`, then use **Launch WebApp**. Use a
hostname or address reachable from the browser. The device stores the WebApp URL in
a 64-byte field. The server supplies CORS headers for component fetches, serves
`.vue` files as text, returns 404 for missing files, and disables browser caching so
new requests use the current assets. Reload an already open WebApp after updating.

The image runs nginx as its unprivileged user. Compose makes its filesystem
read-only, supplies temporary storage, drops capabilities, and requires no persistent
data volume or Docker socket. Application assets are included in the image; Git
history, local agent guidance, the removed catalog, and demo entry pages are excluded.

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

`openiot-webapp` is a local image name, not a published registry. The base-image tag
is a starting default; its current version, digest, supported platforms, and image
size have not been verified. Pin `NGINX_IMAGE` to a verified version or digest when
preparing a release. Building can require network access to obtain the base image.
NAS amd64/arm64 compatibility and browser/device operation need validation on the
selected target; the files do not force the workstation's architecture.

To update, retain the previous image, apply the intended source changes, set a new
`WEBAPP_VERSION` such as `local-002`, then repeat the build and start commands. Check
the WebApp through the device before removing the previous image. To roll back, set
`WEBAPP_VERSION` back to the retained tag and run `docker compose up -d --no-build`.
Do not rebuild that previous tag or prune its image while it is your rollback copy.
There is no background updater; registry delivery can be added when a destination
and release process are chosen. Do not blindly pull upstream source over the local
catalog removal and adaptations.

### Remaining upstream dependencies

Core Vue libraries are bundled. Template import still loads CryptoJS from cdnjs and
the template parser/exporter from the upstream WebApp host, despite local helper
copies being present. Demo configurations use GitHub raw URLs. Release lookups
still target `openshwprojects/OpenBK7231T_App`. These paths have not been adapted,
so local hosting does not establish complete offline operation or OpenIOT-specific
firmware updates.

## Source attribution

Originally created by [btsimonh](https://github.com/btsimonh), with subsequent work
by the [OpenBekenIOT/webapp contributors](https://github.com/OpenBekenIOT/webapp/graphs/contributors).
See [ATTRIBUTION.md](ATTRIBUTION.md) for the upstream source and retained
third-party notices.

## License

OpenIOT-authored contributions and modifications are licensed under
[Creative Commons Attribution 4.0 International (CC BY 4.0)](LICENSE).
This does not relicense inherited application code or bundled third-party libraries;
their existing notices and applicable upstream terms remain in effect. A general
license for the inherited application source was not found in the imported snapshot.
