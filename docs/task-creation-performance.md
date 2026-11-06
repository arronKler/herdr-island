# 新任务链路性能实测

这是本轮早期实验记录，保留当时的实现与失败情况。后续并行优化、测试修复及当前验证结果见 [完整性能报告](performance-optimization-2026-11-06.md)；下文“当前”均指该次早期实验。

2026-11-06，本机 Herdr 0.9.5，项目目录 `herdr-island`。

## 结果与边界

| 指标 | 原 CLI 路径 | 直接 socket 路径 | 比值 |
| --- | ---: | ---: | ---: |
| 状态查询中位数 | 147.18 ms | 8.37 ms | 17.6× |
| 状态查询 p95 | 398.03 ms | 64.11 ms | 6.2× |

同一进程中的 Swift 基准交替执行两种路径，各 30 次；每次均读取真实 Herdr 并解析为相同的 Agent 模型。耗时包含 IPC、解码，以及 CLI 路径的进程启动和临时文件开销。p95 取排序后的第 29 个样本。没有用 mock 延时计算加速比。

完整冷启动另测一次：从调用 `createTask` 到确认新 Claude 为 working，耗时 **12.989 秒**。创建工作区占 **0.327 秒**；收到 working 事件到返回确认约 **1.02 ms**。测试创建的 workspace 已关闭。

**完整创建链路尚未达到 10×。** 原有日志的冷启动在约 9–21 秒之间波动；这些历史样本不是本次交替基准，不能据此宣称端到端加速。查询中位数的 17.6× 也不能替代冷启动指标。

## 改动

- `agent.list` 和 `pane.list` 直接走本地 Unix socket，取消查询时停止等待；不阻塞主线程。读取有期限、响应 ID 校验及大小限制。
- 直接读取不可用时回退 CLI，并冷却 10 秒再探测。写操作继续走 CLI，不因响应不确定而自动重复创建或提交。
- 启动前订阅新 pane，创建确认复用状态事件及现有 1.5 秒采样，取消原先独立的每 400 ms 一次 CLI 查询。无事件连接时由采样兜底。
- 订阅重建取消的读取不会被显示成后端故障。授权阻塞仍交由用户在终端处理。

## 未采用的预热实验

空闲模型被标记为 ready 后发送首条任务，仍触发约 5.85 秒的提交失败。另一种方案先让模型完成一轮初始化回复：准备用了 38.58 秒，随后提交用了 2.20 秒。它需要额外的模型调用与常驻资源，也没有证明稳定的端到端 10×，因此未加入默认流程。

当前主要剩余耗时在 Herdr / Claude 的启动及首次处理。要达到完整冷启动 10×，需要进一步优化这一段；仅减少 Island 查询或移动等待发生的时间不足以达到目标。

## 复现

```bash
# 只读对比
ISLAND_BENCHMARK_READS=1 swift test --filter TaskCreationPerformanceTests/testLiveReadTransport

# 一个真实 Claude 任务，确认启动后清理该测试 workspace
ISLAND_BENCHMARK_CREATE=1 swift test --filter TaskCreationPerformanceTests/testLiveTaskCreation
```

基准在普通测试中默认跳过。第二条命令会实际调用模型；固定任务只要求回复，不使用工具或编辑文件。

## 验证状态

- HerdrKit 69 项普通测试通过，2 项实时基准默认跳过；两项基准已另行启用并成功执行。
- 覆盖 socket 分片、错误响应、断线回退、超时、取消，以及启动事件确认、无事件连接时的采样兜底、授权阻塞和禁止重复提交。
- 当前全量测试并非全绿：重新核对后，`PreviewDigestTests.testFixtureQuestionIsTheApprovalLine` 仍失败。当前 `Fixtures.blockedPreview` 已是另一段终端输出，断言仍期待 `Allow Codex to run this command?`，实际得到 `success。`。本次性能改动未调整这份预览 fixture。
