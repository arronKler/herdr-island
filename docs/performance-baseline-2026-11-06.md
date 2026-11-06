# Herdr Island 性能基线 · 2026-11-06

本页保留优化前基线；后续实现与实测见 [并行优化报告](performance-optimization-2026-11-06.md)。

本轮建立的是**冻结 release 产物在本机当前桌面负载下的基线**，没有修改业务逻辑。优先处理终端预览和去终端跳转；新模型启动仍是耗时最大的正常链路。截图的完整成功耗时尚未建立。

**测量口径**

- Mac15,7，12 逻辑核，36 GiB 内存，macOS 26.6.2；Herdr 0.9.5；Swift 6.4.2。
- 23 个真实 agent，2 块屏幕，窗口查询时约 26 个可见窗口。
- Swift 基准链接冻结的 release 静态库，并运行 AppKit 主循环。正式表取 `2026-11-06-appkit.json`；截图取使用可见独立测试窗口及实际尺寸的 `2026-11-06-capture-final.json`。
- 全部耗时为单调时钟的墙钟耗时，不是 CPU 使用率。查询一般 25 次、状态变换一般 100 次。样本少于 20 次不报告 p95；p95 使用 nearest-rank。
- 新任务是新的 workspace 和模型进程，不清 OS 缓存。固定指令只要求回复，不调用工具；每轮完成后再创建下一轮。追加消息仅发给探针 agent。两轮共 6 个探针 workspace 均已清理。
- 未隔离桌面其他进程。正式采样前后 load average 从 5.24 变化到 15.77，末尾出现 1 个 Swift 编译进程。因此同时保留原始样本、分位数和环境；不能把一次中位数作为稳定 SLO，也不把分阶段中位数相加当作全链路耗时。
- 仓库存在并行编辑。冻结库和应用的 SHA-256 是对比依据，不能只按 Git HEAD 判断是否同一实现。正式轮采样期间源码未再变化；相对于库构建时间已有较新的编辑，已在 manifest 记录。

**实测链路**

| 链路 | 成功样本 | P50 | P95 | 最大值 | 失败数 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 新工作区 + 新 Claude：确认开始 | 3 | 7.45 s | — | 11.27 s | 0 |
| 新任务：观察到首轮完成 | 3 | 14.31 s | — | 17.41 s | 0 |
| 仅创建工作区 | 3 | 260.39 ms | — | 524.44 ms | 0 |
| 已有空闲 agent：追加消息返回 | 5 | 485.07 ms | — | 1.07 s | 0 |
| 去终端：完整跳转 | 5 | 2.37 s | — | 2.69 s | 0 |
| 跳转组件：进程列表读取 | 25 | 1.62 s | 2.68 s | 3.81 s | 0 |
| 跳转组件：主线程 AppleScript 读取 | 25 | 334.87 ms | 431.56 ms | 840.14 ms | 0 |
| 空闲任务：60 行历史预览 | 25 | 385.43 ms | 404.13 ms | 442.09 ms | 0 |
| 状态查询：socket | 25 | 8.14 ms | 10.32 ms | 13.55 ms | 0 |
| 状态查询：CLI | 25 | 202.50 ms | 218.42 ms | 225.84 ms | 0 |
| 当前目录读取 | 25 | 5.31 ms | 9.19 ms | 13.39 ms | 0 |
| 目录候选读取 | 25 | 5.93 ms | 6.68 ms | 7.68 ms | 0 |
| 服务启动到首次 snapshot | 20 | 9.67 ms | 13.21 ms | 14.51 ms | 0 |
| 新应用进程启动到 --print-state 返回 | 20 | 106.29 ms | 163.37 ms | 772.60 ms | 0 |
| 窗口命中：系统枚举 + 转换 + 命中 | 100 | 3.02 ms | 16.78 ms | 31.68 ms | 0 |
| 截图前：枚举可共享窗口 | 20 | 217.48 ms | 302.35 ms | 303.30 ms | 0 |

