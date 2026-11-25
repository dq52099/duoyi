(function () {
  if (window.__duoyiWebResumeGuardInstalled) return;
  window.__duoyiWebResumeGuardInstalled = true;

  var RELOAD_COOLDOWN_MS = 15000;
  var RELOAD_WINDOW_MS = 120000;
  var MAX_RELOADS_IN_WINDOW = 2;
  var HEALTH_RESET_VISIBLE_MS = 20000;
  var HEALTH_CHECK_DELAY_MS = 750;
  var STORAGE_LAST_TS_KEY = 'duoyi_web_resume_reload_ts';
  var STORAGE_HISTORY_KEY = 'duoyi_web_resume_reload_history';

  var tracked = [];
  var trackedByCanvas = typeof WeakMap === 'function' ? new WeakMap() : null;
  var wasHidden = document.visibilityState === 'hidden';
  var contextLostWhileHidden = false;
  var hadActiveContextLoss = false;
  var failedWebglAfterLoss = false;
  var firstFrameSeen = false;
  var healthCheckTimer = null;
  var followupRepaintTimer = null;
  var healthyResetTimer = null;
  var probeCanvas = null;

  var stats = {
    resumeCount: 0,
    nudgeCount: 0,
    lostEventCount: 0,
    restoredEventCount: 0,
    recoveryReloadAttemptCount: 0,
    lastResumeReason: '',
    lastRecoveryReason: '',
    lastHealthResult: 'init'
  };

  function isWebGLType(contextId) {
    return contextId === 'webgl2' ||
      contextId === 'webgl' ||
      contextId === 'experimental-webgl';
  }

  function isCtxLost(ctx) {
    if (!ctx) return true;
    try {
      if (typeof ctx.isContextLost === 'function' && ctx.isContextLost()) {
        return true;
      }
      if (typeof ctx.getError === 'function' &&
          typeof ctx.CONTEXT_LOST_WEBGL === 'number' &&
          ctx.getError() === ctx.CONTEXT_LOST_WEBGL) {
        return true;
      }
    } catch (_) {
      return true;
    }
    return false;
  }

  function isActiveTrackedRecord(rec) {
    if (!rec || !rec.canvas) return false;
    try {
      var w = Number(rec.canvas.width) || 0;
      var h = Number(rec.canvas.height) || 0;
      if (w > 1 || h > 1) return true;
      if (!rec.isOffscreen && rec.canvas.isConnected) return true;
    } catch (_) {
      return false;
    }
    return false;
  }

  function cancelPendingHealthCheck() {
    if (healthCheckTimer !== null) {
      window.clearTimeout(healthCheckTimer);
      healthCheckTimer = null;
    }
  }

  function cancelHealthyResetTimer() {
    if (healthyResetTimer !== null) {
      window.clearTimeout(healthyResetTimer);
      healthyResetTimer = null;
    }
  }

  function scheduleHealthyStorageReset() {
    cancelHealthyResetTimer();
    if (document.visibilityState !== 'visible') return;
    healthyResetTimer = window.setTimeout(function () {
      healthyResetTimer = null;
      if (document.visibilityState !== 'visible') return;
      var webgl = inspectWebGLHealth();
      if (webgl.lostCount > 0 || webgl.failedWebglAfterLoss) return;
      try {
        window.sessionStorage.removeItem(STORAGE_HISTORY_KEY);
      } catch (_) {}
    }, HEALTH_RESET_VISIBLE_MS);
  }

  function attemptRecoveryReload(reason) {
    stats.recoveryReloadAttemptCount++;
    stats.lastRecoveryReason = String(reason || '');
    var now = Date.now();
    try {
      var storage = window.sessionStorage;
      var lastTs = Number(storage.getItem(STORAGE_LAST_TS_KEY) || '0');
      if (lastTs && now - lastTs < RELOAD_COOLDOWN_MS) {
        stats.lastHealthResult = 'cooldown-blocked:' + stats.lastRecoveryReason;
        return false;
      }
      var history = [];
      var rawHistory = storage.getItem(STORAGE_HISTORY_KEY);
      if (rawHistory) {
        var parsed = JSON.parse(rawHistory);
        if (Array.isArray(parsed)) {
          history = parsed.filter(function (ts) {
            return typeof ts === 'number' && now - ts < RELOAD_WINDOW_MS;
          });
        }
      }
      if (history.length >= MAX_RELOADS_IN_WINDOW) {
        stats.lastHealthResult = 'window-limit-blocked:' + stats.lastRecoveryReason;
        return false;
      }
      history.push(now);
      storage.setItem(STORAGE_LAST_TS_KEY, String(now));
      storage.setItem(STORAGE_HISTORY_KEY, JSON.stringify(history));
    } catch (_) {
      stats.lastHealthResult = 'storage-unavailable-blocked:' + stats.lastRecoveryReason;
      return false;
    }

    stats.lastHealthResult = 'reloading:' + stats.lastRecoveryReason;
    if (typeof window.__duoyiWebResumeGuardReloadOverride === 'function') {
      window.__duoyiWebResumeGuardReloadOverride(stats.lastRecoveryReason);
      return true;
    }
    window.location.reload();
    return true;
  }

  function trackWebGLCanvas(canvas, ctx, type, isOffscreen) {
    var existing = trackedByCanvas ? trackedByCanvas.get(canvas) : null;
    if (existing && existing.ctx === ctx) {
      existing.lost = isCtxLost(ctx);
      if (!existing.lost && isActiveTrackedRecord(existing)) {
        failedWebglAfterLoss = false;
      }
      return existing;
    }

    var rec = {
      canvas: canvas,
      ctx: ctx,
      type: type,
      isOffscreen: !!isOffscreen,
      lost: isCtxLost(ctx),
      lostAt: 0,
      restoredCount: 0
    };
    if (trackedByCanvas) trackedByCanvas.set(canvas, rec);
    if (tracked.length >= 16) {
      for (var i = 0; i < tracked.length; i++) {
        if (!isActiveTrackedRecord(tracked[i])) {
          tracked.splice(i, 1);
          break;
        }
      }
    }
    tracked.push(rec);

    if (!rec.lost && isActiveTrackedRecord(rec)) {
      failedWebglAfterLoss = false;
    }

    if (typeof canvas.addEventListener === 'function') {
      canvas.addEventListener('webglcontextlost', function (event) {
        if (event && typeof event.preventDefault === 'function') {
          event.preventDefault();
        }
        rec.lost = true;
        rec.lostAt = Date.now();
        stats.lostEventCount++;
        if (isActiveTrackedRecord(rec)) {
          hadActiveContextLoss = true;
          cancelHealthyResetTimer();
          if (document.visibilityState === 'hidden') {
            contextLostWhileHidden = true;
          } else {
            scheduleHealthCheck(HEALTH_CHECK_DELAY_MS, 'webglcontextlost');
          }
        }
      });

      canvas.addEventListener('webglcontextrestored', function () {
        rec.lost = false;
        rec.restoredCount++;
        stats.restoredEventCount++;
        if (isActiveTrackedRecord(rec)) {
          failedWebglAfterLoss = false;
          if (document.visibilityState === 'visible') {
            nudgeFlutterRepaint('webglcontextrestored');
            scheduleHealthCheck(HEALTH_CHECK_DELAY_MS, 'webglcontextrestored');
          }
        }
      });
    }
    return rec;
  }

  function wrapGetContext(proto, isOffscreen) {
    if (!proto || typeof proto.getContext !== 'function') return;
    if (proto.getContext.__duoyiWrapped) return;
    var origGetContext = proto.getContext;
    var wrapped = function (contextId) {
      var ctx = origGetContext.apply(this, arguments);
      if (isWebGLType(contextId)) {
        if (ctx) {
          trackWebGLCanvas(this, ctx, contextId, isOffscreen);
        } else if (hadActiveContextLoss) {
          failedWebglAfterLoss = true;
          if (document.visibilityState === 'visible') {
            scheduleHealthCheck(HEALTH_CHECK_DELAY_MS, 'webgl-null-after-loss');
          } else {
            contextLostWhileHidden = true;
          }
        }
      }
      return ctx;
    };
    wrapped.__duoyiWrapped = true;
    proto.getContext = wrapped;
  }

  function collectVisibleFlutterCanvases() {
    var result = [];
    var seen = typeof Set === 'function' ? new Set() : null;
    function pushUnique(el) {
      if (!el || (seen && seen.has(el))) return;
      if (seen) seen.add(el);
      try {
        var cw = el.clientWidth || 0;
        var ch = el.clientHeight || 0;
        if (cw > 0 && ch > 0) {
          result.push(el);
        }
      } catch (_) {}
    }

    function scanRoot(root) {
      if (!root || typeof root.querySelectorAll !== 'function') return;
      var canvases = root.querySelectorAll('canvas');
      for (var i = 0; i < canvases.length; i++) {
        pushUnique(canvases[i]);
      }
      var all = root.querySelectorAll('flutter-view, flt-glass-pane');
      for (var j = 0; j < all.length; j++) {
        if (all[j].shadowRoot) {
          scanRoot(all[j].shadowRoot);
        }
      }
    }

    scanRoot(document);
    return result;
  }

  function probeCanvasRenderingHealth() {
    if (!firstFrameSeen) return { status: 'pending' };
    var splash = document.getElementById('duoyi-splash');
    if (splash && !splash.classList.contains('duoyi-splash-hide')) {
      return { status: 'pending' };
    }

    var canvases = collectVisibleFlutterCanvases();
    if (canvases.length === 0) {
      return { status: 'no-canvas' };
    }

    var primary = canvases[0];
    var bestArea = (primary.clientWidth || 0) * (primary.clientHeight || 0);
    for (var i = 1; i < canvases.length; i++) {
      var area = (canvases[i].clientWidth || 0) * (canvases[i].clientHeight || 0);
      if (area > bestArea) {
        bestArea = area;
        primary = canvases[i];
      }
    }
    if ((primary.width || 0) <= 0 || (primary.height || 0) <= 0) {
      return { status: 'zero-size' };
    }

    try {
      if (!probeCanvas) {
        probeCanvas = document.createElement('canvas');
        probeCanvas.width = 8;
        probeCanvas.height = 8;
      }
      var g = probeCanvas.getContext('2d', { willReadFrequently: true });
      if (!g) return { status: 'ok' };
      g.clearRect(0, 0, 8, 8);
      g.drawImage(primary, 0, 0, 8, 8);
      var data = g.getImageData(0, 0, 8, 8).data;
      var nonZeroAlpha = 0;
      var nonBlack = 0;
      for (var p = 0; p < data.length; p += 4) {
        if (data[p + 3] > 0) nonZeroAlpha++;
        if (data[p] > 2 || data[p + 1] > 2 || data[p + 2] > 2) nonBlack++;
      }
      if (nonZeroAlpha === 0) return { status: 'blank', nonZeroAlpha: 0, nonBlack: 0 };
      if (nonBlack === 0) return { status: 'black', nonZeroAlpha: nonZeroAlpha, nonBlack: 0 };
      return { status: 'ok', nonZeroAlpha: nonZeroAlpha, nonBlack: nonBlack };
    } catch (_) {
      return { status: 'ok' };
    }
  }

  function inspectWebGLHealth() {
    var activeCount = 0;
    var healthyCount = 0;
    var lostCount = 0;
    for (var i = 0; i < tracked.length; i++) {
      var rec = tracked[i];
      if (!isActiveTrackedRecord(rec)) continue;
      activeCount++;
      if (isCtxLost(rec.ctx)) {
        rec.lost = true;
      }
      if (rec.lost) {
        lostCount++;
      } else {
        healthyCount++;
      }
    }
    return {
      activeCount: activeCount,
      healthyCount: healthyCount,
      lostCount: lostCount,
      hadActiveContextLoss: hadActiveContextLoss,
      failedWebglAfterLoss: failedWebglAfterLoss
    };
  }

  function evaluateAndRecover(reason) {
    if (document.visibilityState !== 'visible') {
      stats.lastHealthResult = 'hidden-skip';
      return stats.lastHealthResult;
    }

    var webgl = inspectWebGLHealth();
    if ((webgl.hadActiveContextLoss || webgl.lostCount > 0 || webgl.failedWebglAfterLoss) &&
        webgl.healthyCount === 0) {
      attemptRecoveryReload('webgl-unrecovered:' + reason);
      return stats.lastHealthResult;
    }

    var canvasHealth = probeCanvasRenderingHealth();
    if (canvasHealth.status === 'no-canvas' ||
        canvasHealth.status === 'zero-size' ||
        canvasHealth.status === 'blank' ||
        canvasHealth.status === 'black') {
      attemptRecoveryReload('canvas-' + canvasHealth.status + ':' + reason);
      return stats.lastHealthResult;
    }

    contextLostWhileHidden = false;
    stats.lastHealthResult = 'healthy:' + canvasHealth.status;
    if (firstFrameSeen && webgl.healthyCount > 0) {
      scheduleHealthyStorageReset();
    }
    return stats.lastHealthResult;
  }

  function scheduleHealthCheck(delayMs, reason) {
    cancelPendingHealthCheck();
    healthCheckTimer = window.setTimeout(function () {
      healthCheckTimer = null;
      evaluateAndRecover(reason);
    }, delayMs);
  }

  function dispatchWebResumeEvent(reason) {
    try {
      window.dispatchEvent(new CustomEvent('duoyi:web-resume', {
        detail: { reason: reason, ts: Date.now() }
      }));
    } catch (_) {}
  }

  function nudgeFlutterRepaint(reason) {
    stats.nudgeCount++;
    dispatchWebResumeEvent(reason);

    var raf = window.requestAnimationFrame || function (cb) { return window.setTimeout(cb, 16); };
    raf(function () {
      try {
        if (window.visualViewport && typeof window.visualViewport.dispatchEvent === 'function') {
          window.visualViewport.dispatchEvent(new Event('resize'));
        }
      } catch (_) {}
      try {
        window.dispatchEvent(new Event('resize'));
      } catch (_) {}

      var fv = document.querySelector('flutter-view');
      if (fv && fv.style && !fv.style.transform) {
        fv.style.transform = 'translateZ(0)';
        raf(function () {
          if (fv.style.transform === 'translateZ(0)') {
            fv.style.transform = '';
          }
        });
      }
    });

    if (followupRepaintTimer !== null) {
      window.clearTimeout(followupRepaintTimer);
    }
    followupRepaintTimer = window.setTimeout(function () {
      followupRepaintTimer = null;
      if (document.visibilityState === 'visible') {
        dispatchWebResumeEvent(reason + ':settle');
      }
    }, 120);
  }

  function handleResume(reason, opts) {
    var now = Date.now();
    if (now - stats._lastResumeTs < 50 && !(opts && opts.persisted)) {
      return;
    }
    stats._lastResumeTs = now;
    stats.resumeCount++;
    stats.lastResumeReason = String(reason || '');

    nudgeFlutterRepaint(reason);
    scheduleHealthCheck(HEALTH_CHECK_DELAY_MS, reason);
  }
  stats._lastResumeTs = 0;

  if (typeof HTMLCanvasElement !== 'undefined') {
    wrapGetContext(HTMLCanvasElement.prototype, false);
  }
  if (typeof OffscreenCanvas !== 'undefined') {
    wrapGetContext(OffscreenCanvas.prototype, true);
  }

  window.addEventListener('flutter-first-frame', function () {
    firstFrameSeen = true;
    scheduleHealthyStorageReset();
  }, { once: true });

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') {
      wasHidden = true;
      cancelPendingHealthCheck();
      cancelHealthyResetTimer();
    } else if (document.visibilityState === 'visible') {
      if (wasHidden || contextLostWhileHidden) {
        wasHidden = false;
        handleResume('visibilitychange');
      }
    }
  });

  window.addEventListener('pagehide', function () {
    wasHidden = true;
    cancelPendingHealthCheck();
    cancelHealthyResetTimer();
  });

  window.addEventListener('pageshow', function (event) {
    if (event && event.persisted) {
      wasHidden = false;
      handleResume('pageshow-persisted', { persisted: true });
    } else if (wasHidden || contextLostWhileHidden) {
      wasHidden = false;
      handleResume('pageshow');
    }
  });

  document.addEventListener('resume', function () {
    wasHidden = false;
    handleResume('resume');
  });

  window.addEventListener('focus', function () {
    if (wasHidden || contextLostWhileHidden) {
      wasHidden = false;
      handleResume('focus');
    }
  });

  window.__duoyiWebResumeGuard = {
    constants: {
      RELOAD_COOLDOWN_MS: RELOAD_COOLDOWN_MS,
      RELOAD_WINDOW_MS: RELOAD_WINDOW_MS,
      MAX_RELOADS_IN_WINDOW: MAX_RELOADS_IN_WINDOW,
      HEALTH_CHECK_DELAY_MS: HEALTH_CHECK_DELAY_MS
    },
    getState: function () {
      return {
        firstFrameSeen: firstFrameSeen,
        wasHidden: wasHidden,
        contextLostWhileHidden: contextLostWhileHidden,
        hadActiveContextLoss: hadActiveContextLoss,
        failedWebglAfterLoss: failedWebglAfterLoss,
        webgl: inspectWebGLHealth(),
        canvas: probeCanvasRenderingHealth(),
        stats: {
          resumeCount: stats.resumeCount,
          nudgeCount: stats.nudgeCount,
          lostEventCount: stats.lostEventCount,
          restoredEventCount: stats.restoredEventCount,
          recoveryReloadAttemptCount: stats.recoveryReloadAttemptCount,
          lastResumeReason: stats.lastResumeReason,
          lastRecoveryReason: stats.lastRecoveryReason,
          lastHealthResult: stats.lastHealthResult
        }
      };
    },
    checkHealthNow: function (reason) {
      return evaluateAndRecover(reason || 'manual');
    },
    getActiveWebGLContexts: function () {
      var list = [];
      for (var i = 0; i < tracked.length; i++) {
        if (isActiveTrackedRecord(tracked[i])) {
          list.push(tracked[i].ctx);
        }
      }
      return list;
    }
  };
})();
