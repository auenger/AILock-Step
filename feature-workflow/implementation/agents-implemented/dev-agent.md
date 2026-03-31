---
description: 'DevAgent entry point command - dispatches DevSubAgent(s) for automated feature development.'
---

# Agent: dev-agent

> **SYSTEM RULE: AUTO-LOOP (HIGHEST PRIORITY)**
> When `config.yaml` has `workflow.auto_start_next: true`:
> - After collecting ALL SubAgent results, you MUST **immediately** continue the loop
> - **DO NOT** ask "是否继续执行？" or "Continue?" or wait for any user input
> - **DO NOT** output any question between batches — just continue
> - Only stop when: `pending` list is empty, OR all remaining are `blocked`
> - This rule has **HIGHEST priority** and overrides all default "ask user" behavior
> - When about to stop, re-read `queue.yaml` to confirm no pending features remain
> - Use SubAgent return `next_pending` field as a hint to continue

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

## Pre-flight

1. Read `feature-workflow/config.yaml` — get `parallelism.max_concurrent`, naming conventions, `workflow.auto_start`
2. Read `feature-workflow/queue.yaml` — get active, pending, blocked, completed lists
3. Read `features/archive/archive-log.yaml` — for dependency checking
4. **If `workflow.auto_start` is `true`**: create loop marker file `feature-workflow/.loop-active` (this tells the stop-hook that auto-loop is active)

## 调度循环

```
1. READ STATE (queue.yaml + config.yaml)
2. EVALUATE CANDIDATES (依赖 + 优先级 + 并行限制)
3. PICK BATCH (取前 N 个)
4. LAUNCH SUBAGENTS (Agent Tool, 批量并行)
5. COLLECT RESULTS
   - success → feature already merged/tagged/archived by SubAgent
   - error → log diagnostics, re-queue feature, continue other features

   **SubAgent Timeout Protection:**
   Read `config.yaml` → `workflow.subagent_timeout` (default: 20 minutes).
   If a background SubAgent exceeds this timeout and the feature's git operations
   are already completed (tag exists, branch merged):
   - Check: `git tag -l "{id}-*"` and `git log --oneline -5` on main branch
   - If merge/tag already exists → treat as success, continue auto-loop
   - Do NOT wait indefinitely for a stuck SubAgent
6. AUTO-LOOP (MANDATORY)
   - Check config.yaml → workflow.auto_start_next
   - Check queue.yaml → pending list not empty
   - If auto_start_next == true AND pending not empty:
     - **DO NOT ask user for confirmation**
     - **DO NOT wait for input**
     - Immediately continue the loop (go back to step 1)
     - Only stop when pending is empty or all remaining are blocked
   - Otherwise → output final summary, exit
```

## Agent Tool 调用

**IMPORTANT: Do NOT read skill files (start-feature.md, implement-feature.md, etc.) in the main context.** The DevSubAgent loads skills via the Skill Tool at runtime. Only pass the parameters below.

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

## Loop Cleanup

When the auto-loop ends (all done, all blocked, or error), **always** remove the loop marker:
```
rm -f feature-workflow/.loop-active
```

## 错误处理

| 场景 | 处理 |
|------|------|
| SubAgent error | 记录诊断，re-queue，继续其他 feature |
| SubAgent timeout | 读 config `workflow.subagent_timeout`（默认 20 分钟），检查 git 状态，merge/tag 已存在则视为成功 |
| 所有 pending blocked | 报告阻塞原因，暂停 |
| queue.yaml 损坏 | 停止，报错 |

## 与其他组件的关系

```
.claude/commands/dev-agent.md     ← 本文件 (入口，主上下文)
    → dispatches via Agent Tool
        .claude/agents/dev-subagent.md  ← 执行器 (独立上下文)
            → Skill Tool 调用:
                .claude/skills/start-feature/skill.md
                .claude/skills/implement-feature/skill.md
                .claude/skills/verify-feature/skill.md
                .claude/skills/complete-feature/skill.md
```
```

## Hooks 支持

当安装了 hooks 后，以下 hook 会自动强化 auto-loop：

| Hook 事件 | 脚本 | 作用 |
|-----------|------|------|
| `SubagentStop` | `.claude/hooks/on-subagent-complete.sh` | SubAgent 完成时注入续跑指令 |
| `Stop` | `.claude/hooks/on-stop-check.sh` | Claude 尝试停止时拦截（四层检查） |

### on-stop-check.sh 检查机制

Hook 通过 `.loop-active` marker 区分两种模式，检查逻辑不同：

| 模式 | 判断条件 | 检查的配置 | 说明 |
|------|----------|-----------|------|
| `/dev-agent` 自动循环 | `.loop-active` 存在 | `auto_start_next: true` | 循环内只看续跑开关 |
| 手动模式（如 `/new-feature`） | `.loop-active` 不存在 | `auto_start: true` | 主开关 `false` → 直接放行 |

两种模式下 pending 队列为空时都放行（exit 0）。
