# Skill: split-feature

## 元信息

| 属性 | 值 |
|------|-----|
| 名称 | split-feature |
| 触发命令 | `/split-feature <feature-id>` |
| 优先级 | P1 (管理) |
| 依赖 | 无（enrich-feature 可在之后调用） |

## 功能描述

将现有大 feature 拆分为多个独立子 feature：
- 分析 spec 按业务域拆分（非技术层）
- 原始 feature 转换为模块索引（只读）
- 创建子 feature 目录和骨架文档
- 更新 queue.yaml（parents 区 + pending 区联动）

**只做结构拆分，不生成完整文档内容** — 完整内容由 `/enrich-feature` 负责。

## 输入参数

| 参数名 | 类型 | 必需 | 默认值 | 描述 |
|--------|------|------|--------|------|
| feature-id | string | 是 | - | 要拆分的 feature ID |
| --from | string | 否 | - | 外部需求文档路径 |

## 执行流程

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: 加载 Feature                                             │
│ - 读取 queue.yaml 找到 feature                                  │
│ - 读取 features/pending-{id}/spec.md                           │
│ - 如 --from，读取外部文档                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: 分析并提议拆分                                           │
│ - 按业务域识别独立子 feature                                    │
│ - 每个子 feature 独立可交付、S/M 规模                           │
│ - 输出拆分提议（含依赖链可视化）                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: 用户确认                                                 │
│ - Confirm / Edit / Cancel                                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: 生成子 Feature ID                                        │
│ - 自描述 slug（不强制 parent-suffix 格式）                      │
│ - 例: feat-enterprise-org → feat-company, feat-factory          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 5: 创建子 Feature 目录                                      │
│ - features/pending-{child}/spec.md (骨架)                      │
│ - features/pending-{child}/task.md (骨架)                      │
│ - 注: checklist.md 由 enrich-feature 创建                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 6: 转换原始 Feature → 模块索引                             │
│ - 重写 spec.md 为模块索引（子 feature 表 + 依赖图）            │
│ - 重写 task.md 为进度跟踪器                                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 7: 更新 queue.yaml                                         │
│ - Parent → parents 区（含 children 列表）                      │
│ - Children → pending 区（含 parent 字段）                      │
│ - 下游依赖保持指向 parent                                       │
│ - 按 priority 降序排序                                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Step 8: 一致性验证 + 触发 enrich                                │
│ - 检查 children/parent 引用完整性                               │
│ - 检查无重复 ID、无悬空依赖                                    │
│ - 如 auto_enrich=true: 调用 /enrich-feature {parent} --all     │
└─────────────────────────────────────────────────────────────────┘
```

## 拆分提议输出格式

```
Split Proposal for feat-enterprise-org
─────────────────────────────────
Original: 企业管理模块 (L)

Sub-features:
  1. feat-company    公司管理    [M]  depends: []
  2. feat-factory    工厂管理    [M]  depends: [feat-company]
  3. feat-department 部门管理    [S]  depends: [feat-company]

Dependency chain:
  feat-company ──┬── feat-factory
                 └── feat-department

Confirm? [Y/n/edit]
```

## queue.yaml 变更示例

**变更前：**
```yaml
pending:
  - id: feat-enterprise-org
    name: "企业管理模块"
    priority: 90
    size: L
    dependencies: []
```

**变更后：**
```yaml
parents:
  - id: feat-enterprise-org
    name: "企业管理模块"
    priority: 90
    size: L
    status: pending
    children:
      - feat-company
      - feat-factory
      - feat-department

pending:
  - id: feat-company
    name: "公司管理"
    priority: 95
    size: M
    parent: feat-enterprise-org
    dependencies: []

  - id: feat-factory
    name: "工厂管理"
    priority: 94
    size: M
    parent: feat-enterprise-org
    dependencies:
      - feat-company

  - id: feat-department
    name: "部门管理"
    priority: 93
    size: S
    parent: feat-enterprise-org
    dependencies:
      - feat-company
```

## 文件变更

| 文件 | 操作 | 变更内容 |
|------|------|----------|
| features/pending-{child}/spec.md | 创建 | 骨架 spec（基本信息 + 描述 + 空 Gherkin） |
| features/pending-{child}/task.md | 创建 | 骨架 task（分类占位 + 拆分来源进度） |
| features/pending-{parent}/spec.md | 重写 | → 模块索引（子 feature 表 + 依赖图） |
| features/pending-{parent}/task.md | 重写 | → 进度跟踪器（子 feature 复选框） |
| queue.yaml | 修改 | parent 移至 parents 区，children 加入 pending |

## 错误码

| 错误码 | 描述 | 处理建议 |
|--------|------|----------|
| FEATURE_NOT_FOUND | Feature ID 不在队列 | 检查 ID，使用 /list-features |
| FEATURE_ACTIVE | Feature 正在开发 | 先完成或阻塞再拆分 |
| ALREADY_SPLIT | Feature 已有 children | 使用 /list-features 查看 |
| QUEUE_PARSE_ERROR | queue.yaml 格式错误 | 手动修复 YAML |
| ID_CONFLICT | 子 feature ID 已存在 | 使用不同 slug |

## 设计决策

1. **业务优先** — 按业务域拆分，不按技术层（MVC/前后端）
2. **Parent 只读** — 原 feature 转为模块索引，不再直接开发
3. **下游依赖不变** — 依赖 parent 的 feature 不需要改为依赖 children
4. **结构 vs 内容分离** — split 只建骨架，enrich 负责填充（单一职责）
5. **auto_enrich 联动** — 通过 config.yaml 控制，拆分后自动充实

## 与其他 Skill 的关系

```
/new-feature (3+ 价值点) → 建议调用 ↓
/split-feature → 骨架拆分 → 自动触发 ↓
/enrich-feature → 内容充实 → 然后正常进入 ↓
/start-feature → /implement-feature → /verify-feature → /complete-feature
```
