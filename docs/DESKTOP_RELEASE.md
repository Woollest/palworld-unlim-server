# PalOps desktop release

PalOpsのWindows版は、GitHub Releaseの`latest.json`を起動時に確認します。新しいバージョンがある場合は確認画面を表示し、同意後に署名を検証してNSIS更新を適用します。

## 初回だけ必要なGitHub設定

リポジトリの`Settings` → `Secrets and variables` → `Actions`へ、次のRepository secretを登録します。

- `TAURI_SIGNING_PRIVATE_KEY`: `%USERPROFILE%\.tauri\palops.key`の内容
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`: 鍵にパスワードを設定した場合のみ登録

秘密鍵をリポジトリ、Issue、Discord、リリース添付へ置かないでください。秘密鍵を失うと、インストール済みアプリが後続更新を検証できなくなります。暗号化された別媒体へバックアップしてください。

## リリース手順

1. `desktop/src-tauri/Cargo.toml`と`tauri.conf.json`のバージョンを同じ値へ更新します。
2. 同じ値のタグ（例：`v1.3.1`）を作成してpushします。
3. Release workflowがサーバー配布ZIP、NSISインストーラー、署名、`latest.json`を同じGitHub Releaseへ登録します。

Windowsの発行元を表示するAuthenticodeコード署名は更新署名とは別です。コード署名証明書を取得した場合は、証明書をGitHub ActionsのSecretまたは外部署名サービスへ登録してからTauriのWindows署名設定を有効にします。

現時点ではAuthenticode署名を行わず、SmartScreen警告を許容して運用します。更新署名は引き続き必須であり、無効化しません。
