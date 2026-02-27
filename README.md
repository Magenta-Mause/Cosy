<p align="center">
    <a href="https://cosy-docs.jannekeipert.de">
        <img src="./.github/images/logo.gif">
    </a>
</p>


 ***     
<center>
    <h3 align="center">
        Simple and beautiful way to host servers for videogames on your own hardware.
    </h3>
</center>

<p align="center">
  <a href="https://opensource.org/licenses/mit">
    <img src="https://img.shields.io/github/license/Magenta-Mause/Cosy" alt="License of medals" />
  </a>
  <a href="https://github.com/Magenta-Mause/Cosy/releases">
    <img src="https://img.shields.io/github/v/release/Magenta-Mause/Cosy" alt="Newest Release" />
  </a> 
  <a href="https://github.com/Magenta-Mause/Cosy-Templates">
    <img src="https://img.shields.io/badge/github-templates--repository-blue?logo=github">
  </a>
  <a href="https://cosy-docs.jannekeipert.de/">
    <img src="https://img.shields.io/badge/Home%20Page-F7951D" alt="Home Page" />
  </a>
  <a href="https://github.com/Magenta-Mause/Cosy-Templates/tree/main/templates">
    <img src="https://img.shields.io/github/directory-file-count/Magenta-Mause/Cosy-Templates/templates?label=Supported%20Games" alt="Supported Games">
  </a>
</p>

### Features:

- beautiful UI
- containerized game server management on self hosted node
- simple creation of game servers from templates
- start stop with realtime status
- real-time monitoring and dashboards
- send remote commands to your game server
- file management
- user und quota management
- custom metrics API to push custom game server metrics to your game server dashboard
- multi-user collaboration with fine-grained permissions
- event-driven webhooks to subscribe your own services to server lifecycle events

---

### Security

**Docker Socket Access**

When deploying COSY, the installation script configures the application to run with access to the Docker socket (`/var/run/docker.sock`). This grants COSY **root-equivalent privileges** on the host system.

**Implications:**
- COSY can start, stop, inspect, and manage any Docker container on the host
- COSY can access container images, volumes, and networks
- COSY can execute arbitrary commands with root privileges (via container execution)

**Security Recommendations:**
- Only deploy COSY in trusted environments (internal networks, private infrastructure)
- Run COSY on dedicated hosts or in isolated environments when possible
- Regularly update COSY

---

### Quick Start

*Install Cosy*:

```bash
curl -fsSL -o install_cosy.sh https://raw.githubusercontent.com/Magenta-Mause/Cosy/refs/heads/main/install_cosy.sh && chmod +x ./install_cosy.sh && sudo ./install_cosy.sh docker
```

Remove the `install_cosy.sh` file after the installation.

*Uninstall Cosy*:

```bash
curl -fsSL -o uninstall_cosy.sh https://raw.githubusercontent.com/Magenta-Mause/Cosy/refs/heads/main/uninstall_cosy.sh && chmod +x ./uninstall_cosy.sh && sudo ./uninstall_cosy.sh docker
```

Remove the `uninstall_cosy.sh` file after the uninstallation.

### Installation:

```
./install_cosy.sh <command> [OPTIONS]
```

The deployment method is chosen as a **subcommand** — either `docker` or `kubernetes` (alias `k8s`).
Each subcommand accepts its own set of flags. Run `./install_cosy.sh <command> --help` to see the available options for a specific method.

If the script is run interactively (in a terminal) without `--default`, it will prompt for any option that was not provided via a flag.

> ⚠️ **Save the printed password** — it is randomly generated and only stored in a credentials file for Docker installs.

---

#### Requirements

<details>
  <summary><strong>Docker</strong></summary>

  - `docker` (v29.1.3 was tested, others may work)
  - `docker compose` plugin (or standalone `docker-compose`)
  - One of `htpasswd` or `openssl` (for credential generation)
</details>

<details>
  <summary><strong>Kubernetes</strong></summary>

  - `kubectl` configured with access to a Kubernetes cluster
  - An Ingress controller running in the cluster
  - One of `htpasswd`, `openssl`, or `python3` (for credential generation)
  - each node in the cluster must have docker installed
</details>

---

#### Subcommands

| Command | Description |
| --- | --- |
| `docker` | Deploy COSY using Docker Compose. All services run as containers on the host. Configuration files, volumes, and credentials are stored in a local directory. |
| `kubernetes` (or `k8s`) | Deploy COSY to a Kubernetes cluster. All resources are created inside a dedicated namespace. Manifests are downloaded to a temporary directory and cleaned up automatically. |

---

#### `install_cosy.sh docker`

