# Skill: pm-agent

## 元信息

| 属性 | 值 |
|------|-----|
| 名称 | pm-agent |
| 触发命令 | `/pm-agent [options]` |
| 优先级 | P1 (管理) |
| 依赖 | init-project (需要 config.yaml 存在) |
| 所属插件 | feature-workflow (Marketplace) |
| 新增版本 | v3.0.0 |

## 功能描述

项目上下文管理技能。生成和维护 `project-context.md` — 所有 AI Agent 在实现功能时参考的共享知识库。通过深度分析项目代码来提取关键规则、模式和约定，防止 AI 在开发过程中犯错。

核心职责：
- 深度分析项目代码结构和模式
- 提取非显而易见的关键规则和反模式
- 维护技术栈和依赖变更记录
- 追踪近期完成的 feature 变更
- 为所有 AI Agent 提供一致的上下文参考

## 输入参数

| 参数名 | 类型 | 必需 | 默认值 | 描述 |
|--------|------|------|--------|------|
| --fresh | flag | 否 | false | 从头重建（全量分析） |
| --check | flag | 否 | false | 检查上下文是否过期 |
| --section | string | 否 | 全部 | 只更新指定部分 |
| --verbose | flag | 否 | false | 显示分析细节 |

**`--section` 可选值：**

| Section | 说明 |
|---------|------|
| `stack` | 技术栈表 |
| `rules` | 关键规则和反模式 |
| `patterns` | 代码模式和命名规范 |
| `testing` | 测试模式 |
| `changes` | 近期变更（从 queue 读取） |
| `structure` | 目录结构 |

## 执行流程