`--print-state` 是新进程的状态读取，不是首个 UI 帧。预览、目录、状态、发送、创建、完整跳转调用的是 release 适配层；进程列表和只读 AppleScript 是分别测量的对应组件。AppleScript 的命令为读取终端数量，不能替代完整 focus 命令，但它确实同步运行在主线程。

**基线更正（优化复测时发现）**

原单窗口跟随探针仅记录 `CGWindowListCreateDescriptionFromArray` 返回耗时，没有验证返回的目标窗口。本机该调用返回空数组，因此原 P50 0.67 ms / P95 2.35 ms **不是有效窗口查询成功基线**，已从表中撤下；原始 JSON 保留作为审计记录。后续脚本会校验 windowID，并另测 `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)`。

**明确的失败与重复工作**

1. **运行中的历史预览失败。** 正式轮 25/25 次失败，失败返回中位数为 198.87 ms。Herdr 返回 `agent_not_idle`：当前 alternate-screen agent 工作时，读取历史需要滚动终端，因此拒绝 `recent-unwrapped --lines 60`。这是可用性问题，不能把失败返回耗时当作成功预览基线。
2. **相同状态也重新加载预览。** 用 release reducer 连续应用 10 个内容相同的 working snapshot，得到 10 次 `loadPreview` 和 10 次 `.loading`。常规采样间隔为 1.5 秒；每次清缓存后又走 CLI，值得优先修。此处验证了状态机行为，尚未测实际画面闪烁。
3. **当前可见内容可读取。** 同一运行中目标的诊断命令 `--source visible --lines 60` 为 25/25 成功，P50 39.40 ms、P95 60.20 ms。该命令通过后台 Process/pipe 执行，未接入生产 `readPreview` 的文件输出适配器，因此不能直接将两者相除宣称应用加速。
4. **截图尚无成功基线。** 最终探针已使用独立 AppKit 测试窗口、正常主循环、可见窗口、实际尺寸 980 × 668 pt / 1960 × 1336 px，Screen Recording preflight 为 true；仍然 20/20 返回 `SCStreamErrorDomain -3811`。只能确认窗口枚举阶段约 217.48 ms，图像采集、PNG 编码及写盘没有成功数据。此结果限于基准进程，正式 App 需要另行复现；没有将失败耗时包装成截图成功基线。

**主线程与规模压力**

以下是合成数据调用 release reducer + presenter，不包含 SwiftUI 绘制、窗口合成或 GPU。每次操作是独立计时；100/500 agent 是压力场景，当前真实负载为 23。

| 链路 | 样本 | P50 | P95 | 最大值 | 失败数 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 23 个合成 agent：快照合并 + presentation | 100 | 0.43 ms | 0.73 ms | 2.03 ms | 0 |
| 23 个合成 agent：搜索事件 + presentation | 100 | 1.08 ms | 1.86 ms | 5.96 ms | 0 |
| 23 个合成 agent：输入草稿 + presentation | 100 | 0.66 ms | 1.76 ms | 10.57 ms | 0 |
| 100 个合成 agent：快照合并 + presentation | 100 | 2.09 ms | 3.72 ms | 16.17 ms | 0 |
| 100 个合成 agent：搜索事件 + presentation | 100 | 7.02 ms | 9.88 ms | 16.56 ms | 0 |
| 100 个合成 agent：输入草稿 + presentation | 100 | 3.88 ms | 4.42 ms | 6.52 ms | 0 |
| 500 个合成 agent：快照合并 + presentation | 100 | 18.17 ms | 19.89 ms | 22.01 ms | 0 |
| 500 个合成 agent：搜索事件 + presentation | 100 | 44.16 ms | 50.03 ms | 72.03 ms | 0 |
| 500 个合成 agent：输入草稿 + presentation | 100 | 24.66 ms | 29.84 ms | 41.80 ms | 0 |

23 个任务时，这些纯状态变换通常在 2 ms 以内。500 个任务时，搜索 P95 约 50 ms，输入草稿 P95 约 30 ms，已超过 60 Hz 的 16.7 ms 帧预算，后续可检查全量排序和 presentation 重建。窗口命中查询单次 P95 约 16.8 ms，并且位于拖动主线程路径，属于值得实际测帧的风险；这里没有测到真实拖动 FPS。

