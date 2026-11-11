# Herdr Island

Herdr Island 把 Herdr 里的 agent 状态收进 macOS 摄像头刘海的左右两耳，并在刘海下挂一滴水。收起时它只占菜单栏高度，不改变刘海的形状。把水滴拖到桌面任意位置，共享投递框就落在那里：选收件人（默认主 agent）、模型、目录、可选隔离 worktree，添加最多 8 个附件，输入任务后直接在 Herdr 里创建 workspace、启动 agent 并提交；主 agent 忙时排队一条，blocked 时拒绝发送。按住 Option 拖动同一滴水，则改为锁定指针下的窗口，发送时自动带上选中文本、网页地址、文档路径和一张该窗口的截图。

产品页在 <https://arronkler.github.io/herdr-island/>，英文为默认版本，中文在 <https://arronkler.github.io/herdr-island/zh/>；源码在 `site/`，由 GitHub Pages 部署，站点会跟随系统语言并记住手动切换。

## 界面

- **环境条**。左右耳位于刘海两侧，左侧显示待处理或安静，右侧显示运行、完成或空闲。刘海下方 32pt 的透明延伸区只画水滴，不遮挡桌面点击；鼠标移到水滴或两耳上才接收事件。
- **轻提示**。完成一轮时先出现 400 × 248 的 peek，列出一条完成结果；鼠标移入或点击后进入完整 deck。
- **声音提醒**。完成一轮或需要你处理时，可以用 macOS 内置提示音提醒。两类事件各自选择音色，默认关闭；设置页里选中即可试听。
- **任务台**。宽度固定 560，高度随可见行数在 440 到 640 之间自适应。顶部是待处理、运行中、已完成、全部四个筛选，`/` 进入搜索。每一行带对应 agent 的图标和状态点；运行中的行显示最近一行终端输出，可以排队下一条消息，等待你处理的行有独立的操作区。
- **详情**。660 × 640。直接连接当前 agent 的真实终端，支持键盘、中文输入、粘贴、ANSI 色彩、文本选择和历史滚动；也可在 Herdr 打开同一会话。
- **新任务**。Control + Option + N 唤起 420 × 196 的输入框，沿用当前 Herdr pane 的目录和上次选择的模型，可选 worktree。
- **窗口任务**。锁定窗口后出现，默认 380 × 510，遇到阻塞、权限缺口或错误提示时按需增高。使用共享投递框：收件人默认主 agent，可切换或新建；自动读取选中文本、网页地址和文档路径，可添加附件，发送时再截取一张窗口 PNG。
- **水滴输入框**。拖动水滴时，水滴和刘海之间先拉出液态颈部；超过 96pt 后完全脱离，只剩一个小水珠，不保留连线。松手的位置出现涟漪，共享投递框锚定在落点上方。输入框支持收件人、多行任务、模型、目录、worktree 和附件；收件人按 pane + workspace + agent kind 识别主 agent。
- Option + 拖动水滴是窗口锁定，不创建任务。锁定后窗口和岛之间显示一条跟随窗口移动的细线。

界面使用统一的 10 / 11.5 / 12.5 / 13 / 13.5 / 15 / 17pt 字号阶梯，20pt 水平内边距，deck 与 detail 的顶部留出 62pt 的 crown（含刘海）。

所有 agent 行都使用自己的图标和状态点，图标按 kind 区分 Claude、Codex、Cursor、Gemini、Copilot 等。界面文案为中文。

系统开启 Reduce Motion 时，面板改为瞬时切换，状态点不再脉冲，水滴停止呼吸，落点涟漪只淡出。拖拽本身仍然跟随指针，因为它不是补间动画。

## 操作

