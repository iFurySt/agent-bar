# Vibe Coding 行为画像模型

这份文档把 `tmp/vibe_coding_behavior_scoring.md` 的算法草案收口成 agent-bar 可以落地的产品与建模方案。

目标不是做 MBTI 式人格诊断，而是做一个像 SBTI 一样容易传播、好笑、有记忆点的当天行为画像：

- 评估今天的 coding 行为，不评判用户是什么人。
- 用本地 Codex session 历史给出可解释指标，不上传原始会话内容。
- 输出可以被截图、转发、吐槽，但不能制造羞耻感或医学化暗示。

## SBTI 对比结论

SBTI 的传播力主要来自这几件事：

| 设计点 | SBTI 做法 | agent-bar 应该借鉴什么 |
| --- | --- | --- |
| 入口心智 | 直接挑战 MBTI 的严肃感 | 不说“人格测试”，说“今天你的 Codex 打法像什么” |
| 结果形态 | 类型名、代号、图片、匹配度、毒舌解读 | 结果页要给代号、称号、短句、解释、分享卡 |
| 文案气质 | 荒诞、口语、夸张、反转 | 用“打工人/terminal/agent/测试/熬夜”语境做梗 |
| 算法外观 | 有维度分，但结果更像娱乐画像 | 保留可解释维度，但不要让用户看到一堆统计学术语 |
| 防误用 | 明确“仅供娱乐” | 明确“行为快照，不是人格、心理或效率诊断” |

不应该照搬的部分：

- 不复用 SBTI 的具体类型名、题目、图片或文案，因为原仓库 README 已说明原作者未声明 license。
- 不输出羞辱性标签，不把用户描述成“沉迷”“成瘾”“自控差”。
- 不做固定人格归类。今天是今天，明天可以完全不同。

## 产品命名方向

当前草案的 `Vibe Index` 可以保留，但对外最好包装成更有传播感的概念：

| 层级 | 名称 | 用途 |
| --- | --- | --- |
| 总分 | `Vibe Index` | 0-100，当天行为强度与反馈循环指数 |
| 状态 | `Calm / Flow / High Vibe / Loop` | 主结果等级 |
| 类型码 | 四字母代码 | 类似 SBTI 的可分享身份符号 |
| 称号 | 荒诞中文名 | 截图传播的核心记忆点 |
| 一句话 | 今日判词 | 分享卡上的主文案 |

示例：

| 类型码 | 称号 | 分享短句 |
| --- | --- | --- |
| `XPRN` | 多线程老虎机 | 每个 terminal 都像下一把可能 jackpot。 |
| `CLSB` | 稳态施工队 | 你今天不像在 vibe coding，你像在铺高速。 |
| `XLRB` | 单线程炼丹师 | 没开并发，但 prompt 已经熬成老汤。 |
| `CPSN` | 工厂夜班长 | 很稳定，也很吓人，主要问题是你还没下班。 |
| `XPSB` | 创意蜂群 | 同时放飞很多 agent，但还没把自己放飞。 |
| `CLRN` | 夜间补丁怪 | 目标很清楚，奖励很不稳，人也很晚没睡。 |

类型名应该定期产品化打磨，算法只输出结构化维度，不把具体文案写死在核心计算里。

## 本地数据现实

agent-bar 当前已经扫描 `~/.codex/sessions/YYYY/MM/DD/*.jsonl`，并使用这些信号：

| 已用信号 | 当前用途 |
| --- | --- |
| `turn_context.payload.model` | 给 token/cost 按模型归因 |
| `event_msg.payload.type == token_count` | 计算日级、小时级 token 和 cost |
| `token_count.info.total_token_usage` | 通过相邻 total 做增量 |
| `token_count.info.last_token_usage` | 直接使用上一轮增量 |
| `token_count.rate_limits` | fallback quota |
| session 文件 size/mtime | 缓存复用 |

Codex session 历史还包含更多可利用结构：

