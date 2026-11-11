# 单任务实时终端验证（2026-11-10）

## 交互范围

详情中的“实时终端”始终连接选中任务的现有 pane。目标是让用户在这里完成正常终端操作；工作区、标签、分屏等 Herdr 应用界面不属于这个视图。此前加入的完整客户端、独立窗口和对应代理已撤回。

当前直接使用 Herdr 0.9.5 的单 pane 二进制 socket 协议 22 和 SwiftTerm，保留 `TerminalAttach`，不协商 `ClientShell`。关闭详情释放连接，保留原进程；重新连接回到同一任务。只有当前 pane 的自动消息投递暂停，其他任务继续运行。输入失败后不自动重发。

## 本次实际验证

Herdr 0.9.5，macOS 原生 AppKit / SwiftTerm，独立的 `island-terminal-qa-parity-1110` 会话，真实 zsh；没有启动或操作真实模型任务。

通过的终端交互：

- 中文 IME 组合与提交、方向键编辑、Enter / Escape / Ctrl+C。
- 多行括号粘贴，不自动追加 Enter。
- `stty size` 验证真实 PTY 尺寸变化。
- curses 应用光标键、Vim 编辑并保存文件。
- 主屏历史滚动、Shift + Page Up / Down、鼠标报告程序的滚轮。
- 回到实时输出、断开与重连，保留同一会话。
- 当前任务队列暂停、其他任务继续投递，返回任务台后恢复。

复跑命令（仅用于自己创建的可丢弃 shell，cwd 必须为 `/tmp`；旧键盘用例会匹配该提示符）：

```bash
ISLAND_TERMINAL_TEST_SOCKET="$QA_SOCKET" \
ISLAND_TERMINAL_TEST_PANE="$QA_PANE" \
swift test -j 4
```

初次全量结果：281 个用例，276 通过、4 跳过、1 失败，命令退出码 1。失败为 `FixtureTests.testFixturesRenderFourDistinctStates` 中与终端无关的任务台高度断言（440 与 443）。该断言随后由并行的任务台布局改动更新；重新构建后，本次另用 `xcrun xctest .build/out/Products/Debug/IslandCoreTests.xctest` 复跑核心测试，173 项全部通过，退出码 0。本次没有修改那处布局或断言。

合并各目标最后一次结果：277 项实际执行通过、4 项可选测试跳过。两项真实终端交互测试与全部 `TerminalInteractionTests` 均通过。跳过的模型、窗口捕获和性能测试不算验收通过。

上一轮 Debug 应用的隔离会话界面也已截图检查：详情只显示选中任务的“实时终端”，没有 Herdr 工作区、标签栏或分屏界面。那轮检查后关闭测试应用、删除测试会话，并恢复原已打包的日常应用；当时未重新打包 Release。此次追加交付的 Release 结果见下文。

## 尚未实现的能力

本次纠正不能宣称完全替代 Ghostty / Herdr 的全部终端能力。完整按键按下/重复/释放协议、焦点报告、OSC 52 剪贴板、终端内图像显示等仍需补齐。图片输入与终端内图像渲染是不同能力；用户本次明确需要前者。

已对照 Herdr 0.9.5 服务端源码确认：

- JSON 控制 CLI 只转出文本帧和关闭事件，丢弃鼠标及键盘模式消息。
- 单 pane `TerminalAttach` 不下发完整输入模式或图像场景。
- 剪贴板、铃声和标题发往全局前台客户端；直接 attach 不是该客户端，剪贴板事件也缺少来源 pane 标识。
- 焦点和完整图像通道属于 `ClientShell`。它的视口、几何尺寸和焦点按整个 tab 管理；裁剪指定 pane 不能提供独立终端尺寸，也可能影响其他 pane。

后续完整接入需要扩展单 pane 协议：目标绑定的有序语义输入、模式状态、焦点、图像和剪贴板事件，以及独立尺寸同步。不能以嵌入或裁剪整个 Herdr 客户端作为替代。

## 鼠标与图片输入追加实现

- 直接接收服务端 MouseCapture 状态，并发送 AttachMouse 单元格坐标；支持左右键、中键、拖动、移动及修饰键。Shift 开始的选择手势始终留在本地。
- 使用 `⌘V` 或原生拖放接入文字、文件 URL、PNG/TIFF 剪贴板图片。原生图片经过 ImageIO 校验及 PNG 转换，限输入/输出 16 MiB、4000 万像素，路径使用 shell 引号转义。
- 图片缓存目录 `~/Library/Caches/HerdrIsland/TerminalImages` 为 0700，文件为 0600。图片不随详情关闭删除；超过七天的本应用 PNG 在下次打开终端或粘贴图片时清理，不承诺应用关闭期间定时删除。
- 不修改用户 Herdr 服务端或安装私有分支。文字/粘贴/特殊按键仍使用同一确认队列。协议 22 的鼠标、滚动、尺寸通道与输入 API 之间没有处理确认，混合操作的严格全序尚不保证；仅本地排队不能证明服务端执行顺序。服务端扩展实验未纳入产品。

