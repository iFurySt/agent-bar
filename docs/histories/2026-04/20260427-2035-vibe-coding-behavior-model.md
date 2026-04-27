# Vibe Coding behavior model docs

## 用户诉求

对比 `SBTI-test` 的传播型测试风格，重新判断 `tmp/vibe_coding_behavior_scoring.md` 中的算法设计，并结合 agent-bar 当前代码与 Codex session 历史结构，形成可落地的算法和建模方案写入 docs。

## 本次改动

- 新增 `docs/design-docs/vibe-coding-behavior-model.md`。
- 明确产品方向：做诙谐、可传播、当天行为快照，而不是严肃人格测试或心理诊断。
- 对比 SBTI 的入口、结果、文案、类型和免责声明结构，提出 agent-bar 可借鉴与不应复用的边界。
- 梳理 Codex session JSONL 中可用的数据类型，包括 `session_meta`、`response_item`、`turn_context`、`event_msg.token_count`、命令/patch/collab/diff/plan 等事件。
- 将算法拆成 P0 稳定实现、P1 保守推断、P2 不建议依赖三层，并定义 MVP 评分公式、类型码和分享结果结构。

## 设计动机

原草案的指标方向合理，但仍偏严肃行为心理学描述。新的文档把指标模型和传播包装拆开：核心算法保持可解释、可本地计算，产品输出则使用类似 SBTI 的荒诞类型名、短句和分享卡，但不复用其具体素材和文案。

## 影响文件

- `docs/design-docs/vibe-coding-behavior-model.md`
- `docs/histories/2026-04/20260427-2035-vibe-coding-behavior-model.md`