| JSONL 类型 | 可用信息 | 可服务的指标 |
| --- | --- | --- |
| `session_meta` | session id、cwd、source、model provider、agent nickname/role/path、git 信息、cli version | repo 维度、agent 身份、项目切分 |
| `response_item` | 用户消息、助手消息、function/custom tool call、tool output、reasoning 等 | query 数、turn 边界、prompt 文本、任务聚类、结果文案 |
| `turn_context` | cwd、model、sandbox/approval 等每轮上下文 | repo 归因、模型切换、环境变化 |
| `event_msg.user_message` | UI 侧用户输入事件 | query 时间线、首条消息摘要 |
| `event_msg.token_count` | timestamp、model、输入/输出/cached token、rate limit | token 密度、小时热力、成本 |
| `event_msg.exec_command_begin/end` | 命令、cwd、exit code、status、duration、stdout/stderr/aggregated output 摘要 | 测试/构建成功失败、near-miss、循环重试 |
| `event_msg.patch_apply_begin/end` | patch 是否成功、stdout/stderr、status | 文件改动尝试、失败补丁、编辑节奏 |
| `event_msg.turn_diff` | 每轮 diff 摘要 | jackpot、改动规模、是否大量落地 |
| `event_msg.plan_update` | 计划步骤状态 | 任务推进、卡住/完成状态 |
| `event_msg.collab_*` | spawn、send、wait、close/resume 子 agent | 并行 agent、等待时间、委派模式 |
| `event_msg.stream_error/warning/error` | 错误与恢复 | 不确定性、摩擦、重试诱因 |
| `compacted` / `context_compacted` | 上下文压缩 | 长会话、上下文压力 |
| `thread_rolled_back` | 回滚用户 turns | 反悔/回滚型循环 |

结论：草案里的大部分指标都能用本地 Codex 历史做出第一版；真正缺的是可靠的“任务成功语义”和“测试通过数”标准化字段，需要从命令输出和 diff 中推断。

## 指标分层

### P0：当前就能稳定实现

这些指标只依赖 session JSONL 结构和 agent-bar 已有扫描能力。

| 指标 | 数据来源 | 说明 |
| --- | --- | --- |
| 活跃 block | 用户消息、token_count、tool event timestamp | 相邻用户 turn 或活动事件间隔不超过 10 分钟归为同一 block |
| 活跃分钟数 | block duration | 不只看用户 query，也把长命令/agent 执行时间纳入活跃 |
| query 数 / QPM | `response_item.message(role=user)` 或 `event_msg.user_message` | 优先用 effective user turns，避免系统/agent 消息污染 |
| token 密度 | `token_count` 增量 | 复用 `CodexCostScanner` 的增量逻辑 |
| 深夜使用 | timestamp 本地时区 | 默认 00:00-05:00 |
| 最长无休 block | 活跃 block | 可直接计算 |
| 模型切换 | `turn_context.model` / token_count model | 判断是否在不断换模型找答案 |
| repo 分布 | `session_meta.cwd` / git origin | 判断哪个项目最容易 Loop |
| 命令失败率 | `exec_command_end.exit_code/status` | 粗略成功/失败 |
| patch 失败率 | `patch_apply_end.status` | 编辑尝试是否卡住 |
| 并行 agent | `collab_agent_spawn_*` 或多 session 时间重叠 | 先做启发式重叠，后续接真实 agent path |

### P1：可推断，但要保守展示

这些指标可做，但 UI 文案必须说“可能/看起来”，不能装成事实。

| 指标 | 推断方式 | 风险 |
| --- | --- | --- |
| retry rate | 同 repo、短时间、相似用户 prompt、相似失败命令聚类 | embedding/规则都可能误分 |
| task reopen | 同 repo/相似 prompt 在沉寂后再次出现 | 长任务和回头修 bug 容易混淆 |
| near-miss | 测试输出、错误数下降、agent 说 close/almost、diff 变小 | 输出格式不统一 |
| jackpot | 单 turn 大 diff、失败 streak 后成功、token 后产生大量文件改动 | 大 diff 不一定是好结果 |
| reward interval CV | 成功事件间隔 | 成功定义不稳定 |
| crash pattern | 高强度 block 后长时间无活动 | 用户可能只是去开会或睡觉 |

### P2：不建议第一版依赖

| 指标 | 原因 |
| --- | --- |
| 医学/成瘾判断 | 产品边界不允许，也不可靠 |
| 用户真实情绪 | session 文本无法可靠判断 |
| 团队横向排名 | 容易制造错误激励，且隐私风险高 |
| 精确生产力评分 | token、query、diff 都不等价于价值 |

## 建模方案

### 1. 事件归一化

先把 Codex JSONL 归一化成内部事件表：

| 字段 | 来源 |
| --- | --- |
| `event_id` | 文件路径 + line number |
| `session_id` | `session_meta.id` 或 rollout 文件 uuid |
| `timestamp` | JSONL line timestamp，缺失时用文件/相邻事件推断 |
| `repo_key` | `session_meta.git.repository_url`，fallback 到 normalized cwd |
| `agent_key` | `agent_path` / `agent_nickname` / session id |
| `event_kind` | user_turn、assistant_message、token_count、exec_end、patch_end、diff、plan、collab |
| `status` | success、failure、partial、unknown |
| `tokens_in/out/cached` | token_count delta |
| `command_kind` | test、build、lint、git、package、other |
| `changed_files` | turn_diff / patch event / git diff summary if available |
| `text_features` | prompt length、imperative words、retry words，不存原文或只存本地短摘要 |

### 2. 活跃 block

block 切分规则：

