# 功能流程走查：2026-11-09

范围为当前工作区，包括原有未提交的交互终端、图标和界面改动。本次没有提交、推送或替换正在运行的应用。

## 修复的问题

| 场景 | 原来的问题 | 修复后的行为 |
| --- | --- | --- |
| 两个全局快捷键同时注册 | 后注册的处理器吞掉另一个快捷键的事件 | 不匹配的事件继续交给下一个 Carbon 处理器 |
| 排队消息发送失败 | 排队项在发送前移除，失败后正文丢失 | 保留正文并暂停，检查终端后手动重试，不自动重复发送 |
| 发送过程中继续写草稿 | 较晚的成功回调清空新草稿 | 只清除本次实际发送的草稿版本 |
| 创建失败后关闭、重开输入框 | 恢复了文本，却丢失已有 pane，可能重复创建 | 同时恢复阶段、终端和错误；提供明确的“另建任务”入口 |
| 创建目录失败 | 阶段面板一直遮住模型和目录控件 | 确认未创建时回到可编辑状态，可以换目录重试 |
| 工作区创建响应丢失 | 无 pane 被误当成确定失败，并提示直接重试 | 标记创建结果不确定，要求先检查 Herdr，避免重复创建 |
| 窗口任务的目标变忙或消失 | 后台采样把目标改成另一个空闲 agent | 保留原目标并显示拒绝原因；新 agent 选择也不会被改写 |
| 从快捷输入切换到水滴或锁窗 | 隐藏的输入框残留或原草稿丢失 | 保存原草稿，明确交接当前输入界面 |
| 稍后处理 blocked 任务 | 任务从“全部”筛选也消失 | 只移出待处理提醒，仍可在“全部”中找到 |
| 搜索无结果 | 隐藏的旧选择仍可被 Return、R 等快捷键操作 | 清除不可见选择，后续采样也不会恢复错误目标 |
| 多次创建隔离任务 | 八个固定分支名循环使用，容易冲突 | 分支名增加随机后缀 |
| 启动屏幕 socket 读取失败 | CLI 返回 ANSI，被当作 socket JSON 解码 | 按实际读取途径解析，保留安全的只读回退 |
| 新工作区的 shell 尚在初始化 | 立即启动模型可能被 `agent_pane_busy` 拒绝 | 仅对此明确未接受启动的拒绝短暂重试；不重试不确定写入 |
| 模型报告就绪早于真实输入框 | Codex、Cursor 首条文本和回车可能抢在输入处理前到达 | Claude、Cursor 单行任务用原生首条任务参数；Codex 和多行任务检查真实空输入框；Cursor 信任弹窗要求人工处理，后续手动或排队消息也在发送前检查 Cursor 信任弹窗和 Codex 用量/模型选择弹窗 |

额外为事件订阅 socket 关闭 SIGPIPE，避免对端断开时写订阅请求导致应用退出。

## 验证范围

| 功能 | 验证方式与边界 |
| --- | --- |
| 启动、状态采样、完成和 blocked 提醒 | 状态机测试、真实 Unix socket 测试、隔离 Herdr 会话 |
| 断线、CLI 只读回退、写入不重发 | 协议测试覆盖断开、超时、无效响应和明确拒绝 |
| 任务筛选、搜索、选择、稍后处理 | 回归测试及任务台 fixture 渲染 |
| 草稿、排队、取消、失败恢复、手动重试 | 回归测试覆盖较晚回调、状态切换、blocked 拒绝和终端占用 |
| 快捷任务、水滴、窗口任务 | 状态机和适配层测试；创建中、失败、恢复状态渲染 |
| worktree | 在本仓库创建独立测试 worktree，无额外信任参数；随后移除 checkout 和测试分支 |
| 交互终端 | 真实 shell 测试：中文输入、光标编辑、多行粘贴、Ctrl+C、尺寸同步、curses、vim、历史滚动和断开重连 |
| 窗口截图 | 只捕获自建 QA 窗口，验证 PNG 编码和尺寸；没有读取用户窗口 |
| 窗口选择、拖动、连线、多屏坐标 | 源码、几何测试和 fixture；未通过鼠标完整实走跨屏手势 |
| 设置、声音、权限入口、菜单栏图标 | 源码与设置页渲染；没有改变用户设置或系统权限 |
| 界面 | 16 个 fixture/外置水滴场景加 4 个设置页面，共 20 张 PNG；人工查看重点页面；机械检测不替代原生可访问性验收 |
| 打包 | 最终构建和签名结果见下方 |

## 最终结果