```
┌─────────────────────────────────────────────────────────────────┐
│ Pre-flight Checks                                                │
│                                                                  │
│ Check 1: feature-workflow 已初始化?                               │
│   ├── config.yaml 存在 → Continue                                │
│   └── 不存在 → Error: "Run /init-project first"                 │
│                                                                  │
│ Check 2: project-context.md 存在?                                │
│   ├── 存在 + 默认模式 → 增量更新                                  │
│   ├── 存在 + --fresh → 全量重建                                   │
│   └── 不存在 → 全量构建                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Load Configuration                                       │
│                                                                  │
│ Read feature-workflow/config.yaml:                               │
│   project.name        → 项目显示名称                              │
│   project.tech_stack  → 辅助技术栈检测                            │
│   project.test_framework → 测试模式章节                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Deep Project Analysis (6 个扫描维度)                     │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ 2.1 Technology Stack Detection                               │ │
│ │                                                              │ │
│ │ Priority scan:                                               │ │
│ │   pyproject.toml → [tool.poetry] / [project]                 │ │
│ │     ├── python version, dependencies list                    │ │
│ │     └── build system (poetry/setuptools/flit)                │ │
│ │   package.json → engines, dependencies, devDependencies      │ │
│ │     ├── node version, framework                              │ │
│ │     └── scripts (start/build/test commands)                  │ │
│ │   requirements.txt → Python packages (frozen versions)       │ │
│ │   go.mod → Go version, direct/indirect deps                  │ │
│ │   Cargo.toml → Rust edition, dependencies                    │ │
│ │                                                              │ │
│ │ Output: Technology stack table                               │ │
│ │   | Category | Technology | Version | Notes |                │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ 2.2 Directory Structure Mapping                              │ │
│ │                                                              │ │
│ │ Scan:                                                        │ │
│ │   1. ls -d */ → top-level directories                       │ │
│ │   2. key subdirs → src/*, tests/*, config/*                  │ │
│ │   3. special dirs → migrations/, static/, templates/         │ │
│ │                                                              │ │
│ │ Output: ASCII directory tree (2-3 levels)                    │ │
│ │   project/                                                   │ │
│ │   ├── src/                                                   │ │
│ │   │   ├── core/                                              │ │
│ │   │   └── api/                                               │ │
│ │   ├── tests/                                                 │ │
│ │   └── docs/                                                  │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ 2.3 Code Pattern Analysis (抽样扫描 3-5 个文件)              │ │
│ │                                                              │ │
│ │ Naming Conventions:                                          │ │
│ │   Files:    snake_case | camelCase | kebab-case | PascalCase │ │
│ │   Classes:  PascalCase | prefix pattern                     │ │
│ │   Functions: snake_case | camelCase                          │ │
│ │   Constants: UPPER_SNAKE_CASE                                │ │
│ │                                                              │ │
│ │ Import Patterns:                                             │ │
│ │   Style: absolute | relative | mixed                        │ │
│ │   Organization: stdlib / third-party / local grouping        │ │
│ │   Barrel exports: index.ts/js files                          │ │
│ │                                                              │ │
│ │ Error Handling:                                              │ │
│ │   Exception types, try/catch vs Result, logging patterns     │ │
│ │                                                              │ │
│ │ Code Style:                                                  │ │
│ │   Indentation, quotes, semicolons, line length               │ │
│ │                                                              │ │
│ │ Output: Code Patterns section with examples                  │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ 2.4 Test Pattern Analysis                                    │ │
│ │                                                              │ │
│ │ Scan for:                                                    │ │
│ │   Test directory → tests/ | __tests__/ | test/               │ │
│ │   Test files → test_*.py | *.test.ts | *_test.go             │ │
│ │   Test framework → pytest | jest | vitest | go testing       │ │
│ │   Fixtures → conftest.py | setup/teardown patterns           │ │
│ │   Mocking → unittest.mock | jest.fn | testify mock           │ │
│ │                                                              │ │
│ │ Output: Testing Patterns section                             │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ 2.5 Architecture Pattern Detection                           │ │
│ │                                                              │ │
│ │ Detect:                                                      │ │
│ │   Style → MVC | Clean | Hexagonal | Layered | CQRS          │ │
│ │   DI → manual | framework (FastAPI Depends, Spring)          │ │
│ │   State → Redux | Zustand | Pinia | Context | Vuex           │ │
│ │   API → REST | GraphQL | gRPC | tRPC                        │ │
│ │   DB → ORM (SQLAlchemy, Prisma) | raw SQL | Repository      │ │
│ │                                                              │ │
│ │ Output: Architecture notes in Critical Rules                 │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ 2.6 Recent Changes Analysis                                  │ │
│ │                                                              │ │
│ │ Data sources:                                                │ │
│ │   1. queue.yaml → completed[] (last 5 features)              │ │
│ │   2. archive-log.yaml → records[] (last 10)                  │ │
│ │                                                              │ │
│ │ Extract per feature:                                         │ │
│ │   - id, name, completed_at                                   │ │
│ │   - value_points[] (what was delivered)                      │ │
│ │   - archive_path (where docs are)                            │ │
│ │                                                              │ │
│ │ Output: Recent Changes table                                 │ │
│ └──────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Identify Critical Rules                                  │
│                                                                  │
│ Based on code analysis, extract:                                 │
│                                                                  │
│ Must Follow (Rules):                                             │
│   - Framework conventions (e.g., "Use Pydantic models for API")  │
│   - Security requirements (e.g., "All inputs validated via X")   │
│   - Performance patterns (e.g., "Use async for DB queries")      │
│   - Project-specific non-obvious rules                           │
│                                                                  │
│ Must Avoid (Anti-patterns):                                      │
│   - Common mistakes in codebase                                  │
│   - Framework anti-patterns                                      │
│   - Deprecated patterns                                          │
│   - Performance pitfalls                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: Generate / Update project-context.md                     │
│                                                                  │
│ ┌─────────────┐   ┌──────────────┐   ┌─────────────┐           │
│ │ Build Mode  │   │ Update Mode  │   │ Section Mode│           │
│ │ (新建)      │   │ (增量)       │   │ (局部)      │           │
│ │             │   │              │   │             │           │
│ │ 全量生成    │   │ 只更新变化   │   │ 只更新指定  │           │
│ │ 所有 sections│   │ 保留手动内容 │   │ section     │           │
│ └─────────────┘   └──────────────┘   └─────────────┘           │
│                                                                  │
│ Key constraint: 文件应 < 200 行                                   │
│   → 避免消耗过多 AI 上下文窗口                                   │
│   → 聚焦于非显而易见的信息                                       │
│   → 代码示例用真实项目文件（非编造）                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 5: Validation                                               │
│                                                                  │
│ Verify:                                                          │
│   ✓ All sections have content (not placeholders)                 │
│   ✓ Tech stack is accurate                                       │
│   ✓ Code examples from real project files                        │
│   ✓ Recent changes match queue.yaml                              │
│   ✓ File < 200 lines                                             │
└─────────────────────────────────────────────────────────────────┘
```

## Check 模式 (`--check`)

对比项目当前状态与 `project-context.md` 中记录的信息：

```
Project Context Health Check
-----------------------------
✓ Tech stack: matches (python-311)
⚠ New dependencies: 3 untracked (black, ruff, httpx)
✓ Directory structure: up to date
✓ Code patterns: 2 samples verified
⚠ Recent changes: 5 features behind

Recommendation: Run /pm-agent to update
```

**检查逻辑：**

| 检查项 | 对比方法 |
|--------|---------|
| Tech stack | 重新扫描依赖文件，对比 stack table |
| Dependencies | diff pyproject.toml/package.json checksum |
| Directory structure | ls 对比 ASCII tree |
| Code patterns | 抽样对比 2-3 个文件的 pattern |
| Recent changes | queue.yaml completed 数量对比 |

## 输出

### Build Mode

```
Project context built!

File: project-context.md
Size: 2.3 KB

Sections:
  ✓ Technology Stack (5 entries)
  ✓ Directory Structure
  ✓ Critical Rules (3 must-follow, 2 anti-patterns)
  ✓ Code Patterns (naming, imports, error handling)
  ✓ Testing Patterns
  ✓ Recent Changes (5 features)

Run /new-feature to start developing!
```

### Update Mode

