# Palworld Dedicated Server + Unlim（最小構成）

Windows、Docker Desktop、Palworld公式Dockerイメージ、Unlim CLIを組み合わせた、バックアップ・監視・Discord通知・自動復旧付きの非公式Dedicated Server運用プロジェクトです。

> [!IMPORTANT]
> 本プロジェクトはPocketpair, Inc.およびUnlimの公式プロジェクトではありません。Palworldおよび関連名称は各権利者に帰属します。利用前に公式ドキュメントと各サービスの利用条件を確認してください。

## クイックスタート

```powershell
git clone <repository-url> PalworldServer
cd PalworldServer
Set-ExecutionPolicy -Scope Process Bypass
./scripts/setup-project.ps1
./scripts/start.ps1
```

初回セットアップは `.env`、`config/discord.env`、公開用ワールド設定テンプレート、必要なデータフォルダーを作成します。外部公開前に各設定を確認してください。

## 日常操作

`Open-Dashboard.cmd` または互換用の `Open-Server-Manager.cmd` をダブルクリックすると、PalOps Web管理画面が開きます。日常運用はこの画面に一本化されています。旧PowerShellメニューは緊急復旧時に限り `./Manage-Server.ps1 -Legacy` で起動できます。

## PalOps Web管理画面

`Open-Dashboard.cmd` をダブルクリックすると、ローカル管理画面がブラウザーで開きます。

- Palworld・Unlimの稼働状況
- 現在の参加人数と参加者名
- FPS、稼働時間、ディスク空き容量
- 最新バックアップ
- 起動、検証付きバックアップ、安全停止、安全再起動・更新・復元
- メンテナンス予約とゲーム内・Discord事前通知
- 24時間のFPS・CPU・メモリ推移と状態診断
- ワールド設定編集、サーバーログ、オンライン診断
- インシデント記録、設定・データ移行パッケージ作成

管理画面は `http://127.0.0.1:8765` だけで待ち受け、LANやインターネットには公開しません。Windowsログイン後は自動起動・監視されるため、ブラウザーを閉じてもPalOpsとPalworldの処理は継続します。

## 自動テスト

リポジトリ構成だけを検査する場合：

```powershell
./scripts/test-project.ps1
```

実際のワールド設定、最新バックアップ、Docker、Palworld REST API、Unlim、プレイヤー監視、Windows自動タスクまで検査する場合：

```powershell
./scripts/test-project.ps1 -Online
```

結果は画面と `reports/latest-test-results.json` に保存されます。オンライン検査は毎日5:00にも自動実行され、失敗時はDiscordの障害通知先へ送信されます。管理メニューの「10. Run all project checks」からも実行できます。

公開ファイルだけを一時フォルダーへ複製し、初回セットアップを再現する場合：

```powershell
./tests/test-clean-checkout.ps1
```

Windows 11、WSL2、Docker Desktopを想定した緊急構築用セットです。Palworld公式Dockerイメージを使い、ゲーム通信の `8211/udp` だけを公開します。

Discordへの稼働状況の自動通知を利用する場合は、[Discord Bot設定](docs/DISCORD-BOT-SETUP.md) の手順で設定してください。

### Discordコマンド

Botを設定すると、指定チャンネルで次のテキストコマンドを利用できます。`DISCORD_COMMAND_CHANNEL_ID`が空の場合は通常のステータスチャンネルを使用します。

```text
!palops help
!palops status
!palops players
!palops maintenance
```

DiscordのAdministrator権限を持つユーザーは、確認コード付きで次の操作も実行できます。

```text
!palops backup
!palops restart
!palops confirm ABC123
```

管理コマンドの確認コードは2分で失効します。停止、更新、復元はDiscordから直接実行できません。

構成の詳細は[アーキテクチャ](docs/ARCHITECTURE.md)を参照してください。

## 必要なもの

- Windows 10/11（64bit）
- WSL2対応のDocker Desktop（Linuxコンテナ）
- CPU 4コア以上、メモリ16GB以上（32GB超を推奨）、SSD
- Unlim（ホストと参加者の両方）

## ライセンス

自動化コードと文書は[MIT License](LICENSE)で公開できます。Palworld、公式Dockerイメージ、Unlimその他の外部ソフトウェアには、それぞれの権利者のライセンスと利用条件が適用されます。

## CI/CDとリリース

pushとPull RequestではGitHub Actionsがリポジトリ検査、クリーンセットアップ、Pesterを実行します。`v1.0.0` のようなセマンティックバージョンのタグをpushすると、同じ検査後に秘密情報を含まない配布ZIPとSHA-256チェックサムを作成し、GitHub Releaseへ自動公開します。

```powershell
git tag v1.0.0
git push origin v1.0.0
```

公開リポジトリから自宅PCへ直接デプロイする処理は、認証情報とサーバー権限をGitHub側へ持たせないため意図的に含めていません。