- 普通全量：`swift test -j 4`，265 项，260 通过、5 项 opt-in 跳过、0 失败。日志：[final.log](../build/qa-audit/final.log)。
- 真实终端与自建窗口截图：2 项通过、0 失败；其中终端覆盖断开重连、中文、粘贴、尺寸同步、vim/curses 和历史滚动。日志：[live-native-final.log](../build/qa-audit/live-native-final.log)。
- Claude：单行、多行任务创建、实际输出及完成后追问均实跑通过。
- Codex：观察到了首轮实际输出，后续消息遇到客户端的用量/模型选择弹窗。发送前检查正确返回 `agentBlocked`，没有自动代选；不能宣称当前账户下的追问全链路已闭环。人工门禁定向复跑 1 项通过、0 失败，见 [codex-gate-verified.log](../build/qa-audit/codex-gate-verified.log)。
- Cursor：实测发现工作区信任弹窗，启动和消息发送均保留人工决定，不自动批准；未通过该门禁执行真实任务。
- release：`swift build -c release -j 4` 退出 0；独立应用包的 `codesign --verify --deep --strict` 和 Info.plist 校验通过。打包后的应用成功渲染全部 20 张 PNG，证明资源加载路径可用。
- 独立测试包：[HerdrIsland.app](../build/qa-audit/HerdrIsland.app)。没有替换日常运行的应用；ad-hoc 签名与正常 LaunchServices 的权限身份仍需按下方边界验收。

全量通过后，仅调整了真实测试用例对预期人工分支的断言和按客户端复跑选项，随后定向实跑通过；应用源码未再变更。两个临时命名会话已停止并删除，测试 checkout 和测试分支已移除。

最终模型测试区分“任务执行成功”与“已知客户端门禁被安全拦截”。门禁分支通过只证明没有自动作答或重复派发，不代表 Codex 追问或 Cursor 任务已经执行。首次实测失败日志保留，其中 `NO_COLOR`、固定延时及预期人工分支的测试断言已分别定位。

证据目录为本地忽略目录 [build/qa-audit](../build/qa-audit/)，包括完整日志、首次失败记录、20 张渲染图、worktree 创建/移除响应和源码 SHA-256。首次失败记录保留用于区分测试环境问题与代码修复，不能将它们当作最终通过记录。

## 尚需人工或外部环境确认

- Codex 在当前账户显示“Approaching rate limits / Keep current model”的模型选择弹窗，需用户决定；没有替用户切换模型。Herdr 0.9.5 可能将这类新弹窗报告为完成/空闲，因此 Island 在发送前另行检查并拒绝自动回车。
- Cursor 在当前仓库显示 `Workspace Trust Required`。应用必须保留终端，等待用户决定；本次没有信任仓库或批准任何弹窗。
- `NO_COLOR=1` 会移除部分客户端用于区分占位提示和真实输入的样式。无法安全识别空输入框时，多行提交会停止并保留终端；测试服务器重建时去除了此变量。
- 其他九种可选客户端没有逐个执行真实任务，不能从 Claude 或 Codex 的结果推断它们全部可用。
- 原生 UI 自动化通道不可用。实际鼠标拖动、跨屏、Space 切换，以及通过 LaunchServices 启动的应用的 TCC 身份没有完成交互验收；截图通过仅证明 XCTest 身份下的自建测试窗口捕获成功。
- 走查期间另有 `IslandRootView.swift`、`Theme.swift` 及面板动效改动进入工作区，已保留并包含在最终构建和渲染中；动画、真实鼠标手势没有完整交互验收。
- 普通编译中仍有现有的 `NSEvent` Sendable 警告；项目当前使用 Swift 5 语言模式。本次没有进行 Swift 6 迁移。

## 复跑

```sh
swift test -j 4
swift build -c release -j 4
```

真实测试只允许显式指定 `island-terminal-qa-*` 命名会话，避免操作日常会话：

```sh
# 在独立终端中运行测试服务器；不要停止或替换日常 Herdr 服务。
env -u NO_COLOR herdr --session island-terminal-qa-manual server

# 另一个终端中运行。先在该会话创建 cwd=/tmp 的一次性 shell，
# 使用创建响应返回的 pane ID，不要猜测 ID。
ISLAND_LIVE_WORKFLOWS_SOCKET="$HOME/.config/herdr/sessions/island-terminal-qa-manual/herdr.sock" \
  swift test --skip-build --filter LiveWorkflowTests

ISLAND_TERMINAL_TEST_SOCKET="$HOME/.config/herdr/sessions/island-terminal-qa-manual/herdr.sock" \
ISLAND_TERMINAL_TEST_PANE='<创建响应中的 pane_id>' \
ISLAND_CAPTURE_TEST=1 \
  swift test --skip-build --filter 'InteractiveTerminalTests|WindowCaptureTests'
```

重连测试改为等待真实执行回执后再断开，替代固定 150ms 假设；vim 返回也使用独立回执，避免把尚未退出的编辑器内容误当成命令已经完成。
