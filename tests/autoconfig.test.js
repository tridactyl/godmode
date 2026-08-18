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

function createHarness({ firefoxVersion = "999.0a1" } = {}) {
  const cacheClears = [];
  const cacheWrites = [];
  const errors = [];
  const logs = [];

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
        startupError = false,
        temporary = false,
        type = "extension",
      } = {}
    ) {
      this.id = id;
      this.addonData = { type };
      this.loadError = loadError;
      this.startupError = startupError;
      this.temporarilyInstalled = temporary;
      this.ignoreQuarantine = false;
      this.isPrivileged = false;
      this.setupPrivilege = null;
    }

    async startup() {
      await this.loadManifest();
      this._setupStartupPermissions();
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

    cachePermissions() {
      return StartupCache.manifests.set([this.id, "1", "en-US"], {
        permissions: this.permissions,
        originPermissions: this.allowedOrigins.patterns.map(
          pattern => pattern.pattern
        ),
      });
    }
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
        },
        Components: {
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
    cacheClears,
    cacheWrites,
    errors,
    evaluate,
    Extension,
    logs,
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

  process.stdout.write("AutoConfig behavior tests passed.\n");
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
