<p align="center">
    <a href="https://cosy-docs.jannekeipert.de">
        <img src="./.github/images/logo.gif">
    </a>
</p>


 ***     

<center>
    <h3 align="center">
        Placeholder for some herotext
    </h3>
    <p align="center">
        <strong>Latest version:</strong> v.x.x
    </p> 
</center>

### TODO
- docker install script: if not fully uninstalled there should be no message "successfully uninstalled"
- einige flags machen nur sinn bei docker installation, auch nur dann abfragen

### Features:

- TBA

### Installation:

Requirements:
- `docker` (v29.1.3 was tested, others may work)
- `docker compose` plugin (or standalone `docker-compose`)
- One of `htpasswd`, `openssl`, or `python3` (for credential generation)

**Quick install** (interactive, prompts for all options):

```bash
curl -fsSL https://raw.githubusercontent.com/Magenta-Mause/Cosy/main/install_cosy.sh | bash
```


The installer will:
1. Check that Docker and Docker Compose are installed and running
2. Generate all required credentials (database, Loki, InfluxDB, admin account)
3. Download the Docker Compose configuration files
4. Write a `.env` file into the installation directory
5. Start all containers and wait for the backend to become healthy
6. Print the admin credentials and access URL

> ⚠️ **Save the printed password** — it is randomly generated and not stored anywhere else.

---

### Options (install):

<details>
  <summary>Click to expand</summary>

| Option | Description | Default |
| --- | --- | --- |
| `--method docker\|kubernetes` | Deployment method. Only `docker` is currently supported; `kubernetes` is planned. | `docker` |
| `--path /path/to/base` | Base directory to install into. A `cosy/` subdirectory is created inside this path (e.g. `--path /opt` → installs to `/opt/cosy`). Supports `~`, relative paths, and absolute paths. | `/opt` |
| `--username <name>` | Username for the initial COSY admin account created on first boot. | `admin` |
| `--port <port>` | Host port the nginx reverse proxy is exposed on. The frontend is served at `/` and the backend API at `/api/` through this port. | `80` |
| `--domain <domain>` | Domain or hostname used to construct the allowed CORS origin passed to the backend (`<domain>:<port>`). | Value of `/etc/hostname` |
| `--default` | Skip all interactive prompts and use default values for any option not explicitly set via another flag. Useful for scripted/automated installs. | — |
| `-h`, `--help` | Print usage information and exit. | — |

**Example — non-interactive install on a custom port and path:**

```bash
./install_cosy.sh --port 8080 --domain example.com --default
```

</details>

---

### Uninstallation:

```bash
./uninstall_cosy.sh
```

The uninstaller will:
1. Locate the `cosy/` directory inside the provided (or default) base path
2. Run `docker compose down --volumes --remove-orphans` to stop all containers and remove all Docker volumes (database, Loki, InfluxDB)
3. Force-remove any leftover containers by name
4. Delete the entire installation directory

### Options (uninstall):

<details>
  <summary>Click to expand</summary>

| Option | Description | Default |
| --- | --- | --- |
| `--path /path/to/base` | Base directory that contains the `cosy/` folder (same value used during install). | `/opt` |
| `-y`, `--yes` | Skip the confirmation prompt. Useful for scripted teardowns. | — |
| `-h`, `--help` | Print usage information and exit. | — |

**Example — non-interactive uninstall from a custom path:**

```bash
./uninstall_cosy.sh y
```

</details>
