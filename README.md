# PalOps — Palworld Dedicated Server + Unlim

Windows、Docker Desktop、Palworld公式Dockerイメージ、Unlim CLIを組み合わせた、Windowsアプリ「PalOps」によるバックアップ・監視・Discord通知・自動復旧付きの非公式Dedicated Server運用プロジェクトです。

> [!IMPORTANT]
> 本プロジェクトはPocketpair, Inc.およびUnlimの公式プロジェクトではありません。Palworldおよび関連名称は各権利者に帰属します。

## 2つの正式版アプリ

このリポジトリでは、用途の異なるWindowsアプリを2つ公開しています。

| アプリ | 対象 | ダウンロードするファイル |
|---|---|---|
| **PalOps v1.3.0** | サーバー管理者 | [管理者向けRelease](https://github.com/Woollest/palworld-unlim-server/releases/tag/v1.3.0)の`PalOps_1.3.0_x64-setup.exe` |
| **Palworld Join v1.0.2** | ゲーム参加者 | [参加者向けRelease](https://github.com/Woollest/palworld-unlim-server/releases/tag/participant-v1.0.2)の`Palworld-Join-Setup-1.0.2.exe` |

どちらも[GitHub Releases](https://github.com/Woollest/palworld-unlim-server/releases)から取得します。コード署名はないためWindowsの警告が表示される場合があります。必ず本リポジトリのReleaseからダウンロードしてください。

## あなたはどの利用者ですか？

| 利用者 | 最初に読む場所 | 主な操作 |
|---|---|---|
| 初めてサーバーを構築する人 | [導入担当者向け](#導入担当者向け) | 初期設定、PalOps EXEの導入、初回起動 |
| 普段サーバーを管理する人 | [運用管理者向け](#運用管理者向け) | PalOps EXEから起動、停止、バックアップ、更新 |
| ゲームへ参加する人 | [参加者向け](#参加者向け) | Palworld Joinの導入、Unlim接続、Palworld参加 |
| コードを変更・公開する人 | [開発・保守担当者向け](#開発保守担当者向け) | テスト、CI、リリース、緊急復旧 |

## 導入担当者向け

### 必要なもの

- Windows 10/11（64bit）
- WSL2対応のDocker Desktop（Linuxコンテナ）
- CPU 4コア以上、メモリ16GB以上（32GB超を推奨）、SSD
- Unlim CLI

> [!WARNING]
> Palworld公式はDocker DesktopをディスクI/O性能上の理由から推奨していません。この構成では検証済み外部バックアップを必ず使用し、長期安定運用ではLinux実機またはSteamCMD方式も検討してください。

### 初回セットアップ

```powershell
git clone https://github.com/Woollest/palworld-unlim-server.git PalworldServer
cd PalworldServer
Set-ExecutionPolicy -Scope Process Bypass
./scripts/setup-project.ps1
```

初回セットアップで次を生成します。

- `.env`：サーバーと自動保守の設定
- `config/discord.env`：Discord Bot設定
- `config/admin.env`：ローカル管理APIの自動生成パスワード
- `data/Saved/Config/LinuxServer/PalWorldSettings.ini`：ワールド設定

これらはGit管理対象外です。外部公開前に内容を確認してください。

### PalOps EXEをインストール

1. [PalOps v1.3.0 Release](https://github.com/Woollest/palworld-unlim-server/releases/tag/v1.3.0)から`PalOps_1.3.0_x64-setup.exe`をダウンロードする
2. インストーラーを実行する
3. スタートメニューから「PalOps」を起動する
4. 初回だけ、先ほどcloneした`PalworldServer`フォルダーを選択する

現在はWindowsのコード署名証明書を使用していないため、SmartScreenに「不明な発行元」と表示される場合があります。GitHubのこのリポジトリにある公式Releaseから取得したファイルであることを確認して実行してください。

### 初期設定の仕上げ

1. スタートメニューからPalOpsを開く
2. ワールド設定と最大人数を確認する
3. PalOpsの「起動」でPalworldとUnlimを起動する
4. PalOpsから最初のバックアップを作成する
5. 必要なら[Discord Bot設定](docs/DISCORD-BOT-SETUP.md)を行う
6. `./scripts/setup-auto-start.ps1`と`./scripts/setup-maintenance-tasks.ps1`でWindowsタスクを登録する

## 運用管理者向け

### 日常運用はPalOps EXEから

スタートメニューで「PalOps」を検索して起動してください。ブラウザやPowerShellを開く必要はありません。PalOpsのウィンドウを閉じてもPalworld、Unlim、バックグラウンド監視は停止しません。サーバーを終了するときは、PalOps内の「安全停止」を使用してください。

PalOpsで利用できる機能：

- Palworld・Unlim・参加人数・FPS・ディスク容量の確認
- 参加者一覧、オンライン状態、最終オンライン確認時刻、参加回数の確認
- 起動、安全停止、安全再起動、バックアップ、更新、復元
- メンテナンス予約とゲーム内・Discord事前通知
- 24時間のCPU・メモリ・FPS推移と状態診断
- ワールド設定編集、サーバーログ、オンライン診断
- 自動起動、自動バックアップ、自動復旧、監視・保守処理の永続オン／オフ切り替え
- インシデント記録、移行パッケージ作成

PalOpsは`http://127.0.0.1:8765`だけで待ち受けます。LANやインターネットには公開されません。

### EXE版の動作

PalOps EXEはTauri 2とWindows WebView2を使用し、ローカル管理機能を自動起動して専用ウィンドウへ表示します。初回に選択したPalworldServerフォルダーを記憶し、二重起動時は既存ウィンドウを前面へ戻します。新しいPalOpsが公開されると確認画面を表示し、同意後に署名検証済みの更新を適用します。詳細は[PalOps Desktop](desktop/README.md)を参照してください。

現在、WindowsのAuthenticodeコード署名証明書は使用していません。初回インストール時にWindows Defender SmartScreenの「不明な発行元」警告が表示される場合があります。GitHubの公式Release以外から入手したインストーラーは実行しないでください。アプリ内更新には別の更新署名を使用しており、改ざん検証は有効です。

### EXEを起動できない場合

`Open-Dashboard.cmd`はブラウザ版PalOpsを開く復旧用入口です。`Open-Server-Manager.cmd`は互換用として同じ画面を開きます。通常運用では使用しません。さらに復旧が必要な場合のみ、[緊急復旧](#緊急復旧)のPowerShell操作を使用してください。

### バックアップ方針

バックアップは`backups/`へ保存され、作成後にワールド構造を検証します。

| `.env`設定 | 既定値 | 意味 |
|---|---:|---|
| `BACKUP_RETENTION` | 20 | 最大保持件数 |
| `BACKUP_MAX_TOTAL_GB` | 10 | ZIP合計容量の上限 |
| `BACKUP_MIN_RETENTION` | 3 | 容量超過時も残す最低件数 |
| `AUTO_BACKUP_INTERVAL_HOURS` | 6 | 無人時の自動バックアップ間隔 |

安全停止・更新・復元は、参加者への予告、セーブ、バックアップを含む保護された処理です。

### 自動運用

PalOpsの「自動化設定」から各処理を個別に一時停止・再開できます。オフにしてもWindowsタスクの登録内容や実行間隔は削除されず、その状態はPC再起動後も保持されます。自動起動をオフにしても、現在稼働中のサーバーは停止しません。

- Windowsサインイン後にDocker、Palworld、Unlim、PalOpsを自動復旧
- 監視プログラムを5分ごとに確認して自動復旧
- 無人かつ前回から既定時間経過時のみ自動バックアップ
- 最新バックアップの日次検証
- Palworld公式イメージの更新確認
- ログ圧縮、世代管理、Discord障害・復旧通知

Discordの障害・復旧・更新・自動テスト・バックアップ通知は、`DISCORD_ADMIN_LOG_CHANNEL_ID`で指定した管理者専用チャンネルへ集約します。メンテナンス予告、接続情報、稼働状況は参加者向けチャンネルへ分離されます。

### Discordコマンド

```text
!palops help
!palops status
!palops players
!palops maintenance
```

DiscordのAdministrator権限を持つユーザーは、2分で失効する確認コード付きで次も利用できます。

```text
!palops backup
!palops restart
!palops confirm ABC123
```

停止、更新、復元や接続キーの表示はDiscordから実行できません。

### データとログの場所

| 内容 | 場所 |
|---|---|
| ワールドデータ | `data/Saved/` |
| 検証済みバックアップ | `backups/` |
| 復元・更新前の退避データ | `recovery/` |
| サーバー・Unlim・自動起動ログ | `logs/` |
| 参加・退出履歴 | `logs/player-events.csv` |
| プレイヤー別の最終オンライン確認 | `logs/player-access.json` |
| ローカル操作状態 | `runtime/` |
| 秘密情報を除いた移行ZIP | `exports/` |

## 参加者向け

参加者はPowerShellやUnlim CLIを直接操作せず、正式版の**Palworld Join**を使用します。

1. [Palworld Join v1.0.2 Release](https://github.com/Woollest/palworld-unlim-server/releases/tag/participant-v1.0.2)から`Palworld-Join-Setup-1.0.2.exe`をダウンロードする
2. セットアップを実行し、Palworld Joinを起動する
3. 管理者から受け取った接続キーを入力して`接続する`を押す
4. 表示された`127.0.0.1:ポート番号`を`接続先をコピー`でコピーする
5. Steam版Palworldの専用サーバー接続欄へ貼り付ける

初回はアプリがUnlim CLIを導入し、次回以降は更新を確認します。参加中はPalworld Joinを閉じないでください。ポート番号は毎回同じとは限りません。接続キーは参加者以外へ公開しないでください。

詳しい説明は[Palworld Join README](participant-app/README.md)を参照してください。

## 開発・保守担当者向け

### 構成

```text
PalworldServer/
├── desktop/                 # 通常利用するTauri製Windows EXE
├── web/                     # EXE内部UI・ブラウザ復旧版
├── scripts/                 # API・運用・自動化
├── config/                  # 公開テンプレートとローカル設定
├── docker/                  # Palworld起動ラッパー
├── tests/                   # Pester・クリーン環境テスト
├── docs/                    # 設計・Discord設定
├── .github/workflows/       # CI・リリース
└── compose.yaml             # Palworldコンテナ定義
```

詳細は[アーキテクチャ](docs/ARCHITECTURE.md)を参照してください。

### テスト

```powershell
./scripts/test-project.ps1
./scripts/test-project.ps1 -Online
./tests/test-clean-checkout.ps1
```

- 通常検査：公開構成、PowerShell構文、Compose、セキュリティ境界、EXE・ブラウザ復旧版
- オンライン検査：Docker、Palworld API、Unlim、バックアップ、Windowsタスク
- GitHub Actions：pushとPull Requestで通常検査、クリーンセットアップ、Pesterを実行

### 緊急復旧

PowerShellはPalOpsの内部実装と緊急復旧用に残しています。

```powershell
./Manage-Server.ps1 -Legacy
```

代表的な個別処理：

```powershell
./scripts/start.ps1
./scripts/backup.ps1
./scripts/shutdown.ps1
./scripts/restore.ps1
./scripts/update-server.ps1
```

### リリース

`v1.3.0`のようなタグをpushすると管理者向けPalOpsを、`participant-v1.0.0`のようなタグをpushすると参加者向けPalworld JoinをGitHub Releaseへ自動公開します。それぞれのアプリ内バージョンとタグを一致させます。

```powershell
git tag v1.0.0
git push origin v1.0.0

git tag participant-v1.0.0
git push origin participant-v1.0.0
```

自宅PCへの自動デプロイは、GitHub側へサーバー権限や認証情報を持たせないため意図的に含めていません。

## 困ったとき

| 症状 | 確認すること |
|---|---|
| PalOps EXEが開かない | スタートメニューから再度起動し、改善しなければ`Open-Dashboard.cmd`と`logs/dashboard-error.log`を確認 |
| コンテナが起動しない | Docker DesktopがLinuxコンテナで起動しているか確認 |
| 参加者が接続できない | ホスト・参加者双方のUnlimと、表示されたローカルポートを確認 |
| バージョン不一致 | PalOpsの「更新確認」から公式イメージを安全更新 |
| インストール時に警告が出る | GitHub公式Releaseのファイルであることを確認し、SmartScreenの詳細表示から実行 |
| PalworldServerフォルダーを聞かれる | cloneしたプロジェクトのルートフォルダーを選択 |
| 自動起動しない | `logs/autostart.log`とWindowsタスクスケジューラを確認 |

## セキュリティと公開範囲

- PalOps：`127.0.0.1:8765`のみ
- Palworld管理API：`127.0.0.1:8212`のみ
- Unlim公開：ゲーム用UDPポートのみ
- Git対象外：`.env`、Discordトークン、管理パスワード、ワールド、バックアップ、ログ、実行状態
- プレイヤー履歴：このPCの`logs/`内だけに保存し、DiscordやGitHubへ送信しない

脆弱性の報告方法は[SECURITY.md](SECURITY.md)を参照してください。

## ライセンス

自動化コードと文書は[MIT License](LICENSE)です。Palworld、公式Dockerイメージ、Unlimその他の外部ソフトウェアには、それぞれのライセンスと利用条件が適用されます。

## 公式情報

- [Palworld Server Guide](https://docs.palworldgame.com/0.5.0/getting-started/requirements/)
- [Palworld公式Docker](https://github.com/pocketpairjp/palworld-dedicated-server-docker)
- [Unlim Wiki](https://wiki.unlim.cc/getting-started)
- [Unlim `/connect`](https://wiki.unlim.cc/commands/connect)