> Palworld公式は、Docker DesktopではディスクI/O性能の制約からセーブ破損・不具合のリスクが高まるとして非推奨です。今回は最短構築を優先しています。定期バックアップを必ず取得し、安定運用ではLinux実機またはSteamCMD方式への移行を検討してください。

## 1. 起動

Docker Desktopを起動し、このフォルダーをPowerShellで開いて実行します。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./scripts/start.ps1
```

このスクリプトはPalworldの起動完了ログを確認した後、Unlim CLIを `8211/udp`・最大8接続で自動起動します。PalworldとUnlimの両方が起動してからDiscordをONLINEへ更新します。Unlimアプリを別途起動しないでください。

起動後はプレイヤー監視も自動的に始まり、Discordの稼働状況へ現在人数を表示します。参加・退出履歴は `logs/player-events.csv` に保存されます。IPアドレスは履歴へ保存しません。

初回起動ではイメージ取得とサーバー初期化に時間がかかります。ログに致命的エラーがないことを確認します。

```powershell
docker compose logs -f --tail=100
```

ログ表示は `Ctrl+C` で終了できます（サーバーは停止しません）。状態確認:

```powershell
docker compose ps
```

## 2. Unlimで公開

ホスト側のUnlimは `start.ps1` がCLIで自動起動します。PowerShellに表示された接続キーを参加者だけに共有します。確認できない場合は `logs/unlim-current.log` を確認してください。

ルーターのポート開放は不要です。Unlimはサーバーと同じWindows PCで動かしてください。

参加者もUnlimを起動し、次を入力します。

```text
/connect <受け取った接続キー>
```

接続後、Palworldの専用サーバー接続欄へ次を入力します。

```text
127.0.0.1:8211
```

Unlimは同じローカルポートを優先しますが、使用中なら別ポートへ割り当てて画面に表示します。その場合は、表示されたポートに置き換えてください。

## 3. 停止とバックアップ

通常のプレイ終了時は、停止とバックアップをまとめて実行できます。

```powershell
./scripts/shutdown.ps1
```

この処理はDiscordの「お知らせ」へメンテナンス予告を送り、ゲーム内にも停止予告を表示します。既定では60秒後に安全に停止し、バックアップを作成してからコンテナを整理します。終了用途ではこちらを推奨します。

処理内容は、Palworld停止、Dockerログ保存、ZIPバックアップ作成・検証、古いバックアップの整理、Unlim停止、DiscordのOFFLINE更新です。`stop.ps1`を実行した場合も同じ安全な終了処理を行います。

停止:

```powershell
./scripts/stop.ps1
```

バックアップ（稼働中なら安全のため一時停止し、終了後に再開）:

```powershell
./scripts/backup.ps1
```

ZIPは `backups` フォルダーへ保存されます。初回プレイ後、必ず一度バックアップを試してください。

バックアップは古いものから自動削除するローテーション方式です。`.env` の設定は次のとおりです。

- `BACKUP_RETENTION=20`: 最大20件
- `BACKUP_MAX_TOTAL_GB=10`: ZIPの合計を最大10GBに制限
- `BACKUP_MIN_RETENTION=3`: 容量上限を超えても最低3件は保持

件数または容量の上限を超えると、最新のバックアップ作成・検証後に古いZIPから完全に削除されます。`0`を指定した上限は無効になります。

## バックアップから復元

サーバーが停止している状態で実行します。

```powershell
./scripts/restore.ps1
```

一覧からバックアップを選び、確認欄へ `RESTORE` と入力します。復元前の現在データは削除せず、`recovery` フォルダーへ退避します。復元後は `start.ps1` で起動してください。

## ログ

CPU、メモリ、FPS、フレーム時間、参加人数、稼働時間、拠点数、ゲーム内日数、ディスク空き容量は5分ごとに `logs/health-metrics.csv` へ記録されます。管理メニューの「9. Show 24-hour health summary」で直近24時間を確認できます。

終了時に保存された `palworld-*.log` は7日後に `logs/archive` へZIP圧縮され、圧縮ログは90日後に削除されます。性能履歴は30日分を保持します。期間は `.env` の `METRICS_RETENTION_DAYS`、`LOG_COMPRESS_AFTER_DAYS`、`LOG_RETENTION_DAYS` で変更できます。

安全終了時にDockerログを `logs/palworld-日時.log` へ保存します。Unlimの現在のログは `logs/unlim-current.log`、エラーは `logs/unlim-current-error.log` です。

プレイヤーの参加・退出履歴は `logs/player-events.csv` です。監視間隔は `.env` の `MONITOR_INTERVAL_SECONDS`、停止予告時間は `MAINTENANCE_WARNING_SECONDS` で変更できます。

## 自動保守

次のWindowsタスクが登録されます。

- `Palworld-Monitor-Watchdog`: 5分ごとに監視プログラムを確認し、停止していれば再起動
- `Palworld-Idle-Backup`: 30分ごとに確認し、前回から6時間以上かつ参加者0人の場合だけ外部ZIPを作成
- `Palworld-Backup-Verify`: 毎日4:30に最新ZIPを最後まで読み取り、`Level.sav` と `LevelMeta.sav` を検査
- `Palworld-Update-Check`: 毎日12:00に公式GHCRのタグを確認し、新版があればDiscordへ通知

これらのタスクは `run-hidden.vbs` を経由して画面を表示せずに実行するため、定期確認時にPowerShellやコマンドプロンプトが一瞬開くことはありません。

自動ZIPの間隔は `.env` の `AUTO_BACKUP_INTERVAL_HOURS=6` で変更できます。参加者がいる場合は切断せず、次の30分確認まで延期します。空き容量が `DISK_WARNING_FREE_GB=20` 未満になるとDiscordへ警告し、25GB以上へ戻ると復旧通知を送ります。

タスクを再登録する場合:

```powershell
./scripts/setup-maintenance-tasks.ps1
```

## Windows再起動後の自動復旧

自動起動タスクは `Palworld-Unlim-AutoStart` という名前でWindowsへ登録されます。Docker Desktopがユーザーアプリとして動くため、Windows再起動後にこのユーザーがサインインすると、Dockerの準備を待ってPalworldとUnlimを復旧します。

自動起動の実行内容と失敗理由は `logs/autostart.log` に追記されます。タスクは実際の起動処理が完了するまで待機し、失敗時はWindowsタスクスケジューラが最大3回再試行します。

再登録する場合:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./scripts/setup-auto-start.ps1
```

