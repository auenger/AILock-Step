---
description: 'Design: Development SubAgent (DevSubAgent) - Skill orchestrator launched as general-purpose agent with injected prompt for reliable Skill Tool execution.'
---

# Agent Design: DevSubAgent

> Status: Design (see `agents-implemented/dev-subagent.md` for implementation)

## Overview

DevSubAgent 是一个 **Skill 编排器**，通过 Skill Tool 按顺序调用已注册的 `.claude` Skills 完成一个 feature 的完整生命周期。

**Core Principle: 通过 Skill Tool 调用，不读文档，不重复实现。**

> ⚠️ **v3.1 变更**: 改用 `general-purpose` agent 类型 + 详细注入 prompt，解决自定义 SubAgent 不执行 Skill 的问题。

## Architecture

```
/dev-agent → Agent Tool (subagent_type: "general-purpose")
              │
              └── DevSubAgent (独立 200k 上下文)
                  │  ⚠️ MANDATORY RULE: Skill Tool Only
                  │
                  ├── Skill Tool → /start-feature {id}
                  ├── Skill Tool → /implement-feature {id} --auto
                  ├── Skill Tool → /verify-feature {id} --auto-fix
                  ├── Skill Tool → /complete-feature {id} --auto
                  └── Return JSON result
```

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent 类型 | `general-purpose` + prompt 注入 | 自定义 SubAgent 在新版中 Skill 调用不可靠 |
| Implementation | 委托给 Skills，不重复实现 | 单一数据源，Skills 改了自动跟进 |
| Automation | 通过 `--auto` / `--auto-fix` / `--auto-resolve` 标志 | 与手动路径共用同一套 Skills |
| Prompt 策略 | 详细 prompt（含 MANDATORY RULE + DO NOT 指令） | 强制 SubAgent 通过 Skill Tool 执行 |
| Error handling | 自动修复+重试（最多2次），verify 失败不阻塞 | 全自动原则 |

## Replaces

| Old Component | Reason |
|---------------|--------|
| `dev-agent` (old, in-session) | Context isolation via SubAgent |
| `start-feature-agent.sh` | Native Agent Tool |
| `dev-subagent` (custom agent file) | 改用 general-purpose + prompt |

## Skill Chain

```
start-feature {id}
  → implement-feature {id} --auto
    → verify-feature {id} --auto-fix
      → complete-feature {id} --auto
```

## See Also

- Implementation: `agents-implemented/dev-subagent.md`
- Entry point: `agents-implemented/dev-agent.md`
- Design doc: `docs/dev-agent-subagent-optimization.md`
