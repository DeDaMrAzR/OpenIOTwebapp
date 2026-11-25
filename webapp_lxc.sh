#!/usr/bin/env bash
# Create a new Proxmox VE LXC serving OpenIOT WebApp. Run as root on a node.
# Intended for a standard Debian 12 or 13 amd64 template.
#
# Local invocation: bash ./webapp_lxc.sh
# Self-contained invocation:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/DeDaMrAzR/OpenIOTwebapp/main/webapp_lxc.sh)"
# No checkout or community-scripts framework is required. Prompts use /dev/tty.
#
# Optional environment settings (interactive defaults shown):
#   CTID=<next free cluster ID> CT_HOSTNAME=openiot-webapp
#   STORAGE=<active rootdir storage> TEMPLATE_STORAGE=<active template storage>
#   TEMPLATE=<auto-select installed or download latest matching Debian template>
#   DEBIAN_VERSION=13 WEBAPP_REF=main
#   BRIDGE=vmbr0 IP=dhcp GATEWAY= VLAN= NAMESERVER=
#   CORES=1 MEMORY=256 DISK_GB=2 WEBAPP_PORT=6468 ONBOOT=1
#   SOURCE_DIR=<optional local checkout, otherwise download source from GitHub>
#   INTERACTIVE=1 CONFIRM=<set yes to accept without an interactive confirmation>
# Interactive installation asks for a root console password without displaying it.
# Unattended installation leaves the template's root password unset/locked; use
# pct enter <CTID> or pct exec <CTID> -- passwd root to configure access later.
# Static example: IP=192.168.1.120/24 GATEWAY=192.168.1.1
# VLAN sets an optional bridge VLAN tag. IPv6 is disabled for this provisioning.
#
# The node needs internet for source and possibly a Debian template; the CT needs
# internet/DNS for packages. Nesting is enabled for systemd in the unprivileged CT.
# The host gets no packages installed. No Docker, host firewall changes, or
# automatic WebApp updates are used.
# WEBAPP_REF resolves to an immutable commit printed during installation. Pin a
# full commit SHA to reproduce the same source. SOURCE_DIR copies local files.
# Only curated assets are served. Existing cluster CT/VM IDs are refused.
# Failure leaves the new CT intact for inspection; it is never auto-destroyed.
# To update reversibly, create a new CT from the desired checkout and validate it
# through a device before switching its Configure WebApp URL or retiring the old CT.

set -Eeuo pipefail

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

work=
created=0
cleanup() {
    unset root_password root_password_confirm
    if [[ "$work" == /tmp/openiot-webapp.* && -d "$work" ]]; then
        rm -rf -- "$work"
    fi
}
failed() {
    local result=$?
    trap - ERR
    printf 'Provisioning failed (exit %s).\n' "$result" >&2
    if (( created )); then
        printf 'CT %s was retained. Inspect with: pct status %s; pct enter %s\n' \
            "${CTID:-unknown}" "${CTID:-unknown}" "${CTID:-unknown}" >&2
    else
        printf 'If pct create failed partway, inspect CT %s before retrying.\n' "${CTID:-unknown}" >&2
    fi
    exit "$result"
}
trap cleanup EXIT
trap failed ERR

[[ $EUID == 0 ]] || die 'Run this script as root on a Proxmox VE node.'
for command in pct pvesh pvesm pveam curl tar mktemp ip awk grep sed sort; do
    command -v "$command" >/dev/null || die "Required host command missing: $command"
done

CTID=${CTID:-$(pvesh get /cluster/nextid)}
CT_HOSTNAME=${CT_HOSTNAME:-openiot-webapp}
# Only active stores advertising the required content are offered.
root_stores=$(pvesm status --content rootdir | awk 'NR > 1 && $3 == "active" {print $1}')
template_stores=$(pvesm status --content vztmpl | awk 'NR > 1 && $3 == "active" {print $1}')
[[ -n "$root_stores" && -n "$template_stores" ]] || die 'An active rootdir store and an active vztmpl store are required.'
default_storage() {
    local available=$1 preferred
    shift
    for preferred in "$@"; do
        if printf '%s\n' "$available" | grep -Fxq -- "$preferred"; then
            printf '%s\n' "$preferred"
            return
        fi
    done
    printf '%s\n' "$available" | sed -n '1p'
}
STORAGE=${STORAGE:-$(default_storage "$root_stores" local-lvm local)}
TEMPLATE_STORAGE=${TEMPLATE_STORAGE:-$(default_storage "$template_stores" local)}
TEMPLATE=${TEMPLATE:-}
DEBIAN_VERSION=${DEBIAN_VERSION:-13}
WEBAPP_REF=${WEBAPP_REF:-main}
BRIDGE=${BRIDGE:-vmbr0}
IP=${IP:-dhcp}
GATEWAY=${GATEWAY:-}
VLAN=${VLAN:-}
NAMESERVER=${NAMESERVER:-}
CORES=${CORES:-1}
MEMORY=${MEMORY:-256}
DISK_GB=${DISK_GB:-2}
WEBAPP_PORT=${WEBAPP_PORT:-6468}
ONBOOT=${ONBOOT:-1}
SOURCE_DIR=${SOURCE_DIR:-}
INTERACTIVE=${INTERACTIVE:-1}
CONFIRM=${CONFIRM:-}