| 操作 | 作用 |
| --- | --- |
| Control + Option + H | 打开或收起岛 |
| Control + Option + N | 新任务输入框 |
| 拖动水滴 | 在落点创建新任务 |
| Option + 拖动水滴 | 锁定指针下的窗口 |
| `/` | 打开任务台并搜索 |
| `R` | 聚焦回复输入框；blocked 时不生效 |
| `S` | 稍后处理选中的 agent |
| `↑` `↓` | 移动选择 |
| `Return` | 打开选中 agent 的详情 |
| `Command + Return` | 发送或排队消息，或在新任务、水滴输入框、窗口任务里提交 |
| `Esc` | 逐层退出：先收输入框，再退出搜索、详情，最后收起面板；终端聚焦时交给终端程序 |
| `Command + W` | 终端聚焦时从详情返回任务台 |

## Herdr 能力

- **状态同步**。通过 Unix socket 直接读取 `agent.list` / `pane.list`，避免每次查询启动 CLI 和创建临时文件。每 1.5 秒采样，状态事件即时更新。直接读取不兼容或断线时回退 CLI，并冷却 10 秒后再尝试 socket；创建和提交等写操作不走自动重试。
- **交互终端**。详情通过 Herdr 的单 pane socket 协议连接现有会话，使用 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm/tree/v1.20.0) 原生渲染连续 ANSI 帧，尺寸直接同步给该 pane。支持中文输入、文本选择、`⌘C / ⌘V`、文件和图片粘贴或拖入；图片转成当前任务可读取的本地 PNG 路径，不追加 Enter，关闭详情后仍保留。程序启用鼠标报告时，点击、拖动、右键和滚轮转给程序；按住 Shift 拖动可选择文字。`⌘W` 返回任务台；Esc、方向键、Tab 和 Ctrl+C 交给终端。滚轮读取 Herdr 的主屏历史，Page Up / Down 交给终端程序。文字、粘贴和特殊按键按顺序等待 socket API 确认，特殊按键由 Herdr 按实际程序模式编码；协议 22 的鼠标通道没有处理确认，鼠标与键盘跨通道的严格排序仍不保证。关闭详情只释放连接，不停止 agent。断线后手动重连，输入不会自动重发；其他客户端占用时可以显式接管。
- **队列预览**。任务台仍通过 `herdr agent read --source recent-unwrapped` 读取最近输出；交互终端打开期间停止该 pane 的预览读取和排队消息投递，其他任务状态变化不会抢走选中会话。
- **标签与目录**。读取 `state_labels`、`name` 和 `foreground_cwd`，优先用前台目录作为项目名。标签会显示在详情里，也参与搜索。
- **消息发送**。任务台通过 `herdr agent prompt` 提交；运行中的 agent 可以排队一条消息，本轮结束且未打开交互终端时自动投递，排队项可以取消；发送失败后保留正文并暂停，先检查终端，再在任务台手动重试。详情终端中的输入则按你实际键入的内容发送，不追加 Enter。
- **新任务**。显示准备目录、启动模型、提交并确认三个真实阶段，以及等待耗时。Claude、Cursor 的单行首条任务通过 `herdr agent start -- -- <任务>` 原生传入，避免输入框挂载前收到粘贴和回车；Codex 和多行任务先确认真实空输入框，再通过 `herdr agent prompt --wait` 提交。其他模型沿用 Herdr 的就绪和提交确认。确认后自动选中新 pane，轮询和 socket 接管状态。开启隔离时改用 `herdr worktree create --cwd ... --branch ... --label ... --no-focus`。
- **启动确认**。在模型启动前订阅新 pane，复用状态事件和已有采样确认 working / blocked / done，不再为创建任务另外启动每 400 毫秒一次的 CLI 查询。事件断开仍由周期采样兜底。减少的是应用的查询开销和确认延迟，模型冷启动仍取决于本机模型客户端。
- **窗口截图**。ScreenCaptureKit 在发送时截取锁定窗口一张 PNG。prompt 里包含窗口标题、捕获时间、窗口尺寸、网页地址、文档路径、选中文本、附件绝对路径、截图绝对路径和任务；自动上下文来自辅助功能，缺失时留空。附件最多 8 个，只传路径，不复制文件。

新任务的 worktree 不会带 `--trust-repository`。仓库是否可信由你在 Herdr 里确认。

