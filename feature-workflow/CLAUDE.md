# Feature Workflow - Claude Code 初始化指南

## 项目概述

基于 Git Worktree 的 AI 辅助开发工作流系统，核心架构: **一个 Feature = 一个 Worktree = 一个独立开发环境**。

## 架构 (v3)

基于 Claude Code v2.1.x 的 **Command + Agent + Skill** 三层架构：

```text
User → /dev-agent (Command, .claude/commands/)
         │  ← 主上下文，负责调度（读取队列、评估依赖、批量派发）
         │
         └── Agent Tool → DevSubAgent (.claude/agents/)
              │  ← 独立 200k 上下文，不污染主对话
              │
              ├── Skill Tool → /start-feature {id}
              ├── Skill Tool → /implement-feature {id} --auto
              ├── Skill Tool → /verify-feature {id} --auto-fix
              ├── Skill Tool → /complete-feature {id} --auto
              └── Return JSON result
```

**设计决策：**

* DevSubAgent 是 **Skill 编排器**，通过 Skill Tool 调用预加载的 Skills，不重复实现逻辑

* MateAgent 已废弃 — v2.1.x 不支持 SubAgent 嵌套，调度逻辑合并到 dev-agent Command

* 并行开发：`/dev-agent` 通过 Agent Tool 批量派发 DevSubAgent × N（`run_in_background: true`）

## 目录结构

```text
{project-root}/
├── .claude/                          ← Claude Code 部署目录
│   ├── commands/
│   │   └── dev-agent.md              ← /dev-agent 入口命令（主上下文）
│   ├── agents/
│   │   └── (dev-subagent.md 已删除)   ← DevSubAgent 行为由 dev-agent.md 注入 prompt 定义
│   └── skills/                       ← 12 个 Skill
│       ├── start-feature.md
│       ├── implement-feature.md      ← 支持 --auto
│       ├── verify-feature.md         ← 支持 --auto-fix
│       ├── complete-feature.md       ← 支持 --auto-resolve / --auto
│       ├── query-archive.md          ← 渐进式归档查询（索引 → SubAgent 深度加载）
│       ├── new-feature.md
│       ├── list-features.md
│       ├── block-feature.md
│       ├── unblock-feature.md
│       ├── feature-config.md
│       ├── cleanup-features.md
│       └── pm-agent.md
│
├── feature-workflow/
│   ├── config.yaml                   ← 主配置（项目名、并行数、Git 策略、归档规则）
│   ├── config.yaml.example           ← 配置模板
│   ├── queue.yaml                    ← 状态中心：active / pending / blocked / completed / parents
│   ├── templates/                    ← 文档模板（spec.md, task.md, checklist.md, project-context.md）
│   ├── docs/                         ← 架构设计文档
│   │   ├── dev-agent-subagent-optimization.md
│   │   └── dev-agent-subagent-implementation-plan.md
│   ├── scripts/
│   │   └── start-feature-agent.sh    ← [DEPRECATED] 已被 /dev-agent 替代
│   ├── implementation/
│   │   ├── core-lib.md               ← 共享工具函数、Git 命令参考、错误码定义
│   │   ├── skills/                   ← Skill 设计文档
│   │   ├── skills-implemented/       ← Skill 实现参考
│   │   ├── agents/                   ← Agent 设计文档
│   │   │   ├── pm-agent.md
│   │   │   ├── feature-manager.md
│   │   │   ├── dev-agent.md          ← dev-agent + dev-subagent 联合设计
│   │   │   ├── dev-subagent.md       ← DevSubAgent 设计
│   │   │   └── mate-agent.md         ← [DEPRECATED]
│   │   ├── agents-implemented/       ← Agent 实现参考
│   │   │   ├── pm-agent.md
│   │   │   ├── feature-manager.md
│   │   │   ├── dev-agent.md          ← dev-agent 入口设计
│   │   │   ├── dev-subagent.md       ← DevSubAgent 实现
│   │   │   └── mate-agent.md         ← [DEPRECATED]
│   │   ├── workflows/                ← Workflow 设计文档
│   │   ├── workflows-implemented/    ← Workflow 实现参考
│   │   └── templates/                ← 实现用的内部模板
│   ├── tests/                        ← 测试文档
│   ├── workflow-spec.md              ← 完整工作流规范
│   └── README.md                     ← 项目说明
│
├── features/                         ← 需求目录
│   ├── pending-feat-xxx/
│   ├── active-feat-xxx/
│   └── archive/
│       ├── archive-log.yaml
│       └── done-feat-xxx/
│
└── src/

{project-root}-feat-xxx/              ← worktree（同级目录）
```

