const $ = id => document.getElementById(id);
const savedTheme = localStorage.getItem('palops-theme') === 'light' ? 'light' : 'dark';
document.documentElement.dataset.theme = savedTheme;
let pendingAction = null;
let updateAvailable = false;
let pendingRestore = null;
let installPrompt = null;

window.addEventListener('beforeinstallprompt', event => {
  event.preventDefault(); installPrompt = event; $('installApp').hidden = false;
});
window.addEventListener('appinstalled', () => { installPrompt = null; $('installApp').hidden = true; });
$('installApp').addEventListener('click', async () => {
  if (!installPrompt) { $('installHelp').showModal(); return; }
  await installPrompt.prompt();
  installPrompt = null; $('installApp').hidden = true;
});
if (window.matchMedia('(display-mode: standalone)').matches) $('installApp').hidden = true;
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/service-worker.js').catch(() => {});

function renderThemeButton() {
  const light = document.documentElement.dataset.theme === 'light';
  $('themeToggle').textContent = light ? 'ダークモード' : 'ライトモード';
  $('themeToggle').setAttribute('aria-pressed', String(light));
}
$('themeToggle').addEventListener('click', () => {
  const next = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
  document.documentElement.dataset.theme = next;
  localStorage.setItem('palops-theme', next);
  renderThemeButton();
});
renderThemeButton();

const actionLabels = {
  start: { name: '起動', confirm: 'サーバーを起動しますか？', detail: 'PalworldとUnlimを起動し、接続可能になるまで確認します。' },
  restart: { name: '安全再起動', confirm: 'サーバーを安全再起動しますか？', detail: '参加者へ予告し、セーブとバックアップを作成してから再起動します。' },
  backup: { name: 'バックアップ', confirm: 'バックアップを作成しますか？', detail: '参加者がいる場合は予告後に一時停止し、検証済みバックアップを作成して再開します。' },
  shutdown: { name: '安全停止', confirm: 'サーバーを安全停止しますか？', detail: '参加者へ予告し、セーブとバックアップを作成してから停止します。' },
  'check-update': { name: '更新確認', confirm: '公式サーバーの更新を確認しますか？', detail: '公式コンテナレジストリだけを確認します。サーバーは停止しません。' },
  update: { name: '安全更新', confirm: 'Palworldサーバーを安全更新しますか？', detail: '参加者確認、予告、セーブ、バックアップ後に更新します。失敗時は以前のバージョンへ自動復旧します。' }
  , restore: { name: '復元' }, 'migration-export': { name: '移行パッケージ作成' }, diagnostics: { name: 'システム診断', confirm: '診断を実行しますか？', detail: 'Docker、バックアップ、設定、自動起動などを停止せずに検査します。' }
};

const diagnosisText = {
  'disk-low': item => ['ディスク空き容量が少なくなっています', `空き容量は${item.value} GBです。バックアップを確認してください。`],
  'backup-missing': () => ['バックアップがありません', '最初のバックアップを作成してください。'],
  'backup-stale': item => ['バックアップが古くなっています', `最後のバックアップから${item.value}時間経過しています。`],
  'unlim-offline': () => ['Unlimが切断されています', 'Palworldは稼働していますが、外部から接続できない可能性があります。'],
  'cpu-high': item => ['CPU使用率が高い状態です', `直近3回の平均は${item.value}%です。`],
  'memory-high': item => ['メモリ使用率が高くなっています', `現在の使用率は${item.value}%です。`],
  'fps-low': item => ['サーバーFPSが低下しています', `現在のサーバーFPSは${item.value}です。`]
};

