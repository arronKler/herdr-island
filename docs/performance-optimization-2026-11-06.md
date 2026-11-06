# Herdr Island 并行性能优化 · 2026-11-06

已优化终端跳转、预览、状态计算、拖动、截图准备、创建与发送传输，并修复创建中的反馈。**尚未实现所有链路端到端 10×**：模型冷启动、消息提交和完整历史采集未达到目标；完整截图成功验证受正常启动方式下的系统权限检查阻挡。失败样本、缓存命中和新建压力场景分别记录，不代替全链路成功。

## 测量口径与结果

同一台 Mac15,7、12 逻辑 CPU、36 GiB 内存、23 个真实 agent、2 块屏幕；macOS 26.6.2、Herdr 0.9.5。原基线见 [基线报告](performance-baseline-2026-11-06.md)。正式 v2 使用冻结的 release 库与应用，记录源码及产物 SHA-256；采样期间源码无变化，开始/结束 Swift 编译进程均为 0。初始 appkit 基线的 load average 为 5.24 → 15.77，采样末尾有 1 个编译进程；优化 v1 为 5.02 → 6.16，v2 为 12.13 → 13.80。桌面未隔离，倍数仅代表本次实验，不能承诺为稳定 SLO。总表对应冻结 v2；之后仅修改 HerdrKit 的多行就绪检查、socket 环境绑定和取消处理，最终任务验证另列。

表内使用单调时钟的墙钟耗时。状态与文本项目是生产计算代码的合成输入测量，不包含 SwiftUI/GPU 绘制；文本使用固定 ASCII 样本。样本少于 20 时不报告 P95。

| 链路 | 原 P50 | v2 P50 | 比值 | v2 成功样本 |
| --- | ---: | ---: | ---: | ---: |
| 终端跳转调用完成 | 2369.476 ms | 33.590 ms | 70.5× | 5 |
| 创建工作区 | 260.391 ms | 48.613 ms | 5.4× | 4 |
| 空闲任务 60 行历史预览 | 385.427 ms | 225.258 ms | 1.7× | 25 |
| 已有 agent 追加消息返回 | 485.072 ms | 305.176 ms | 1.6× | 5 |
| 500 agent 相同快照与展示 | 18.173 ms | 2.870 ms | 6.3× | 100 |
| 500 agent 搜索与展示 | 44.157 ms | 1.902 ms | 23.2× | 100 |
| 500 agent 草稿与展示 | 24.658 ms | 0.289 ms | 85.4× | 100 |
| 60 行终端文本规范化 | 1.361 ms | 0.022 ms | 62.0× | 200 |
| 1000 行输入取末尾 60 行 | 22.035 ms | 0.069 ms | 317.1× | 100 |

终端跳转样本为连续 5 次对同一 pane 调用 `service.focusPane` 并等待返回，包含 Herdr focus 与 Ghostty 定位，但不测屏幕首帧，也不是每次都从另一个窗口切入。

23 agent 场景中，相同快照仅提升 2.21×、搜索 4.69×、草稿 28.49×，不能把 500 agent 的收益套用到所有规模。

- **工作中预览**：原来 25/25 次 `agent_not_idle`，现在 25/25 成功，P50 7.92 ms / P95 25.96 ms。工作时读取可见区域，空闲时保留完整 60 行历史语义；没有原成功基线，因此不报告加速倍数。
- **重复加载**：10 个相同 working snapshot 原来触发 10 次重读和 10 次 loading，现在均为 0。terminal revision/内容变化才刷新；后台更新保留旧文本，失败后下次采样再试。
- **持续输出**：每轮改变 500 agent 中一条 lastLine，v1 P50 15.50 ms，v2 1.674 ms / P95 3.514 ms。这是本轮新增场景，不是初始基线。单独冻结 v1 库进行 v1→v2→v2→v1 交错采样，每版 200 样本：15.539 → 3.397 ms，额外改善 4.57×；桌面负载导致不同轮次差异。
- **时间变化**：500 agent 草稿与展示在时钟持续变化时 P50 0.421 ms / P95 0.560 ms；缓存仍按最新时间更新 waited，支持时间回拨。
- **拖动**：缓存就绪后，实际 `WindowDragCoordinator.update` P50 0.130 ms / P95 0.366 ms；首次找到合成目标 111.67 ms（仅 1 个样本），最终 drop 新鲜查询 P50 1.405 ms / P95 2.446 ms。均校验目标 windowID。后台快照减少每个指针事件的工作，但不能据此宣称首次命中或真实拖动 FPS 提高 10×。
- **窗口跟随**：旧单窗口探针实际返回空数组，旧 0.67 ms 已从有效基线撤下；v2 用正确 Quartz API 并核验 windowID，100/100 成功，P50 0.424 ms。
- **文本结果波动**：v1 的 60 行/1000 行 P50 为 0.057/0.157 ms，v2 为 0.022/0.069 ms；两轮都超过 10×，不将最快一次当作恒定性能。

