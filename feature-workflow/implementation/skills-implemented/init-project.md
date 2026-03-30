# Skill: init-project

## 元信息

| 属性 | 值 |
|------|-----|
| 名称 | init-project |
| 触发命令 | `/init-project [options]` |
| 优先级 | P0 (核心) |
| 依赖 | 无（首个运行的 skill） |
| 所属插件 | feature-workflow (Marketplace) |
| 新增版本 | v3.0.0 |

## 功能描述

项目初始化技能，在空白项目中一键建立 Feature Workflow 开发环境。负责：

- 检测 Git 仓库和技术栈
- 创建 `feature-workflow/` 配置目录和文件
- 创建 `features/` 需求管理目录
- 生成 `project-context.md` 项目上下文
- 复制模板文件到 `feature-workflow/templates/`

> 注意：技能文件（skills/commands/agents）的部署由 Claude Code Plugin 系统或 `install-plugin.sh` 脚本负责，不在 init-project 的职责范围内。

## 输入参数

| 参数名 | 类型 | 必需 | 默认值 | 描述 |
|--------|------|------|--------|------|
| --name | string | 否 | 目录名 PascalCase | 项目名称 |
| --tech | string | 否 | 自动检测 | 技术栈（如 python-311） |
| --test | string | 否 | 自动检测 | 测试框架（如 pytest） |
| --branch | string | 否 | 自动检测 | 主分支名 |
| --parallel | number | 否 | 3 | 最大并行开发数 |
| --quick | flag | 否 | false | 快速模式，跳过交互确认 |
| --check | flag | 否 | false | 仅检查初始化状态 |
| --force | flag | 否 | false | 强制重新初始化（备份旧配置） |

## 执行流程

```
┌─────────────────────────────────────────────────────────────────┐
│ Pre-flight Checks                                                │
│                                                                  │
│ Check 1: Git Repository?                                         │
│   ├── Yes → Continue                                             │
│   └── No → Error: "Run git init first"                          │
│                                                                  │
│ Check 2: Already Initialized? (config.yaml exists)               │
│   ├── Yes + --force → Backup config, Continue                    │
│   ├── Yes + no-force → Error: "Use --force to reinit"           │
│   └── No → Continue                                              │
│                                                                  │
│ Check 3: Detect Main Branch                                      │
│   ├── origin HEAD → use it                                       │
│   ├── local main → use "main"                                    │
│   ├── local master → use "master"                                │
│   └── fallback → "main"                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Collect Project Information                              │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ Auto-Detection Engine                                        │ │
│ │                                                              │ │
│ │ Tech Stack:                                                  │ │
│ │   pyproject.toml → python-{ver}                              │ │
│ │   package.json  → node-{ver}                                 │ │
│ │   go.mod        → go-{ver}                                   │ │
│ │   Cargo.toml    → rust                                       │ │
│ │                                                              │ │
│ │ Framework (secondary scan):                                  │ │
│ │   settings.py + manage.py → python-django                    │ │
│ │   app/main.py (FastAPI)   → python-fastapi                   │ │
│ │   next.config.*            → node-nextjs                     │ │
│ │   src/App.*x               → node-react                      │ │
│ │                                                              │ │
│ │ Test Framework:                                              │ │
│ │   conftest.py / pytest.ini → pytest                          │ │
│ │   jest.config.*            → jest                            │ │
│ │   vitest.config.*          → vitest                          │ │
│ │   test_*.py files          → pytest (python default)         │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ --quick: Skip all prompts, use detected defaults                 │
│ Default: Display preview, ask (y/n/edit)                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Confirm Configuration                                    │
│                                                                  │
│ Project Initialization Preview                                   │
│ ──────────────────────────────                                   │
│ Name:       MyProject    ← detected / user input                │
│ Tech:       python-311   ← detected                             │
│ Test:       pytest       ← detected                             │
│ Branch:     main         ← detected                             │
│ Worktree:   ../MyProject-feat-xxx                                │
│ Parallel:   3                                                   │
│                                                                  │
│ Files to create: ✓ list all                                      │
│ Continue? (y / n / edit)                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Create Directory Structure                               │
│                                                                  │
│ {project-root}/                                                  │
│ ├── feature-workflow/              ← NEW                        │
│ │   ├── config.yaml                ← Step 4.1                   │
│ │   ├── queue.yaml                 ← Step 4.2                   │
│ │   └── templates/                 ← Step 6 (copy templates)    │
│ ├── features/                      ← NEW                        │
│ │   └── archive/                   ← NEW                        │
│ │       └── archive-log.yaml       ← Step 4.3                   │
│ └── project-context.md             ← Step 5                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: Generate Configuration Files                             │
│                                                                  │
│ 4.1 config.yaml  ← Template + detected values                   │
│     Variables:                                                   │
│     {PROJECT_NAME}     → user input / dir name                  │
│     {MAIN_BRANCH}      → detected                               │
│     {TECH_STACK}       → detected                               │
│     {TEST_FRAMEWORK}   → detected                               │
│     {WORKTREE_PREFIX}  → = PROJECT_NAME                         │
│     {MAX_CONCURRENT}   → user input / default 3                 │
│                                                                  │
│ 4.2 queue.yaml   ← Empty template                               │
│     meta.last_updated = ISO timestamp                            │
│     All lists empty                                               │
│                                                                  │
│ 4.3 archive-log.yaml ← Empty template                           │
│     meta.total_completed = 0                                     │
│     records = []                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 5: Generate Project Context                                 │
│                                                                  │
│ Quick Scan (3-5 files):                                          │
│   1. Directory listing → directory structure section             │
│   2. Dependency file  → tech stack table                         │
│   3. 2-3 source files  → naming/import patterns                 │
│   4. Test files        → test patterns                          │
│                                                                  │
│ Generate project-context.md from template with:                  │
│   - Detected tech stack                                          │
│   - ASCII directory tree                                         │
│   - Initial code patterns                                        │
│   - Placeholder rules/anti-patterns                              │
│                                                                  │
│ Note: Full deep analysis is /pm-agent's job.                     │
│       init-project only does quick scan for minimal viable       │
│       context.                                                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 6: Copy Templates                                           │
│                                                                  │
│ Copy template files to feature-workflow/templates/:              │
│   spec.md, task.md, checklist.md, project-context.md,           │
│   config.yaml, queue.yaml, archive-log.yaml                     │
│                                                                  │
│ Source: plugin templates/ directory                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 7: Git Stage                                                │
│                                                                  │
│ git add feature-workflow/                                        │
│ git add features/                                                │
│ git add project-context.md                                       │
│                                                                  │
│ DO NOT auto-commit. Let user review and commit manually.        │
└─────────────────────────────────────────────────────────────────┘
```