```
Project context updated!

Changes:
  + 3 new dependencies in tech stack
  + 5 recent features added
  ~ Anti-patterns section updated
  - No removed content
```

### Section Mode

```
Section updated: rules

  + 1 new rule: "Always use async for database operations"
  + 1 new anti-pattern: "Don't use raw SQL strings"
```

## 错误码

| 错误码 | 描述 | 解决方案 |
|--------|------|---------|
| NOT_INITIALIZED | feature-workflow 未初始化 | 先运行 `/init-project` |
| EMPTY_PROJECT | 项目无源代码可分析 | 先创建项目基本结构 |
| PERMISSION_ERROR | 无法写入 project-context.md | 检查文件系统权限 |
| DETECTION_FAILED | 无法检测技术栈 | 在 config.yaml 中手动指定 |

## 设计决策

### 为什么限制 200 行？

`project-context.md` 会被所有 Skill（new-feature、implement-feature、verify-feature 等）加载到 AI 的上下文窗口中。如果文件太长，会：
1. 占用宝贵的 context window 空间
2. 降低 AI 对关键信息的注意力
3. 增加 Token 消耗

200 行是一个经验值，足够记录关键信息而不至于太长。

### 为什么区分 Build / Update / Section 三种模式？

- **Build**: 首次创建或重大重构时使用，全量分析确保完整
- **Update**: 日常维护，只更新变化部分，效率高且不破坏手动内容
- **Section**: 针对性修复，比如只更新规则或只更新近期变更

### 增量更新如何保留手动内容？

`project-context.md` 中用户手动添加的内容不会被覆盖。更新逻辑：
1. 读取现有文件，识别各 section 边界
2. 只替换自动生成的部分
3. 检测 `<!-- auto-generated -->` 标记内的内容
4. 无标记的内容视为手动添加，跳过

## 与其他 Skill 的关系

```
init-project → 生成初始 project-context.md (最小化)
    │
    ▼
pm-agent → 深度分析，完善 project-context.md
    │
    ├── 被 new-feature 读取 → 创建需求时理解项目上下文
    ├── 被 implement-feature 读取 → 实现时遵循代码模式
    ├── 被 verify-feature 读取 → 验证时检查是否违反规则
    ├── 被 complete-feature Step 12 调用 → 完成后增量更新
    │
    └── → 在 complete-feature 后建议运行 /pm-agent 更新 recent changes
```

## project-context.md 完整结构参考

```markdown
---
last_updated: '2026-03-30'
version: 3
features_completed: 15
---

# Project Context: {ProjectName}

> This file contains critical rules and patterns that AI agents must follow
> when implementing code. Keep it concise and focused on non-obvious details.

---

## Technology Stack

| Category | Technology | Version | Notes |
|----------|-----------|---------|-------|
| Language | Python | 3.11 | Type hints required |
| Framework | FastAPI | 0.104 | Async by default |
| Database | PostgreSQL | 15 | Via SQLAlchemy 2.0 |
| Testing | pytest | 7.4 | With async support |
| Package Manager | Poetry | 1.7 | pyproject.toml |

## Directory Structure

```
src/
├── core/           # Core utilities, config
├── api/            # REST API endpoints
├── models/         # Database models
├── services/       # Business logic
├── channels/       # IM channels (CLI, Discord, Feishu)
├── skills/         # Skill system
└── tools/          # Tool implementations
tests/
├── unit/
└── integration/
```

## Critical Rules

### Must Follow

- Use Pydantic models for all API request/response schemas
- All async functions must use `async/await`, not callbacks
- Use dependency injection via FastAPI `Depends()`
- All file operations must go through `PathGuard`

### Must Avoid

- Never use `eval()` or `exec()` on user input
- Don't create circular imports between modules
- Avoid synchronous DB calls in async context

## Code Patterns

### Naming Conventions

- Files: snake_case (e.g., `agent_loop.py`)
- Classes: PascalCase (e.g., `AgentLoop`)
- Functions: snake_case (e.g., `process_message`)
- Constants: UPPER_SNAKE_CASE (e.g., `MAX_RETRIES`)

### Import Patterns

```python
# Standard library
import asyncio
from pathlib import Path

# Third-party
from pydantic import BaseModel

# Local
from src.core.config import settings
```

## Testing Patterns

- Location: `tests/unit/` and `tests/integration/`
- Naming: `test_{module}_{scenario}.py`
- Fixtures: `conftest.py` with `@pytest.fixture`
- Async tests: `@pytest.mark.asyncio`

## Recent Changes

| Date | Feature | Impact |
|------|---------|--------|
| 2026-03-23 | feat-pptx-skill | Added PPTX processing skill |
| 2026-03-22 | feat-chat-history | Refactored session key format |
| 2026-03-21 | feat-llm-resilience | Added empty response detection |

## Update Log

- 2026-03-30: Full rebuild (pm-agent --fresh)
- 2026-03-23: Updated recent changes (5 features)
- 2026-03-20: Initial build (init-project)
```