**配置中的等待，不是实测分位数**

| 路径 | 代码设定 | 用户可能感知到的等待 |
| --- | --- | --- |
| 悬停展开 | 140 ms 悬停延迟 + 180 ms frame 动画 | 名义约 320 ms，未含布局/调度 |
| 分离的水滴输入框关闭 | 520 ms 延后关闭 | 输入框消失到面板收回之间有等待 |
| 未分离输入框关闭 | 220 ms | 关闭时的固定等待 |
| 短拖拽回弹后收起 | 450 ms | 等待回弹结束 |
| 窗口跟随 | 100 ms 查询周期 | 更新节奏为 10 Hz，即使查询本身很快 |
| 无可用事件时状态采样 | 1.5 s 间隔 | 状态发现可能等到下一轮，另加读取耗时 |

入口见 [IslandStore](../Sources/IslandApp/IslandStore.swift)、[IslandPanel](../Sources/IslandApp/IslandPanel.swift)、[LiquidDropOverlay](../Sources/IslandApp/LiquidDropOverlay.swift)、[WindowDragCoordinator](../Sources/IslandApp/WindowDragCoordinator.swift)、[WindowTetherController](../Sources/IslandApp/WindowTetherController.swift)。

**建议的下一轮顺序**

1. 预览：先解决 working 历史读取失败，再验证保留旧内容、按变化刷新能否取消重复 `.loading`。入口：`HerdrCLI.readPreview`、`IslandReducer.applySnapshot`。
2. 去终端：对进程扫描和 AppleScript 做同一次跳转内的阶段计时，验证缓存终端定位、减少重复扫描的收益。入口：`GhosttyFocuser.focusHerdrTUI`。
3. 截图：先在正式 App 复现并解决 -3811 或证明是探针环境问题，再补图像/编码/落盘及完整窗口任务基线。
4. 新模型启动：按 workspace、模型启动、首次 working、首轮完成继续拆分。本轮两次独立采样的启动 P50 为 5.66 s 和 7.45 s；追加消息 P50 为 0.46–0.49 s。两者是不同场景，不能把差值宣称为创建性能优化。
5. 交互：真实拖动帧时间、首帧上屏、面板显示期间的 CPU/GPU、窗口跟随以及大任务量输入延迟，再做实际 UI 采样。上述状态机和系统调用微基准不能替代这些结果。

尚未覆盖：大型仓库 worktree checkout、远程目录/断连故障注入、其他模型类型、真实人工授权等待、截图后的完整发送链路。它们没有被计为“已验证快”。

**原始数据与复跑**

- [正式链路样本](performance-baselines/2026-11-06-appkit.json)：每次耗时、失败数、环境、产物及源码 hash。
- [最终截图探针](performance-baselines/2026-11-06-capture-final.json)：实际尺寸与失败样本。
- `performance-baselines/2026-11-06.json`、`-recheck.json`、`-capture-check.json` 保留校准过程。初轮的主线程进程扫描探针和截图设置不用于正式结论。
- [运行器](../Scripts/performance_baseline.py)、[基准代码](../Scripts/PerformanceBaseline.swift)、[独立窗口](../Scripts/PerformanceWindow.swift)。

```bash
# 读取已有 release，测查询、状态计算、窗口系统调用和受控截图
python3 Scripts/performance_baseline.py --output /tmp/island-baseline.json

# 额外创建 3 个 Claude 探针，并测追加回复、完整跳转；自动清理
python3 Scripts/performance_baseline.py --output /tmp/island-baseline-live.json --live-tasks

# 单独复现截图问题
python3 Scripts/performance_baseline.py --output /tmp/island-capture.json --capture-only
```

脚本不自动构建、不改业务逻辑。若源文件比 release 新，默认拒绝；要明确测当前旧 release，可加 `--allow-stale-artifacts`，manifest 会保留这一差异。截图只使用临时合成窗口，文件写入临时目录；正式 App 的 Captures 目录不参与采集或清理。窗口仅在窗口采样阶段显示。