ask() {
    local variable=$1 label=$2 answer
    printf '%s [%s]: ' "$label" "${!variable}" > /dev/tty
    read -r answer < /dev/tty || die 'Input closed.'
    [[ -z "$answer" ]] || printf -v "$variable" '%s' "$answer"
}
choose_storage() {
    local variable=$1 label=$2 available=$3 purpose=$4 answer choice index
    local -a choices
    mapfile -t choices <<< "$available"
    printf '\n%s\n%s\n' "$label" "$purpose" > /dev/tty
    for (( index=0; index<${#choices[@]}; index++ )); do
        printf '  %s) %s\n' "$(( index + 1 ))" "${choices[index]}" > /dev/tty
    done
    while true; do
        printf 'Choose a number or storage ID [%s]: ' "${!variable}" > /dev/tty
        read -r answer < /dev/tty || die 'Input closed.'
        answer=${answer:-${!variable}}
        for choice in "${choices[@]}"; do
            if [[ "$answer" == "$choice" ]]; then
                printf -v "$variable" '%s' "$choice"
                return
            fi
        done
        if [[ "$answer" =~ ^[1-9][0-9]{0,3}$ ]] && (( answer <= ${#choices[@]} )); then
            printf -v "$variable" '%s' "${choices[answer-1]}"
            return
        fi
        printf 'Invalid choice. Select one of the storage IDs listed above.\n' > /dev/tty
    done
}
printf '\nOpenIOT WebApp LXC installer\n'
if [[ "$INTERACTIVE" == 1 && -r /dev/tty && -w /dev/tty ]]; then
    ask CTID 'Container ID'
    ask CT_HOSTNAME 'Container hostname'
    choose_storage STORAGE 'Root filesystem storage' "$root_stores" \
        'Stores the running container disk. Only stores supporting container filesystems are listed.'
    choose_storage TEMPLATE_STORAGE 'Template archive storage' "$template_stores" \
        'Stores the downloaded Debian template archive; it can differ from the running container disk storage.'
    ask BRIDGE 'Network bridge'
    ask IP 'IPv4 (dhcp or address/prefix)'
    [[ "$IP" == dhcp ]] || ask GATEWAY 'Gateway'
    ask WEBAPP_REF 'WebApp branch, tag or commit'
fi

[[ "$CTID" =~ ^[1-9][0-9]{2,8}$ ]] || die 'CTID must be a numeric Proxmox ID (at least 100).'
[[ "$CT_HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || die 'Use a simple CT_HOSTNAME (1-63 letters, digits or hyphens).'
[[ "$STORAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die 'Invalid storage ID.'
[[ "$TEMPLATE_STORAGE" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || die 'Invalid template storage ID.'
printf '%s\n' "$root_stores" | grep -Fxq -- "$STORAGE" || die 'Selected storage does not offer active rootdir content.'
printf '%s\n' "$template_stores" | grep -Fxq -- "$TEMPLATE_STORAGE" || die 'Selected template storage does not offer active vztmpl content.'
[[ "$BRIDGE" =~ ^[a-zA-Z0-9_.-]+$ ]] || die 'Invalid bridge name.'
[[ "$DEBIAN_VERSION" == 12 || "$DEBIAN_VERSION" == 13 ]] || die 'DEBIAN_VERSION must be 12 or 13.'
[[ -z "$TEMPLATE" || "$TEMPLATE" =~ ^[a-zA-Z0-9_-]+:vztmpl/debian-(12|13)-[^/]+_amd64\.tar\.(zst|xz|gz)$ ]] || die 'Use a Debian 12/13 amd64 template volume ID.'
[[ "$WEBAPP_REF" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]] || die 'Invalid WebApp source ref.'
[[ "$ONBOOT" =~ ^[01]$ ]] || die 'ONBOOT must be 0 or 1.'
for setting in CORES MEMORY DISK_GB WEBAPP_PORT; do
    [[ "${!setting}" =~ ^[1-9][0-9]{0,5}$ ]] || die "$setting must be a positive integer."
done
(( WEBAPP_PORT <= 65535 )) || die 'WEBAPP_PORT must be at most 65535.'
(( MEMORY >= 128 )) || die 'MEMORY must be at least 128 MiB.'
if [[ -n "$VLAN" ]]; then
    [[ "$VLAN" =~ ^[1-9][0-9]{0,3}$ ]] && (( VLAN <= 4094 )) || die 'VLAN must be 1-4094.'
fi
[[ "$IP" == dhcp || "$IP" =~ ^[0-9.]+/[0-9]{1,2}$ ]] || die 'IP must be dhcp or an IPv4 CIDR address.'
[[ -z "$GATEWAY" || "$GATEWAY" =~ ^[0-9.]+$ ]] || die 'GATEWAY must be an IPv4 address.'
[[ "$IP" != dhcp || -z "$GATEWAY" ]] || die 'Do not set GATEWAY with DHCP.'
[[ -z "$NAMESERVER" || "$NAMESERVER" =~ ^[0-9.]+$ ]] || die 'NAMESERVER must be one IPv4 DNS address.'
ip link show dev "$BRIDGE" >/dev/null || die "Bridge not found: $BRIDGE"
# This checks the cluster-wide ID namespace, including VMs and other nodes.
pvesh get /cluster/nextid --vmid "$CTID" >/dev/null

printf '\nCT %s (%s), unprivileged with nesting enabled for systemd; %s CPU, %s MiB RAM, %s GiB on %s\n' \
    "$CTID" "$CT_HOSTNAME" "$CORES" "$MEMORY" "$DISK_GB" "$STORAGE"
printf 'Network: %s, %s; gateway=%s VLAN=%s DNS=%s; port=%s; onboot=%s\n' \
    "$BRIDGE" "$IP" "${GATEWAY:-default}" "${VLAN:-none}" "${NAMESERVER:-inherited}" "$WEBAPP_PORT" "$ONBOOT"
printf 'Template: %s; source: %s\n' "${TEMPLATE:-auto Debian $DEBIAN_VERSION on $TEMPLATE_STORAGE}" "${SOURCE_DIR:-GitHub DeDaMrAzR/OpenIOTwebapp ref $WEBAPP_REF}"
printf 'Installation downloads source/template as needed and installs packages inside the new CT.\n'
if [[ "$CONFIRM" != yes ]]; then
    [[ "$INTERACTIVE" == 1 && -r /dev/tty && -w /dev/tty ]] || die 'Use an interactive terminal, or set CONFIRM=yes for unattended installation.'
    printf 'Create this container? [y/N]: ' > /dev/tty
    read -r answer < /dev/tty || die 'Input closed.'
    [[ "$answer" == y || "$answer" == Y ]] || die 'Cancelled; no container created.'
fi

root_password_set=0
if [[ "$INTERACTIVE" == 1 && -r /dev/tty && -w /dev/tty ]]; then
    set +x
    set +a
    unset root_password root_password_confirm
    while true; do
        printf 'Root console password: ' > /dev/tty
        IFS= read -r -s root_password < /dev/tty || die 'Input closed.'
        printf '\nConfirm root console password: ' > /dev/tty
        IFS= read -r -s root_password_confirm < /dev/tty || die 'Input closed.'
        printf '\n' > /dev/tty
        if [[ -n "$root_password" && "$root_password" == "$root_password_confirm" ]]; then
            root_password_set=1
            unset root_password_confirm
            break
        fi
        unset root_password root_password_confirm
        printf 'Passwords must be nonempty and match. Try again.\n' > /dev/tty
    done
fi

if [[ -z "$TEMPLATE" ]]; then
    TEMPLATE=$(pveam list "$TEMPLATE_STORAGE" | awk -v v="$DEBIAN_VERSION" \
        '$1 ~ (":vztmpl/debian-" v "-standard_.*_amd64\\.tar\\.(zst|xz|gz)$") {print $1}' | sort -V | sed -n '$p')
    if [[ -z "$TEMPLATE" ]]; then
        pveam update
        template_name=$(pveam available --section system | awk -v v="$DEBIAN_VERSION" \
            '$2 ~ ("^debian-" v "-standard_.*_amd64\\.tar\\.(zst|xz|gz)$") {print $2}' | sort -V | sed -n '$p')
        [[ -n "$template_name" ]] || die "No Debian $DEBIAN_VERSION amd64 standard template found; select TEMPLATE explicitly."
        pveam download "$TEMPLATE_STORAGE" "$template_name"
        TEMPLATE="$TEMPLATE_STORAGE:vztmpl/$template_name"
    fi
fi
template_path=$(pvesm path "$TEMPLATE")
[[ -f "$template_path" ]] || die "Template not found locally: $TEMPLATE"
work=$(mktemp -d /tmp/openiot-webapp.XXXXXXXX)
source_label="local directory: $SOURCE_DIR"
if [[ -z "$SOURCE_DIR" ]]; then
    download=(curl --fail --silent --show-error --location --retry 3 --proto '=https' --tlsv1.2)
    if [[ "$WEBAPP_REF" =~ ^[0-9a-f]{40}$ ]]; then
        source_commit=$WEBAPP_REF
    else
        api=$("${download[@]}" "https://api.github.com/repos/DeDaMrAzR/OpenIOTwebapp/commits/$WEBAPP_REF")
        source_commit=$(printf '%s\n' "$api" | sed -n 's/^  "sha": "\([0-9a-f]\{40\}\)",$/\1/p' | sed -n '1p')
    fi
    [[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || die 'Could not resolve WebApp ref to a commit (GitHub API may be rate limited).'
    source_label="https://github.com/DeDaMrAzR/OpenIOTwebapp commit $source_commit"
    printf 'Installing WebApp commit: %s\n' "$source_commit"
    "${download[@]}" "https://codeload.github.com/DeDaMrAzR/OpenIOTwebapp/tar.gz/$source_commit" -o "$work/source.tar.gz"
    prefix="OpenIOTwebapp-$source_commit"
    # Extract exact asset classes only; never copy a .git or local guidance tree.
    tar -tzf "$work/source.tar.gz" > "$work/members"
    mapfile -t members < <(grep -E "^$prefix/(startup\\.js|templateParser\\.js|tuyaExporter\\.js|nginx\\.conf|lib/[^/]+\\.js|vue/[^/]+\\.vue)$" "$work/members")
    (( ${#members[@]} > 0 )) || die 'Source archive has no expected assets.'
    SOURCE_DIR="$work/source"
    mkdir "$SOURCE_DIR"
    tar -xzf "$work/source.tar.gz" -C "$SOURCE_DIR" --strip-components=1 -- "${members[@]}"
fi
cd -- "$SOURCE_DIR"
shopt -s nullglob
assets=(startup.js templateParser.js tuyaExporter.js nginx.conf lib/*.js vue/*.vue)
[[ -f lib/vue.min.js && -f lib/httpVueLoader.js && -f vue/myComponent.vue ]] || die 'SOURCE_DIR is not a complete WebApp checkout.'
for asset in "${assets[@]}"; do
    [[ -f "$asset" && ! -L "$asset" ]] || die "Missing or symbolic-link asset: $asset"
done
[[ ! -L lib && ! -L vue ]] || die 'Asset directories must not be symbolic links.'
# The native service requires a /run PID file. Refuse unfamiliar config layouts.
grep -qx 'pid /tmp/nginx.pid;' nginx.conf || die 'Unexpected nginx PID configuration.'
grep -qx '        listen 8080;' nginx.conf || die 'Unexpected nginx listen configuration.'
archive="$work/assets.tar.gz"
tar -czf "$archive" -- "${assets[@]}"

network="name=eth0,bridge=$BRIDGE,ip=$IP,ip6=manual"
[[ -z "$GATEWAY" ]] || network+=",gw=$GATEWAY"
[[ -z "$VLAN" ]] || network+=",tag=$VLAN"
create_options=(--hostname "$CT_HOSTNAME" --unprivileged 1 --features nesting=1 --cores "$CORES"
    --memory "$MEMORY" --swap 0 --rootfs "$STORAGE:$DISK_GB"
    --net0 "$network" --onboot "$ONBOOT")
[[ -z "$NAMESERVER" ]] || create_options+=(--nameserver "$NAMESERVER")

printf 'Creating CT %s from %s; source: %s\n' "$CTID" "$TEMPLATE" "$PWD"
pct create "$CTID" "$TEMPLATE" "${create_options[@]}"
created=1
ct_config=$(pct config "$CTID")
grep -Fxq 'unprivileged: 1' <<< "$ct_config" || die "CT $CTID is not confirmed unprivileged; refusing to start. Inspect with: pct config $CTID"
printf 'Confirmed CT %s is unprivileged.\n' "$CTID"
pct start "$CTID"
ready=0
for (( attempt=0; attempt<30; attempt++ )); do
    if pct exec "$CTID" -- /bin/true 2>/dev/null; then
        ready=1
        break
    fi
    sleep 2
done
(( ready )) || die "CT $CTID did not become ready; inspect it before retrying."
if (( root_password_set )); then
    if ! printf 'root:%s\n' "$root_password" | pct exec "$CTID" --keep-env 0 -- chpasswd; then
        unset root_password root_password_confirm
        die "Failed to set the root password in CT $CTID; inspect it before continuing."
    fi
    unset root_password root_password_confirm
fi
pct push "$CTID" "$archive" /tmp/openiot-webapp.tar.gz --perms 0644
pct exec "$CTID" --keep-env 0 -- bash -s -- "$WEBAPP_PORT" "$source_label" <<'CONTAINER'
set -Eeuo pipefail
port=$1
source_label=$2
. /etc/os-release
[[ "$ID" == debian && ( "$VERSION_ID" == 12 || "$VERSION_ID" == 13 ) ]] || {
    echo 'Only Debian 12/13 templates are supported by this script.' >&2
    exit 1
}
export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=3 update
apt-get -o Acquire::Retries=3 install -y --no-install-recommends nginx-light ca-certificates curl
systemctl stop nginx
install -d -m 0755 /srv/webapp
tar -xzf /tmp/openiot-webapp.tar.gz -C /srv/webapp
printf '%s\n' "$source_label" > /etc/openiot-webapp-source
chmod 0644 /etc/openiot-webapp-source
chown -R root:root /srv/webapp
find /srv/webapp -type d -exec chmod 0755 {} +
find /srv/webapp -type f -exec chmod 0644 {} +
install -d -m 0755 /var/log/nginx
sed -e 's|^pid /tmp/nginx.pid;$|pid /run/nginx.pid;|' \
    -e 's|^error_log /dev/stderr warn;$|error_log /var/log/nginx/error.log warn;|' \
    -e 's|^    access_log /dev/stdout;$|    access_log /var/log/nginx/access.log;|' \
    -e "s|^        listen 8080;$|        listen $port;|" \
    /srv/webapp/nginx.conf > /etc/nginx/nginx.conf
rm -- /srv/webapp/nginx.conf
nginx -t
systemctl enable nginx
systemctl restart nginx
# Check the served assets and hosting contract before reporting success.
base="http://127.0.0.1:$port"
curl --fail --silent --show-error "$base/startup.js" -o /tmp/openiot-startup.js
cmp /srv/webapp/startup.js /tmp/openiot-startup.js
headers=$(curl --fail --silent --show-error --head "$base/vue/myComponent.vue")
printf '%s\n' "$headers" | grep -iq '^Access-Control-Allow-Origin: \*'
printf '%s\n' "$headers" | grep -iq '^Content-Type: text/plain'
[[ $(curl --silent --show-error -o /dev/null -w '%{http_code}' "$base/__openiot_missing_asset__") == 404 ]]
[[ $(curl --silent --show-error -X OPTIONS -o /dev/null -w '%{http_code}' "$base/startup.js") == 204 ]]
rm -- /tmp/openiot-webapp.tar.gz /tmp/openiot-startup.js
CONTAINER

addresses=$(pct exec "$CTID" --keep-env 0 -- ip -4 -o addr show dev eth0 scope global | \
    awk '{split($4, address, "/"); print address[1]}')
[[ -n "$addresses" ]] || die "CT $CTID has no IPv4 address yet. Inspect its DHCP/network configuration before using it."
printf '\nCT %s is running. Container asset URL(s):\n' "$CTID"
while IFS= read -r address; do
    printf '  http://%s:%s/\n' "$address" "$WEBAPP_PORT"
done <<< "$addresses"
printf '\nSet device Configure WebApp to the chosen URL and use Launch WebApp.\n'
if (( root_password_set )); then
    printf 'Console login: root, using the password chosen during installation.\n'
else
    printf 'No root password was configured. Set one from the host with: pct exec %s -- passwd root\n' "$CTID"
fi
printf 'Enter the container from the Proxmox host with: pct enter %s\n' "$CTID"
printf 'Validate the WebApp through a device before retiring any previous deployment.\n'
