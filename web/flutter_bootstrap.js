{{flutter_js}}
{{flutter_build_config}}

async function clearStaleWebCache() {
  if (!('serviceWorker' in navigator)) return false;

  const hadController = Boolean(navigator.serviceWorker.controller);
  const registrations = await navigator.serviceWorker.getRegistrations();
  await Promise.all(registrations.map((registration) => registration.unregister()));

  if ('caches' in window) {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map((cacheName) => caches.delete(cacheName)));
  }

  const recoveryKey = 'mobile_agent_cache_recovered';
  if (hadController && !sessionStorage.getItem(recoveryKey)) {
    sessionStorage.setItem(recoveryKey, '1');
    location.reload();
    return true;
  }
  sessionStorage.removeItem(recoveryKey);
  return false;
}

clearStaleWebCache()
    .catch(() => false)
    .then((reloaded) => {
      if (!reloaded) {
        _flutter.loader.load();
      }
    });
