# Configuration

- The project-root `.env` controls the Docker image, ports, backup policy and maintenance intervals.
- `discord.env` contains the Discord Bot token and channel IDs. Create it from `discord.env.example`.
- `admin.env` is generated automatically and contains the local Palworld REST API password.
- `PalWorldSettings.ini.example` is the sanitized public world-settings template copied during first-time setup.

Files ending in `.env` inside this directory are local secrets and are excluded from Git. Files ending in `.env.example` are safe templates and may be committed.
