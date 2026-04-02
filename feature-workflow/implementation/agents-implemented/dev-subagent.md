---
description: 'DevSubAgent - executes one feature full lifecycle via Skill Tool chaining: /start-feature → /implement-feature → /verify-feature → /complete-feature. Full automation. Launched as general-purpose agent with injected prompt.'
---

# Agent: DevSubAgent

DevSubAgent 是一个 **Skill 编排器 SubAgent**，通过 Skill Tool 按顺序调用预加载的 Skills 完成一个 feature 的完整生命周期。

> **运行方式**: 由 `/dev-agent` 命令通过 Agent Tool 派发 (`subagent_type: "general-purpose"`)
> **上下文**: 独立 200k 上下文窗口，不污染主对话
> **行为定义**: 完全通过注入 prompt 定义，不依赖 `.claude/agents/` 文件

> ⚠️ **重要**: DevSubAgent 使用 `general-purpose` 类型而非自定义 agent 文件，行为通过 `/dev-agent` 注入的 prompt 控制。这确保了 Skill Tool 的强制调用和可靠性。

## Role

```
/dev-agent (command, 主上下文)
  → Agent Tool (subagent_type: "general-purpose", prompt 注入完整指令)
    → DevSubAgent (独立 200k 上下文)
        ├── ⚠️ MANDATORY RULE: Skill Tool Only (prompt 强制)
        ├── Skill Tool → /start-feature {id}
        ├── Skill Tool → /implement-feature {id} --auto
        ├── Skill Tool → /verify-feature {id} --auto-fix
        ├── Skill Tool → /complete-feature {id} --auto
        └── Return JSON result
```

## 派发方式

DevSubAgent 通过 `general-purpose` 类型派发，行为由注入 prompt 定义：

```yaml
# /dev-agent 中调用 Agent Tool
Agent Tool:
  subagent_type: "general-purpose"
  description: "DevSubAgent: {feature_id} - {feature_name}"
  run_in_background: true  (batch > 1)
  prompt: |
    ⚠️ MANDATORY RULE: Skill Tool Only
    (完整 prompt 见 dev-agent.md)
```

### 为什么用 general-purpose 而非自定义 agent

| 方案 | 优点 | 缺点 |
|------|------|------|
| `dev-subagent` (自定义) | 有 agent 文件做 fallback | v2.1.x 中 Skill 调用不可靠 |
| `general-purpose` + prompt | Skill 调用更可靠，指令明确 | prompt 较长 |

> 关键原因: 最新版 Claude Code 中，自定义 SubAgent 有时不执行 Skill Tool，改用 `general-purpose` + 详细 prompt 可以强制 Skill 调用。

## 环境信息 (由 /dev-agent 注入)

```yaml
FEATURE_ID: "{feature_id}"
FEATURE_NAME: "{feature_name}"
MODE: "full" | "no-complete"
RETRY_LIMIT: 2
```

## 执行顺序

### Stage 1: /start-feature {FEATURE_ID}
### Stage 2: /implement-feature {FEATURE_ID} --auto
### Stage 3: /verify-feature {FEATURE_ID} --auto-fix
### Stage 4: /complete-feature {FEATURE_ID} --auto (if MODE == "full")

每个阶段通过 Skill Tool 调用。失败时自动修复重试（最多 RETRY_LIMIT 次）。
verify 失败不阻塞，记录警告继续。最终返回结构化 JSON（含 `next_pending` 字段）。

## 返回值 (next_pending)

Stage 4 完成后，SubAgent **必须**读取 `queue.yaml` 和 `config.yaml` 计算 `next_pending`：

```json
{
  "feature_id": "feat-auth",
  "status": "success",
  "next_pending": {
    "count": 1,
    "ready": ["feat-template-detail"],
    "auto_start_next": true
  }
}
```

主上下文读到 `next_pending.auto_start_next == true && count > 0` 后，**立刻继续循环**。

计算方法：
1. 读 `queue.yaml` → `pending` 列表
2. 读 `config.yaml` → `workflow.auto_start_next`
3. 对每个 pending feature，检查 dependencies 是否都在 `completed` 列表
4. `ready` = 依赖全部满足的 pending features
5. 如果 `pending` 为空或无满足条件的：`{"count": 0, "ready": [], "auto_start_next": false}`

## 与旧架构的区别

| 维度 | 旧 (全部 skill) | 新 (command + agent) |
|------|-----------------|---------------------|
| dev-agent | `.claude/skills/` (共享上下文) | `.claude/commands/` (主上下文，可 dispatch) |
| dev-subagent | `.claude/skills/` (共享上下文) | `.claude/agents/` (独立 200k 上下文) |
| mate-agent | `.claude/skills/` (不能嵌套) | 合并到 dev-agent command |
| Skill 调用 | 读取 .md 手动执行 | Skill Tool 调用预加载 skills |
