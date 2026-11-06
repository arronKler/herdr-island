# Herdr Island

Herdr Island 把 Herdr 里的 agent 状态收进 macOS 摄像头刘海的左右两耳，并在刘海下挂一滴水。收起时它只占菜单栏高度，不改变刘海的形状。把水滴拖到桌面任意位置，输入框就落在那里：选模型、选目录、可选隔离 worktree，输入任务后直接在 Herdr 里创建 workspace、启动 agent 并提交。按住 Option 拖动同一滴水，则改为锁定指针下的窗口，发送任务时附带一张该窗口的截图。

## 界面

- **环境条**。左右耳位于刘海两侧，左侧显示待处理或安静，右侧显示运行、完成或空闲。刘海下方 32pt 的透明延伸区只画水滴，不遮挡桌面点击；鼠标移到水滴或两耳上才接收事件。
- **轻提示**。完成一轮时先出现 400 × 248 的 peek，列出一条完成结果；鼠标移入或点击后进入完整 deck。
- **任务台**。宽度固定 560，高度随可见行数在 440 到 640 之间自适应。顶部是待处理、运行中、已完成、全部四个筛选，`/` 进入搜索。每一行带对应 agent 的图标和状态点；运行中的行显示最近一行终端输出，可以排队下一条消息，等待你处理的行有独立的操作区。
- **详情**。660 × 640。左侧是分组 rail，右侧是当前 agent 的只读终端预览、阻塞原因、命令复制、去终端和稍后。
- **新任务**。Control + Option + N 唤起 420 × 196 的输入框，沿用当前 Herdr pane 的目录和上次选择的模型，可选 worktree。
- **窗口任务**。锁定窗口后出现，默认 560 × 510，遇到阻塞、权限缺口或错误提示时按需增高。选目标 agent 或新建 agent，写下任务，发送时截取一张窗口 PNG。
- **水滴输入框**。拖动水滴时，水滴和刘海之间先拉出液态颈部；超过 96pt 后完全脱离，只剩一个小水珠，不保留连线。松手的位置出现涟漪，输入框锚定在落点上方。输入框支持多行任务、模型选择、目录选择和 worktree 开关。
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
| `Command + Return` | 发送消息，或在新任务、窗口任务、水滴输入框里提交 |
| `Esc` | 逐层退出：先收输入框，再退出搜索、详情，最后收起面板 |

## Herdr 能力

- **状态同步**。通过 Unix socket 直接读取 `agent.list` / `pane.list`，避免每次查询启动 CLI 和创建临时文件。每 1.5 秒采样，状态事件即时更新。直接读取不兼容或断线时回退 CLI，并冷却 10 秒后再尝试 socket；创建和提交等写操作不走自动重试。
- **终端预览**。`herdr agent read --source recent-unwrapped` 读取最近输出，跳过被 TUI 换行折断的行。
- **标签与目录**。读取 `state_labels`、`name` 和 `foreground_cwd`，优先用前台目录作为项目名。标签会显示在详情里，也参与搜索。
- **发送**。只通过 `herdr agent prompt` 提交，不使用 `send-keys`。运行中的 agent 可以排队一条消息，本轮结束后自动投递；排队项可以取消。
- **新任务**。显示准备目录、启动模型、提交并确认三个真实阶段，以及等待耗时。Claude 通过 `herdr agent start -- -- <任务>` 传入首条任务，避免启动时文本粘贴成功但未提交；其他模型通过 `herdr agent prompt --wait` 确认启动。确认后自动选中新 pane，轮询和 socket 接管状态。开启隔离时改用 `herdr worktree create --cwd ... --branch ... --label ... --no-focus`。
- **启动确认**。在模型启动前订阅新 pane，复用状态事件和已有采样确认 working / blocked / done，不再为创建任务另外启动每 400 毫秒一次的 CLI 查询。事件断开仍由周期采样兜底。减少的是应用的查询开销和确认延迟，模型冷启动仍取决于本机模型客户端。
- **窗口截图**。ScreenCaptureKit 在发送时截取锁定窗口一张 PNG，把绝对路径、app 名、窗口标题、捕获时间和任务拼成 prompt。

