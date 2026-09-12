# DeepSeek Harness — one-click installer for Windows

For people who don't want to touch a terminal and don't have Node.js installed: **double-click one file**, and it downloads Node.js, installs DeepSeek Harness, sets up a launcher with desktop / Start Menu shortcuts, and starts it for you.

> No administrator rights. No Node.js required beforehand. No commands to type.
> Installs into `%LOCALAPPDATA%\DeepSeekHarness` and shows up in *Settings → Apps* for easy uninstallation.

中文说明见 [README.md](README.md)。

---

## What it solves

DeepSeek Harness (`dsh`) is normally installed like this:

```sh
npm install -g @deepseek-ai/dsh
dsh web
```

That's fine if you live in a terminal. This repo removes every step for everyone else:

| Normally you'd have to | The installer does it |
|---|---|
| Install Node.js from nodejs.org | Detects it, or downloads the official **portable** zip into your user folder |
| Run `npm install` somewhere | Runs npm for you, with its cache inside the install folder |
| Remember `dsh web` and the port | Writes a launcher + desktop / Start Menu shortcuts |
| Track upgrades and uninstall manually | Re-run the installer to upgrade; uninstall from *Settings → Apps* |

## Quick start

**Option A — one file**

1. Download [`Install-DeepSeekHarness.cmd`](https://github.com/QDchuan/deepseek-harness-setup/raw/main/Install-DeepSeekHarness.cmd)
2. Double-click it and wait a few minutes (the first run downloads ~200 MB of dependencies)
3. DSH starts and your browser opens automatically

**Option B — the whole repo**

1. **Code → Download ZIP**, extract it anywhere
2. Double-click **`setup.cmd`**

**The one thing you must do yourself:** paste a DeepSeek API key (from <https://platform.deepseek.com>) into the onboarding dialog on first launch. It is stored write-only in the local credential store (`%USERPROFILE%\.dsh`) — never in a config file.

## After installation

| Task | How |
|---|---|
| Start | Double-click **DeepSeek Harness** on the Desktop or in the Start Menu |
| Stop | Close the console window that opened (that window *is* the server) |
| Change port | Edit `$Port` in the launcher script, or `-Port 8081` |
| Change default workspace | Edit the line between the `# >>> 默认工作区` markers in the launcher |
| Upgrade DSH | Re-run the installer |
| Uninstall | Start Menu → **卸载 DeepSeek Harness**, or *Settings → Apps* |

Everything lives in `%LOCALAPPDATA%\DeepSeekHarness` (`app\`, `runtime\node\`, `launcher\`, `cache\`, `logs\`).
Your sessions and credentials live in `%USERPROFILE%\.dsh` and are kept unless you uninstall with `-PurgeData`.
A fresh install (including the portable Node) needs roughly **600 MB**, about 300 MB of which is download cache you can delete at any time.

## Installer options

```powershell
.\src\setup.ps1 -InstallDir D:\DSH -Workspace D:\code -NoLaunch
```

| Option | Meaning |
|---|---|
| `-InstallDir` | Install root, default `%LOCALAPPDATA%\DeepSeekHarness` |
| `-Workspace` | Default working directory for DSH sessions |
| `-NodeVersion` | Node version to download when needed, default `v22.23.2` |
| `-DshSpec` | npm spec, default `@deepseek-ai/dsh@latest` |
| `-Registry` | npm registry; falls back to `registry.npmmirror.com` once on failure |
| `-NodeZip` | Offline: use a local `node-vXX-win-x64.zip` |
| `-ForcePortableNode` | Ignore any system Node, use the bundled portable one |
| `-NoShortcuts`, `-NoLaunch`, `-DryRun` | Skip shortcuts / don't launch / dry run |

## How it works

```
[1/6] Preflight        architecture, disk space, existing install
[2/6] Node.js          reuse an existing Node 22+, else download the portable zip
[3/6] Install DSH      npm install --prefix app @deepseek-ai/dsh@latest
[4/6] Launcher         write launcher\, bake in the default workspace
[5/6] Shortcuts        Desktop + Start Menu + Add/Remove Programs entry
[6/6] Launch           DSH opens the browser itself (token URL -> signed cookie)
```

Design choices worth knowing: no admin rights anywhere (HKCU registry only); downloads fall back through `node → curl.exe → Invoke-WebRequest → BITS`; the npm cache lives inside the install folder so uninstalling leaves nothing behind; re-running is safe and idempotent; and the launcher refuses to start a second instance when the port is already serving DSH.

## Troubleshooting

- **Window flashes and closes / an error appears** — the installer pauses on failure and logs everything to `<InstallDir>\logs\setup-*.log`.
- **Downloads fail** — the bootstrap tries GitHub plus two public mirrors, then prints a manual link. For Node, download the zip yourself and pass `-NodeZip <file>`. Behind a corporate proxy, set `HTTPS_PROXY` first.
- **Browser shows 401 / unauthorized** — open the launch URL that includes `token=`, or just use the launcher.
- **Port already in use** — that's an existing DSH instance; the launcher opens the browser instead of starting a second one. Use `-Port 8081` if something else owns the port.

## License

MIT — see [LICENSE](LICENSE). DeepSeek Harness itself belongs to DeepSeek; this repository only installs it.