## 创建与等待反馈

三个入口共用真实阶段：准备目录 → 启动模型 → 提交并确认。提供旋转进度标记、持续计时、长等待提示和终端入口，遵循系统减少动态效果设置。已创建终端后失败，会保留草稿及 pane，引导检查已有任务，避免重复创建/发送。

原生渲染检查已覆盖 [创建中](performance-baselines/2026-11-06-creation-ui/quickTaskCreating.png)、[创建失败](performance-baselines/2026-11-06-creation-ui/quickTaskFailed.png)、[拖放创建中](performance-baselines/2026-11-06-creation-ui/dropCreating.png)。这是静态原生视图检查，不能替代真实动画连续性或端到端点击验收。

创建耗时从 `service.createTask` 调用到实际状态确认，不是从鼠标点击到 UI 首帧。

**最终 release 单行任务**：3/3 成功，开始执行确认分别为 **22.27 / 17.80 / 6.65 秒**，P50 **17.80 秒**；首轮完成 P50 **40.10 秒**。此前 v2 为 7.85 / 6.59 / 7.13 秒，P50 7.13 秒，首轮完成 P50 14.23 秒；初始基线为 7.45 / 14.31 秒。最后这轮比先前慢，不能用较早的快样本证明当前冷启动提升。运行期间 load average 17.37 → 17.81，编译进程起止均为 0，但仅凭负载不能把波动归因给机器或模型服务。

这里的冷启动指新建 Claude 进程，不清空系统文件缓存，不与已有热 agent 混算。最终 4 次工作区创建 P50 39.96 ms；主要剩余等待在工作区就绪之后。**冷启动目标未完成，当前证据不能证明它获得加速**。[最终 release 任务样本与哈希](performance-baselines/2026-11-06-task-final-validation.json)

