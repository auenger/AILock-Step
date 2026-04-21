# Skill: enrich-feature

## 元信息

| 属性 | 值 |
|------|-----|
| 名称 | enrich-feature |
| 触发命令 | `/enrich-feature <feature-id>` |
| 优先级 | P1 (管理) |
| 依赖 | archive-log.yaml（可选，无归档时降级运行） |

## 功能描述

充实子 feature（由 `/split-feature` 创建）的文档内容。使用渐进式归档加载提取已完成 feature 的实现模式，然后填充：
- **spec.md**: 用户价值点、上下文分析（引用归档代码）、完整 Gherkin 场景
- **task.md**: 具体任务分解（非占位符），映射到 Gherkin 场景，引用归档模式
- **checklist.md**: 补创建（split-feature 不生成此文件）

也适用于任何文档不完整的 pending feature。

## 输入参数

| 参数名 | 类型 | 必需 | 默认值 | 描述 |
|--------|------|------|--------|------|
| feature-id | string | 是 | - | 要充实的 feature ID |
| --all | flag | 否 | false | 充实指定 parent 下的所有子 feature |
| --from | string | 否 | - | 外部需求文档路径 |
| --auto | flag | 否 | false | 跳过确认直接写入（SubAgent 模式） |

## 架构：渐进式归档加载

```
enrich-feature (主上下文)
    │
    ├─ Level 1: 读取 archive-log.yaml（索引，轻量）
    │   → 从目标 feature 提取关键词
    │   → 匹配 archived features（keywords/category/related）
    │   → 评分排序，选择 top 3-5 候选
    │
    └─ Level 2: SubAgent 深度加载（top 候选归档）
        │  ← 独立 200k 上下文，并行执行
        │
        ├─ 读取 features/archive/done-{id}/spec.md
        ├─ 读取 features/archive/done-{id}/task.md
        ├─ 提取：实现模式、文件结构、测试约定
        └─ 返回结构化上下文摘要
```

### 评分算法

| 匹配类型 | 权重 | 说明 |
|----------|------|------|
| 关键词重叠 | × 3 | keywords[] 交集 |
| 同分类 | × 2 | category 精确匹配 |
| 直接依赖 | × 5 | 目标 feature 的 dependency 已完成 |
| 关联链接 | × 2 | related_features[] 双向匹配 |

## 执行流程

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: 加载本地上下文                                           │
│ - 目标 feature spec.md                                          │
│ - Parent spec.md（如有 parent）                                 │
│ - 兄弟 feature specs（边界清晰性）                              │
│ - 外部文档（--from）                                            │
│ - project-context.md                                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Level 1 — 归档索引扫描                                   │
│ - 读取 archive-log.yaml                                         │
│ - 从目标 feature 提取关键词                                     │
│ - 评分排序 → 选择 top 3-5 候选                                  │
│ - 输出 Level 1 摘要                                             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Level 2 — SubAgent 深度归档加载                          │
│ - Agent Tool (general-purpose) 加载候选归档                     │
│ - 提取：实现模式、文件结构、测试约定、可复用代码引用             │
│ - 如 SubAgent 失败：降级到 Level 1 索引数据                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: 分析充实需求                                             │
│ - 扫描三文件，识别哪些是空的/占位符                             │
│ - 输出 gap report                                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 5: 充实 spec.md                                            │
│ - 5.1: 从 parent spec 提取子 feature 价值点（不与兄弟重叠）    │
│ - 5.2: Context Analysis — 引用归档中的实际文件路径和模式        │
│        + 交叉引用 archive-log.yaml 的 related features          │
│ - 5.3: 完整 Gherkin 场景（参考归档的场景结构）                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 6: 充实 task.md                                            │
│ - 从 Gherkin 场景推导具体实现工作                               │
│ - 镜像归档中的任务分解模式                                      │
│ - 分类：Data Layer / Backend / Frontend / Testing               │
│ - 每个任务映射到 Gherkin 场景 + 引用归档模式                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 7: 创建 checklist.md                                       │
│ - 如缺失，从模板创建                                            │
│ - 根据 feature 类型定制（backend/frontend/fullstack）           │
│ - 参照归档的测试覆盖标准                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 8: 确认并写入                                              │
│ - 用户确认 / Edit / Partial                                     │
│ - --auto 模式：直接写入                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 9: 更新 task.md 进度日志                                    │
│ - 记录：价值点数、场景数、任务数、归档引用数                     │
└─────────────────────────────────────────────────────────────────┘
```

## Batch 模式 (--all)

```
/enrich-feature feat-enterprise-org --all