追加真实验收使用隔离会话 `island-terminal-qa-input-1110`，通过原生 AppKit 的 `TerminalController` / `IslandTerminalNSView` 操作 Herdr 真实 PTY：

- 左键 down/drag/up、Ctrl+右键、Shift 本地选择、退出鼠标报告模式后恢复本地选择均通过。
- PNG 从独立 NSPasteboard 粘贴到 shell，真实读取 PNG 签名成功；断开详情连接后图片仍存在。
- Claude Code 2.1.322、Codex 0.167.0 的真实输入框均将粘贴图片显示为 `[Image ...]` 附件。另经真实输入 API 检查含空格和单引号的图片路径，两者均识别；测试草稿未提交，不代表模型端图像推理已验收。
- 文件 URL 和原生拖放共用粘贴入口。文件 URL 转义由测试覆盖；未执行 Finder 到应用窗口的手动拖放。当前环境未启用 CUA 原生窗口控制。
- 初次追加回归中重连历史滚动断言超时（退出码 1）；同一用例在新空 pane 通过。测试标记随后改为每轮唯一值，避免旧历史匹配本轮断言；最终复跑通过。
- 后续 `swift test -j 4` 使用了 cwd 为测试子目录的 pane，旧键盘测试固定等待 `/tmp` 提示符，导致该用例超时，命令退出码 1。改用 cwd 为 `/tmp` 的 pane，直接复跑整个 `IslandAppTests.xctest`，12 项中 10 通过、2 可选跳过，退出码 0；键盘/IME/粘贴/尺寸/Vim/重连与滚动两个真实用例均通过。

最后一次各测试目标结果：`IslandCoreTests` 173/173 通过；`HerdrKitTests` 99 通过、3 可选跳过；`IslandAppTests` 10 通过、2 可选跳过。合计 282 通过、5 跳过、0 失败。被默认跳过的 Claude/Codex 附件用例另行启用并通过。跳过的性能、窗口捕获和其他模型测试不算验证通过。

`swift build -c release -j 4` 退出码 0；应用包 ad-hoc 签名及 `codesign --verify --deep --strict` 通过，隔离 socket 的 `--print-state` 启动检查通过。已替换 `build/HerdrIsland.app` 并重新启动（新 PID 70377）；原 Herdr 服务 PID 2118 保持不变。只关闭并删除了本次隔离测试会话。

打包后可执行文件 SHA-256：`ea1fb463a33fd46f78b37d2f6fff8b785280742b2086c12170624de3a5bb5bc2`。

本机日志：`/tmp/island-terminal-final-focused.log`、`/tmp/island-terminal-final-all.log`、`/tmp/island-terminal-app-final.log`、`/tmp/island-terminal-release.log`、`/tmp/island-terminal-release-smoke.log`。

此前的真实终端结果属于上节版本，不能代替此次新增能力的验收。

## 终端标题栏精简

移除列数和行数，常驻的“回到实时”改为仅查看历史输出时出现的“回到底部 ↓”。通过当前 pane 的真实 `scroll.offset_from_bottom` 判断状态；关闭详情或断线时停止读取并隐藏按钮。向下滚到底部、开始输入或点击按钮后，按服务端状态自动隐藏。程序内部的鼠标滚动不会当成终端历史滚动。

在独立 `island-terminal-qa-history-1110` 会话中，用 Release 配置执行 `HerdrTerminalTests` 和 `InteractiveTerminalTests.testLiveWheelScrollsHistoryAndMouseReportingApplication`，8 项全部通过，命令退出码 0。真实终端断言覆盖上翻历史时出现、回到底部及输入时隐藏、应用内鼠标滚动不触发、断开重连后的状态恢复。本次没有重跑无关测试目标。

应用包签名验证和隔离 socket 启动检查通过，已更新并重启 `build/HerdrIsland.app`（PID 89990）；Herdr 服务 PID 2118 保持不变，测试会话已删除。当前应用可执行文件 SHA-256：`2ea76987a1625e0942a3ff0aab7b351c8b1d870f0a74cb211b4d72a6c4bb01a3`。日志：`/tmp/island-history-verify.log`、`/tmp/island-history-smoke.log`。
