---
description: 'Design: Development SubAgent (DevSubAgent) - Skill orchestrator that chains start → implement → verify → complete in sequence with full automation.'
---

# Agent Design: DevSubAgent

> Status: Design (see `agents-implemented/dev-subagent.md` for implementation)

## Overview

DevSubAgent 是一个 **Skill 编排器**，通过 Skill Tool 按顺序调用已注册的 `.claude` Skills 完成一个 feature 的完整生命周期。

**Core Principle: 通过 Skill Tool 调用，不读文档，不重复实现。**

## Architecture

```
DevSubAgent
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
| Implementation | 委托给 Skills，不重复实现 | 单一数据源，Skills 改了自动跟进 |
| Automation | 通过 `--auto` / `--auto-fix` / `--auto-resolve` 标志 | 与手动路径共用同一套 Skills |
| Prompt size | 极简（~80行） | 只定义调度顺序和规则，不包含操作细节 |
| Error handling | 自动修复+重试（最多2次），verify 失败不阻塞 | 全自动原则 |

## Replaces

| Old Component | Reason |
|---------------|--------|
| `dev-agent` (old, in-session) | Context isolation via SubAgent |
| `start-feature-agent.sh` | Native Agent Tool |

## Skill Chain

```
start-feature {id}
  → implement-feature {id} --auto
    → verify-feature {id} --auto-fix
      → complete-feature {id} --auto
```

## See Also

- Implementation: `agents-implemented/dev-subagent.md`
- Scheduler: `agents-implemented/mate-agent.md`
- Entry point: `agents-implemented/dev-agent.md`
- Design doc: `docs/dev-agent-subagent-optimization.md`
