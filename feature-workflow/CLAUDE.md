# Feature Workflow - Claude Code 初始化指南

## 项目概述

基于 Git Worktree 的 AI 辅助开发工作流系统，核心架构: **一个 Feature = 一个 Worktree = 一个独立开发环境**。

## 目录结构

```
feature-workflow/
├── config.yaml              # 主配置（项目名、并行数、Git 策略、归档规则）
├── config.yaml.example      # 配置模板
├── queue.yaml               # 状态中心：active / pending / blocked / completed / parents
├── archive-log.yaml         # 已完成需求的归档记录
├── templates/               # 文档模板（spec.md, task.md, checklist.md, project-context.md）
├── docs/
│   ├── dev-agent-subagent-optimization.md   # SubAgent 架构优化设计方案
│   └── dev-agent-subagent-implementation-plan.md  # 实施变更计划
├── scripts/
│   └── start-feature-agent.sh   # [DEPRECATED] 启动独立进程（已被 /dev-agent 替代）
├── implementation/
│   ├── core-lib.md              # 共享工具函数、Git 命令参考、错误码定义
│   ├── skills/                  # 10 个 Skill 定义（设计版）
│   ├── skills-implemented/      # 10 个 Skill 实现（已实现版）
│   ├── agents/                  # Agent 定义（设计版）
│   │   ├── pm-agent.md
│   │   ├── feature-manager.md
│   │   ├── dev-agent.md         # dev-agent + dev-subagent 联合设计
│   │   ├── dev-subagent.md      # DevSubAgent 设计
│   │   └── mate-agent.md        # [DEPRECATED] 调度逻辑合并到 dev-agent
│   ├── agents-implemented/      # Agent 实现（已实现版）
│   │   ├── pm-agent.md
│   │   ├── feature-manager.md   # 用户交互层
│   │   ├── dev-agent.md         # dev-agent 入口 + DevSubAgent 设计
│   │   └── dev-subagent.md      # DevSubAgent 实现
│   ├── workflows/               # 2 个 Workflow 定义（设计版）
│   ├── workflows-implemented/   # 2 个 Workflow 实现（已实现版）
│   └── templates/               # 实现用的内部模板
├── tests/                   # 测试文档（MVP 流程、冲突处理、上下文、切分）
├── workflow-spec.md         # 完整工作流规范（数据结构、命令细节、验收规范）
├── PARALLEL-DEV-SPEC.md     # 并行开发方案（无状态主 Agent + 文件状态机）
├── DOCUMENTATION.md         # 用户文档（安装、配置、命令参考、最佳实践）
├── implementation-plan.md   # 架构概览 + 实现优先级
└── README.md                # 项目说明

# Claude Code 部署文件（不在 git 中）
.claude/
├── commands/
│   └── dev-agent.md           # /dev-agent 入口命令（主上下文，负责调度）
├── agents/
│   └── dev-subagent.md        # DevSubAgent 执行器（独立上下文，预加载 skills）
└── skills/
    ├── start-feature.md        # Skill: 创建分支+worktree
    ├── implement-feature.md    # Skill: 实现代码 (--auto)
    ├── verify-feature.md       # Skill: 验证 (--auto-fix)
    ├── complete-feature.md    # Skill: 完成归档 (--auto-resolve)
    ├── new-feature.md         # Skill: 创建需求
    ├── list-features.md       # Skill: 查看状态
    ├── block-feature.md        # Skill: 阻塞
    ├── unblock-feature.md      # Skill: 解除阻塞
    ├── feature-config.md       # Skill: 修改配置
    ├── cleanup-features.md     # Skill: 清理
    └── pm-agent.md            # Skill: 项目上下文
```

## 核心配置文件

### config.yaml
- `project.name`: AnyClaw, `main_branch`: main, `tech_stack`: python-311
- `parallelism.max_concurrent`: 3
- `naming`: feature 前缀 `feat`, 分支前缀 `feature`, worktree 前缀 `AnyClaw`
- `completion.archive`: 自动创建 tag (`{id}-{date}`), 自动清理 worktree/分支
- `workflow.splitting`: 3+ 价值点自动拆分

### queue.yaml
状态中心，所有 Skill 读写此文件:
- `meta`: last_updated, version
- `parents`: 父需求分组（含 children 列表）
- `active[]`: 正在开发（含 branch, worktree, started, dependencies）
- `pending[]`: 等待中（含 priority, size, dependencies, parent）
- `blocked[]`: 阻塞中（含 reason）
- `completed[]`: 已完成（含 completed_at, value_points）

### archive-log.yaml
位于 `features/archive/`，记录已完成需求的 tag、merge commit、统计信息、验收结果。

## 命令体系（1 Command + 10 Skills + 1 SubAgent）

### /dev-agent 命令（入口）
| 用法 | 说明 |
|------|------|
| `/dev-agent` | 批量模式：自动调度所有 pending features |
| `/dev-agent feat-xxx` | 单 feature 模式：执行指定 feature |
| `/dev-agent --resume` | 恢复模式：从断点继续 |
| `/dev-agent --no-complete` | 跳过 complete 阶段 |