## 核心配置文件

### workflow-state.json（运行时状态）

位于 `~/.claude/projects/-{encoded-path}/workflow-state.json`，不在 git 树中，所有 worktree 共享。

* `loop`: 主循环状态（active/status/iteration）

* `agents`: 活跃 SubAgent 跟踪（status/stage）

* `locks`: 文件写锁（queue.yaml/archive-log.yaml）

### config.yaml

* `project.name`, `main_branch`, `tech_stack`

* `parallelism.max_concurrent`: 最大并行数

* `naming`: feature/分支/worktree 前缀

* `completion.archive`: 自动创建 tag、清理 worktree/分支

* `workflow.splitting`: 3+ 价值点自动拆分

### queue.yaml

状态中心，所有 Skill 读写此文件：

* `meta`: last_updated, version

* `parents`: 父需求分组（含 children 列表）

* `active[]`: 正在开发（含 branch, worktree, started, dependencies）

* `pending[]`: 等待中（含 priority, size, dependencies, parent）

* `blocked[]`: 阻塞中（含 reason）

* `completed[]`: 已完成（含 completed_at, value_points）

### archive-log.yaml

位于 `features/archive/`，记录已完成需求的完整索引（渐进式加载的索引层）：

* `meta`: last_updated, version

* `archived[]`: 每条记录包含：

  * 基础信息: id, name, completed, tag, merge_commit, branch/worktree

  * **索引元数据**: keywords[], category, value_points, related_features[]（支持关键词搜索，无需加载完整归档）

  * conflicts: 冲突记录

  * verification: 验收状态

  * stats: 开发统计

通过 `/query-archive` skill 实现渐进式加载：先读索引过滤，再通过 SubAgent 按需加载完整归档内容。

## 命令体系（2 Commands + 12 Skills）

### /dev-agent 命令（批量调度）

| 用法                         | 说明                                    |
| -------------------------- | ------------------------------------- |
| `/dev-agent`               | 批量模式：自动调度所有 pending features          |
| `/dev-agent feat-xxx`      | 单 feature 模式：通过 SubAgent 执行指定 feature |
| `/dev-agent --resume`      | 恢复模式：从断点继续                            |
| `/dev-agent --no-complete` | 跳过 complete 阶段                        |

### /run-feature 命令（手动单个）

| 用法                                     | 说明                    |
| -------------------------------------- | --------------------- |
| `/run-feature feat-xxx`                | 全自动执行：主上下文直接调用 Skills |
| `/run-feature feat-xxx --no-complete`  | 跳过 complete 阶段        |
| `/run-feature feat-xxx --from <stage>` | 从指定阶段继续               |

### DevSubAgent（已废弃，由 general-purpose 替代，`.claude/agents/dev-subagent.md` 已删除）

### 核心 Skills（P0）

| 命令                        | 功能   | 关键操作                                                                        |
| ------------------------- | ---- | --------------------------------------------------------------------------- |
| `/new-feature <描述>`       | 创建需求 | 对话确认 → 搜索归档关联 → AI 分析价值点 → 规模评估(S/M/L) → 可选拆分 → 生成文档 → 加入 queue              |
| `/start-feature <id>`     | 启动开发 | 检查并行限制 + 依赖 → 加载关联 feature 上下文 → 重命名 pending→active → 创建分支 → 创建 worktree        |
| `/implement-feature <id>` | 实现代码 | 读取 spec/task → 在 worktree 中实现 → 更新 task.md 进度（`--auto` 跳过确认）                |
| `/verify-feature <id>`    | 验证完成 | 检查任务 → 运行测试 → Gherkin 场景验证 → 生成证据（`--auto-fix` 自动修复，最多 2 次）                 |
| `/complete-feature <id>`  | 完成归档 | commit → rebase → merge → tag → 归档 → 清理 → 更新 queue（`--auto-resolve` 自动冲突解决） |
| `/list-features`          | 查看状态 | 展示 active/pending/blocked/completed 汇总                                      |

### 管理 Skills（P1）

| 命令                         | 功能                               |
| -------------------------- | -------------------------------- |
| `/query-archive [options]` | 查询归档（渐进式加载：索引搜索 → SubAgent 深度分析） |
| `/block-feature <id>`      | 阻塞需求（标记原因）                       |
| `/unblock-feature <id>`    | 解除阻塞                             |
| `/feature-config`          | 修改配置                             |
| `/cleanup-features`        | 清理无效 worktree                    |

