## [2026-04-27 18:33] | Task: Add Usage Day/Year switch

### 🤖 Execution Context

- **Agent ID**: `Codex`
- **Base Model**: `GPT-5`
- **Runtime**: `Codex CLI`

### 📥 User Query

> 参考截图里的 Day/Year 切换，在 Usage 支持切到 Day；随后 Day 里放类似 Screen Time 的 24 小时 token 柱状图，按模型颜色区分；小时上要有 hover，窗口调小时柱状之间的间距可以变小，最极端贴在一起；标题简化为 Tokens，堆叠柱内部不要有圆角；tooltip 只向上展开；legend 不要写死未出现的模型，并且要和柱状图有间距；横轴 24 改成 Hours，legend 居中且过多时换行继续居中。

### 🛠 Changes Overview

**Scope:** AgentBar settings Usage page and local token scanner

**Key Actions:**

- **[Action 1]**: 在 Usage header 增加 Day/Year segmented control，默认选中 Year。
- **[Action 2]**: 保留 Year 年度热力图、年份切换和汇总逻辑，切到 Day 时隐藏这些 Year-only 控件。
- **[Action 3]**: `CodexCostScanner` 新增今天 24 小时按模型聚合的 token usage API，并把 session 文件缓存扩展为 day/hour/model 聚合。
- **[Action 4]**: Day 视图新增小时级堆叠柱状图，横轴 00-24，纵轴显示 token 规模，底部按模型显示颜色图例。
- **[Action 5]**: 为 Day 小时柱增加 hover 命中与 tooltip，显示该小时 token 总量和模型拆分。
- **[Action 6]**: 取消 Day 图表固定 intrinsic width，并将设置窗口最小宽度降到 480pt；窗口变窄时柱间距逐步缩小，极窄时允许柱子贴合。
- **[Action 7]**: 将 Day 图表标题简化为 `Tokens`，并调整堆叠柱圆角：内部段和底部直角，只给最上方段的上两角圆角。
- **[Action 8]**: 调整 Day hover tooltip 位置，按鼠标点绘制指示三角，避免浮层压住当前指针。
- **[Action 9]**: 将 Day hover tooltip 固定为只向上展开，避免向下覆盖鼠标。
- **[Action 10]**: Day 图例和颜色不再预置 Claude/Gemini/Other，而是按当天实际出现的模型动态生成，并拉开 legend 与柱状图/横轴标签的底部间距。
- **[Action 11]**: 将 Day hover tooltip 提升到 Usage 页面级 overlay，避免高柱顶部 hover 时被图表 bounds 压低，并让同一小时内上下移动鼠标时 tooltip 持续跟随。
- **[Action 12]**: 将横轴末尾的 `24` 改成 `Hours`，并让 legend 按行居中，数量过多时自动换行且每行继续居中。
- **[Action 13]**: 在 Day 视图年份切换对应位置增加日期左右切换，按自然日加减处理跨月和跨年，并让小时图读取所选日期。
- **[Action 14]**: 将 Year 的年度汇总移动到年份切换同一行，Day 同一位置显示日汇总；随后去掉右侧文案里的重复日期/年份，只保留 `Total x Tokens` 格式的当前视图总量。
- **[Action 15]**: 更新架构、界面协作说明、稳定性/安全说明、质量评分和功能发布记录，记录 Usage 视图切换和 Day 图表行为。

### 🧠 Design Intent (Why)

Usage 的 Year 视图适合看长期趋势，但今天的峰值和模型构成需要更细粒度的时间轴。Day 视图复用本地 session `token_count` 增量，按事件 timestamp 分到 00-23 点，再用克制的原生自绘柱状图表达，不引入远程依赖或假数据。Day 图表不应该像年度热力图一样拥有固定自然宽度，否则会把整个设置窗口撑住；它应当随窗口宽度重排，把横向压力吸收到柱宽和柱间距里。

### 📁 Files Modified

- `Sources/AgentBar/AgentBarSettings.swift`
- `Sources/AgentBarCore/AgentBarCacheStore.swift`
- `Sources/AgentBarCore/CodexCostScanner.swift`
- `Tests/AgentBarCoreTests/CodexCostScannerTests.swift`
- `docs/ARCHITECTURE.md`
- `docs/FRONTEND.md`
- `docs/QUALITY_SCORE.md`
- `docs/RELIABILITY.md`
- `docs/SECURITY.md`
- `docs/releases/feature-release-notes.md`
- `docs/histories/2026-04/20260427-1833-usage-day-year-switch.md`