### DevSubAgent（执行器）
| 位置 | 类型 | 说明 |
|------|------|------|
| `.claude/commands/dev-agent.md` | Command | 入口，主上下文运行，负责调度 |
| `.claude/agents/dev-subagent.md` | SubAgent | 执行器，独立 200k 上下文，预加载 4 个 skill |

### 核心 Skills（P0）
| 命令 | 功能 | 关键操作 |
|------|------|---------|
| `/new-feature <描述>` | 创建需求 | 对话确认 → AI 分析价值点 → 规模评估(S/M/L) → 可选拆分 → 生成文档 → 加入 queue |
| `/start-feature <id>` | 启动开发 | 检查并行限制 + 依赖 → 重命名 pending→active → 创建分支 → 创建 worktree |
| `/implement-feature <id>` | 实现代码 | 读取 spec/task → 在 worktree 中实现 → 更新 task.md 进度 (`--auto` 跳过确认) |
| `/verify-feature <id>` | 验证完成 | 检查任务 → 运行测试 → Gherkin 场景验证 → Playwright(frontend) → 生成证据 (`--auto-fix` 自动修复) |
| `/complete-feature <id>` | 完成归档 | commit → rebase → merge → tag → 归档目录 → 清理 worktree/分支 → 更新 queue (`--auto-resolve` 自动冲突解决) |
| `/list-features` | 查看状态 | 展示 active/pending/blocked/completed 汇总 |

### 管理 Skills（P1）
| 命令 | 功能 |
|------|------|
| `/block-feature <id>` | 阻塞需求（标记原因） |
| `/unblock-feature <id>` | 解除阻塞 |
| `/feature-config` | 修改配置 |
| `/cleanup-features` | 清理无效 worktree |

### 全自动原则
- DevSubAgent 全程无人值守（独立上下文，不污染主对话）
- 测试失败 → 自动修复代码 → 重跑测试（最多 2 次）
- Rebase 冲突 → 智能分析 → 自动合并 → 重新验证
- Lint 报错 → 修复代码 → 重跑 lint
- 多次重试仍失败 → 返回 error（附带详细诊断），不阻塞其他 feature

### 架构说明
- `/dev-agent` 是 Command（主上下文），负责调度，可通过 Agent Tool 派发 SubAgent
- DevSubAgent 是 Agent（独立 200k 上下文），预加载 4 个核心 skill，按顺序执行
- **MateAgent 已废弃** — v2.1.x 不支持 SubAgent 嵌套，调度逻辑合并到 dev-agent command

### 并行开发（新架构）
- `/dev-agent` → MateAgent → Agent Tool → DevSubAgent × N
- 每个 SubAgent 独立 merge 到 main
- 并行 merge 安全性: merge 前 pull 最新 main，冲突自动解决
- 状态通过 Agent Tool 返回值直接通信（无需 EVENT token）

## Feature 生命周期

### 手动模式
```
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

### 自动模式 (/dev-agent)
```
/dev-agent feat-xxx → DevSubAgent
                        ├── start (branch + worktree)
                        ├── implement (write code)
                        ├── verify (test + auto-fix)
                        ├── complete (merge + auto-resolve + tag + archive)
                        └── return JSON result

/dev-agent → MateAgent → 批量启动 DevSubAgent × N → 自动循环
```

## Feature 类型与验收方式
- **backend**: 代码分析（AI 验证 Gherkin 场景）
- **frontend**: Playwright MCP 浏览器测试
- **fullstack**: 混合方式

## 需求拆分规则
- 3+ 用户价值点 → 建议拆分
- 按用户价值（非技术层）拆分
- 子需求间无循环依赖
- 父子关系通过 `parent`/`children` 字段管理

## Git 操作约定
- 合并策略: `--no-ff`（保留 merge commit）
- 冲突处理: Rebase 到最新 main → 自动解决冲突（SubAgent 模式）或手动解决
- 归档 tag 格式: `{id}-{YYYYMMDD}`（如 `feat-auth-20260302`）
- 分支删除后可通过 tag 恢复

## 关键文件路径速查
- 配置: `feature-workflow/config.yaml`
- 队列: `feature-workflow/queue.yaml`
- 归档日志: `features/archive/archive-log.yaml`
- 项目上下文: `{project-root}/project-context.md`
- 共享工具: `feature-workflow/implementation/core-lib.md`
- Skill 定义: `feature-workflow/implementation/skills/`
- Skill 实现: `feature-workflow/implementation/skills-implemented/`
- Agent 定义: `feature-workflow/implementation/agents/`
- Agent 实现: `feature-workflow/implementation/agents-implemented/`
- MateAgent: `feature-workflow/implementation/agents-implemented/mate-agent.md`
- DevSubAgent: `feature-workflow/implementation/agents-implemented/dev-subagent.md`
- 设计文档: `feature-workflow/docs/dev-agent-subagent-optimization.md`

## 实现状态
- Phase 1-4 全部完成（Skills + Workflows + Agents）
- Phase 5: SubAgent 架构优化（MateAgent + DevSubAgent）已完成
- MVP 流程测试 100% 通过
- 当前项目 (AnyClaw) 已完成 40+ features