解除する場合:

```powershell
./scripts/remove-auto-start.ps1
```

## ローカル管理API

参加人数取得と安全な停止にはPalworld公式REST APIを使用します。管理パスワードは初回設定時に `config/admin.env` へ自動生成され、Git管理から除外されます。管理ポート8212/TCPは `127.0.0.1` にだけ公開され、Unlimでは共有しません。

Discordのメンテナンス予告先は `config/discord.env` の `DISCORD_ANNOUNCEMENT_CHANNEL_ID` です。Botには対象チャンネルの「チャンネルを見る」「メッセージを送信」「埋め込みリンク」権限が必要です。

障害・復旧通知は `DISCORD_ALERT_CHANNEL_ID`、バックアップ成功・失敗記録は管理者向けの `DISCORD_BACKUP_CHANNEL_ID` へ投稿します。バックアップ通知先が未設定の場合は障害通知先へフォールバックします。同じ障害の通知は連続送信せず、復旧したときに改めて通知します。

## 設定変更

初回起動時に `.env.example` から `.env` が作られます。ポートまたは人数を変える場合は、停止後に `.env` を編集して再起動します。Unlimの `/now` と参加者の接続ポートも同じ番号へ変更してください。

サーバー名、パスワード、ゲーム設定は初回起動後に生成される次のファイルを、停止中に編集します。

```text
data/Saved/Config/LinuxServer/PalWorldSettings.ini
```

書式を壊しやすいため、編集前にバックアップしてください。公式イメージ内の初期値は次で確認できます。

現在の性能関連設定は、オートセーブ300秒、パル同期距離10000、公式マルチスレッド起動引数です。WSL2にはホスト32GBのうち20GB、8論理プロセッサ、8GBスワップを割り当てています。

```powershell
docker compose exec palworld-server sh -c 'cat /pal/Package/DefaultPalWorldSettings.ini'
```

## 更新

通常は `Open-Server-Manager.cmd` の「8. Safely update to the latest version」を使用してください。公式レジストリの最新版を確認し、更新前の安全停止とバックアップを行います。更新後に起動できなかった場合は、旧イメージと更新前セーブを自動復元します。確認欄へ表示どおり `UPDATE バージョン` と入力しない限り更新されません。

更新前に `./scripts/backup.ps1` を実行します。その後、Palworld公式Dockerリポジトリで対応する最新タグを確認し、`.env` の `PALWORLD_IMAGE` を変更して起動してください。`latest` の自動追従は、ゲーム更新との不整合を避けるため使用していません。

## 困ったとき

- コンテナが起動しない: Docker DesktopがLinuxコンテナで起動中か確認
- 参加者が接続できない: ホスト/参加者双方でUnlimを起動し、Unlim画面の実際のローカル割当ポートを確認
- Palworldのバージョン不一致: 公式リポジトリの対応イメージタグへ更新
- 保存領域: `data/Saved`、バックアップ: `backups`

## 確認した公式情報（2026-07-31確認）

- Palworld Server Guide: https://docs.palworldgame.com/0.5.0/getting-started/requirements/
- Palworld公式Docker: https://github.com/pocketpairjp/palworld-dedicated-server-docker
- Unlim Wiki: https://wiki.unlim.cc/getting-started
- Unlim `/connect`: https://wiki.unlim.cc/commands/connect