const maintenanceLabels = { restart: '安全再起動', update: '安全更新', backup: 'バックアップ', shutdown: '安全停止' };
const maintenanceStates = { scheduled: '予約済み', running: '実行中', succeeded: '完了', failed: '失敗', cancelled: '取消済み' };
const settingGroups = { gameplay: 'ゲームプレイ', world: 'ワールド進行', performance: 'パフォーマンス', server: 'サーバー' };
const settingText = {
  ExpRate: ['経験値倍率', 'プレイヤーとパルの経験値'], PalCaptureRate: ['捕獲率', 'パルの捕まえやすさ'], PalSpawnNumRate: ['パル出現数', '高すぎる値は負荷が増加'],
  CollectionDropRate: ['採集ドロップ倍率', '採集オブジェクトの獲得量'], EnemyDropItemRate: ['敵ドロップ倍率', '敵から得られるアイテム量'], WorkSpeedRate: ['作業速度倍率', '拠点作業の進行速度'],
  DayTimeSpeedRate: ['昼の進行速度', '小さいほど昼が長い'], NightTimeSpeedRate: ['夜の進行速度', '小さいほど夜が長い'], PalEggDefaultHatchingTime: ['巨大卵の孵化時間', 'ゲーム内時間単位。0.166667で約10分'],
  CollectionObjectRespawnSpeedRate: ['採集物リスポーン速度', '小さいほど再出現が早い'], SupplyDropSpan: ['補給物資の間隔', '秒単位'], AutoSaveSpan: ['自動セーブ間隔', '秒単位'],
  DropItemMaxNum: ['ドロップ上限', 'ワールド全体の落下アイテム'], PhysicsActiveDropItemMaxNum: ['物理演算アイテム上限', '同時に物理演算する個数'], DropItemAliveMaxHours: ['落下アイテム保持時間', '時間単位'],
  ItemContainerForceMarkDirtyInterval: ['コンテナ同期間隔', '秒単位。長いほど通信負荷を抑制'], ServerPlayerMaxNum: ['最大参加人数', '再起動後に反映']
};

function duration(seconds) {
  if (seconds == null) return '–';
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor(seconds % 3600 / 60);
  return hours ? `${hours}時間 ${minutes}分` : `${minutes}分`;
}

function date(value) {
  return value ? new Intl.DateTimeFormat('ja-JP', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value)) : '–';
}

function renderHistory(history) {
  const container = $('historyList');
  if (!history?.length) {
    container.innerHTML = '<p class="empty">操作履歴はありません</p>';
    return;
  }
  container.replaceChildren(...history.map(item => {
    const row = document.createElement('div');
    row.className = 'history-row';
    const name = document.createElement('span');
    name.className = 'history-name';
    name.textContent = item.target ? `${actionLabels[item.name]?.name ?? item.name} · ${item.target}` : actionLabels[item.name]?.name ?? item.name;
    const result = document.createElement('span');
    result.className = `history-result ${item.state}`;
    result.textContent = item.state === 'succeeded' ? '完了' : '失敗';
    const time = document.createElement('time');
    time.className = 'history-time';
    time.textContent = date(item.completedAt);
    row.append(name, result, time);
    return row;
  }));
}

function renderBackups(backups) {
  $('backupCount').textContent = `${backups.length}件`;
  const container = $('backupList');
  if (!backups.length) { container.innerHTML = '<p class="empty">バックアップはありません。</p>'; return; }
  container.replaceChildren(...backups.map(backup => {
    const row = document.createElement('div'); row.className = 'backup-row';
    const name = document.createElement('span'); name.className = 'backup-name'; name.textContent = backup.name;
    const created = document.createElement('span'); created.className = 'backup-meta'; created.textContent = date(backup.createdAt);
    const size = document.createElement('span'); size.className = 'backup-meta'; size.textContent = `${backup.sizeMb} MB`;
    const action = document.createElement('button'); action.type = 'button'; action.textContent = '復元'; action.dataset.restore = backup.name; action.disabled = !backup.valid;
    const validity = document.createElement('span'); validity.className = backup.valid ? 'backup-valid' : 'backup-invalid'; validity.textContent = backup.fullyVerified ? '検証済み' : backup.valid ? '構造確認済み' : '破損の可能性';
    row.append(name, created, size, validity, action);
    return row;
  }));
}

async function refreshBackups() {
  try { const response = await fetch('/api/backups', { cache: 'no-store' }); const body = await response.json(); renderBackups(body.backups ?? []); }
  catch { $('backupCount').textContent = '取得失敗'; }
}

