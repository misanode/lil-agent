const DEFAULT_INTERVAL_MS = 24 * 60 * 60 * 1000;

function errorMessage(error, operation) {
  const detail = `${error?.code ?? ''} ${error?.message ?? error ?? ''}`;
  if (/checksum|sha512|hash mismatch/i.test(detail)) return 'The update failed its integrity check. Please try again.';
  if (/signature|publisher|certificate/i.test(detail)) return 'The update could not be verified. Please try again.';
  if (/ENOTFOUND|ECONN|ETIMEDOUT|network|timed? out|offline/i.test(detail)) return 'Couldn’t reach the update server. Check your connection and try again.';
  if (/404|ERR_UPDATER_LATEST_VERSION_NOT_FOUND|ERR_UPDATER_CHANNEL_FILE_NOT_FOUND/i.test(detail)) return 'The update files are not available yet. Please try again later.';
  if (/cancel/i.test(detail)) return 'The update download was cancelled. Please try again.';
  if (/EACCES|EPERM|permission|access denied/i.test(detail)) return 'The update could not be saved or installed. Check permissions and try again.';
  return operation === 'check' ? 'Couldn’t check for updates. Please try again.'
    : operation === 'install' ? 'Couldn’t install the update. Please try again.'
      : 'Couldn’t download the update. Please try again.';
}

function version(info) {
  const value = typeof info?.version === 'string' ? info.version.replace(/^v/i, '') : '';
  return /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.+-]+)?$/.test(value) && value.length <= 80 ? value : null;
}

export function createAutomaticUpdates({ updater, onChange = () => {}, intervalMs = DEFAULT_INTERVAL_MS }) {
  updater.autoDownload = false;
  updater.autoInstallOnAppQuit = false;
  updater.allowPrerelease = false;
  updater.allowDowngrade = false;
  updater.disableWebInstaller = true;

  let state = { status: 'idle' };
  let latest = null;
  let timer = null;
  let stopped = false;
  let checking = null;
  let downloading = null;
  let applyAfterCheck = null;
  let downloaded = false;
  let installing = false;
  let requested = false;

  function set(next) {
    if (stopped || JSON.stringify(next) === JSON.stringify(state)) return;
    state = next;
    try { onChange(state); } catch {}
  }

  function failCheck(request, error) {
    if (stopped || request?.failed) return;
    if (request) request.failed = true;
    if (request?.quiet) set(request.previous);
    else set({ status: 'failed', operation: 'check', error: errorMessage(error, 'check') });
  }

  function failDownload(error) {
    if (stopped || downloading?.failed) return;
    if (downloading) downloading.failed = true;
    requested = false;
    downloaded = false;
    set({ status: 'failed', operation: 'download', latest, error: errorMessage(error, 'download') });
  }

  function failInstall(error) {
    if (stopped) return;
    installing = false;
    requested = false;
    set({ status: 'failed', operation: 'install', latest, error: errorMessage(error, 'install') });
  }

  function install() {
    if (stopped || installing || !downloaded || !requested) return false;
    requested = false;
    installing = true;
    set({ status: 'installing', latest });
    if (stopped) return false;
    try {
      updater.quitAndInstall(true, true);
      return installing;
    } catch (error) {
      failInstall(error);
      return false;
    }
  }

  function available(info) {
    if (stopped || downloading || downloaded || installing || checking?.failed) return;
    const next = version(info);
    if (!next) return failCheck(checking, new Error('Invalid update metadata'));
    if (checking) checking.result = true;
    latest = next;
    set({ status: 'available', latest });
  }

  function current() {
    if (stopped || downloading || downloaded || installing || checking?.failed) return;
    if (checking) checking.result = false;
    latest = null;
    set({ status: 'current' });
  }

  function onError(error) {
    if (stopped) return;
    if (installing) failInstall(error);
    else if (downloading || state.status === 'downloading') failDownload(error);
    else failCheck(checking, error);
  }

  const listeners = {
    'update-available': available,
    'update-not-available': current,
    'download-progress': (info) => {
      if (stopped || state.status !== 'downloading' || downloading?.failed || !Number.isFinite(info?.percent)) return;
      const percent = Math.max(state.percent, Math.min(100, Math.max(0, Math.floor(info.percent))));
      if (percent !== state.percent) set({ status: 'downloading', latest, percent });
    },
    'update-downloaded': (info) => {
      if (stopped || installing || downloading?.failed || state.operation === 'download' && state.status === 'failed') return;
      const next = version(info);
      if (!next || latest && next !== latest) return;
      latest = next;
      downloaded = true;
      set({ status: 'downloaded', latest });
      if (requested) install();
    },
    'update-cancelled': () => {
      if (!stopped && (downloading || state.status === 'downloading')) failDownload(new Error('Download cancelled'));
    },
    error: onError,
  };
  for (const [event, listener] of Object.entries(listeners)) updater.on(event, listener);

  function check({ quiet = false } = {}) {
    if (stopped || downloading || downloaded || installing || state.status === 'downloading') return Promise.resolve(false);
    if (checking) {
      if (!quiet && checking.quiet) {
        checking.quiet = false;
        set({ status: 'checking' });
      }
      return checking.promise;
    }
    const request = { quiet, previous: state, failed: false, result: null };
    checking = request;
    if (!quiet) set({ status: 'checking' });
    request.promise = Promise.resolve().then(() => stopped ? null : updater.checkForUpdates()).then((result) => {
      if (stopped || request.failed) return false;
      if (request.result === null) {
        if (result?.isUpdateAvailable === true) available(result.updateInfo);
        else if (result?.isUpdateAvailable === false) current();
        else failCheck(request, new Error('Automatic updates are unavailable'));
      }
      return !request.failed;
    }, (error) => {
      failCheck(request, error);
      return false;
    }).finally(() => {
      if (checking === request) checking = null;
    });
    return request.promise;
  }

  function apply() {
    if (stopped || installing) return Promise.resolve(false);
    if (downloading) return downloading.promise;
    if (downloaded) {
      requested = true;
      return Promise.resolve(install());
    }
    if (state.status !== 'available' && !(state.status === 'failed' && state.operation === 'download' && latest)) return Promise.resolve(false);
    if (checking) {
      if (!applyAfterCheck) applyAfterCheck = checking.promise.then(() => {
        applyAfterCheck = null;
        return apply();
      });
      return applyAfterCheck;
    }
    const request = { failed: false };
    downloading = request;
    requested = true;
    set({ status: 'downloading', latest, percent: 0 });
    request.promise = Promise.resolve().then(() => stopped ? null : updater.downloadUpdate()).then(() => {
      return !stopped && !request.failed && state.status !== 'failed' && (downloaded || installing);
    }, (error) => {
      if (!stopped && !request.failed && !downloaded && !installing) failDownload(error);
      return false;
    }).finally(() => {
      if (downloading === request) downloading = null;
    });
    return request.promise;
  }

  return {
    get state() { return state; },
    check,
    apply,
    start() {
      if (stopped || timer !== null) return;
      check({ quiet: true });
      timer = setInterval(() => check({ quiet: true }), intervalMs);
    },
    stop() {
      if (stopped) return;
      stopped = true;
      requested = false;
      if (timer !== null) clearInterval(timer);
      timer = null;
      for (const [event, listener] of Object.entries(listeners)) updater.removeListener(event, listener);
    },
  };
}
