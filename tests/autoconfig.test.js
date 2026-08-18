"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const configPath = path.join(
  root,
  "autoconfig",
  "tridactyl-godmode.cfg"
);
const config = fs.readFileSync(configPath, "utf8").replace(/^[^\n]*\n/, "");
const internalMatches = [
  "about:*",
  "chrome://*/*",
  "resource://*/*",
  "view-source:*",
];
const stableId = "tridactyl.vim@cmcaine.co.uk";

function createHarness({
  firefoxVersion = "999.0a1",
  keyHandoff = false,
  shutdownHook = true,
} = {}) {
  const actorQueries = [];
  const actorRegistrations = [];
  const actorResults = [];
  const cacheClears = [];
  const cacheWrites = [];
  const errors = [];
  const keyListeners = [];
  const logs = [];
  const observers = [];
  const resourceSubstitutions = [];

  const actor = {
    sendQuery(name, data) {
      actorQueries.push({ name, data });
      const result = actorResults.shift();
      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve(result || { delivered: true });
    },
  };
  const selectedBrowser = {
    focusCount: 0,
    browsingContext: {
      currentWindowGlobal: {
        getActor() {
          return actor;
        },
      },
    },
    focus() {
      this.focusCount += 1;
      browserWindow.document.activeElement = this;
    },
  };
  const browserWindow = {
    closed: false,
    document: {
      activeElement: {},
      documentElement: {
        getAttribute(name) {
          return name === "windowtype" ? "navigator:browser" : null;
        },
      },
      readyState: "complete",
    },
    gBrowser: { selectedBrowser },
    addEventListener(type, listener) {
      if (type === "keydown") {
        keyListeners.push(listener);
      }
    },
  };

  function dispatchChromeKey(overrides = {}) {
    const event = {
      altKey: false,
      code: "KeyJ",
      ctrlKey: false,
      isComposing: false,
      key: "j",
      metaKey: false,
      repeat: false,
      shiftKey: false,
      defaultPrevented: false,
      propagationStopped: false,
      preventDefault() {
        this.defaultPrevented = true;
      },
      stopImmediatePropagation() {
        this.propagationStopped = true;
      },
      ...overrides,
    };
    for (const listener of keyListeners) {
      listener(event);
    }
    return event;
  }

  function patternSet(patterns) {
    return { patterns: patterns.map(pattern => ({ pattern })) };
  }

  const StartupCache = {
    async clearAddonData(id) {
      cacheClears.push(id);
    },
    manifests: {
      async set(cachePath, value) {
        cacheWrites.push({ path: cachePath, value });
      },
    },
  };

  class Extension {
    constructor(
      id,
      {
        loadError = false,
        startupGate = null,
        startupError = false,
        temporary = false,
        type = "extension",
      } = {}
    ) {
      this.id = id;
      this.addonData = { type };
      this.loadError = loadError;
      this.startupGate = startupGate;
      this.startupError = startupError;
      this.temporarilyInstalled = temporary;
      this.ignoreQuarantine = false;
      this.isPrivileged = false;
      this.setupPrivilege = null;
    }

    async startup() {
      await this.loadManifest();
      this._setupStartupPermissions();
      await this.startupGate;
      if (this.startupError) {
        throw new Error("startup failed");
      }
      return this;
    }

    async loadManifest() {
      await this.startupClearCachePromise;
      if (this.loadError) {
        throw new Error("manifest failed");
      }
      this.permissions = new Set(["tabs", "<all_urls>"]);
      this.allowedOrigins = patternSet([
        "<all_urls>",
        "moz-extension://generated-uuid/*",
      ]);
      this.contentScripts = [
        { matches: ["<all_urls>"], jsPaths: ["content.js"] },
      ];
      this.manifest = {
        permissions: ["tabs", "<all_urls>"],
        content_scripts: [
          { matches: ["<all_urls>"], js: ["content.js"] },
        ],
      };
      return this.manifest;
    }

    _setupStartupPermissions() {
      this.setupPrivilege = this.isPrivileged;
    }

    async shutdown() {
      return this;
    }

    cachePermissions() {
      return StartupCache.manifests.set([this.id, "1", "en-US"], {
        permissions: this.permissions,
        originPermissions: this.allowedOrigins.patterns.map(
          pattern => pattern.pattern
        ),
      });
    }
  }
  if (!shutdownHook) {
    delete Extension.prototype.shutdown;
  }

  const modules = new Map([
    ["resource://gre/modules/Services.sys.mjs", {
      Services: {
        appinfo: { version: firefoxVersion },
        console: {
          logStringMessage(message) {
            logs.push(message);
          },
        },
        dirsvc: {
          get() {
            return {
              path: "/firefox",
              append(name) {
                this.path += `/${name}`;
              },
              exists() {
                return true;
              },
              isFile() {
                return true;
              },
              get parent() {
                return { path: "/firefox" };
              },
            };
          },
        },
        io: {
          getProtocolHandler() {
            return {
              QueryInterface() {
                return this;
              },
              setSubstitutionWithFlags(...args) {
                resourceSubstitutions.push(args);
              },
            };
          },
          newFileURI(file) {
            return { spec: `file://${file.path}/` };
          },
        },
        obs: {
          addObserver(callback, topic) {
            observers.push({ callback, topic });
          },
        },
        prefs: {
          getBoolPref(name, fallback) {
            assert.equal(name, "tridactyl.godmode.chrome_key_handoff");
            return keyHandoff ?? fallback;
          },
        },
        wm: {
          getEnumerator(type) {
            assert.equal(type, "navigator:browser");
            return [browserWindow];
          },
        },
      },
    }],
    ["resource://gre/modules/Extension.sys.mjs", { Extension }],
    [
      "resource://gre/modules/ExtensionParent.sys.mjs",
      { ExtensionParent: { StartupCache } },
    ],
    [
      "resource://gre/modules/ExtensionUtils.sys.mjs",
      {
        ExtensionUtils: {
          parseMatchPatterns(patterns) {
            return patternSet(patterns);
          },
        },
      },
    ],
  ]);

  function evaluate() {
    vm.runInNewContext(
      config,
      {
        ChromeUtils: {
          getClassName(value) {
            return Object.prototype.toString.call(value).slice(8, -1);
          },
          importESModule(uri) {
            assert(modules.has(uri), `Unexpected module import: ${uri}`);
            return modules.get(uri);
          },
          registerWindowActor(name, options) {
            actorRegistrations.push({ name, options });
          },
        },
        Components: {
          interfaces: {
            nsIFile: {},
            nsISubstitutingProtocolHandler: {},
          },
          utils: {
            reportError(error) {
              errors.push(String(error));
            },
          },
        },
      },
      { filename: configPath }
    );
  }

  return {
    actorQueries,
    actorRegistrations,
    actorResults,
    browserWindow,
    cacheClears,
    cacheWrites,
    dispatchChromeKey,
    errors,
    evaluate,
    Extension,
    logs,
    observers,
    resourceSubstitutions,
    selectedBrowser,
  };
}

