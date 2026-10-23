import { LOAD_TIMEOUT_MS, loadApi, settleWithin, solve, withWatchdog, writeToken } from "./core.js";

const ONLOAD_PREFIX = "hcaptchaLiveViewOnload";
const EVENT = "hcaptcha:execute";

let loading = null;
let attempts = 0;
let lockOwner = null;

function loadHcaptcha(src) {
  loading ??= loadApi({
    src,
    onload: `${ONLOAD_PREFIX}${attempts++}`,
    nonce: document.querySelector("script[nonce]")?.nonce,
  }).catch((error) => {
    loading = null;
    throw error;
  });

  return loading;
}

export const Hcaptcha = {
  mounted() {
    const { sitekey, src } = this.el.dataset;
    this.form = this.el.closest("form");

    if (!this.form) {
      console.error(`hCaptcha: #${this.el.id} must be inside a <form>`);
      return;
    }

    if (this.form.method !== "post") {
      console.error(
        `hCaptcha: the form of #${this.el.id} must use method="post". The hook submits it natively, and a GET puts the fields in the URL.`,
      );
      return;
    }

    this.widget = loadHcaptcha(src)
      .then((hcaptcha) => {
        if (this.gone) return null;
        const { options, watch } = withWatchdog({ sitekey, size: "invisible" });
        return { hcaptcha, id: hcaptcha.render(this.el, options), watch };
      })
      .catch((error) => {
        console.error(error);
        return null;
      });

    this.handleEvent(EVENT, (payload) => {
      if (payload?.id === this.el.id) this.execute();
    });
  },

  destroyed() {
    this.gone = true;
    this.release();
    this.widget?.then((widget) => widget?.hcaptcha.remove?.(widget.id));
  },

  release() {
    window.clearTimeout(this.watch?.timer);
    if (lockOwner === this) lockOwner = null;
  },

  async execute() {
    if (lockOwner) return;
    lockOwner = this;

    const widget = await settleWithin(this.widget, LOAD_TIMEOUT_MS, null);

    let token = "";
    if (widget) {
      this.watch = widget.watch;
      const result = await solve(widget);
      if (result.dismissed) return this.release();
      token = result.token;
    }

    writeToken(this.form, token);
    HTMLFormElement.prototype.submit.call(this.form);
  },
};
