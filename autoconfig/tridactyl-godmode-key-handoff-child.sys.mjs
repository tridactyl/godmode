const MESSAGE_NAME = "TridactylGodmodeKeyHandoff:Keydown";

export class TridactylGodmodeKeyHandoffChild extends JSWindowActorChild {
  async receiveMessage({ name, data }) {
    if (
      name !== MESSAGE_NAME ||
      typeof data?.key !== "string" ||
      typeof data.code !== "string"
    ) {
      return { delivered: false };
    }

    const document = this.document;
    const window = document?.defaultView;
    let target = document?.activeElement || document?.documentElement;
    if (!window || !target) {
      return { delivered: false };
    }
    while (target.openOrClosedShadowRoot?.activeElement) {
      target = target.openOrClosedShadowRoot.activeElement;
    }

    const event = new window.KeyboardEvent("keydown", {
      bubbles: true,
      cancelable: true,
      composed: true,
      view: window,
      key: data.key,
      code: data.code,
      repeat: data.repeat,
      ctrlKey: data.ctrlKey,
      shiftKey: data.shiftKey,
      altKey: data.altKey,
      metaKey: data.metaKey,
    });
    const notCanceled =
      window.windowUtils.dispatchDOMEventViaPresShellForTesting(target, event);

    return { delivered: true, defaultPrevented: !notCanceled };
  }
}