### PM Agent Skill

| 命令          | 功能                             |
| ----------- | ------------------------------ |
| `/pm-agent` | 建立/更新项目上下文（project-context.md） |

### 全自动原则

* DevSubAgent 全程无人值守（独立上下文，不污染主对话）

* 测试失败 → 自动修复代码 → 重跑测试（最多 2 次）

* Rebase 冲突 → 智能分析 → 自动合并 → 重新验证

* Lint 报错 → 修复代码 → 重跑 lint

* 多次重试仍失败 → 返回 error（附带详细诊断），不阻塞其他 feature

## Feature 生命周期

### 手动模式（逐步）

```text
/new-feature → pending-feat-xxx/
                   ↓
/start-feature → active-feat-xxx/ + worktree + branch
                   ↓
/implement-feature → 在 worktree 中写代码
                   ↓
/verify-feature → 测试 + 验收证据
                   ↓
/complete-feature → merge + tag + archive → done-feat-xxx/
```

### 手动模式（一键 /run-feature）

```text
/run-feature feat-xxx → 主上下文直接执行
                        ├── start-feature (branch + worktree)
                        ├── implement-feature --auto (write code)
                        ├── verify-feature --auto-fix (test + auto-fix)
                        └── complete-feature --auto (merge + tag + archive)
```

### 自动模式 (/dev-agent)

```text
/dev-agent feat-xxx → SubAgent (general-purpose)
                        ├── start (branch + worktree)
                        ├── implement --auto (write code)
                        ├── verify --auto-fix (test + auto-fix)
                        ├── complete --auto (merge + auto-resolve + tag + archive)
                        └── return JSON result

/dev-agent → 批量启动 SubAgent × N → 自动循环
```

## Feature 类型与验收方式

* **backend**: 代码分析（AI 验证 Gherkin 场景）

* **frontend**: Playwright MCP 浏览器测试

* **fullstack**: 混合方式

## 需求拆分规则

* 3+ 用户价值点 → 建议拆分

* 按用户价值（非技术层）拆分

* 子需求间无循环依赖

* 父子关系通过 `parent`/`children` 字段管理

## Git 操作约定

* 合并策略: `--no-ff`（保留 merge commit）

* 冲突处理: Rebase 到最新 main → 自动解决冲突（SubAgent 模式）或手动解决

* 归档 tag 格式: `{id}-{YYYYMMDD}`（如 `feat-auth-20260302`）

* 分支删除后可通过 tag 恢复

## 关键文件路径速查

* 配置: `feature-workflow/config.yaml`

* 队列: `feature-workflow/queue.yaml`

* 归档日志: `features/archive/archive-log.yaml`

* 项目上下文: `{project-root}/project-context.md`

* 共享工具: `feature-workflow/implementation/core-lib.md`

* 状态工具函数: `feature-workflow/scripts/state-utils.sh`

* 运行时状态: `~/.claude/projects/-{encoded-path}/workflow-state.json`

* dev-agent 入口: `.claude/commands/dev-agent.md`

* run-feature 入口: `.claude/commands/run-feature.md`

* DevSubAgent: 已删除（行为由 dev-agent.md 注入 prompt 定义）

* Skills: `.claude/skills/`

* Skill 设计: `feature-workflow/implementation/skills/`

* Skill 实现: `feature-workflow/implementation/skills-implemented/`

* Agent 设计: `feature-workflow/implementation/agents/`

* Agent 实现: `feature-workflow/implementation/agents-implemented/`

* 架构设计: `feature-workflow/docs/dev-agent-subagent-optimization.md`

## 实现状态

* Phase 1-4: Skills + Workflows + Agents — 全部完成

* Phase 5: SubAgent 架构优化（Command + Agent v3）— 已完成

* Phase 6: 归档渐进式加载 + 自动关联 — 已完成
  * `/query-archive` skill: 渐进式归档查询（Level 1 索引 → Level 2 SubAgent 深度加载）
  * `/complete-feature`: 归档时写入丰富元数据（keywords/category/value_points/related_features）
  * `/new-feature`: 自动搜索关联归档，填充 spec.md Dependencies/Related Features
  * `/start-feature`: 自动加载依赖 feature 的实现上下文（Agent Tool deep load）
  * 删除冗余 `.claude/agents/dev-subagent.md`

* MVP 流程测试 100% 通过

⠀