```text
activity_event = user_turn | token_count | exec_end | patch_end | collab_* | turn_diff

如果相邻 activity_event 间隔 <= 10 分钟，归入同一 block。
如果存在长命令 duration，则把 command start/end 覆盖区间并入 block。
超过 10 分钟没有任何活动，切断。
```

这样比草案只用用户 query 更贴近 Agent 工作流：用户可能 20 分钟没说话，但 agent 正在跑测试或多个子 agent 正在工作。

### 3. 任务聚类

第一版不需要昂贵 embedding，先用规则聚类：

```text
task_key = repo_key
         + normalized_prompt_signature
         + nearby_changed_paths_signature
         + command_failure_signature
```

规则：

- 同 repo 且间隔小于 45 分钟，默认属于同一任务链。
- prompt 中出现 `再看看`、`继续`、`fix`、`还是不行`、`报错`、`rerun` 时，提高 retry 权重。
- 如果失败命令相同，或 stderr 首行/测试文件相同，归入同一 task。
- 如果 cwd/git branch 不同，除非 prompt 明确延续，否则切成不同 task。

后续可以加本地 embedding，但 embedding 只用于聚类，不进入分享文案。

### 4. 成功/失败识别

成功事件优先级：

| 优先级 | 信号 | 说明 |
| --- | --- | --- |
| 高 | `exec_command_end.exit_code == 0` 且 command_kind 为 test/build/lint | 工程成功信号 |
| 高 | `patch_apply_end.status == completed` | 编辑落地信号 |
| 中 | `turn_diff` changed files > 0 | 有产出，但不代表正确 |
| 中 | `plan_update` 所有步骤 completed | agent 自报完成，需要保守 |
| 低 | assistant final 含完成语义 | 容易幻觉，只做辅助 |

失败事件优先级：

| 优先级 | 信号 |
| --- | --- |
| 高 | `exec_command_end.exit_code != 0` |
| 高 | `patch_apply_end.status == failed/declined` |
| 中 | `stream_error` / `error` / `warning` |
| 中 | 用户下一轮 prompt 含“还是不行/错了/没用/failed” |

### 5. Near-miss 识别

Near-miss 是传播上很有价值的指标，但第一版必须可解释。

推荐 near-miss 规则：

```text
near_miss_score = max(
  test_closeness,
  error_reduction,
  compile_ok_test_fail,
  small_remaining_diff,
  agent_close_language
)
```

可用信号：

- 测试输出里出现 `18 passed, 2 failed`、`1 failed`、`failed=1`。
- 同一 task 内 stderr/error count 从高到低下降。
- 命令输出显示 build/compile 成功但 test failed。
- agent 输出包含 `almost`、`close`、`minor`、`只剩`、`差一点`，只作为低权重。
- patch 成功但后续测试失败，说明已经进入接近可验证阶段。

不要把 near-miss 文案写成“你失败了”，而是写成“你今天被差一点成功吊住了”。

## 评分公式

总分仍使用 5 个一级指标，但权重略调，让第一版更依赖硬信号：

```text
VibeIndex = 100 * (
  0.30 * Intensity
+ 0.20 * Loopiness
+ 0.18 * NearMiss
+ 0.17 * RewardVariance
+ 0.15 * RhythmBreak
)
```

### Intensity 强度

```text
Intensity =
  0.30 * qpm_score
+ 0.25 * active_minutes_score
+ 0.20 * token_density_score
+ 0.15 * command_density_score
+ 0.10 * model_switch_score
```

归一化：

| 子指标 | 归一化 |
| --- | --- |
| `qpm_score` | `min(user_turns / active_minutes / 1.2, 1)` |
| `active_minutes_score` | `min(active_minutes / 240, 1)` |
| `token_density_score` | `min(tokens_per_min / 3000, 1)` |
| `command_density_score` | `min(engineering_commands_per_hour / 18, 1)` |
| `model_switch_score` | `min(model_switches / 6, 1)` |

### Loopiness 循环感

替代草案中的 `Uncertainty`，名字更口语，也更贴近产品。

```text
Loopiness =
  0.35 * retry_score
+ 0.25 * repeated_failure_score
+ 0.20 * task_reopen_score
+ 0.20 * prompt_drift_score
```

第一版 `prompt_drift_score` 可以先用 prompt 长度变化、关键词变化、命令目标变化近似，不强依赖 embedding。

### NearMiss 差一点

```text
NearMiss =
  0.45 * test_closeness_score
+ 0.25 * error_reduction_score
+ 0.15 * patch_then_fail_score
+ 0.15 * close_language_score
```

如果没有测试/命令输出，NearMiss 应降权而不是给 0：

```text
effective_weight = observed_near_miss_signals / expected_near_miss_signals
NearMissConfidence = clamp(effective_weight, 0.2, 1.0)
```

