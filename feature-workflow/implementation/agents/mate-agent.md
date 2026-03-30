---
description: 'Design: MateAgent - DEPRECATED. Scheduling logic merged into dev-agent command due to v2.1.x SubAgent nesting limitation.'
---

# Agent Design: MateAgent (DEPRECATED)

> **Status: 已废弃 (v3)**
> 调度逻辑已合并到 `.claude/commands/dev-agent.md`
> 原因: Claude Code v2.1.x 自定义 SubAgent 不支持嵌套（不能在 SubAgent 中再派生 SubAgent）

## 废弃原因

| 问题 | 说明 |
|------|------|
| **嵌套限制** | MateAgent 如果是 SubAgent，就无法再启动 DevSubAgent |
| **不需要** | 调度逻辑（读取队列、评估依赖、批量启动）在主上下文执行即可 |
| **简化** | 一个 `/dev-agent` command 同时承担入口和调度角色 |

## 迁移映射

| 旧组件 | 新组件 |
|--------|--------|
| `.claude/agents/mate-agent.md` | 不存在，已废弃 |
| `.claude/skills/mate-agent.md` | 不存在，已删除 |
| MateAgent 调度循环 | `.claude/commands/dev-agent.md` 内的 batch mode |
| MateAgent 评估逻辑 | `/dev-agent` command 直接实现 |

## See Also

- 替代方案: `.claude/commands/dev-agent.md`
- 执行器: `.claude/agents/dev-subagent.md`