function renderMaintenance(schedules) {
  $('maintenanceCount').textContent = `${schedules.filter(item => item.status === 'scheduled').length}件予約中`;
  const container = $('maintenanceList');
  if (!schedules.length) { container.innerHTML = '<p class="empty">予約はありません。</p>'; return; }
  container.replaceChildren(...schedules.slice(0, 10).map(schedule => {
    const row = document.createElement('div'); row.className = 'maintenance-row';
    const operation = document.createElement('span'); operation.className = 'maintenance-operation'; operation.textContent = maintenanceLabels[schedule.operation] ?? schedule.operation;
    const runAt = document.createElement('span'); runAt.className = 'backup-meta'; runAt.textContent = `${date(schedule.runAt)} · ${schedule.warningMinutes}分前に予告`;
    const status = document.createElement('span'); status.className = `maintenance-status ${schedule.status}`; status.textContent = maintenanceStates[schedule.status] ?? schedule.status;
    const action = document.createElement('button'); action.type = 'button'; action.textContent = '取消'; action.dataset.cancelMaintenance = schedule.id; action.disabled = schedule.status !== 'scheduled';
    row.append(operation, runAt, status, action);
    return row;
  }));
}

async function refreshMaintenance() {
  try { const response = await fetch('/api/maintenance', { cache: 'no-store' }); const body = await response.json(); renderMaintenance(body.schedules ?? []); }
  catch { $('maintenanceCount').textContent = '取得失敗'; }
}

function renderSettings(payload) {
  const groups = $('settingsGroups');
  groups.replaceChildren(...Object.keys(settingGroups).map(groupName => {
    const section = document.createElement('section'); section.className = 'settings-group';
    const heading = document.createElement('h3'); heading.textContent = settingGroups[groupName];
    const grid = document.createElement('div'); grid.className = 'settings-grid';
    payload.schema.filter(field => field.group === groupName).forEach(field => {
      const wrapper = document.createElement('div'); wrapper.className = 'setting-field';
      const label = document.createElement('label'); label.textContent = settingText[field.key]?.[0] ?? field.key;
      const input = document.createElement('input'); input.type = 'number'; input.name = field.key; input.value = payload.values[field.key]; input.min = field.min; input.max = field.max; input.step = field.step; input.required = true;
      const help = document.createElement('small'); help.textContent = settingText[field.key]?.[1] ?? `${field.min}～${field.max}`;
      label.append(input); wrapper.append(label, help); grid.append(wrapper);
    });
    section.append(heading, grid); return section;
  }));
  $('settingsState').textContent = payload.restartRequired ? '保存済みの変更があります・再起動が必要' : '主要項目を安全に編集';
}

async function refreshSettings() {
  try { const response = await fetch('/api/settings', { cache: 'no-store' }); const body = await response.json(); if (!response.ok) throw new Error(body.error); renderSettings(body); }
  catch (error) { $('settingsMessage').textContent = `設定を読み込めませんでした: ${error.message}`; }
}

function renderAction(action) {
  const running = action?.state === 'running';
  document.querySelectorAll('[data-action]').forEach(button => { button.disabled = running || (button.dataset.action === 'update' && !updateAvailable); });
  if (!action) {
    $('actionState').textContent = '実行する操作を選択してください。';
  } else if (running) {
    $('actionState').textContent = `${actionLabels[action.name]?.name ?? action.name}を実行中です。画面を閉じても処理は継続します。`;
  } else if (action.state === 'succeeded') {
    $('actionState').textContent = `前回の${actionLabels[action.name]?.name ?? action.name}は正常に完了しました。`;
  } else {
    $('actionState').textContent = `前回の操作に失敗しました: ${action.message ?? '詳細はログを確認してください。'}`;
  }
}