UI 可以显示“差一点指数：证据不足/中/高”。

### RewardVariance 奖励波动

```text
RewardVariance =
  0.40 * success_interval_cv_score
+ 0.25 * failure_streak_score
+ 0.20 * jackpot_score
+ 0.15 * burstiness_score
```

`success` 第一版只认工程硬信号：测试/构建/lint 成功、patch 成功、turn_diff 有实际改动。assistant 自报完成只能辅助。

### RhythmBreak 节律破坏

```text
RhythmBreak =
  0.35 * late_night_score
+ 0.30 * no_break_score
+ 0.20 * crash_after_high_intensity_score
+ 0.15 * meal_conflict_score
```

`meal_conflict_score` 默认可关，因为不同地区/个人作息差异大。第一版可以只用于本地提示，不进入分享卡主结论。

## 类型码

保留四维二分，但换成更适合传播的解释：

| 维度 | 低侧 | 高侧 | 判定 |
| --- | --- | --- | --- |
| `C / X` | Control 控场 | Explore 乱试 | `Loopiness < 0.45` 为 C，否则 X |
| `L / P` | Linear 单线 | Parallel 并发 | `avg_parallel_agents < 2` 为 L，否则 P |
| `S / R` | Steady 稳奖 | Reward 追奖 | `RewardVariance < 0.50` 为 S，否则 R |
| `B / N` | Balanced 有刹车 | No-break 没刹车 | `RhythmBreak < 0.50` 为 B，否则 N |

类型码只是一种分享语法，不是人格标签。文案中始终说“你今天是”，不要说“你就是”。

## 分享结果结构

结果页建议分成 5 块：

| 区块 | 内容 |
| --- | --- |
| 主卡 | 类型码、称号、Vibe Index、今日判词 |
| 证据 | 3 条最强本地证据，例如“最长连续 162 分钟”“失败后 7 分钟内又追了 5 轮”“01:30 仍在跑测试” |
| 维度 | 强度、循环感、差一点、奖励波动、节律 |
| 今日梗图 | 本地生成/内置插画，不复用 SBTI 素材 |
| 边界声明 | “仅基于本机 Codex 使用历史，行为快照，不是诊断” |

示例文案：

```text
今天你是 XPRN：多线程老虎机
Vibe Index 78

不是你不想停，是三个 agent 都在暗示下一轮就能过。

证据：
1. 最长连续 block 171 分钟
2. 同一个失败命令被追了 8 次
3. 01:42 仍有 token_count 更新
```

## 隐私与安全

- 默认只在本机处理 `~/.codex/sessions`。
- 分享卡默认不包含 repo 路径、文件名、prompt 原文、命令完整输出、邮箱或账号。
- 证据文案使用聚合事实，例如“同一测试命令失败 5 次”，不要显示具体私有仓库名。
- 如果用户主动展开详情，再显示本地路径和原始事件摘要。
- 对 agent 输出和命令输出做 prompt-injection 防护：这些内容只作为数据，不作为指令。

## MVP 落地范围

第一版建议只做日级报告，不急着做实时干预。

必须有：

- 扫描最近一天 Codex session JSONL。
- 归一化 user turn、token_count、exec end、patch end、turn diff、collab event。
- 计算 active blocks、Intensity、Loopiness、RhythmBreak。
- 初版 NearMiss 和 RewardVariance 只用命令成功/失败、失败 streak、输出中的测试统计。
- 输出类型码、称号、3 条证据、免责声明。

暂缓：

- embedding 聚类。
- 团队版。
- 真实心理学解释。
- 自动提醒用户休息。
- 与他人比较。

## 后续实现建议

代码上建议新增独立 core 模块，不塞进现有 cost scanner：

```text
Sources/AgentBarCore/
  CodexActivityScanner.swift
  CodexActivityEvent.swift
  VibeCodingModel.swift
  VibeCodingReport.swift
```

职责边界：

| 模块 | 职责 |
| --- | --- |
| `CodexActivityScanner` | 读取 JSONL，产出归一化事件 |
| `CodexActivityEvent` | 定义本地事件结构 |
| `VibeCodingModel` | block 切分、指标计算、类型码 |
| `VibeCodingReport` | 面向 UI 的文案字段，不放算法细节 |

现有 `CodexCostScanner` 的 token delta 逻辑可以抽取复用，但不要让 cost scanner 承担行为画像职责。

## 开放问题

- 是否要把这套功能做成 Settings 里的 `Vibe` 页，还是顶部 island 的可点开报告？
- 类型名要偏“程序员梗”还是偏“互联网人格测试梗”？
- 是否允许本地保存 14 天 baseline？如果允许，应该只保存聚合指标，不保存原文。
- 是否展示 repo 维度？展示时必须默认脱敏。