新任务的 worktree 不会带 `--trust-repository`。仓库是否可信由你在 Herdr 里确认。

## 安全边界

blocked 是人必须亲自处理的闸门。Herdr Island 不会自动批准，也不会发送 `y` 或 Enter 去关闭批准提示。blocked 状态下唯一的操作是去终端，输入框会显示拒绝原因。向已有 agent 发送消息只通过 `herdr agent prompt`，它本身会拒绝 blocked 的 agent。Claude 的首条任务作为新进程的启动参数传入，不模拟确认按键。

新任务只向刚创建的 workspace 和 agent 提交内容，不会向已有 blocked agent 发送。新 agent 启动后如果进入 blocked，仍然需要你亲自处理。

窗口截图只在明确按下发送时发生，不会在锁定期间持续截屏。截图保存在本机 `~/Library/Application Support/HerdrIsland/Captures/`，prompt 里只带绝对路径和窗口元数据，不会上传到别处。

## 环境

- macOS 14 或更新版本
- Herdr 0.9.x。默认二进制路径 `~/.local/bin/herdr`，socket 路径 `~/.config/herdr/herdr.sock`
- Ghostty。精确跳转需要它；没有 Ghostty 时仍会聚焦 Herdr pane
- Automation 权限。首次 Jump 时 macOS 会询问是否可以控制 Ghostty
- Screen Recording 权限。窗口锁定功能需要它在发送时截图；授权后可能需要重启 app

## 构建

```bash
swift build
Scripts/make-app.sh
open build/HerdrIsland.app
```

`Scripts/make-app.sh` 执行 release 构建，组装 `build/HerdrIsland.app`，然后做 ad-hoc 签名。应用是 `LSUIElement`，不会出现在 Dock。

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
- 新任务接口负责派发和跟踪，不保证任务本身一定完成。`agent start` 失败时已创建的 workspace 会保留，错误里带 pane ID。不会固定空等 TUI 稳定；提交后确认 working、blocked 或 done。启动或提交失败时保留草稿、当前阶段和终端入口；已有 pane 时禁止直接重复创建，需先去终端检查。
- 多行 Claude 任务会在首次发送前确认真实空输入框就绪，原样保留换行和缩进。无法识别输入区或已有内容时最多检查 20 秒后安全退出，保留终端供检查，不补回车或重复发送任务。
- 每个新任务创建一个独立 workspace，label 取任务文本前 40 个字符；开启隔离时创建 `island/<单词>` 分支。任务结束后可以在 Herdr 里关闭这个 workspace。

## 测试

```bash
swift test
```

核心测试使用固定时钟和 fixture，不需要运行 Herdr。

性能基准默认跳过，可按需运行：

```bash
# 只读，交替执行各 30 次 CLI / socket 查询，输出中位数和 p95
ISLAND_BENCHMARK_READS=1 swift test --filter TaskCreationPerformanceTests/testLiveReadTransport

# 会创建一个真实 Claude 任务，确认开始后清理该测试 workspace
ISLAND_BENCHMARK_CREATE=1 swift test --filter TaskCreationPerformanceTests/testLiveTaskCreation
```

查询加速比与完整冷启动耗时分别报告，不用查询微基准替代端到端性能结论。

完整链路的 [初始基线](docs/performance-baseline-2026-11-06.md) 和 [并行优化报告](docs/performance-optimization-2026-11-06.md) 包含原始样本、成功与失败数、源码/产物哈希及复跑命令。覆盖任务创建、预览、终端跳转、状态计算、拖动和截图；已达到的局部 10× 收益与尚未达到的端到端目标分别记录。