## 安全边界

blocked 需要人亲自处理。可以直接在详情的交互终端中阅读、选择并确认，也可在 Herdr 打开同一会话。Island 不会自动批准；自动派发仍通过会拒绝 blocked agent 的 `herdr agent prompt`。终端只转发你主动输入的按键和粘贴内容。Claude、Cursor 的单行首条任务作为新进程的启动参数传入，不模拟确认按键。Cursor 的工作区信任弹窗和 Codex 的用量/模型选择弹窗必须由你亲自处理；自动消息发送前也会检查这些弹窗。

新任务只向刚创建的 workspace 和 agent 提交内容，不会向已有 blocked agent 发送。新 agent 启动后如果进入 blocked，仍然需要你亲自处理。

窗口截图只在明确按下发送时发生，不会在锁定期间持续截屏。截图保存在本机 `~/Library/Application Support/HerdrIsland/Captures/`，prompt 里是截图绝对路径、窗口元数据、自动上下文和附件路径；截图和文件都不会被复制或上传。

## 环境

- macOS 14 或更新版本
- Herdr 0.9.5（交互终端当前适配单 pane 二进制协议 22；其他协议版本会明确提示不兼容）。默认二进制路径 `~/.local/bin/herdr`，socket 路径 `~/.config/herdr/herdr.sock`
- Ghostty。精确跳转需要它；没有 Ghostty 时仍会聚焦 Herdr pane
- Automation 权限。首次 Jump 时 macOS 会询问是否可以控制 Ghostty
- Screen Recording 权限。窗口锁定功能需要它在发送时截图；授权后可能需要重启 app
- 辅助功能权限。窗口锁定时读取选中文本、网页地址和文档路径；不授权则这些字段为空，不影响发送

## 安装

