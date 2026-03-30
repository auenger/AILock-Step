# Feature Workflow

基于 Git Worktree 的多需求并行开发工作流，核心架构: **一个 Feature = 一个 Worktree = 一个独立开发环境**。

## 核心理念

- **项目上下文**: 通过 PM Agent 建立项目上下文，确保 AI 开发一致性
- **并行开发**: 支持多个需求同时开发，通过 worktree 物理隔离
- **自动调度**: 根据优先级自动安排开发顺序
- **状态追踪**: 通过 queue.yaml 统一管理需求状态
- **文档驱动**: 每个需求包含 spec/task/checklist 三个文档
- **归档策略**: 完成后创建 tag 归档，删除 worktree 和分支

## 架构 (v3)

基于 Claude Code v2.1.x 的 **Command + Agent + Skill** 三层架构：

```
User → /dev-agent (Command, 主上下文)
         │  ← 调度：读取队列、评估依赖、批量派发
         │
         ├── Agent Tool → DevSubAgent (Agent, 独立 200k 上下文)
         │                    ├── Skill Tool → /start-feature
         │                    ├── Skill Tool → /implement-feature --auto
         │                    ├── Skill Tool → /verify-feature --auto-fix
         │                    └── Skill Tool → /complete-feature --auto
         │
         └── Agent Tool → DevSubAgent × N (批量并行, run_in_background)
```

**MateAgent 已废弃** — v2.1.x 不支持 SubAgent 嵌套，调度逻辑合并到 dev-agent Command。

## 目录结构

```
{project-root}/
├── .claude/                          ← Claude Code 部署目录
│   ├── commands/
│   │   └── dev-agent.md              ← /dev-agent 入口命令（主上下文）
│   ├── agents/
│   │   └── dev-subagent.md           ← DevSubAgent 执行器（独立 200k 上下文）
│   └── skills/                       ← 11 个 Skill
│       ├── start-feature.md
│       ├── implement-feature.md      ← 支持 --auto
│       ├── verify-feature.md         ← 支持 --auto-fix
│       ├── complete-feature.md       ← 支持 --auto-resolve / --auto
│       ├── new-feature.md
│       ├── list-features.md
│       ├── block-feature.md
│       ├── unblock-feature.md
│       ├── feature-config.md
│       ├── cleanup-features.md
│       └── pm-agent.md
│
├── feature-workflow/                 ← 工作流设计 + 配置
│   ├── config.yaml                   ← 项目配置（并行数、命名规则、归档策略）
│   ├── queue.yaml                    ← 状态中心（active/pending/blocked/completed）
│   ├── templates/                    ← 文档模板（spec.md, task.md, checklist.md）
│   ├── implementation/               ← 设计文档 + 实现参考
│   │   ├── core-lib.md               ← 共享工具函数、Git 命令参考、错误码
│   │   ├── skills/                   ← Skill 设计文档
│   │   ├── skills-implemented/       ← Skill 实现参考
│   │   ├── agents/                   ← Agent 设计文档
│   │   └── agents-implemented/       ← Agent 实现参考
│   ├── docs/                         ← 架构设计文档
│   ├── tests/                        ← 测试文档
│   ├── workflow-spec.md              ← 完整工作流规范
│   └── README.md                     ← 本文件
│
├── features/                         ← 需求目录
│   ├── pending-feat-xxx/             ← 等待中
│   ├── active-feat-xxx/              ← 进行中
│   └── archive/                      ← 归档区
│       ├── archive-log.yaml          ← 归档日志
│       └── done-feat-xxx/            ← 已完成
│
└── src/

{project-root}-feat-xxx/              ← worktree（同级目录）
```

## 命令列表

### /dev-agent（入口命令）

| 用法 | 说明 |
|------|------|
| `/dev-agent` | 批量模式：自动调度所有 pending features |
| `/dev-agent feat-xxx` | 单 feature 模式：执行指定 feature |
| `/dev-agent --resume` | 恢复模式：从断点继续 |
| `/dev-agent --no-complete` | 跳过 complete 阶段 |

### Skills

| 命令 | 功能 | 自动化标志 |
|------|------|-----------|
| `/new-feature <描述>` | 创建需求 | — |
| `/start-feature <id>` | 启动开发（分支 + worktree） | — |
| `/implement-feature <id>` | 实现代码 | `--auto` 跳过确认 |
| `/verify-feature <id>` | 验证完成 | `--auto-fix` 自动修复 |
| `/complete-feature <id>` | 完成归档 | `--auto-resolve` 自动冲突解决 |
| `/list-features` | 查看所有需求状态 | — |
| `/block-feature <id>` | 阻塞需求 | — |
| `/unblock-feature <id>` | 解除阻塞 | — |
| `/feature-config` | 修改配置 | — |
| `/cleanup-features` | 清理无效 worktree | — |
| `/pm-agent` | 建立/更新项目上下文 | — |

## 完整开发流程

### 手动模式

```
/pm-agent                 建立项目上下文
      ↓
/new-feature              创建需求（对话 → 文档 → 队列）
      ↓
/start-feature            启动开发（分支 → worktree）
      ↓
/implement-feature        实现代码（spec → task → 写代码）
      ↓
/verify-feature           验证功能（checklist → 测试）
      ↓
/complete-feature         完成需求（提交 → 合并 → tag → 归档）
```

### 自动模式

```
/dev-agent feat-xxx → DevSubAgent
                        ├── start (分支 + worktree)
                        ├── implement --auto (写代码)
                        ├── verify --auto-fix (测试 + 自动修复)
                        ├── complete --auto (合并 + 自动冲突解决 + tag + 归档)
                        └── return JSON result

/dev-agent → 批量启动 DevSubAgent × N → 自动循环
```

## 全自动原则

- DevSubAgent 全程无人值守（独立 200k 上下文，不污染主对话）
- 测试失败 → 自动修复代码 → 重跑测试（最多 2 次）
- Rebase 冲突 → 智能分析 → 自动合并 → 重新验证
- 多次重试仍失败 → 返回 error（附带详细诊断），不阻塞其他 feature

## 状态流转

```
/new-feature → pending-feat-xxx/ → queue.yaml(pending)
                    ↓
/start-feature → active-feat-xxx/ → queue.yaml(active) + worktree
                    ↓
/complete-feature → archive/done-feat-xxx/ → archive-log.yaml + tag
```

## 归档策略

- 创建归档 tag（格式: `feat-auth-20260302`）
- 删除 worktree（释放空间）
- 删除分支（可通过 tag 恢复）
- 更新 archive-log.yaml

## 关键文件路径

| 文件 | 位置 | 说明 |
|------|------|------|
| config.yaml | feature-workflow/ | 项目配置 |
| queue.yaml | feature-workflow/ | 调度队列（状态中心） |
| archive-log.yaml | features/archive/ | 归档日志 |
| templates/ | feature-workflow/ | 文档模板 |
| project-context.md | {project-root}/ | 项目上下文（由 /pm-agent 生成） |
| core-lib.md | feature-workflow/implementation/ | 共享工具函数 |

## 实现状态

- Phase 1-4: Skills + Workflows + Agents — 全部完成
- Phase 5: SubAgent 架构优化（Command + Agent v3）— 已完成
- MVP 流程测试 100% 通过
