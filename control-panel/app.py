import re
import subprocess
from pathlib import Path

import webview

BASE = Path(__file__).resolve().parent.parent
CONF = BASE / "settings.conf"
LOG = Path.home() / "Library/Logs/vg32vq1b-restore.log"
ENV = {
    "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME": str(Path.home()),
}

HTML = """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>VG32VQ1B</title>
<style>__CSS__</style>
<style>
.controls { display: flex; gap: var(--space-sm); align-items: center; flex-wrap: wrap; }
.controls + .controls { margin-top: var(--space-md); }
.number-input { width: 90px; }
.note { font-size: 12px; color: var(--medium-gray); margin-top: var(--space-sm); }
.output {
    margin-top: var(--space-xl);
    padding: var(--space-md);
    background: var(--off-white);
    border: 1px solid var(--light-gray);
    font-family: var(--font-mono);
    font-size: 11px;
    white-space: pre-wrap;
    max-height: 360px;
    overflow: auto;
}
button:disabled { opacity: 0.4; cursor: default; }
button:disabled:hover { background: var(--white); color: var(--black); }
button.btn-primary:disabled:hover { background: var(--black); color: var(--white); }
</style>
</head>
<body>
<nav class="nav">
    <div class="nav-brand">
        <span class="nav-title">VG32VQ1B</span>
        <span class="nav-subtitle" id="subtitle"></span>
    </div>
    <div>
        <button class="btn" id="verify">Verify</button>
    </div>
</nav>
<main class="main">
    <div class="stats-grid">
        <div class="stat-card"><div class="stat-value" id="resolution">-</div><div class="stat-label">Resolution</div></div>
        <div class="stat-card"><div class="stat-value" id="refresh">-</div><div class="stat-label">Refresh</div></div>
        <div class="stat-card"><div class="stat-value" id="brightness">-</div><div class="stat-label">Brightness</div></div>
        <div class="stat-card"><div class="stat-value" id="smoothing">-</div><div class="stat-label">Font smoothing</div></div>
    </div>

    <section class="section">
        <div class="section-header">
            <div class="section-title">Brightness</div>
            <div class="section-desc">DDC/CI brightness, 0 to 100.</div>
        </div>
        <div class="controls">
            <input class="filter-input number-input" id="brightness-input" type="number" min="0" max="100" step="1">
            <button class="btn" id="set-brightness">Set brightness</button>
        </div>
    </section>

    <section class="section">
        <div class="section-header">
            <div class="section-title">Font smoothing</div>
            <div class="section-desc">0 is crispest. Higher values are softer and bolder. Changes take effect after a logout and login.</div>
        </div>
        <div class="controls" id="smoothing-buttons"></div>
    </section>

    <section class="section">
        <div class="section-header">
            <div class="section-title">Actions</div>
            <div class="section-desc">Apply re-applies settings.conf and reinstalls the login agent. Log shows recent agent activity.</div>
        </div>
        <div class="controls">
            <button class="btn btn-primary" id="apply">Apply now</button>
            <button class="btn" id="log">Show log</button>
        </div>
    </section>

    <pre class="output" id="out">Ready.</pre>
</main>
<script>
const $ = (id) => document.getElementById(id);
const out = $("out");
const SMOOTHING_LABELS = ["0 off", "1 light", "2 medium", "3 strong"];

function renderState(s) {
    $("subtitle").textContent = s.name + " · " + s.width + "×" + s.height + " @ " + s.refresh + " Hz";
    $("resolution").textContent = s.height + "p";
    $("refresh").textContent = s.refresh + " Hz";
    $("brightness").textContent = s.brightness;
    $("smoothing").textContent = s.smoothing;
    $("brightness-input").value = s.brightness;

    const box = $("smoothing-buttons");
    box.innerHTML = "";
    SMOOTHING_LABELS.forEach((label, i) => {
        const b = document.createElement("button");
        b.className = "btn" + (i === s.smoothing ? " btn-primary" : "");
        b.textContent = label;
        b.onclick = () => run("set_smoothing", i);
        box.appendChild(b);
    });
}

function setBusy(on) {
    document.querySelectorAll("button").forEach((b) => (b.disabled = on));
}

async function run(name, ...args) {
    setBusy(true);
    out.textContent = "working...";
    try {
        const r = await pywebview.api[name](...args);
        out.textContent = r.output;
        if (r.state) renderState(r.state);
    } catch (err) {
        out.textContent = String(err);
    } finally {
        setBusy(false);
    }
}

window.addEventListener("pywebviewready", async () => {
    renderState(await pywebview.api.state());
});

$("verify").onclick = () => run("verify");
$("apply").onclick = () => run("apply");
$("log").onclick = () => run("log");
$("set-brightness").onclick = () => run("set_brightness", $("brightness-input").value);
</script>
</body>
</html>
"""


def read_conf():
    values = {}
    for line in CONF.read_text().splitlines():
        m = re.match(r'^([A-Z_]+)="?([^"#\s]*)"?\s*(#.*)?$', line.strip())
        if m:
            values[m.group(1)] = m.group(2)
    return values


def write_conf(key, value):
    text = CONF.read_text()
    text, count = re.subn(rf"^{key}=.*$", f"{key}={value}", text, flags=re.M)
    if count != 1:
        raise RuntimeError(f"{key} not found exactly once in settings.conf")
    CONF.write_text(text)


def state():
    v = read_conf()
    return {
        "name": v["DISPLAY_NAME"],
        "width": int(v["DISPLAY_WIDTH"]),
        "height": int(v["DISPLAY_HEIGHT"]),
        "refresh": int(v["DISPLAY_REFRESH"]),
        "brightness": int(v["BRIGHTNESS"]),
        "smoothing": int(v["FONT_SMOOTHING"]),
    }


def zsh(script):
    try:
        p = subprocess.run(
            ["/bin/zsh", str(BASE / script)],
            cwd=BASE, capture_output=True, text=True, timeout=180, env=ENV,
        )
        return (p.stdout + p.stderr).strip() or f"{script} finished with no output"
    except subprocess.TimeoutExpired:
        return f"{script} timed out"


class Api:
    def state(self):
        return state()

    def verify(self):
        return {"output": zsh("verify.sh"), "state": state()}

    def apply(self):
        return {"output": zsh("install.sh"), "state": state()}

    def set_brightness(self, value):
        try:
            n = int(value)
        except (TypeError, ValueError):
            return {"output": "brightness must be a whole number", "state": state()}
        if not 0 <= n <= 100:
            return {"output": "brightness must be between 0 and 100", "state": state()}
        write_conf("BRIGHTNESS", n)
        return {"output": "saved, applying...\n" + zsh("install.sh"), "state": state()}

    def set_smoothing(self, value):
        n = int(value)
        if n not in (0, 1, 2, 3):
            return {"output": "smoothing must be 0 to 3", "state": state()}
        write_conf("FONT_SMOOTHING", n)
        return {
            "output": "saved, applying...\n" + zsh("install.sh")
            + "\nLog out and back in for font smoothing to take effect.",
            "state": state(),
        }

    def log(self):
        if not LOG.exists():
            return {"output": "no log yet"}
        lines = LOG.read_text(errors="replace").splitlines()[-40:]
        return {"output": "\n".join(lines)}


def main():
    css = (Path(__file__).resolve().parent / "styles.css").read_text(encoding="utf-8")
    webview.create_window(
        "VG32VQ1B",
        html=HTML.replace("__CSS__", css),
        js_api=Api(),
        width=900,
        height=820,
    )
    webview.start()


if __name__ == "__main__":
    main()