async function main() {
  const harness = createHarness();
  harness.evaluate();
  harness.evaluate();

  const tridactyl = await new harness.Extension(stableId).startup();
  assert.equal(tridactyl.isPrivileged, true);
  assert.equal(tridactyl.ignoreQuarantine, true);
  assert.equal(tridactyl.setupPrivilege, false);
  assert(tridactyl.permissions.has("mozillaAddons"));
  assert.deepEqual(harness.cacheClears, [stableId]);

  const origins = tridactyl.allowedOrigins.patterns.map(
    pattern => pattern.pattern
  );
  for (const match of internalMatches) {
    assert(origins.includes(match), `Missing allowed origin ${match}`);
    assert(
      tridactyl.contentScripts[0].matches.includes(match),
      `Missing runtime content-script match ${match}`
    );
    assert(
      tridactyl.manifest.content_scripts[0].matches.includes(match),
      `Missing manifest content-script match ${match}`
    );
    assert(
      tridactyl.manifest.permissions.includes(match),
      `Missing manifest permission ${match}`
    );
  }

  await tridactyl.cachePermissions();
  const cached = harness.cacheWrites[0].value;
  assert(!cached.permissions.has("mozillaAddons"));
  assert(
    !cached.originPermissions.some(pattern => internalMatches.includes(pattern))
  );
  assert(tridactyl.permissions.has("mozillaAddons"));

  const unrelated = await new harness.Extension("other@example.com").startup();
  assert.equal(unrelated.isPrivileged, false);
  assert.equal(unrelated.ignoreQuarantine, false);
  assert(!unrelated.permissions.has("mozillaAddons"));

  const temporary = await new harness.Extension(stableId, {
    temporary: true,
  }).startup();
  assert.equal(temporary.isPrivileged, false);
  assert(!temporary.permissions.has("mozillaAddons"));

  const manifestFailure = new harness.Extension(stableId, {
    loadError: true,
  });
  await assert.rejects(manifestFailure.startup(), /manifest failed/);
  assert.equal(manifestFailure.isPrivileged, false);
  assert.equal(manifestFailure.ignoreQuarantine, false);

  const startupFailure = new harness.Extension(stableId, {
    startupError: true,
  });
  await assert.rejects(startupFailure.startup(), /startup failed/);
  assert.equal(startupFailure.isPrivileged, false);
  assert.equal(startupFailure.ignoreQuarantine, false);
  assert(!startupFailure.permissions.has("mozillaAddons"));

  assert.equal(harness.cacheClears.length, 3);
  assert.deepEqual(harness.errors, []);
  assert(
    harness.logs.some(message =>
      message.includes(`enabled internal-page access for ${stableId}`)
    )
  );
  assert.deepEqual(harness.actorRegistrations, []);

  const noShutdown = createHarness({ keyHandoff: true, shutdownHook: false });
  noShutdown.evaluate();
  const noShutdownTridactyl = await new noShutdown.Extension(stableId).startup();
  assert.equal(noShutdownTridactyl.isPrivileged, true);
  assert.deepEqual(noShutdown.actorRegistrations, []);
  assert(noShutdown.errors.some(error => error.includes("shutdown hooks")));

  const racing = createHarness({ keyHandoff: true });
  racing.evaluate();
  let releaseStartup;
  const startupGate = new Promise(resolve => {
    releaseStartup = resolve;
  });
  const racingTridactyl = new racing.Extension(stableId, { startupGate });
  const interruptedStartup = racingTridactyl.startup();
  await racingTridactyl.shutdown();
  releaseStartup();
  await interruptedStartup;
  assert.deepEqual(racing.actorRegistrations, []);
  await racingTridactyl.startup();
  assert.equal(racing.actorRegistrations.length, 1);

  const handoff = createHarness({ keyHandoff: true });
  handoff.evaluate();
  await new handoff.Extension("other@example.com").startup();
  assert.deepEqual(handoff.actorRegistrations, []);
  const handoffStable = new handoff.Extension(stableId);
  const handoffBeta = new handoff.Extension(
    "tridactyl.vim.betas@cmcaine.co.uk"
  );
  await handoffStable.startup();
  await handoffBeta.startup();
  assert.equal(handoff.actorRegistrations.length, 1);
  assert.equal(
    handoff.actorRegistrations[0].name,
    "TridactylGodmodeKeyHandoff"
  );
  assert.deepEqual(JSON.parse(JSON.stringify(handoff.actorRegistrations[0].options)), {
    child: {
      esModuleURI:
        "resource://tridactyl-godmode/tridactyl-godmode-key-handoff-child.sys.mjs",
    },
    allFrames: false,
    safeForUntrustedWebProcess: true,
  });
  assert.equal(handoff.resourceSubstitutions.length, 1);
  assert.equal(handoff.observers[0].topic, "domwindowopened");

  for (const key of ["Control", "CapsLock", "NumLock", "ScrollLock"]) {
    const modifier = handoff.dispatchChromeKey({ key, code: key });
    assert.equal(modifier.defaultPrevented, false);
  }
  assert.equal(handoff.selectedBrowser.focusCount, 0);
  const relayed = handoff.dispatchChromeKey({ ctrlKey: true });
  assert.equal(relayed.defaultPrevented, true);
  assert.equal(relayed.propagationStopped, true);
  assert.equal(handoff.selectedBrowser.focusCount, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(handoff.actorQueries)), [
    {
      name: "TridactylGodmodeKeyHandoff:Keydown",
      data: {
        key: "j",
        code: "KeyJ",
        repeat: false,
        ctrlKey: true,
        shiftKey: false,
        altKey: false,
        metaKey: false,
      },
    },
  ]);

  handoff.browserWindow.document.activeElement = {};
  const toggleOff = handoff.dispatchChromeKey({
    code: "F12",
    key: "F12",
    ctrlKey: true,
    shiftKey: true,
  });
  assert.equal(toggleOff.defaultPrevented, true);
  const ignored = handoff.dispatchChromeKey({ key: "k", code: "KeyK" });
  assert.equal(ignored.defaultPrevented, false);
  assert.equal(handoff.actorQueries.length, 1);
  handoff.dispatchChromeKey({
    code: "F12",
    key: "F12",
    ctrlKey: true,
    shiftKey: true,
  });
  handoff.dispatchChromeKey({
    code: "F12",
    key: "F12",
    ctrlKey: true,
    shiftKey: true,
    repeat: true,
  });
  const composing = handoff.dispatchChromeKey({ isComposing: true });
  assert.equal(composing.defaultPrevented, false);
  assert.equal(handoff.actorQueries.length, 1);

  const navigation = new Error("navigated");
  navigation.name = "AbortError";
  handoff.actorResults.push(navigation);
  handoff.browserWindow.document.activeElement = {};
  handoff.dispatchChromeKey({ key: "n", code: "KeyN" });
  await Promise.resolve();
  handoff.browserWindow.document.activeElement = {};
  const afterNavigation = handoff.dispatchChromeKey({ key: "m", code: "KeyM" });
  assert.equal(afterNavigation.defaultPrevented, true);
  assert.equal(handoff.actorQueries.length, 3);

  handoff.actorResults.push({ delivered: false });
  handoff.browserWindow.document.activeElement = {};
  handoff.dispatchChromeKey({ key: "x", code: "KeyX" });
  await Promise.resolve();
  handoff.browserWindow.document.activeElement = {};
  assert.equal(handoff.dispatchChromeKey().defaultPrevented, false);
  handoff.dispatchChromeKey({
    code: "F12",
    key: "F12",
    ctrlKey: true,
    shiftKey: true,
  });

  await handoffStable.shutdown();
  await handoffBeta.shutdown();
  handoff.browserWindow.document.activeElement = {};
  assert.equal(handoff.dispatchChromeKey().defaultPrevented, false);

  process.stdout.write("AutoConfig behavior tests passed.\n");
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
