/**
 * Unit tests for sw.js.
 *
 * The service worker runs in a ServiceWorkerGlobalScope, not a window. jsdom
 * provides `self` (aliased to window) but none of the worker APIs, so the
 * globals the worker touches -- skipWaiting, clients, caches -- are stubbed
 * here and the lifecycle events are dispatched by hand.
 */

describe("service worker", () => {
  let skipWaiting;
  let claim;
  let cachesDelete;

  /** Installs worker globals and loads a fresh copy of sw.js. */
  function loadWorker(cacheNames = ["swapboard-v1", "swapboard-v2"]) {
    jest.resetModules();

    skipWaiting = jest.fn();
    claim = jest.fn();
    cachesDelete = jest.fn().mockResolvedValue(true);

    self.skipWaiting = skipWaiting;
    self.clients = { claim };
    global.caches = {
      keys: jest.fn().mockResolvedValue(cacheNames),
      delete: cachesDelete,
    };

    require("./sw.js");
  }

  afterEach(() => {
    delete self.skipWaiting;
    delete self.clients;
    delete global.caches;
  });

  test("install activates the new worker immediately", () => {
    loadWorker();
    self.dispatchEvent(new Event("install"));
    expect(skipWaiting).toHaveBeenCalled();
  });

  test("activate clears every previous cache and claims open clients", async () => {
    loadWorker();

    const event = new Event("activate");
    let waited;
    event.waitUntil = (promise) => {
      waited = promise;
    };
    self.dispatchEvent(event);

    await waited;
    expect(global.caches.keys).toHaveBeenCalled();
    expect(cachesDelete).toHaveBeenCalledWith("swapboard-v1");
    expect(cachesDelete).toHaveBeenCalledWith("swapboard-v2");
    expect(claim).toHaveBeenCalled();
  });

  test("activate is a no-op when there is nothing cached", async () => {
    loadWorker([]);

    const event = new Event("activate");
    let waited;
    event.waitUntil = (promise) => {
      waited = promise;
    };
    self.dispatchEvent(event);

    await waited;
    expect(cachesDelete).not.toHaveBeenCalled();
    expect(claim).toHaveBeenCalled();
  });
});