function renderUpdate(update) {
  updateAvailable = Boolean(update?.known && update.available);
  $('currentVersion').textContent = update?.currentTag || '–';
  $('latestVersion').textContent = update?.known ? update.latestTag : '未確認';
  $('updateState').textContent = !update?.known ? '未確認' : updateAvailable ? '更新あり' : '最新版';
  $('updateChecked').textContent = update?.checkedAt ? `確認 ${date(update.checkedAt)}` : '更新確認を実行してください';
  $('updateButton').disabled = !updateAvailable;
}

function renderChart(svgId, points, field, maximum, suffix) {
  const svg = $(svgId);
  svg.replaceChildren();
  const values = points.map((point, index) => ({ index, value: point[field] })).filter(point => Number.isFinite(point.value));
  if (!values.length) return null;
  const namespace = 'http://www.w3.org/2000/svg';
  for (const y of [1, 36, 71]) {
    const line = document.createElementNS(namespace, 'line');
    line.setAttribute('x1', '0'); line.setAttribute('x2', '300'); line.setAttribute('y1', y); line.setAttribute('y2', y); line.setAttribute('class', 'grid-line');
    svg.append(line);
  }
  const widthDivisor = Math.max(1, points.length - 1);
  const coordinates = values.map(point => {
    const x = point.index / widthDivisor * 300;
    const y = 71 - Math.min(maximum, Math.max(0, point.value)) / maximum * 70;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');
  const polyline = document.createElementNS(namespace, 'polyline');
  polyline.setAttribute('points', coordinates);
  polyline.setAttribute('class', 'trend-line');
  svg.append(polyline);
  return `${values.at(-1).value}${suffix}`;
}

function renderHealth(health) {
  const points = health?.points ?? [];
  const hasData = points.length > 0;
  $('charts').hidden = !hasData;
  $('chartEmpty').hidden = hasData;
  if (!hasData) {
    $('healthSummary').textContent = 'データなし';
    return;
  }
  $('fpsLatest').textContent = renderChart('fpsChart', points, 'fps', 60, '') ?? '–';
  $('cpuLatest').textContent = renderChart('cpuChart', points, 'cpu', 100, '%') ?? '–';
  $('memoryLatest').textContent = renderChart('memoryChart', points, 'memory', 100, '%') ?? '–';
  const summary = health.summary;
  $('healthSummary').textContent = summary ? `稼働率 ${summary.availability}% · ${summary.samples}件` : `${points.length}件`;
}

function renderInsights(insights) {
  const list = $('diagnosisList');
  const stateLabels = { healthy: '正常', warning: '要確認', critical: '障害', stopped: '停止中' };
  $('diagnosisState').textContent = stateLabels[insights?.state] ?? '確認不能';
  if (!insights || insights.state === 'stopped') {
    list.innerHTML = '<div class="diagnosis-stopped">サーバー停止中のため、稼働状態の診断を休止しています。</div>';
    return;
  }
  if (!insights.items?.length) {
    list.innerHTML = '<div class="diagnosis-ok">現在、対応が必要な兆候はありません。</div>';
    return;
  }
  list.replaceChildren(...insights.items.map(item => {
    const row = document.createElement('div');
    row.className = `diagnosis-item ${item.severity}`;
    const mark = document.createElement('span');
    mark.className = 'diagnosis-mark';
    const content = document.createElement('div');
    const title = document.createElement('strong');
    const translated = diagnosisText[item.code]?.(item) ?? [item.title, item.detail];
    title.textContent = translated[0];
    const detail = document.createElement('p');
    detail.textContent = translated[1];
    content.append(title, detail);
    row.append(mark, content);
    return row;
  }));
}

async function refresh() {
  try {
    const response = await fetch('/api/status', { cache: 'no-store' });
    const status = await response.json();
    $('overall').className = `status ${status.server.status}`;
    $('overall').querySelector('span').textContent = status.server.status === 'online' ? '稼働中' : '停止中';
    $('players').textContent = `${status.server.players} / ${status.server.maxPlayers}`;
    $('fps').textContent = status.server.fps ?? '–';
    $('uptime').textContent = duration(status.server.uptimeSeconds);
    $('disk').textContent = status.disk ? `${status.disk.freeGb} GB` : '–';
    $('unlim').className = `inline-status ${status.unlim.status}`;
    $('unlim').textContent = status.unlim.status === 'online' ? '接続中' : '停止中';
    $('backup').textContent = status.backup ? `${date(status.backup.createdAt)} · ${status.backup.sizeMb} MB` : 'まだありません';
    $('playerNames').textContent = status.server.playerNames.length ? status.server.playerNames.join(' · ') : '参加者はいません';
    renderUpdate(status.update);
    renderAction(status.action);
    renderHistory(status.history);
    renderHealth(status.health);
    renderInsights(status.insights);
    $('updated').textContent = `更新 ${new Date().toLocaleTimeString('ja-JP')}`;
  } catch {
    $('overall').className = 'status offline';
    $('overall').querySelector('span').textContent = '管理画面との通信エラー';
  }
}

document.querySelectorAll('[data-action]').forEach(button => button.addEventListener('click', () => {
  pendingAction = button.dataset.action;
  $('dialogTitle').textContent = actionLabels[pendingAction].confirm;
  $('dialogText').textContent = actionLabels[pendingAction].detail;
  $('confirmDialog').showModal();
}));

$('confirmDialog').addEventListener('close', async () => {
  if ($('confirmDialog').returnValue !== 'confirm' || !pendingAction) return;
  const action = pendingAction;
  pendingAction = null;
  try {
    const response = await fetch(`/api/actions/${action}`, { method: 'POST' });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error);
    $('actionState').textContent = `${actionLabels[action].name}を受け付けました。`;
  } catch (error) {
    $('actionState').textContent = `操作を開始できませんでした: ${error.message}`;
  }
  await refresh();
});

$('backupList').addEventListener('click', event => {
  const button = event.target.closest('[data-restore]');
  if (!button) return;
  pendingRestore = button.dataset.restore;
  $('restoreTarget').textContent = pendingRestore;
  $('restoreConfirmation').value = '';
  $('restoreButton').disabled = true;
  $('restoreDialog').showModal();
});

$('restoreConfirmation').addEventListener('input', () => { $('restoreButton').disabled = $('restoreConfirmation').value !== '復元'; });
$('restoreDialog').addEventListener('close', async () => {
  if ($('restoreDialog').returnValue !== 'confirm' || !pendingRestore) { pendingRestore = null; return; }
  const name = pendingRestore; pendingRestore = null;
  try {
    const response = await fetch('/api/actions/restore', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name }) });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error);
    $('actionState').textContent = `${name} の復元を受け付けました。`;
  } catch (error) { $('actionState').textContent = `復元を開始できませんでした: ${error.message}`; }
  await refresh();
});

