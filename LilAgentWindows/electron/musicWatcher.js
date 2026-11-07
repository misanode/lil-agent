import { execFile, spawn } from 'node:child_process';

const POLL_S = 3;
const WINDOWS_SCRIPT = `
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation\`1' })[0]
[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime] | Out-Null
$op = [Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
$mgr = $asTask.MakeGenericMethod([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]).Invoke($null, @($op)).Result
while ($true) {
  $playing = $false
  foreach ($s in $mgr.GetSessions()) {
    if ($s.SourceAppUserModelId -match 'spotify|applemusic|itunes' -and $s.GetPlaybackInfo().PlaybackStatus -eq 'Playing') { $playing = $true }
  }
  if ($playing) { [Console]::Out.WriteLine('playing') } else { [Console]::Out.WriteLine('stopped') }
  [Console]::Out.Flush()
  Start-Sleep -Seconds ${POLL_S}
}
`;

function macState(app) {
  const script = `if application "${app}" is running then\n  tell application "${app}" to return (player state as text)\nend if\nreturn "stopped"`;
  return new Promise((resolve) => execFile('osascript', ['-e', script], { timeout: 4000 }, (err, out) => resolve(err ? 'unknown' : out.trim())));
}

export function startMusicWatcher({ enabled, onChange }) {
  let playing = false;
  let child = null;
  let timer = null;
  const set = (now) => {
    if (now !== playing) {
      playing = now;
      onChange(now);
    }
  };

  function startWindows() {
    if (child) return;
    child = spawn('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', WINDOWS_SCRIPT], { windowsHide: true });
    let buf = '';
    child.stdout.on('data', (d) => {
      buf += d.toString();
      const lines = buf.split(/\r?\n/);
      buf = lines.pop();
      const last = lines.filter(Boolean).pop();
      if (last) set(enabled() && last.trim() === 'playing');
    });
    child.on('exit', () => {
      child = null;
      set(false);
    });
  }

  async function pollMac() {
    if (!enabled()) return set(false);
    for (const app of ['Spotify', 'Music']) if ((await macState(app)) === 'playing') return set(true);
    set(false);
  }

  const watcher = {
    get playing() { return playing; },
    poll() {
      if (!enabled()) return set(false);
      if (process.platform === 'win32') startWindows();
      else pollMac();
    },
    stop() {
      child?.kill();
      clearInterval(timer);
    },
  };
  if (process.platform === 'win32') {
    if (enabled()) startWindows();
    timer = setInterval(() => { if (enabled()) startWindows(); else set(false); }, POLL_S * 1000);
  } else if (process.platform === 'darwin') {
    timer = setInterval(pollMac, 5000);
    pollMac();
  }
  return watcher;
}