<details>
  <summary>Options</summary>

| Flag | Description | Allowed values | Default |
| --- | --- | --- | --- |
| `--path /path/to/base` | Base directory to install into. A `cosy/` subdirectory is created inside this path (e.g. `--path /opt` → `/opt/cosy`). Supports `~`, relative paths, and absolute paths. | Any writable directory path | `/opt` |
| `--port <port>` | Host port cosy is exposed on. | Integer between `1` and `65535` | `80` |
| `--username <name>` | Username for the initial COSY admin account created on first boot. | Any non-empty string | `admin` |
| `--domain <domain>` | Domain or hostname used to construct the allowed CORS origin (`http://<domain>:<port>`). Should match the address users will use to access COSY. | Any valid hostname or domain | Value of `/etc/hostname` |
| `--default` | Skip all interactive prompts and use default values for any option not explicitly provided. Useful for scripted / automated installs. | — | — |
| `-h`, `--help` | Print the Docker-specific help message and exit. | — | — |

</details>

**Examples:**

```bash
# Interactive — prompts for all options not provided
./install_cosy.sh docker

# Non-interactive with custom port and domain
./install_cosy.sh docker --port 8080 --domain example.com --default

# Custom install path and admin username
./install_cosy.sh docker --path ~/cosy-install --username myadmin --default
```

---

#### `install_cosy.sh kubernetes`

<details>
  <summary>Options</summary>

| Flag | Description | Allowed values | Default |
| --- | --- | --- | --- |
| `--username <name>` | Username for the initial COSY admin account. | Any non-empty string | `admin` |
| `--domain <domain>` | Domain used for the Ingress host rules and CORS origin. Must match the DNS name pointing to the cluster's Ingress controller. | Any valid hostname or domain | Value of `/etc/hostname` |
| `--default` | Skip all interactive prompts and use defaults. | — | — |
| `-h`, `--help` | Print the Kubernetes-specific help message and exit. | — | — |

</details>

**Examples:**

```bash
# Interactive
./install_cosy.sh kubernetes

# Shorthand alias, non-interactive
./install_cosy.sh k8s --domain cosy.example.com --default

# Custom admin username
./install_cosy.sh k8s --username myadmin --domain cosy.example.com --default
```

---

### Uninstallation:

```
./uninstall_cosy.sh <command> [OPTIONS]
```

The uninstall method is chosen as a **subcommand** — either `docker` or `kubernetes` (alias `k8s`).
Run `./uninstall_cosy.sh <command> --help` to see the available options for a specific method.

A confirmation prompt is shown before any destructive action unless `-y` / `--yes` is passed.

---

#### `uninstall_cosy.sh docker`

Performs the following steps:
1. Locates the `cosy/` directory inside the provided (or default) base path
2. Runs `docker compose down --volumes --remove-orphans` to stop all containers and remove Docker volumes (database, Loki, InfluxDB data)
3. Force-removes any leftover containers by name
4. Deletes the entire installation directory

<details>
  <summary>Options</summary>

| Flag | Description | Allowed values | Default |
| --- | --- | --- | --- |
| `--path /path/to/base` | Base directory that contains the `cosy/` folder. Must be the same value used during installation. | Any directory path | `/opt` |
| `-y`, `--yes` | Skip the confirmation prompt. Useful for scripted teardowns. | — | — |
| `-h`, `--help` | Print the Docker-specific help message and exit. | — | — |

</details>

**Examples:**

```bash
# Interactive — prompts for confirmation
./uninstall_cosy.sh docker

# Custom path, skip confirmation
./uninstall_cosy.sh docker --path ~/cosy-install -y
```

---

#### `uninstall_cosy.sh kubernetes`

Performs the following steps:
1. Checks that `kubectl` is installed and the cluster is reachable
2. Verifies the target namespace exists
3. Deletes the entire Kubernetes namespace, which removes all Deployments, Services, Secrets, PVCs, and other resources within it

<details>
  <summary>Options</summary>

| Flag | Description | Allowed values | Default |
| --- | --- | --- | --- |
| `--namespace <ns>` | The Kubernetes namespace to delete. Must match the namespace used during installation. | Any existing namespace name | `cosy` |
| `-y`, `--yes` | Skip the confirmation prompt. | — | — |
| `-h`, `--help` | Print the Kubernetes-specific help message and exit. | — | — |

</details>

**Examples:**

```bash
# Interactive — prompts for confirmation
./uninstall_cosy.sh kubernetes

# Shorthand alias, custom namespace, skip confirmation
./uninstall_cosy.sh k8s --namespace my-cosy-ns -y
```
