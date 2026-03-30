---
description: 'DevAgent entry point command - dispatches DevSubAgent(s) for automated feature development.'
---

# Agent: dev-agent

dev-agent 是自动化 feature 开发的**入口命令**，运行在主对话上下文中，负责调度 DevSubAgent(s)。

> **部署位置**: `.claude/commands/dev-agent.md`
> **运行方式**: 用户输入 `/dev-agent [feature-id] [--resume] [--no-complete]`
> **上下文**: 主对话上下文，可使用 Agent Tool 派发 SubAgent

## 架构

```
User → /dev-agent (command, 主上下文)
         │
         ├── /dev-agent feat-xxx       → Agent Tool → DevSubAgent (单个)
         ├── /dev-agent                 → Agent Tool → DevSubAgent × N (批量)
         └── /dev-agent --resume        → Agent Tool → DevSubAgent × N (恢复)
```

**dev-agent 合并了旧 MateAgent 的调度逻辑**，因为：
- 自定义 SubAgent 不能再派生 SubAgent（v2.1.x 限制）
- 调度必须在主上下文中执行（才能使用 Agent Tool）
- 不需要单独的 MateAgent

## 命令格式

```
/dev-agent                      # 批量模式
/dev-agent <feature-id>         # 单个模式
/dev-agent --resume             # 恢复模式
/dev-agent --no-complete        # 跳过 complete 阶段
```

## 调度循环

```
1. READ STATE (queue.yaml + config.yaml)
2. EVALUATE CANDIDATES (依赖 + 优先级 + 并行限制)
3. PICK BATCH (取前 N 个)
4. LAUNCH SUBAGENTS (Agent Tool, 批量并行)
5. COLLECT RESULTS (成功/失败)
6. AUTO-LOOP (继续下一批 pending)
```

## Agent Tool 调用

```
Agent Tool:
  subagent_type: "dev-subagent"
  description: "DevSubAgent: {feature_id}"
  run_in_background: true  (batch > 1)

  prompt: |
    FEATURE_ID: {id}
    FEATURE_NAME: {name}
    MODE: {full | no-complete}
    RETRY_LIMIT: 2
```

## 错误处理

| 场景 | 处理 |
|------|------|
| SubAgent error | 记录诊断，re-queue，继续其他 feature |
| 所有 pending blocked | 报告阻塞原因，暂停 |
| queue.yaml 损坏 | 停止，报错 |

## 与其他组件的关系

```
.claude/commands/dev-agent.md     ← 本文件 (入口，主上下文)
    → dispatches via Agent Tool
        .claude/agents/dev-subagent.md  ← 执行器 (独立上下文)
            → Skill Tool 调用:
                .claude/skills/start-feature.md
                .claude/skills/implement-feature.md
                .claude/skills/verify-feature.md
                .claude/skills/complete-feature.md
```
