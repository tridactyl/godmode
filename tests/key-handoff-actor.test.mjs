import assert from "node:assert/strict";

globalThis.JSWindowActorChild = class {};
const { TridactylGodmodeKeyHandoffChild } = await import(
  "../autoconfig/tridactyl-godmode-key-handoff-child.sys.mjs"
);

const target = {};
const shadowTarget = {};
target.openOrClosedShadowRoot = { activeElement: shadowTarget };
let dispatched;
const document = {
  activeElement: target,
  documentElement: {},
  defaultView: {
    KeyboardEvent: class {
      constructor(type, options) {
        this.type = type;
        this.options = options;
      }
    },
    windowUtils: {
      dispatchDOMEventViaPresShellForTesting(actualTarget, event) {
        dispatched = { target: actualTarget, event };
        return false;
      },
    },
  },
};
const actor = new TridactylGodmodeKeyHandoffChild();
Object.defineProperty(actor, "document", { value: document });
const data = {
  key: "j",
  code: "KeyJ",
  repeat: false,
  ctrlKey: false,
  shiftKey: false,
  altKey: false,
  metaKey: false,
};

assert.deepEqual(
  await actor.receiveMessage({
    name: "TridactylGodmodeKeyHandoff:Keydown",
    data,
  }),
  { delivered: true, defaultPrevented: true }
);
assert.equal(dispatched.target, shadowTarget);
assert.equal(dispatched.event.type, "keydown");
assert.equal(dispatched.event.options.key, "j");
assert.deepEqual(
  await actor.receiveMessage({ name: "unexpected", data }),
  { delivered: false }
);

process.stdout.write("Key handoff actor tests passed.\n");
