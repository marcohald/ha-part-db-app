# Part-DB app

Runs [Part-DB](https://github.com/Part-DB/Part-DB-server), an open source
inventory management system for electronic components, from the
`marcohald/part-db` Docker image.

## Installation

1. In Home Assistant go to **Settings -> Apps -> Install Apps**.
2. Open the three-dot menu, choose **Repositories**, and add:
   `https://github.com/argaar/ha-part-db-app`
3. Go back to the **Store** and install the **Part-DB** app (scroll down if
   you can't find it).
4. Review the options below, then **Start** the app.
5. Open the UI from the **Open Web UI** button or the Part-DB entry in the
   Home Assistant sidebar (Ingress). Direct access on a host port is optional
   and off by default; map one under the app's **Network** settings if you
   want to reach Part-DB outside Home Assistant.

On first start Part-DB creates the database and an administrator account. Watch
the app log: the initial admin password is printed there the first time the
database is initialized. Log in with user `admin` and that password, then
change it.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `default_lang` | `en` | Default UI language. |
| `default_timezone` | `Europe/Rome` | PHP timezone identifier. |
| `base_currency` | `EUR` | Reference currency (ISO 4217). |
| `instance_name` | `Part-DB` | Name shown in the UI. |
| `allow_attachment_downloads` | `false` | Allow downloading attachments from URLs. |
| `max_attachment_file_size` | `100M` | Attachment upload limit. |
| `db_automigrate` | `true` | Run DB migrations on start (backup taken first). |
| `trusted_proxies` | `172.30.32.0/23,127.0.0.0/8,::1` | Trusted reverse-proxy ranges. |
| `trusted_hosts` | (empty) | Optional unquoted regex of allowed host names, e.g. `^(192\.168\.1\.253)$`. Empty = accept any host. |
| `database_url` | (empty) | Optional external DB DSN. Empty = built-in SQLite. |
| `header_auth_enabled` | `false` | Enable authentication via HTTP Headers (useful for reverse proxies/Ingress). |
| `header_auth_header_name` | `REMOTE_USER` | The HTTP header name that passes the username. |
| `header_auth_auto_create` | `true` | Automatically create a user if they do not exist. |
| `header_auth_disable_password_expiration` | `true` | Disable password expiration for auto-created users. |
| `header_auth_default_group` | (empty) | Group name to assign to auto-created users. |

## Data persistence

The app stores all mutable data in its `app_config` folder, which Home
Assistant keeps and exposes to you (mounted as `/config` inside the container):

- `uploads/` (attachments and, by default, the SQLite database `app.db`)
- `media/` (generated thumbnails and public media)
- `app_secret` (a unique random `APP_SECRET` generated on first start,
  replacing the insecure default shipped with the image)

The app symlinks Part-DB's `/app/uploads` and `/app/public/media` directories
to these locations on start.

**Why `app_config` and not `/data`.** Home Assistant *always* deletes an
app's `/data` volume on uninstall - there is no option to keep it. The
`app_config` folder is different: it is preserved on uninstall unless you tick
**"Also remove app data"** in the uninstall dialog. Storing data here means an
uninstall/reinstall keeps your database, uploads, media, and `APP_SECRET`.

- Uninstall with the box **unchecked** -> data kept, reinstalling the same app
  (same repository, so same slug) picks it back up automatically.
- Uninstall with the box **checked** -> clean slate (empty DB, new `APP_SECRET`).

Preserved data is tied to the app's slug. Reinstalling from a different source
(for example a local copy instead of the repository) gets a fresh folder. For a
portable copy, take a Home Assistant backup of the app and restore it.

## Using an external database

Set `database_url` to a Doctrine DSN to use MySQL/MariaDB or PostgreSQL instead
of SQLite, for example:

```
mysql://partdb:secret@core-mariadb:3306/partdb?serverVersion=10.11.2-MariaDB
postgresql://partdb:secret@host:5432/partdb?serverVersion=16&charset=utf8
```

With `db_automigrate` enabled the schema is created and upgraded automatically.

## Updating Part-DB

This app pins a specific upstream version. To move to a newer Part-DB
release, edit `build.yaml` (the `marcohald/part-db` tags) and the
`version` in `config.yaml`, then rebuild the app.

## Notes and limitations

- Home Assistant Ingress is the default access path: the UI is available from
  the sidebar panel. Direct access on a host port is optional and disabled by
  default (map one under **Network** if wanted). For Ingress to work, keep the
  Home Assistant range in `trusted_proxies` (the default already includes it);
  the app's `X-Frame-Options` header is stripped so it can be embedded in the
  Home Assistant UI.
- The app runs the container as the image ships it (FrankenPHP/Caddy serving
  plain HTTP on port 80, mapped to host `8085`).
