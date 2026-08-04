# Discord Bot連携の設定

Palworldサーバーの起動・停止状態を、Discordの `#サーバー稼働状況` に自動表示します。Botは1つのメッセージを作成し、その後は同じメッセージを更新します。

## 1. Discord Botを作成

1. https://discord.com/developers/applications を開く
2. `New Application` を選択
3. 名前（例: `Palworld Server Bot`）を入力して作成
4. 左側の `Bot` を開く
5. `Reset Token` を選択してBotトークンをコピー

Botトークンはパスワードと同じ機密情報です。Discordへの投稿、画面共有、Gitへの登録をしないでください。漏えいした場合はDeveloper Portalで直ちに再生成してください。

## 2. BotをDiscordサーバーへ追加

1. Developer Portalの `Installation` を開く
2. Guild Installへ `bot` スコープを追加
3. Bot Permissionsで `View Channels`、`Send Messages`、`Embed Links` を選択
4. Install Linkをブラウザーで開く
5. 対象のDiscordサーバーを選択して追加

管理者権限は不要です。`#サーバー稼働状況` のチャンネル権限でも、Botに「チャンネルを見る」「メッセージを送信」「埋め込みリンク」を明示的に許可してください。一般参加者の投稿が禁止されている読み取り専用チャンネルでは、Botへの個別許可が必要です。

## 3. チャンネルIDを取得

1. Discordの「ユーザー設定」→「詳細設定」を開く
2. 「開発者モード」を有効にする
3. `#サーバー稼働状況` を右クリック
4. 「チャンネルIDをコピー」を選択

## 4. このPCへ設定

プロジェクトフォルダーでPowerShellを開き、次を実行します。

```powershell
./scripts/setup-discord-bot.ps1
```

順番にBotトークンとチャンネルIDを入力します。初回の「停止中」メッセージがDiscordへ投稿されたら、そのメッセージをピン留めしてください。

資格情報は `config/discord.env` に保存され、Git管理の対象から除外されるファイルです。他人へ渡さないでください。

## 自動更新のタイミング

- `./scripts/start.ps1`: 🟢 ONLINE
- `./scripts/shutdown.ps1` 開始時: 🟡 MAINTENANCE
- バックアップ・終了完了時: 🔴 OFFLINE
- バックアップまたは終了処理の異常時: ERROR

Discordへの通知が失敗しても、Palworldサーバーの起動・停止処理は継続します。

## メンテナンス予告と接続人数

プレイヤー監視が現在の接続人数を `#サーバー稼働状況` へ自動反映します。停止処理では、設定したチャンネルへメンテナンス予告を投稿します。

`config/discord.env` に次の値を設定してください。

```text
DISCORD_ANNOUNCEMENT_CHANNEL_ID=お知らせチャンネルID
DISCORD_ALERT_CHANNEL_ID=障害・バックアップ通知チャンネルID
DISCORD_BACKUP_CHANNEL_ID=管理者用バックアップ記録チャンネルID
```

Botにはお知らせチャンネルの「チャンネルを見る」「メッセージを送信」「埋め込みリンク」権限が必要です。

`DISCORD_ALERT_CHANNEL_ID` を空欄にした場合は、`DISCORD_CHANNEL_ID` の稼働状況チャンネルへ障害・復旧通知を送ります。

`DISCORD_BACKUP_CHANNEL_ID` には管理者だけが閲覧できるバックアップ記録チャンネルを指定します。未設定の場合は `DISCORD_ALERT_CHANNEL_ID` へ送ります。

## 無効化

`config/discord.env` の次の値を変更します。

```text
DISCORD_ENABLED=false
```
