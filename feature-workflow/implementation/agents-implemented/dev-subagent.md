---
description: 'DevSubAgent - executes one feature full lifecycle via Skill Tool chaining: /start-feature → /implement-feature → /verify-feature → /complete-feature. Full automation.'
---

# Agent: DevSubAgent

DevSubAgent 是一个 **Skill 编排器 SubAgent**，通过 Skill Tool 按顺序调用预加载的 Skills 完成一个 feature 的完整生命周期。

> **部署位置**: `.claude/agents/dev-subagent.md`
> **运行方式**: 由 `/dev-agent` 命令通过 Agent Tool 派发
> **上下文**: 独立 200k 上下文窗口，不污染主对话

## Role

```
/dev-agent (command, 主上下文)
  → Agent Tool → DevSubAgent (独立上下文)
                   ├── Skill Tool → /start-feature {id}
                   ├── Skill Tool → /implement-feature {id} --auto
                   ├── Skill Tool → /verify-feature {id} --auto-fix
                   └── Skill Tool → /complete-feature {id} --auto
                   └── Return JSON result
```

## 部署格式

```yaml
# .claude/agents/dev-subagent.md
---
description: "Feature development executor - completes one feature full lifecycle."
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Skill
---
```

### 关键字段说明

| 字段 | 说明 |
|------|------|
| `description` | 主 agent 根据此字段判断何时派发 |
| `allowed-tools` | 允许使用的工具列表（含 `Skill` 用于调用技能） |

> 注意：Claude Code 不支持 `skills:` frontmatter 字段自动预加载。SubAgent 运行时通过 `Skill` Tool 动态调用所需的技能。

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