1. 单次 Level 1 扫描（一次 archive-log.yaml 读取）
2. 单次并行 Level 2 深度加载（一个 SubAgent 加载所有相关归档）
3. 逐个充实子 feature（共享归档上下文）
4. 兄弟边界检查（无重叠的价值点和任务）
5. 输出汇总统计
```

## 归档上下文应用示例

**Level 1 扫描结果：**
```
Archive context scan for feat-company:
  [Score: 20] feat-auth | User Authentication | 2026-03-02
    keywords: [auth, jwt, login] | overlap: 3 keywords
  [Score: 12] feat-rbac | Role-Based Access | 2026-03-10
    keywords: [rbac, permission] | overlap: 2 keywords
  → Deep-loading top 2 for implementation patterns...
```

**Level 2 深度加载结果 → 充实 spec.md：**
```markdown
### Reference Code
- src/api/auth/ — JWT middleware pattern (from feat-auth)
- src/models/user.py — SQLAlchemy model with timestamps
- src/services/base_service.py — CRUD service base class
- src/api/rbac/ — Permission decorator pattern (from feat-rbac)
- tests/test_auth.py — Test naming and mock strategy

### Related Features
- feat-auth (completed 2026-03-02) — JWT pattern reused, extends user model
- feat-rbac (completed 2026-03-10) — Permission system to integrate with
```

**Level 2 深度加载结果 → 充实 task.md：**
```markdown
### 1. Data Layer
- [ ] Define Company model — mirror User model from feat-auth
- [ ] Create migration — follow migration pattern from feat-auth
- [ ] Add CompanyRepository — extend BaseRepository pattern
```

## 文件变更

| 文件 | 操作 | 变更内容 |
|------|------|----------|
| features/pending-{id}/spec.md | 重写 | 填充价值点 + 上下文分析 + Gherkin 场景 |
| features/pending-{id}/task.md | 重写 | 具体任务分解（替代占位符） |
| features/pending-{id}/checklist.md | 创建 | 如缺失则创建 |

## 错误码

| 错误码 | 描述 | 处理建议 |
|--------|------|----------|
| NOT_FOUND | Feature ID 不在队列 | 检查 ID，使用 /list-features |
| NO_PARENT | 无 parent 且无 --from | 提供 --from 或用于子 feature |
| ALREADY_COMPLETE | 所有部分已填充 | 使用 --force 覆盖 |
| CONTEXT_MISSING | 无 project-context.md 且无 parent | 先运行 /pm-agent |
| NO_ARCHIVES | archive-log.yaml 不存在 | 跳过归档上下文，仅用 parent spec |
| SUBAGENT_FAILED | Level 2 深度加载失败 | 降级到 Level 1 索引数据 |

## 设计决策

1. **渐进式加载** — Level 1 始终快速（索引扫描），Level 2 仅对 top 候选触发
2. **归档指导而非决定** — 提取的模式指导任务分解，不覆盖 feature 特定需求
3. **优雅降级** — 无归档或 SubAgent 失败时，仅用 parent spec + 项目上下文继续
4. **幂等性** — 多次运行不会重复填充，只补缺
5. **批量优化** — --all 模式共享一次归档扫描和深度加载
6. **单一职责** — 只负责内容充实，不涉及 queue.yaml 或 git 操作

## 与其他 Skill 的关系

```
/split-feature → 骨架拆分 → 调用 ↓
/enrich-feature → 内容充实（渐进式归档加载）
                    ↑ 也可独立使用（任何不完整的 feature）

/query-archive → 共享 Level 1/2 渐进式加载架构
/new-feature → 3+ 价值点时建议 split → enrich 流程
/pm-agent → 提供 project-context.md（enrich 的输入之一）
```
