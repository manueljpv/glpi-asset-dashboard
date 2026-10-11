# glpi-asset-dashboard

[Português](README.md) · **English** · [Español (Honduras)](README.es-HN.md)

A friendly web dashboard for IT asset control, built on top of [GLPI](https://glpi-project.org/), plus a GPO that keeps the GLPI Agent installed and the inventory always up to date.

GLPI stores everything, but it is not the most practical tool for a department manager who just wants to know "which equipment in my area needs replacing or upgrading this year?". This project answers that question with a simple lookup page fed live by GLPI itself.

> **Disclaimer: fictitious data.** Every name, domain, IP address and hostname in this repository (`empresa.example.com`, `empresa.local`, `10.0.0.x`, `203.0.113.x`, `WS-EX01`…) is an invented example. Nothing here comes from a real environment. See the [final section](#disclaimer-fictitious-data).

## The problem

- Managers need to plan their budget for maintenance, upgrades and replacement of equipment, but the GLPI interface is aimed at the IT team.
- Exporting CSV files from GLPI and building spreadsheets by hand goes stale quickly and creates rework.
- An inventory is only reliable if the agents are installed and reporting on time. A poorly done GPO installation (for example, reinstalling at every boot) produces duplicate inventory and stale data.

## What the project delivers

**1. Asset dashboard (`painel/`)**

- A single page (HTML, CSS and JS, no external dependencies) that queries GLPI through a PHP layer. The API tokens stay on the server only, never in the browser.
- Covers the **Computer**, **Monitor** and **Phone** itemtypes.
- Classifies each endpoint by CPU: **OK**, **Attention** or **Obsolete**.
- Raises **RAM upgrade** and **SSD upgrade** alerts.
- Has its own category for **servers/VMs** and for **peripherals** (no hardware classification).
- Provides **data quality indicators** for IT: duplicated hostnames, empty group/department, unusual type, and equipment with no owner.
- Offers free-text search, filters by department, type, status and upgrade, clickable cards, and sorting by column.
- Groups the monitor or phone under the computer of the same owner.

**2. GLPI Agent automation through GPO (`gpo/`)**

- Installs or updates the agent **without downgrading**, and does not reinstall when the version is already current.
- Makes sure the service is running and fixes the `server` value in the registry.
- Creates a local scheduled task that **forces an inventory** at boot and at logon, with a minimum interval of 2 hours.
- Enables the agent's tray icon (see the [GPO documentation](docs/gpo-glpi-agent.md) for why this takes some care).

## High-level architecture

```
Browser ──► Reverse proxy (TLS) ──► Nginx ──► PHP-FPM ──► GLPI REST API
                                       │          │
                                       │          └─ api_ativos.php + glpi_client.php
                                       │             (tokens live here, with a file cache)
                                       └─ painel_ativos.html (static)

Windows workstations ──► GPO (Startup) ──► Install-GLPIAgent.ps1
                                            └─ scheduled task ──► Invoke-GLPIInventory.ps1
                                                                    └─ http://127.0.0.1:62354/now ──► agent ──► GLPI
```

The reverse proxy is optional: it is used to get a valid certificate and to restrict access to private networks. The design decision was to keep the dashboard **without login**, for internal use or over VPN only. Details in [`docs/painel-documentacao.md`](docs/painel-documentacao.md) (in Portuguese).

## Prerequisites

**Dashboard**

- GLPI 10.x with the **REST API** enabled.
- A GLPI **API client** (it generates the `App-Token`) and a **read-only service user** (it generates the `User-Token`).
- A web server with **PHP** (with the `curl` extension) and HTTPS. The examples use Nginx + PHP-FPM.
- Network access from the dashboard server to the GLPI API.

**Agent GPO**

- Active Directory with a Startup GPO (Computer Configuration).
- A network share readable by the workstations (the examples use `NETLOGON`).
- The [GLPI Agent](https://github.com/glpi-project/glpi-agent/releases) MSI installer (this repository does **not** include the `.msi`).

## Deployment

### 1. Dashboard

1. Create a directory **separate** from the GLPI installation, for example `/var/www/painel-ativos/`, and copy the contents of `painel/` into it. Do not put the dashboard inside the GLPI folder and do not edit the GLPI vhost.
2. Copy `config.example.php` to `config.php` and fill in `glpi_url`, `app_token` and `user_token`. **Never commit the filled-in `config.php`.**
3. Set ownership and permissions (example with Nginx and PHP-FPM running as `apache`):

   ```bash
   chown -R apache:nginx /var/www/painel-ativos
   chmod 640 /var/www/painel-ativos/config.php
   chown apache:apache /var/www/painel-ativos/cache && chmod 770 /var/www/painel-ativos/cache
   ```

   If you copy a file as root after the `chown`, it goes back to `root:root`. Reapply `chown`/`chmod` after every upload.
4. Check the PHP syntax: `for f in config.php glpi_client.php api_ativos.php common.php; do php -l "$f"; done`.
5. Create a vhost of its own, in a new file (for example `/etc/nginx/conf.d/ativos.conf`). This is the vhost used in the project, anonymized; it shares port 443 with GLPI and reuses the Let's Encrypt certificate (adjust the paths to your certbot or your certificate):

   ```nginx
   server {
       listen 443 ssl;
       server_name ativos.empresa.example.com;

       root /var/www/painel-ativos;
       index painel_ativos.html;

       ssl_certificate     /etc/letsencrypt/live/glpi.empresa.example.com/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/glpi.empresa.example.com/privkey.pem;
       include /etc/letsencrypt/options-ssl-nginx.conf;
       ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

       # Never serve the configuration or the internal code, nor the cache.
       location ~* /(config\.example\.php|config\.php|common\.php|glpi_client\.php)$ {
           deny all;
           return 404;
       }
       location ~ ^/cache/ {
           deny all;
           return 404;
       }

       location ~ \.php$ {
           fastcgi_pass unix:/run/php-fpm/www.sock;
           fastcgi_split_path_info ^(.+\.php)(/.+)$;
           try_files $fastcgi_script_name =404;
           set $path_info $fastcgi_path_info;
           fastcgi_param PATH_INFO $path_info;
           fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
           include fastcgi_params;
           fastcgi_index index.php;
       }

       location / {
           try_files $uri $uri/ =404;
       }
   }
   ```

   Nginx picks the vhost by name (`server_name`), so several sites can share port 443 without conflict and **without editing** the GLPI vhost. The PHP-FPM socket path (`/run/php-fpm/www.sock`) varies by distribution.
6. Run `nginx -t` and only then `systemctl reload nginx` (avoid `restart`).
7. Edit the `SSD_EXPANSION_LIST` list in `painel_ativos.html` with the hostnames that make sense in your environment.

### 2. Agent GPO

1. Put the following on the network share (for example `\\empresa.local\netlogon\scripts\GLPI\`): the agent MSI, `Install-GLPIAgent.ps1`, `Invoke-GLPIInventory.ps1` and `install-glpi.bat`.
2. In `Install-GLPIAgent.ps1`, adjust the parameter block: `$TargetVersion`, `$SetupLocation` and `$GlpiServerUrl`. The MSI name must match `GLPI-Agent-<version>-x64.msi`.
3. Create a GPO with a **Startup Script** (Computer Configuration) pointing to `install-glpi.bat`, and link it to the computer OUs.
4. In GLPI, shorten the server's inventory interval (the project used 12 h) as a safety net in case the local script fails.
5. The scripts run as `SYSTEM` and write a log to `C:\ProgramData\GLPI-Agent-Deploy\install-glpi-agent.log`.

## How to validate

**Dashboard**

- Open `api_ativos.php?debug=1`. The expected result is `campos_faltando: []` (no missing fields) for Computer, Monitor and Phone.
- Use `api_ativos.php?nocache=1` to bypass the cache and query GLPI again.
- Open the dashboard in the browser and check the total number of assets in the header and a sample of records against GLPI.

**GPO**

- Check the log at `C:\ProgramData\GLPI-Agent-Deploy\install-glpi-agent.log` on a workstation.
- `Get-ScheduledTask -TaskName 'GLPI-Agent - Forcar Inventario'` should show the task created; a `LastTaskResult` of `0` means success.
- The installed version is in `HKLM:\SOFTWARE\GLPI-Agent\Installer` (`Version`).
- To force an inventory manually, open `http://127.0.0.1:62354/now` on the workstation itself.

## Common problems

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| HTTP 500 when opening the API | PHP-FPM cannot read `config.php` (file copied as root) | `chown apache:nginx config.php && chmod 640 config.php` |
| Syntax error in `config.php` | Tokens pasted without single quotes | Put single quotes around each token and run `php -l config.php` |
| `campos_faltando` is not empty | GLPI uses compound uids (`Computer.<Type>.<field>`) that vary between installations | Open `?debug=1&itemtype=Computer`, find the real uid and adjust `candidatos_de_campo()` in `glpi_client.php` |
| No asset shows up as "needs RAM" | GLPI stores memory in **MB** and the rule expects GB | Already handled in `glpi_client.php` (division by 1024); if you change it, validate with `?nocache=1` |
| Stale data | 15-minute cache | Use the "Atualizar dados" (refresh data) button or `?nocache=1` |
| Certificate warning | The certificate covers a different name than the vhost | Issue a certificate for the dashboard name (for example through a reverse proxy) |
| `curl` tests on the GLPI server itself do not resolve the dashboard name | The server uses public DNS, without the internal records | Use `curl --resolve <name>:443:<ip>` |
| Agent tray icon "disappeared" right after installing | Autostart only fires in a **new session** | Log off and back on before investigating |
| `msiexec` error 1625 after a reboot | Transient Windows Installer condition | Reboot again before investigating further |
| Cannot overwrite the scripts on the share | Only administrators of the file server have write access | Use an account with administrator rights on that server |

## Security

- The dashboard has **no authentication** (a design decision). Expose it only on an internal network or VPN, and/or restrict it by IP at the proxy.
- The `api_ativos.php?debug=1` endpoint shows the GLPI field structure and is also unauthenticated. Restrict access to it or remove it in production.
- Keep `config.php` and `cache/` out of the browser's reach (see the example vhost) and **never** commit them.
- Use a **read-only** service user and, if possible, restrict the API client by IP.

## Documentation and roadmap

- [`docs/painel-documentacao.md`](docs/painel-documentacao.md): architecture, business rules and how to update the dashboard.
- [`docs/gpo-glpi-agent.md`](docs/gpo-glpi-agent.md): diagnosis, design and tests of the GPO.
- [`docs/historico-painel.md`](docs/historico-painel.md): history of decisions and bugs found during deployment.
- [`ROADMAP.en.md`](ROADMAP.en.md): future improvements.

The `docs/` folder is available in Portuguese only.

## Disclaimer: fictitious data

This repository was derived from a real infrastructure project and **was anonymized before publication**. Every company name, domain, IP address, hostname, account and person that appears here is **fictitious** and serves only as an example:

- Domains: `empresa.example.com` (public) and `empresa.local` (internal).
- Networks: `10.0.0.x` (internal) and `203.0.113.x` (range reserved for documentation).
- Machines: `WS-EX01`, `srv-ad01`, `srv-proxy01`, etc.

The values in `config.example.php` are placeholders only. Replace everything with your own environment.

## License

[GNU GPL v3.0](LICENSE).

Maintained by [@manueljpv](https://github.com/manueljpv).
