export function createPanelPresentation({ window, prepare, activate, afterShow }) {
  let painted = false;
  let panelRendered = false;
  let closed = false;
  let pending = null;

  function reveal() {
    if (!pending || !painted || !panelRendered || closed) return;
    const request = pending;
    pending = null;
    if (window.isDestroyed()) {
      request.resolve(false);
      return;
    }
    try {
      prepare(window, request.anchor);
      window.show();
      activate();
      window.focus();
      window.webContents.focus();
      afterShow();
      request.resolve(true);
    } catch (error) {
      request.reject(error);
    }
  }

  function onPaint() {
    painted = true;
    reveal();
  }

  window.once('ready-to-show', onPaint);
  window.once('closed', () => {
    closed = true;
    window.removeListener('ready-to-show', onPaint);
    pending?.resolve(false);
    pending = null;
  });

  return {
    show(anchor) {
      if (closed || window.isDestroyed()) return Promise.resolve(false);
      if (pending) {
        pending.anchor = anchor;
        return pending.promise;
      }
      const request = { anchor };
      request.promise = new Promise((resolve, reject) => {
        request.resolve = resolve;
        request.reject = reject;
      });
      pending = request;
      reveal();
      return request.promise;
    },
    rendered() {
      if (closed) return;
      panelRendered = true;
      reveal();
    },
  };
}