**启动契约**：v1 曾尝试把启动也移到裸 RPC，3 次中 1 次 commandFailed；原始 harness 未保留该次具体错误消息，不能追认成某个确定的错误码。官方实现中，RPC 只派发启动，而 CLI 会绑定终端身份、在 shell 初始化时做受限重试并等待交互就绪，因此 v2 已恢复 `agent start` CLI，配合状态订阅尽早确认实际工作开始。[Herdr CLI 启动实现](https://raw.githubusercontent.com/herdrdev/herdr/v0.9.5/src/cli/agent.rs)

**多行真实任务**：v2 首次实测 0/1 成功，27.91 秒超时。后续诊断确认 CLI 就绪早于 Claude 输入框出现；提前写入的多行原文停留在输入区。现已在发送前增加真实空输入框检查：绑定新 pane、terminal ID、名称、idle 与完成序列，连续两次识别标准 Claude 输入区及全 dim 的空框提示；每 150 ms 只读检查，20 秒截止，可取消。非空输入或无法识别的 UI 不发送，保留终端。诊断探针原样多行与 tab 单次提交后约 605 ms 进入 working，约 4.56 秒完成；该次带人工诊断等待，不作为冷启动基准。最终 release 的全新多行任务 **1/1 成功，13.34 秒确认执行，16.34 秒完成首轮**；该次从创建工作区开始计时，没有模型预热或再次发送。失败数据保留在 v2 文件中。[合成诊断证据](performance-baselines/2026-11-06-multiline-diagnosis.json)

此门槛兼容本次实测 Claude Code 标准输入框；未来终端 UI 或占位符样式变化可能触发安全超时。未对 Codex/Cursor 的真实启动作等价实测。

**发送与历史采集**：socket 消除 CLI 子进程后，已有 agent 追加消息返回仍约 305 ms，空闲完整历史约 225 ms，未达 10×。Herdr 的 prompt 提交自身包含等待；没有用可见屏幕替代完整历史来报相同语义的倍数。[Herdr prompt 实现](https://raw.githubusercontent.com/herdrdev/herdr/v0.9.5/src/app/api/agents.rs)

## 截图边界

缓存仅保存窗口元数据，不缓存像素。选择目标时提前准备；使用前验证 windowID/PID/尺寸，枚举期间 resize 最多重取一次；实际进程退出后拒绝旧窗口。v2 热查询 P50 0.458 ms / P95 1.891 ms，冷查询 117.90 ms（1 个样本）。外部生命周期探针按即时 Quartz 尺寸验证 resize，并在 helper 进程退出后约 1.58 ms 拒绝旧窗口。owner 不符拒绝在早期校准中单独验证。正式冷/热数值来自 [v2 的 capture.lookup 指标](performance-baselines/2026-11-06-optimized-final.json)。

早期校准保留了两项未通过的断言：resize 对比请求尺寸而非当时 Quartz 尺寸，NSWindow.close 也没有保证 WindowServer 对象实际销毁。后续改用外部 helper、即时 Quartz 和进程退出检查，并补上枚举完成后的尺寸重验；早期文件不作为当前 resize/销毁验收。

**完整截图没有成功基线。** v2 的等价采集管线 20/20、生产 capture 20/20、直启 bundle 3/3 均失败；直接启动报告 preflight=true，系统返回 -3811。通过 LaunchServices 打开同一 bundle 的截图诊断模式时，1/1 返回 preflight=false/屏幕录制未授权。两种启动方式获得的授权状态不同，未读取 TCC 内部归因；不能把直启结果当成正常 GUI 已授权，也不能认定正常应用的系统采集服务损坏。诊断模式仍不是交互点击截图验收。最终 release 打包后再次通过 LaunchServices 检查，仍返回未授权；两个版本各 1 次，均受权限拦截。已请求用户在系统设置授权，尚未获得授权完成的反馈；未重置 TCC、重启桌面进程或触碰用户 Captures。[v2 正常启动权限](performance-baselines/2026-11-06-capture-launchservices.json) · [最终包权限与哈希](performance-baselines/2026-11-06-capture-launchservices-final.json)

## 实现与验证

- workspace 创建、prompt、focus 使用本地 RPC；写入只派发一次，超时、断连、取消、错误或空响应不会再通过 CLI 重发。start 保留 CLI 的必要准备语义；CLI 子进程显式绑定与 RPC 相同的 `HERDR_SOCKET_PATH`，保留旧 `HERDR_SOCKET` 配置别名。
- Ghostty 每次从内核快照重新定位 Herdr TTY，后台发送公开 AppleEvent，保留权限、超时和应用未启动处理。独立组件 25/25 次精确命中，零 activate 兜底。
- 状态派生缓存保留值语义；排序保存 ID、搜索依赖定向失效、行展示只更新变化任务，并按当前时间计算等待时长。拖动结果按会话代次失效，drop 始终检查当前窗口。
- 最终全量 XCTest：Core 105 + Kit 87，共 192 项，190 通过、2 个 opt-in 真实测试跳过、0 失败，包含 socket 环境固定、取消、多行门槛、CRLF、未知/非空输入区和身份变化回归。不能以 mock 绿测替代真实任务成功。
- 最终 release 构建成功（480.26 秒），应用位于 `build/HerdrIsland.app`，`codesign --verify --deep --strict` 通过。已有 IslandPanel 的 NSEvent/Swift 6 Sendable 警告仍存在，当前语言模式为 Swift 5。
- v2 的 4 个真实探针 workspace 已清理，原 Ghostty terminal 读回核验恢复；最终创建验证的另 4 个 workspace 及全部合成窗口也已清理。最终轮未重复跳转测试。源码没有提交或推送。

## 数据与复跑

- [初始原始样本](performance-baselines/2026-11-06-appkit.json)
- [首轮 v1 样本与失败](performance-baselines/2026-11-06-optimized.json)
- [v2 样本、源码及产物哈希](performance-baselines/2026-11-06-optimized-final.json)
- [最终 release 创建验证](performance-baselines/2026-11-06-task-final-validation.json)
- [持续输出交错比较](performance-baselines/2026-11-06-changed-state-comparison.json)
- [精确终端组件 25 次](performance-baselines/2026-11-06-focus-component.json)
- [截图早期校准，非最终验收](performance-baselines/2026-11-06-capture-lookup.json) · [外部 resize/实际销毁](performance-baselines/2026-11-06-capture-lifecycle.json)

```bash
swift test -j 4
bash Scripts/make-app.sh
python3 Scripts/performance_baseline.py --output /tmp/island-performance.json --live-tasks --live-multiline
```

仅复查创建可加 `--tasks-only`，会跳过状态/窗口基准、追加消息与跳转。最终验证使用此模式；IslandCore archive 与 v2 SHA-256 完全相同，Source 变化仅限上述四个 HerdrKit 文件。

默认不调用模型；`--live-tasks` 创建 3 个固定文本 Claude 探针，发送追加消息并测试跳转；`--live-multiline` 另加 1 个多行任务。脚本在 finally 中只清理本次 journal 记录的 workspace。截图仅针对独立合成窗口，写临时目录，不触碰用户 Captures。`--capture-probe-window <windowID>` 为应用内部诊断模式，不请求权限、不创建任务，图像随后删除；通过 `open -n -W -a ... --args` 启动可验证正常应用身份。
