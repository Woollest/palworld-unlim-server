# Contributing

Contributions are welcome for bug fixes, documentation and operational safety improvements.

## Before submitting a change

1. Do not include world saves, Discord tokens, channel IDs, passwords, Unlim keys, logs or backups.
2. Keep the Palworld REST API bound to `127.0.0.1`.
3. Run the repository checks:

   ```powershell
   ./scripts/test-project.ps1
   ```

4. Run Pester when available:

   ```powershell
   Invoke-Pester ./tests/Project.Tests.ps1
   ```

5. Run the clean-checkout setup test:

   ```powershell
   ./tests/test-clean-checkout.ps1
   ```

6. Update the README or documentation when behavior changes.

7. For desktop changes, also run:

   ```powershell
   cargo fmt --manifest-path desktop/src-tauri/Cargo.toml -- --check
   cargo clippy --release --locked --manifest-path desktop/src-tauri/Cargo.toml -- -D warnings
   ```

The installed PalOps EXE is the primary user interface. `Open-Dashboard.cmd`, the browser PWA and individual PowerShell scripts are compatibility or recovery surfaces. Operational changes should preserve safe shutdown, verified backup and rollback behavior across both the EXE and recovery paths.