$('maintenanceForm').addEventListener('submit', async event => {
  event.preventDefault();
  const localValue = $('maintenanceRunAt').value;
  if (!localValue) return;
  const payload = { operation: $('maintenanceOperation').value, runAt: new Date(localValue).toISOString(), warningMinutes: Number($('maintenanceWarning').value) };
  try {
    const response = await fetch('/api/maintenance/schedule', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error);
    $('maintenanceMessage').textContent = `${date(body.runAt)}の${maintenanceLabels[body.operation]}を予約しました。`;
    await refreshMaintenance();
  } catch (error) { $('maintenanceMessage').textContent = `予約できませんでした: ${error.message}`; }
});

$('maintenanceList').addEventListener('click', async event => {
  const button = event.target.closest('[data-cancel-maintenance]');
  if (!button) return;
  button.disabled = true;
  try {
    const response = await fetch(`/api/maintenance/${button.dataset.cancelMaintenance}/cancel`, { method: 'POST' });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error);
    $('maintenanceMessage').textContent = '予約を取り消しました。';
  } catch (error) { $('maintenanceMessage').textContent = `取消できませんでした: ${error.message}`; }
  await refreshMaintenance();
});

$('settingsForm').addEventListener('submit', async event => {
  event.preventDefault();
  const settings = {};
  new FormData(event.currentTarget).forEach((value, key) => { settings[key] = Number(value); });
  try {
    const response = await fetch('/api/settings', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ settings }) });
    const body = await response.json();
    if (!response.ok) throw new Error(body.error);
    $('settingsMessage').textContent = body.changes.length ? `${body.changes.length}項目を保存しました。安全再起動後に反映されます。` : '変更はありません。';
    await refreshSettings();
  } catch (error) { $('settingsMessage').textContent = `保存できませんでした: ${error.message}`; }
});

