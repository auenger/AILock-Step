---
description: 'Design: DevAgent entry point command + DevSubAgent executor agent.'
---

# Agent Design: dev-agent + dev-subagent

> Status: 已实现 (v3 — command + agent 架构)
> 旧 MateAgent 已废弃，调度逻辑合并到 dev-agent command

## 架构 (v3)

基于 Claude Code v2.1.x 文档，使用 **command + agent** 架构替代全 skill 架构：

```
User → /dev-agent (command, .claude/commands/)
         │  ← 主上下文，可 dispatch SubAgent
         │
         └── Agent Tool → DevSubAgent (.claude/agents/)
              │  ← 独立 200k 上下文
              │
              ├── Skill Tool → /start-feature
              ├── Skill Tool → /implement-feature --auto
              ├── Skill Tool → /verify-feature --auto-fix
              └── Skill Tool → /complete-feature --auto
```

## 为什么废弃 MateAgent

| 问题 | 说明 |
|------|------|
| 嵌套限制 | v2.1.x 自定义 SubAgent 不能再派生 SubAgent |
| 不需要 | 调度逻辑在主上下文执行即可，不需要独立上下文 |

## 文件位置

| 组件 | 类型 | 位置 |
|------|------|------|
| dev-agent | Command (`.claude/commands/`) | `.claude/commands/dev-agent.md` |
| dev-subagent | Agent (`.claude/agents/`) | `.claude/agents/dev-subagent.md` |
| start-feature | Skill (`.claude/skills/`) | `.claude/skills/start-feature.md` |
| implement-feature | Skill (`.claude/skills/`) | `.claude/skills/implement-feature.md` |
| verify-feature | Skill (`.claude/skills/`) | `.claude/skills/verify-feature.md` |
| complete-feature | Skill (`.claude/skills/`) | `.claude/skills/complete-feature.md` |
| mate-agent | **已废弃** | 调度逻辑合并到 dev-agent |

## See Also

- 实现版: `agents-implemented/dev-agent.md`, `agents-implemented/dev-subagent.md`
- 设计文档: `docs/dev-agent-subagent-optimization.md`
