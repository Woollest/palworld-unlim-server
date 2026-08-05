# Architecture

## Directory layout

```text
PalworldServer/
├── Open-Dashboard.cmd           # Browser-based recovery entry point
├── Open-Server-Manager.cmd      # Compatibility recovery alias
├── Manage-Server.ps1            # Recovery launcher; -Legacy enables recovery menu
├── compose.yaml                 # Palworld container definition
├── .env.example                 # Public server configuration template
├── desktop/                     # Primary Tauri/WebView2 Windows application
├── web/                         # Shared PalOps UI and browser fallback assets
├── config/
│   ├── PalWorldSettings.ini.example
│   ├── discord.env.example      # Public Discord configuration template
│   ├── discord.env              # Local Discord credentials (ignored)
│   └── admin.env                # Local REST API credential (ignored)
├── data/Saved/                  # Palworld world and server settings (ignored)
├── docker/helper.sh             # Official image startup wrapper
├── scripts/                     # PalOps backend, operations and automation
├── tests/                       # Pester and clean-checkout tests
├── .github/workflows/           # CI and release workflows
├── runtime/                     # PIDs, locks and state markers (ignored)
├── backups/                     # Verified external ZIP backups (ignored)
├── recovery/                    # Data preserved during restore/rollback (ignored)
├── exports/                     # Secret-free migration packages (ignored)
├── logs/                        # Operational logs and metrics (ignored)
├── reports/                     # Local test reports (ignored)
├── work/                        # Temporary restore/update work (ignored)
├── private/                     # Local-only notes (ignored)
└── docs/                        # Operations documentation
```

## Management layers

1. The installed PalOps EXE is the normal operator entry point.
2. `desktop/` provides the native lifecycle, single-instance and signed-update layer.
3. `web/` provides the shared operator interface rendered inside the EXE.
4. `scripts/dashboard.ps1` exposes a localhost-only HTTP API and validates every request.
5. `scripts/dashboard-action.ps1` serializes long-running operations and records their result.
6. Dedicated scripts perform backup, restore, update, monitoring and Discord integration.
7. Docker runs the Palworld process; Unlim remains a host-side process for UDP connectivity.

PowerShell remains an implementation and recovery layer, but is no longer the normal operator interface.

The native desktop shell locates or prompts for an existing project directory, remembers that selection in the user's local application data, starts the localhost dashboard through the constrained hidden runner when necessary, and permits navigation only to `127.0.0.1:8765`. The current-user NSIS installer creates the normal Windows application registration and Start menu shortcut. A single-instance guard focuses the existing window instead of starting a duplicate. The shell does not expose Node.js or arbitrary shell commands to the web UI.

## Browser recovery model

The same PalOps UI can be opened in a browser through `Open-Dashboard.cmd` when the native application cannot start. It remains an installable progressive web app for backward compatibility, but it is not the documented normal operating path. The service worker uses network-first caching only for the static application shell; `/api/` requests are never intercepted, so status and administrative operations always use live local state. Neither entry point exposes PalOps beyond `127.0.0.1`.

## Data flow

Docker mounts `data/Saved` into `/pal/Package/Pal/Saved`. Palworld's management REST API is bound only to `127.0.0.1:8212`; PalOps is bound only to `127.0.0.1:8765`; Unlim publishes only the game UDP port. PalOps invokes constrained PowerShell operations for backups, monitoring, Discord updates and safe lifecycle control.

The player monitor keeps the append-only join/leave audit trail in `logs/player-events.csv` and a derived local player directory in `logs/player-access.json`. The directory stores the latest observed display name, account name, first and last observation time, join count and current online state. PalOps exposes it only through the loopback `/api/players` endpoint; it is excluded from Git and Discord output.

## Repository boundary

Only code, documentation and example configuration belong in source control. World data, credentials, runtime state, backups, recovery copies and logs are excluded by `.gitignore`.