async function refreshIncidents() {
  try { const body=await (await fetch('/api/incidents',{cache:'no-store'})).json(); const items=body.incidents??[]; $('incidentCount').textContent=`${items.length}件`; $('incidentList').replaceChildren(...items.slice(0,8).map(item=>{const row=document.createElement('div');row.className='compact-row';const title=document.createElement('strong');title.textContent=`${item.severity==='critical'?'障害':item.severity==='warning'?'注意':'情報'} · ${item.title}`;const meta=document.createElement('span');meta.textContent=`${date(item.createdAt)}${item.detail?' · '+item.detail:''}`;row.append(title,meta);return row;})); }
  catch { $('incidentMessage').textContent='記録を読み込めませんでした。'; }
}
$('incidentForm').addEventListener('submit',async event=>{event.preventDefault();const payload={severity:$('incidentSeverity').value,title:$('incidentTitle').value,detail:$('incidentDetail').value};try{const response=await fetch('/api/incidents',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});const body=await response.json();if(!response.ok)throw new Error(body.error);event.currentTarget.reset();$('incidentMessage').textContent='記録しました。';await refreshIncidents();}catch(error){$('incidentMessage').textContent=`記録できませんでした: ${error.message}`;}});

async function refreshMigrations(){try{const body=await(await fetch('/api/migrations',{cache:'no-store'})).json();const items=body.packages??[];$('migrationList').replaceChildren(...items.map(item=>{const row=document.createElement('div');row.className='compact-row';const title=document.createElement('strong');title.textContent=item.name;const meta=document.createElement('span');meta.textContent=`${date(item.createdAt)} · ${item.sizeMb} MB`;row.append(title,meta);return row;}));}catch{$('migrationMessage').textContent='移行履歴を読み込めませんでした。';}}
$('migrationExport').addEventListener('click',async()=>{try{const response=await fetch('/api/actions/migration-export',{method:'POST'});const body=await response.json();if(!response.ok)throw new Error(body.error);$('migrationMessage').textContent='作成を開始しました。完了後に一覧へ表示されます。';setTimeout(refreshMigrations,5000);}catch(error){$('migrationMessage').textContent=`開始できませんでした: ${error.message}`;}});
async function refreshLogs(){try{const body=await(await fetch('/api/logs',{cache:'no-store'})).json();$('serverLogs').textContent=(body.lines??[]).join('\n')||'ログはありません。';}catch{$('serverLogs').textContent='ログを取得できませんでした。';}}
$('refreshLogs').addEventListener('click',event=>{event.preventDefault();refreshLogs();});
document.querySelector('.log-viewer').addEventListener('toggle',event=>{if(event.currentTarget.open)refreshLogs();});

const defaultMaintenance = new Date(Date.now() + 30 * 60 * 1000);
defaultMaintenance.setMinutes(Math.ceil(defaultMaintenance.getMinutes() / 5) * 5, 0, 0);
$('maintenanceRunAt').value = `${defaultMaintenance.getFullYear()}-${String(defaultMaintenance.getMonth() + 1).padStart(2, '0')}-${String(defaultMaintenance.getDate()).padStart(2, '0')}T${String(defaultMaintenance.getHours()).padStart(2, '0')}:${String(defaultMaintenance.getMinutes()).padStart(2, '0')}`;

refresh();
refreshBackups();
refreshMaintenance();
refreshSettings();
refreshIncidents();
refreshMigrations();
setInterval(refresh, 5000);
setInterval(refreshBackups, 30000);
setInterval(refreshMaintenance, 30000);