预编译版本发布在 [Releases](https://github.com/arronKler/herdr-island/releases)，为 Apple Silicon 构建，要求 macOS 14 或更新版本。

1. 下载 `HerdrIsland-<版本>.zip` 和 `HerdrIsland-<版本>.zip.sha256`，放在同一目录后校验：

   ```bash
   shasum -a 256 -c HerdrIsland-<版本>.zip.sha256
   ```

2. 解压，把 `HerdrIsland.app` 拖进 `/Applications`。
3. 首次打开会被 Gatekeeper 拦截。应用只有 ad-hoc 签名，没有经过 Apple 公证，所以系统不会显示“已识别的开发者”。到 **系统设置 → 隐私与安全性**，在“安全性”一栏点 **仍要打开**，再输入管理员密码。也可以在终端去掉下载隔离标记后正常打开：

   ```bash
   xattr -dr com.apple.quarantine /Applications/HerdrIsland.app
   ```

   每个新下载的版本可能都需要再放行一次。不要用 `sudo spctl --master-disable` 全局关闭 Gatekeeper。
4. 按提示授予 Screen Recording、Automation 和辅助功能权限。辅助功能只用于读取锁定窗口的上下文，不授权也不影响发送。替换应用后这些权限可能再次询问。

从源码构建的 app 没有 quarantine 标记，不需要上面的放行步骤。

## 构建

```bash
swift build
Scripts/make-app.sh
open build/HerdrIsland.app
```

`Scripts/make-app.sh` 执行 release 构建，组装 `build/HerdrIsland.app`，然后做 ad-hoc 签名。应用是 `LSUIElement`，不会出现在 Dock。

发版用 `Scripts/make-release.sh`：

```bash
Scripts/make-release.sh 0.1.0
```

脚本把版本写入 `Info.plist`，重新做 ad-hoc 签名，在 `build/release/` 生成 `HerdrIsland-<版本>.zip` 和同名的 `.sha256`。推送 `v<版本>` 标签会触发 `.github/workflows/release.yml`，执行同一脚本并创建 GitHub Release；带 `-` 的版本（如 `0.1.0-beta.1`）标记为 prerelease。

站点由 `.github/workflows/pages.yml` 发布。推送 `site/` 下的改动后，工作流先运行 `python3 Scripts/check-site.py site` 检查本地链接与页内锚点，再把 `site/` 上传到 GitHub Pages。首次部署前，在仓库的 Settings → Pages 把 Source 设为 GitHub Actions。本地预览：

```bash
python3 -m http.server --directory site 8000
```

应用图标采用「负形之岛」：冰蓝色底板上的刘海轮廓，用水滴负形留出开口。[SVG 源文件](Sources/IslandApp/Resources/Brand/HerdrIsland.svg) 是唯一手工维护的图稿；菜单栏、任务台、设置页和设计预览页共用从它派生的标记。菜单栏始终使用无底板、透明镂空的单色模板，由 macOS 按背景自动显示为白色或深色，不随任务状态变色；状态通过提示文字和任务面板呈现。

修改 SVG 后运行 `Scripts/make-icons.sh`，生成原生矢量 PDF、透明标记 SVG 和 `Resources/HerdrIsland.icns`；该脚本需要 `rsvg-convert`（`brew install librsvg`）、Python 3 和 macOS 自带的 `iconutil`。生成物已随源码保存，正常构建无需安装图像工具。打包脚本会复制图标和 SwiftPM 资源包，系统通过 `CFBundleIconFile` 加载应用图标；直接 `swift run` 时窗口和菜单栏也使用相同标记。

## 开发参数

| 参数 | 作用 |
| --- | --- |
| `--render <dir>` | 渲染全部 fixture PNG，包括 ambient、peek 相关状态、deck 筛选、详情、水滴输入框、窗口任务和新任务 |
| `--print-state` | 只读执行 `herdr agent list`，打印推导后的状态 JSON |
| `--demo` | 使用固定 fixture 展示 blocked 面板，不依赖 Herdr |
| `--no-auto-expand` | 关闭 blocked 和完成的自动展开 |
| `--log <path>` | 同时把日志写入指定文件 |
| `--new-task <text>` | 启动后打开新任务输入框并预填文本，测试用 |
| `--new-task-send` | 与 `--new-task` 一起用，预填后自动提交，会创建真实 agent |
| `--open-pane <pane-id>` | 首次发现该 agent 后打开其交互终端，遵循 `HERDR_SOCKET_PATH` 指定的会话 |

`--render` 写出 `collapsed`、`expanded`、`blocked`、`completed`、`quickTask`、`windowLocked`、`deckRunning`、`deckDone`、`deckCrowded`、`detail`、`drop` 及创建中的新任务、水滴任务和失败状态图，并用 `manifest.json` 记录尺寸和 headline。

## 结构

```text
Sources/IslandCore  纯状态机。domain、reducer、presenter、几何、键盘路由。没有 AppKit
Sources/HerdrKit    Herdr 适配层。CLI、Unix socket、DTO、Ghostty 聚焦
Sources/IslandApp   AppKit + SwiftUI 外壳。面板、菜单栏、快捷键、渲染和设置
Tests/              核心行为测试和 Herdr 适配测试
```

`IslandCore` 不依赖 Herdr。所有 Herdr 事实在边界解析成 `Agent`，状态变化由 `IslandReducer` 一处决定，视图只渲染 `IslandPresenter` 给出的 `IslandPresentation`。

## 已知限制

- 精确 Ghostty 聚焦依赖 Herdr TUI 客户端进程的 tty。只有一个客户端时是精确的；有多个时聚焦第一个匹配的终端。
- ad-hoc 签名在每次重新构建后可能改变 TCC 身份，Automation 和 Screen Recording 权限可能再次询问。
- 窗口锁定只能选当前 Space、当前屏幕上的窗口，锁的是具体 windowID。窗口关闭再打开会换 ID，MVP 不会自动重新绑定；最小化或切到别的 Space 时连线隐藏，截图会失败。锁定只存在于本次运行期间。
- 受 DRM 或安全保护的窗口可能只能截到黑屏，公开 API 无法绕过。
- 水滴只在有刘海的屏幕上常驻；没有刘海时窗口锁定暂不可用，其他功能不受影响。
- 刘海是摄像头遮挡区，屏幕在它内部没有像素。刘海下的 32pt 区域是透明的，只有水滴和液态拖拽会画在那里。
- 悬停展开依赖窗口能收到鼠标移动事件。面板不抢焦点，鼠标移入即展开，移出约 220ms 后收起，除非有 blocked、完成停留或未发送的草稿。
- 新任务接口负责派发和跟踪，不保证任务本身一定完成。`agent start` 失败时已创建的 workspace 会保留，错误里带 pane ID。不会固定空等 TUI 稳定；提交后确认 working、blocked 或 done。启动或提交失败时保留草稿、当前阶段和终端入口；已有 pane 或创建结果不确定时禁止直接重复创建，关闭后重开仍保留恢复状态，需先去终端检查；“另建任务”会清空草稿后开始一项新任务。
- 多行 Claude、Codex、Cursor 任务会在首次发送前确认真实空输入框就绪，原样保留换行和缩进。无法识别输入区或已有内容时最多检查 20 秒后安全退出，保留终端供检查，不补回车或重复发送任务。
- 主 agent 按 pane + workspace + agent kind 一起识别。Herdr 可能把 pane ID 复用到另一个 workspace 或 agent；只有三者都匹配才算同一个 agent，否则提示“主 Agent 已退出，这次将新建”，不会把消息发给错误对象。
- 忙碌的 agent 只保留一条排队消息，本轮结束且未打开交互终端时自动投递；已有排队时再发会被拒绝。blocked 或状态未知的 agent 不能接收自动消息，需要先在终端处理。
- 未授权 Screen Recording 时不附截图；未授权辅助功能时不读取选中文本、网页地址和文档路径。两者都不阻断发送。自动上下文是 best-effort，上限分别为 4,000 / 2,048 / 1,024 字符。
- 截图调用没有单独的取消按钮；权限弹窗或 ScreenCaptureKit 卡住时，一次发送可能等待较久。关闭投递框不会中止已经开始的截图调用。
- 附件只传绝对路径，最多 8 个；发送前检查文件仍可读，排队消息投递前再次检查，缺失的文件会被移除。粘贴图片单张最多 16 MB / 4000 万像素，超过 7 天的缓存在下次打开终端或粘贴时清理。
- 每个新任务创建一个独立 workspace，label 取任务文本前 40 个字符；开启隔离时创建 `island/<单词>-<随机后缀>` 分支。任务结束后可以在 Herdr 里关闭这个 workspace。

## 测试

```bash
swift test
```

核心测试使用固定时钟和 fixture，不需要运行 Herdr。

单任务“实时终端”的实际交互验证与尚未实现的能力见 [终端验证记录](docs/terminal-verification-2026-11-10.md)。

终端标题栏不显示列数和行数；仅在查看历史输出时显示“回到底部 ↓”，返回底部后自动隐藏。

性能基准默认跳过，可按需运行：

```bash
# 只读，交替执行各 30 次 CLI / socket 查询，输出中位数和 p95
ISLAND_BENCHMARK_READS=1 swift test --filter TaskCreationPerformanceTests/testLiveReadTransport

# 会创建一个真实 Claude 任务，确认开始后清理该测试 workspace
ISLAND_BENCHMARK_CREATE=1 swift test --filter TaskCreationPerformanceTests/testLiveTaskCreation
```

查询加速比与完整冷启动耗时分别报告，不用查询微基准替代端到端性能结论。

完整链路的 [初始基线](docs/performance-baseline-2026-11-06.md) 和 [并行优化报告](docs/performance-optimization-2026-11-06.md) 包含原始样本、成功与失败数、源码/产物哈希及复跑命令。覆盖任务创建、预览、终端跳转、状态计算、拖动和截图；已达到的局部 10× 收益与尚未达到的端到端目标分别记录。
