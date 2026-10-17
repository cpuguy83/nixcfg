// From repo root: node --input-type=commonjs - <retained scratch dir> < modules/home/hyprland/tests/osd-ipc-test.js
// Requires installed qs/go and the existing Go module cache. No live devices,
// compositor, audio imports, downloads, file deletion or service restarts.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {spawn, spawnSync} = require("node:child_process");

const scratch = path.resolve(process.argv[2]);
assert.ok(path.basename(scratch).startsWith("nixcfg-osd-correction."));
const fixture = path.resolve("modules/home/hyprland/tests/osd-ipc");
for (const dir of ["runtime", "ipc-config/quickshell/bar", "cache", "mock-bin"])
  fs.mkdirSync(path.join(scratch, dir), {recursive: true, mode: 0o700});
const config = path.join(scratch, "ipc-config/quickshell/bar");
for (const [name, source] of [
  ["shell.qml", path.join(fixture, "shell.qml")],
  ["osd", path.resolve("modules/home/hyprland/quickshell/osd")],
]) {
  if (!fs.existsSync(path.join(config, name)))
    fs.symlinkSync(source, path.join(config, name));
}
const env = {
  ...process.env,
  XDG_RUNTIME_DIR: path.join(scratch, "runtime"),
  XDG_CONFIG_HOME: path.join(scratch, "ipc-config"),
  XDG_CONFIG_DIRS: path.join(scratch, "ipc-config"),
  XDG_CACHE_HOME: path.join(scratch, "cache"),
  QT_QPA_PLATFORM: "offscreen",
  DISPLAY: "", WAYLAND_DISPLAY: "", HYPRLAND_INSTANCE_SIGNATURE: "",
  QS_MIC_MUTE_HELPER: path.join(fixture, "fake-microphone"),
  BRIGHTNESS_OSD_INTEGRATION: "1",
  GOPROXY: "off", GOTOOLCHAIN: "local",
  GOMODCACHE: path.join(process.env.TMPDIR, "brightness-go-mod.13T5oU"),
  GOCACHE: path.join(scratch, "go-cache"),
};
delete env.QS_CONFIG_PATH;
delete env.QS_CONFIG_NAME;
const wpctl = path.join(scratch, "mock-bin/wpctl");
if (!fs.existsSync(wpctl))
  fs.symlinkSync(path.join(fixture, "fake-wpctl"), wpctl);
for (const [args, failOperation, status, calls] of [
  [["42"], "", 0, [["set-mute", "42", "toggle"], ["get-volume", "42"]]],
  [["42"], "set-mute", 7, [["set-mute", "42", "toggle"]]],
  [["42"], "get-volume", 7, [["set-mute", "42", "toggle"], ["get-volume", "42"]]],
  [["@DEFAULT_AUDIO_SINK@"], "", 2, []],
  [["42; false"], "", 2, []],
  [[], "", 2, []],
]) {
  const result = spawnSync("bash", ["-e", "-u", "-o", "pipefail",
    "modules/home/hyprland/mic-mute-feedback.sh", ...args], {
    env: {...env, PATH: path.join(scratch, "mock-bin") + ":" + env.PATH, OSD_FAIL_OPERATION: failOperation},
    encoding: "utf8", timeout: 2000,
  });
  assert.equal(result.status, status, result.stderr);
  const observed = result.stderr.split("\n").filter(line => line.startsWith("[")).map(line => JSON.parse(line));
  assert.deepEqual(observed, calls);
  assert.equal(result.stdout, status === 0 ? "Volume: 0.75 [MUTED]\n" : "");
}
console.log("PASS: helper exact source argv, invalid selectors, set/get failures");
const shell = spawn("qs", ["-c", "bar"], {env, stdio: ["ignore", "pipe", "pipe"]});
let logs = "";
shell.stdout.on("data", data => { logs += data; });
shell.stderr.on("data", data => { logs += data; });
const exited = new Promise(resolve => shell.once("exit", resolve));
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
function call(...args) {
  const result = spawnSync("qs", ["-c", "bar", "ipc", "call", ...args], {env, encoding: "utf8", timeout: 2000});
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  return result.stdout.trim();
}
async function waitEvents(count) {
  for (let i = 0; i < 70; ++i) {
    const events = JSON.parse(call("probe", "events"));
    if (events.length === count)
      return events;
    await sleep(50);
  }
  throw new Error(`did not receive ${count} microphone events`);
}
(async () => {
  try {
    let ready = false;
    for (let i = 0; i < 60; ++i) {
      const result = spawnSync("qs", ["-c", "bar", "ipc", "show"], {env, encoding: "utf8", timeout: 1000});
      if (result.status === 0 && result.stdout.includes("brightness")) {
        console.log(result.stdout.trim());
        ready = true;
        break;
      }
      await sleep(50);
    }
    assert.ok(ready, logs);
    const go = spawnSync("go", ["test", "-race", "-count=1", "-run", "TestOSDProductionEndpoint", "-v", "./..."], {
      env, cwd: path.resolve("modules/home/brightnessd"), encoding: "utf8", timeout: 120000,
    });
    console.log(go.stdout);
    assert.equal(go.status, 0, go.stderr || go.error?.message);
    call("probe", "microphone", "42", "3");
    const successes = await waitEvents(3);
    for (const event of successes) {
      assert.equal(event.value, 75);
      assert.equal(event.muted, true);
      assert.equal(event.text, "");
    }
    call("probe", "microphone", "43", "2");
    const failures = await waitEvents(5);
    assert.match(failures[3].text, /test helper refused source/);
    assert.equal(failures[4].value, -1);
    call("probe", "microphone", "44", "1");
    assert.match((await waitEvents(6))[5].text, /Invalid wpctl/);
    call("probe", "missingHelper");
    call("probe", "microphone", "42", "2");
    const missing = await waitEvents(8);
    assert.match(missing[6].text, /failed to start/);
    assert.match(missing[7].text, /failed to start/);
    console.log("PASS: production brightness IPC and queued microphone Process success/failure/start failure");
  } finally {
    shell.kill("SIGTERM");
    await exited;
    console.log(logs);
  }
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
