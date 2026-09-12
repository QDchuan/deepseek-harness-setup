# DeepSeek Harness 一键安装器（Windows）

给**不想碰命令行、机器上也没装开发环境**的人用的安装程序：双击一个文件，剩下的它全干了 —— 下载 Node.js、安装 DeepSeek Harness、配好启动器、建好桌面图标，然后直接帮你启动。

> 不需要管理员权限，不需要提前装 Node.js，不需要敲任何命令。
> 安装位置默认在 `%LOCALAPPDATA%\DeepSeekHarness`，随时可以从「设置 → 应用」里卸载。
>
> English: [README.en.md](README.en.md)

---

## 这是什么

[DeepSeek Harness](https://www.npmjs.com/package/@deepseek-ai/dsh)（简称 DSH）是一个跑在本机的 agent 工作台，用浏览器当界面：

```sh
npm install -g @deepseek-ai/dsh
dsh web
```

对熟悉命令行的人来说这没什么；对不熟悉的人来说，光是「先装 Node.js」这一步就能卡住。本仓库就是来消掉这些步骤的：

| 平时要做的 | 这个安装器 |
|---|---|
| 去 nodejs.org 下载安装 Node.js | 自动检测；没有就下载官方便携版解压到用户目录 |
| 打开终端敲 `npm install` | 自动用 npm 装好，缓存也放在自己的目录里 |
| 记住 `dsh web` 这个命令和端口 | 生成启动器 + 桌面 / 开始菜单快捷方式 |
| 手动管理升级、卸载 | 重跑安装即升级；「设置 → 应用」里可卸载 |

---

## 快速开始

### 方式 A：只下载一个文件（推荐）

1. 下载 [`Install-DeepSeekHarness.cmd`](https://github.com/QDchuan/deepseek-harness-setup/raw/main/Install-DeepSeekHarness.cmd)（点开后按 `Ctrl+S`，或右键「链接另存为」）
2. **双击它**，等几分钟（第一次要下载约 200MB 依赖）
3. 装完会自动启动，浏览器也会自动打开 DSH 界面

> 有些浏览器/杀毒软件会对 `.cmd` 文件报警，这是因为它确实会下载并安装东西。脚本全文可读： [`Install-DeepSeekHarness.cmd`](Install-DeepSeekHarness.cmd) 只是把仓库 zip 下下来，真正的逻辑在 [`src/setup.ps1`](src/setup.ps1)。

### 方式 B：下载整个仓库

1. 点 **Code → Download ZIP**，解压到任意位置
2. 双击文件夹里的 **`setup.cmd`**

### 首次启动后要做的唯一一件事

DSH 需要一个 DeepSeek API 密钥才能对话：

1. 到 <https://platform.deepseek.com> 申请一个 API Key
2. 首次启动 DSH 时它会弹出引导，把密钥粘进去即可

密钥是以**只写**方式存进本机凭据库的（`%USERPROFILE%\.dsh\.credentials.yaml` 里的引用），不会写进配置文件，也不会上传到别处。

---

## 装完之后

| 想干什么 | 怎么做 |
|---|---|
| 启动 | 双击桌面或开始菜单里的 **DeepSeek Harness** |
| 停止 | 关掉启动后的那个**控制台窗口**（它就是 DSH 本体） |
| 继续以前的会话 | 直接启动即可，会话记录在 `%USERPROFILE%\.dsh\sessions` |
| 换端口 | 改启动器脚本里的 `$Port`，或命令行 `Start-DeepSeekHarness.ps1 -Port 8081` |
| 换默认工作目录 | 改启动器脚本里 `# >>> 默认工作区` 标记之间那一行 |
| 升级 DSH | 重跑一次安装（已装的部分会复用，只更新 dsh） |
| 卸载 | 开始菜单里的 **卸载 DeepSeek Harness**，或「设置 → 应用」 |

已经在用 DSH 的人（比如一直用 `npx @deepseek-ai/dsh web` 的）也可以装：安装器会把 dsh 装到自己的目录，启动器优先用它，npx 缓存那份不受影响。

---

## 安装到哪里去了

默认安装根目录：`%LOCALAPPDATA%\DeepSeekHarness`

| 路径 | 内容 | 能不能删 |
|---|---|---|
| `app\` | DeepSeek Harness 本体（npm 装的依赖） | 卸载时删 |
| `runtime\node\` | 便携版 Node.js（仅当机器上没有 Node 22+ 时） | 卸载时删 |
| `launcher\` | 启动器脚本和图标 | 卸载时删 |
| `cache\` | 下载缓存（Node 压缩包、npm 缓存） | 可以随时删，只是下次升级要重新下载 |
| `logs\` | 安装日志，出问题时要看的就是它 | 可以删 |
| `dsh-setup.json` | 安装清单，启动器据此定位 Node 和 dsh | 别删 |
| `卸载.cmd` | 卸载入口 | — |

两点说明：

- **全部在你的用户目录里**：不写 `Program Files`、不需要管理员。注册表只加了一项 `HKCU\...\Uninstall\DeepSeekHarness`，就是为了让「设置 → 应用」里能卸载。
- **会话与密钥不在安装目录里**，而在 `%USERPROFILE%\.dsh`。卸载默认**保留**它；确实想清空就运行 `uninstall.ps1 -PurgeData`。

磁盘占用（实测，含便携 Node 的全新安装）：**约 600MB**，其中下载缓存约 300MB。空间紧张的话删掉 `cache\` 能省下这部分（下次升级会重新下载）。

---

## 高级用法

安装器本身是一个 PowerShell 脚本，所有参数都可以显式指定：

```powershell
# 装到 D 盘，默认工作目录设为 D:\code，装完先不启动
.\src\setup.ps1 -InstallDir D:\DSH -Workspace D:\code -NoLaunch
```

| 参数 | 作用 |
|---|---|
| `-InstallDir <路径>` | 安装根目录，默认 `%LOCALAPPDATA%\DeepSeekHarness` |
| `-Workspace <路径>` | DSH 会话的默认工作目录，会写进启动器 |
| `-NodeVersion <vX.Y.Z>` | 没有可用 Node 时下载哪个版本，默认 `v22.23.2`（Node 22 LTS） |
| `-DshSpec <包@版本>` | 装哪个版本，默认 `@deepseek-ai/dsh@latest` |
| `-Registry <npm 源>` | 指定 npm 源；不指定就用本机配置，失败时自动换 `registry.npmmirror.com` 重试一次 |
| `-NodeZip <文件>` | 离线安装：直接用本机已有的 `node-vXX-win-x64.zip`，不联网下载 |
| `-ForcePortableNode` | 忽略系统里的 Node，强制用安装目录里的便携版 |
| `-NoShortcuts` | 不创建快捷方式 |
| `-NoLaunch` | 装完不启动 |
| `-DryRun` | 只检查环境、报告将要做什么，不下载不写入 |

启动器（`<安装目录>\launcher\Start-DeepSeekHarness.ps1`）：

```powershell
.\Start-DeepSeekHarness.ps1 -Diagnose          # 只检查：Node 在哪、dsh 在哪、端口占用没
.\Start-DeepSeekHarness.ps1 -Port 8081         # 换端口启动
.\Start-DeepSeekHarness.ps1 -NoBrowser         # 只起服务，不开浏览器
```

---

## 安装器做了什么

```
[1/6] 检查环境        系统架构 / 磁盘空间 / 是否已装过
[2/6] 准备 Node.js    已有 22+ 就复用；否则下载官方便携版解压到 runtime\node
[3/6] 安装 DSH        npm install --prefix app @deepseek-ai/dsh@latest
[4/6] 安装启动器      写入 launcher\，并把默认工作目录写进去
[5/6] 创建快捷方式    桌面 + 开始菜单 + 应用列表卸载项
[6/6] 启动           浏览器自动打开 DSH 界面
```

几个刻意的设计决定：

- **不用管理员权限**：宁可下载便携版 Node，也不去装 MSI 或改系统目录。
- **下载有多条退路**：优先借用机器上已有的 Node 下载，其次 `curl.exe`（Win10 1803+ 自带），再退到 PowerShell 的 `Invoke-WebRequest` / BITS。
- **npm 缓存放进安装目录**：不污染全局缓存，也不会因为全局缓存权限坏掉而装不上，卸载时一起删干净。
- **重复运行安全**：已装的 Node 和依赖会复用，只把 dsh 升到最新。
- **启动器不认识第二个实例**：端口上已经有 DSH 在跑时，只打开浏览器，不会起第二个进程去抢同一个会话库。

---

## 常见问题

**双击后窗口一闪而过 / 报错了？**
安装器出错时会自己停住并打印原因，同时把过程写进 `<安装目录>\logs\setup-*.log`。把那个文件的内容发出来即可定位。

**下载不下来（GitHub 打不开、npm 很慢）？**
- `Install-DeepSeekHarness.cmd` 会依次尝试 GitHub 官方源和两个公共镜像；都失败时它会打印手动下载链接。
- 也可以自己在浏览器里下载 zip 解压后跑 `setup.cmd`，绕开脚本下载这一步。
- Node 下载失败时，手动下载 <https://nodejs.org/dist/v22.23.2/node-v22.23.2-win-x64.zip>（或 [国内镜像](https://registry.npmmirror.com/-/binary/node/v22.23.2/node-v22.23.2-win-x64.zip)），然后：
  ```powershell
  .\src\setup.ps1 -NodeZip "路径\node-v22.23.2-win-x64.zip"
  ```
- 公司网络要走代理：先设环境变量 `HTTPS_PROXY=http://代理地址:端口`，再运行安装器（npm 也认这个变量）。

**浏览器打开显示「未授权 / 401」？**
DSH 的登录凭据是启动时一次性发给浏览器的。用启动器正常启动不会遇到；如果你是手动打开 `http://127.0.0.1:3080`，请改用启动时打印的、带 `token=` 的那条 URL。

**提示端口被占用？**
说明已经有一个 DSH 在跑，启动器会直接开浏览器而不是再起一个。占用者是别的程序时，用 `-Port 8081` 换个端口。

**杀毒软件报警？**
`Install-DeepSeekHarness.cmd` / `setup.cmd` 会下载并安装软件，被拦是正常的。所有脚本都是纯文本，可以逐行审阅；也可以在拦截时选择「允许」。

**DSH 是什么、安全吗？**
它是跑在你本机的程序，只监听 `127.0.0.1`（不接受局域网访问），会话记录、密钥都只存在本机。模型调用走你自己填的 DeepSeek API 密钥。

---

## 仓库结构

```
Install-DeepSeekHarness.cmd   单文件引导器（从 GitHub 抓本仓库并运行安装器）
setup.cmd                     解压后直接双击的入口
src\setup.ps1                 安装器主体
src\uninstall.ps1             卸载器
src\launcher\                 启动器（Start-DeepSeekHarness.ps1 / start-dsh.cmd / dsh.ico）
src\launcher\tools\           图标生成脚本与图标源文件（从前端 favicon.svg 现场生成 .ico）
LICENSE                       MIT
```

## 许可

MIT，见 [LICENSE](LICENSE)。DeepSeek Harness 本身是 DeepSeek 的项目，本仓库只是它的安装器。
