# Feature Workflow

基于 Git Worktree 的多需求并行开发工作流，核心架构: **一个 Feature = 一个 Worktree = 一个独立开发环境**。

## 核心理念

- **项目上下文**: 通过 PM Agent 建立项目上下文，确保 AI 开发一致性
- **并行开发**: 支持多个需求同时开发，通过 worktree 物理隔离
- **自动调度**: 根据优先级自动安排开发顺序
- **状态追踪**: 通过 queue.yaml 统一管理需求状态
- **文档驱动**: 每个需求包含 spec/task/checklist 三个文档
- **归档策略**: 完成后创建 tag 归档，删除 worktree 和分支

## 安装与分发

技能通过 **Company AI Marketplace** 分发，支持两种安装方式。

### 方式一：Claude Code Plugin 系统（推荐）

```bash
# 添加公司市场源（只需一次）
claude plugin marketplace add http://119.119.119.4:9090/meper/meper-claude-marketplace

# 安装插件
claude plugin install feature-workflow
```

更新时：
```bash
claude plugin update feature-workflow
```

管理命令：
```bash
claude plugin list                    # 查看已安装插件
claude plugin disable feature-workflow # 禁用
claude plugin enable feature-workflow  # 启用
claude plugin uninstall feature-workflow # 卸载
```

### 方式二：本地脚本安装

适用于无法访问 Git 仓库的场景，使用打包好的 zip 文件：

```bash
# 解压 marketplace
unzip company-ai-marketplace.zip

# 安装到目标项目（复制 skills/commands/agents 到 .claude/）
cd company-ai-marketplace
./scripts/install-plugin.sh /path/to/your/project
```

更新时重新解压再跑一次脚本即可。

> **zip 文件位置**: `feature-workflow/company-ai-marketplace.zip`（89KB）
>
> 包含内容：1 command + 1 agent + 13 skills + 8 templates + 安装脚本

## 项目初始化

安装插件后，在项目中初始化：

```
/init-project              # 交互模式
/init-project --quick      # 快速模式（全默认）
/init-project --check      # 检查初始化状态
```

或使用命令行脚本：
```bash
./scripts/init-project.sh --quick
```

初始化只负责生成项目配置（config.yaml、queue.yaml、features/、project-context.md），不涉及技能文件部署。

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

## 目录结构

```
{project-root}/
├── feature-workflow/                 ← 工作流配置
│   ├── config.yaml                   ← 项目配置（并行数、命名规则、归档策略）
│   ├── queue.yaml                    ← 状态中心（active/pending/blocked/completed）
│   ├── templates/                    ← 文档模板（spec.md, task.md, checklist.md）
│   ├── implementation/               ← 设计文档 + 实现参考
│   │   ├── core-lib.md               ← 共享工具函数、Git 命令参考、错误码
│   │   ├── skills/                   ← Skill 设计文档
│   │   ├── skills-implemented/       ← Skill 实现参考
│   │   ├── agents/                   ← Agent 设计文档
│   │   └── agents-implemented/       ← Agent 实现参考
│   ├── company-ai-marketplace.zip    ← Marketplace 分发包
│   └── README.md                     ← 本文件
│
├── features/                         ← 需求目录
│   ├── pending-feat-xxx/             ← 等待中
│   ├── active-feat-xxx/              ← 进行中
│   └── archive/                      ← 归档区
│       ├── archive-log.yaml          ← 归档日志
│       └── done-feat-xxx/            ← 已完成
│
├── project-context.md                ← 项目上下文（由 /pm-agent 生成）
└── src/

{project-root}-feat-xxx/              ← worktree（同级目录）
```

> Skills、Commands、Agents 由 Plugin 系统管理，不存储在项目目录中。

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
| `/init-project` | 初始化项目配置 | `--quick` 跳过确认 |
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
| `/pm-agent` | 建立/更新项目上下文 | `--fresh` 全量重建 |

## 完整开发流程

### 手动模式

```
/init-project              初始化项目配置
      ↓
/pm-agent                  建立项目上下文
      ↓
/new-feature               创建需求（对话 → 文档 → 队列）
      ↓
/start-feature             启动开发（分支 → worktree）
      ↓
/implement-feature         实现代码（spec → task → 写代码）
      ↓
/verify-feature            验证功能（checklist → 测试）
      ↓
/complete-feature          完成需求（提交 → 合并 → tag → 归档）
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

### Stop Hook 智能拦截

`on-stop-check.sh` 通过 `.loop-active` marker 区分两种模式，避免手动操作（如 `/new-feature`）被误拦截：

| 模式 | 判断条件 | 检查配置 | 说明 |
|------|----------|---------|------|
| `/dev-agent` 自动循环 | `.loop-active` 存在 | `auto_start_next: true` | 循环内只看续跑开关 |
| 手动模式 | `.loop-active` 不存在 | `auto_start: true` | 主开关 `false` → 放行 |

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
| company-ai-marketplace.zip | feature-workflow/ | Marketplace 分发包 |
| core-lib.md | feature-workflow/implementation/ | 共享工具函数 |

## 实现状态

- Phase 1-4: Skills + Workflows + Agents — 全部完成
- Phase 5: SubAgent 架构优化（Command + Agent v3）— 已完成
- Marketplace 分发体系 — 已完成
- MVP 流程测试 100% 通过