## 生成文件清单

| 文件路径 | 来源 | 说明 |
|----------|------|------|
| `feature-workflow/config.yaml` | 模板 + 检测值 | 主配置，含项目信息、Git 策略、并行控制 |
| `feature-workflow/queue.yaml` | 空模板 | 调度队列，meta.version=1 |
| `features/` | 新建目录 | 需求根目录 |
| `features/archive/` | 新建目录 | 归档目录 |
| `features/archive/archive-log.yaml` | 空模板 | 归档日志，total_completed=0 |
| `project-context.md` | 快速扫描生成 | 项目上下文，建议后续用 /pm-agent 深化 |
| `feature-workflow/templates/*.md` | 插件模板复制 | spec/task/checklist/project-context 模板 |

## 模板变量

| 变量 | 来源 | 示例 |
|------|------|------|
| `{PROJECT_NAME}` | 用户输入 / 目录名 | AnyClaw |
| `{MAIN_BRANCH}` | Git 检测 | main |
| `{TECH_STACK}` | 文件扫描 | python-311 |
| `{TEST_FRAMEWORK}` | 文件扫描 | pytest |
| `{WORKTREE_PREFIX}` | = PROJECT_NAME | AnyClaw |
| `{MAX_CONCURRENT}` | 用户输入 / 默认 3 | 3 |
| `{ISO_TIMESTAMP}` | 系统时间 | 2026-03-30T10:00:00 |
| `{TEST_DIR}` | 目录检测 | tests |
| `{PYTEST_ENABLED}` | 根据测试框架判断 | true |

## 错误码

| 错误码 | 描述 | 解决方案 |
|--------|------|---------|
| NOT_GIT_REPO | 不是 Git 仓库 | 先执行 `git init` |
| ALREADY_INITIALIZED | config.yaml 已存在 | 加 `--force` 重新初始化 |
| PERMISSION_ERROR | 无法创建目录 | 检查文件系统权限 |
| DETECTION_FAILED | 无法检测技术栈 | 手动指定 `--tech=python-311` |
| TEMPLATE_ERROR | 模板处理失败 | 检查模板文件完整性 |

## 设计决策

### 为什么 init-project 只做快速扫描？

`/init-project` 负责最小化可用（minimally viable）的项目初始化。它只做快速扫描来填充 `project-context.md` 的基本框架，因为：

1. 用户刚初始化时项目可能还没什么代码
2. 深度分析是 `/pm-agent` 的职责
3. 保持 init 流程快速（<30 秒）

### 为什么不自动 commit？

初始化是重要操作，生成的配置可能需要调整。让用户先 review 再 commit 更安全。

### 技能部署不由 init-project 负责

技能文件（skills、commands、agents）通过两种方式部署：
- **Claude Code Plugin 系统**：`claude plugin install feature-workflow` 自动处理
- **本地脚本**：`scripts/install-plugin.sh` 纯复制文件

init-project 只负责生成项目配置文件和目录结构。

## 与其他 Skill 的关系

```
init-project (无依赖，最先运行)
    │
    ├── 生成 → project-context.md
    │               │
    │               ▼
    │           pm-agent (深化上下文)
    │
    ├── 生成 → queue.yaml (空)
    │               │
    │               ▼
    │           new-feature (写入 queue)
    │               │
    │               ▼
    │           start-feature (读取 queue, 创建 worktree)
    │               │
    │               ▼
    │           dev-agent (读取 queue, 调度 SubAgent)
    │
    └── 生成 → config.yaml
                    │
                    ▼
                feature-config (查看/修改配置)
```
