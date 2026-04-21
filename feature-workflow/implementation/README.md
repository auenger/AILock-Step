# Implementation 目录说明

本目录包含 Feature Workflow 的所有实现文档。

## 目录结构

```
implementation/
├── README.md                 ← 本文件
│
├── core-lib.md               ← 共享工具函数、Git 命令参考、错误码定义
│
├── skills/                   ← Skill 设计文档 (14个)
│   ├── new-feature.md        ← P0: 创建需求
│   ├── start-feature.md      ← P0: 启动环境
│   ├── implement-feature.md  ← P0: 实现需求
│   ├── verify-feature.md     ← P0: 验证需求
│   ├── complete-feature.md   ← P0: 完成需求（含 tag 归档）
│   ├── list-features.md      ← P0: 查看状态
│   ├── split-feature.md      ← P1: 拆分大 feature（结构拆分）
│   ├── enrich-feature.md     ← P1: 充实子 feature（渐进式归档加载）
│   ├── block-feature.md      ← P1: 阻塞需求
│   ├── unblock-feature.md    ← P1: 解除阻塞
│   ├── feature-config.md     ← P1: 修改配置
│   ├── cleanup-features.md   ← P1: 清理
│   ├── pm-agent.md           ← P1: 项目上下文管理
│   ├── init-project.md       ← P1: 项目初始化
│   └── parallel-dev.md       ← P1: 并行开发
│
├── skills-implemented/       ← Skill 实现参考
│
├── workflows/                ← Workflow 文档
│   ├── feature-lifecycle.md  ← 完整生命周期
│   └── auto-schedule.md      ← 自动调度
│
├── workflows-implemented/    ← Workflow 实现参考
│
├── agents/                   ← Agent 设计文档
│   ├── feature-manager.md    ← 主控 Agent
│   ├── dev-agent.md          ← 开发 Agent 入口
│   ├── dev-subagent.md       ← DevSubAgent 设计
│   └── pm-agent.md           ← PM Agent
│
├── agents-implemented/       ← Agent 实现参考
│
├── hooks/                    ← Hook 配置
├── templates/                ← 实现用的内部模板
└── config.yaml               ← 实现层配置备份
```

## 组件清单

### Skills (14个)

#### P0 核心 Skills

| Skill | 触发命令 | 职责 |
|-------|----------|------|
| `new-feature` | `/new-feature` | 创建需求（对话 → 归档关联 → AI 分析 → 文档 → 队列） |
| `start-feature` | `/start-feature` | 启动环境（依赖检查 → 关联上下文加载 → 分支 → worktree） |
| `implement-feature` | `/implement-feature` | 实现需求（spec → task → 代码，支持 `--auto`） |
| `verify-feature` | `/verify-feature` | 验证需求（任务检查 → 测试 → Gherkin 场景验证） |
| `complete-feature` | `/complete-feature` | 完成需求（提交→合并→tag→归档→清理） |
| `list-features` | `/list-features` | 查看状态（active/pending/blocked/completed） |

#### P1 管理 Skills

| Skill | 触发命令 | 职责 |
|-------|----------|------|
| `split-feature` | `/split-feature <id>` | 拆分大 feature 为子 feature（结构拆分 → 模块索引） |
| `enrich-feature` | `/enrich-feature <id>` | 充实子 feature 文档（渐进式归档加载 → AI 填充三文件） |
| `block-feature` | `/block-feature` | 阻塞需求 |
| `unblock-feature` | `/unblock-feature` | 解除阻塞 |
| `feature-config` | `/feature-config` | 修改配置 |
| `cleanup-features` | `/cleanup-features` | 清理 |
| `pm-agent` | `/pm-agent` | 建立/更新项目上下文（project-context.md） |
| `init-project` | `/init-project` | 初始化项目 |

### 拆分流程（split + enrich 两阶段）

```
/split-feature feat-xxx          阶段 1: 结构拆分
  ├── 分析 spec，按业务域拆分
  ├── 创建子 feature 目录（骨架 spec.md + task.md）
  ├── 原 feature → 模块索引
  ├── 更新 queue.yaml（parents + pending）
  └── auto_enrich=true 时自动触发 ↓

/enrich-feature feat-xxx --all   阶段 2: 内容充实
  ├── Level 1: 扫描 archive-log.yaml 索引（关键词匹配 + 评分排序）
  ├── Level 2: SubAgent 深度加载 top 3-5 相关归档
  ├── 提取实现模式 → 充实 spec.md（价值点 + 上下文 + Gherkin）
  ├── 充实 task.md（具体任务 + 归档模式引用）
  ├── 创建 checklist.md
  └── 确保兄弟 feature 边界不重叠
```

### Workflows

| Workflow | 触发命令 | 职责 |
|----------|----------|------|
| `feature-lifecycle` | `/feature-lifecycle` | 完整生命周期管理（交互式） |
| `auto-schedule` | 自动触发 | 自动调度待处理需求 |

### Agents

| Agent | 职责 |
|-------|------|
| `feature-manager` | 主控 Agent：整体调度、状态监控、用户交互 |
| `dev-agent` | 开发 Agent 入口：读取队列、评估依赖、批量派发 SubAgent |
| `dev-subagent` | DevSubAgent：独立上下文，编排 Skill 执行 |
| `pm-agent` | PM Agent：项目上下文管理 |

## 完整开发流程

### 标准流程

```
/new-feature              创建需求（对话 → 归档关联 → AI 分析 → 文档 → 队列）
      ↓
/start-feature            启动开发（依赖检查 → 关联上下文 → 分支 → worktree）
      ↓
/implement-feature        实现代码（读取 spec → 分析 task → 写代码）
      ↓
/verify-feature           验证功能（执行 checklist → 运行测试 → Gherkin 验证）
      ↓
/complete-feature         完成需求（提交 → 合并 → 创建 tag → 归档 → 清理）
      ↓
自动调度下一个
```

### 大 feature 拆分流程

```
/new-feature              创建需求（AI 分析发现 3+ 价值点）
      ↓
/split-feature            拆分为子 feature（结构拆分 + 模块索引）
      ↓
/enrich-feature --all     充实所有子 feature（归档模式 + Gherkin + 任务分解）
      ↓
对每个子 feature 执行标准流程...
```

## 实现阶段

### Phase 1: 核心 Skills (MVP) ✅ 已完成

- [x] `new-feature` - 创建需求
- [x] `start-feature` - 启动开发
- [x] `implement-feature` - 实现需求
- [x] `verify-feature` - 验证需求
- [x] `complete-feature` - 完成需求（含 tag 归档）
- [x] `list-features` - 查看状态

### Phase 2: 管理 Skills ✅ 已完成

- [x] `block-feature` - 阻塞需求
- [x] `unblock-feature` - 解除阻塞
- [x] `feature-config` - 修改配置
- [x] `cleanup-features` - 清理

### Phase 3: Workflows ✅ 已完成

- [x] `feature-lifecycle` - 完整生命周期
- [x] `auto-schedule` - 自动调度

### Phase 4: Agents ✅ 已完成

- [x] `feature-manager` - 主控 Agent
- [x] `dev-agent` - 开发 Agent

### Phase 5: SubAgent 架构优化 ✅ 已完成

- [x] Command + Agent v3 架构
- [x] DevSubAgent 由 general-purpose 替代

### Phase 6: 归档渐进式加载 + 自动关联 ✅ 已完成

- [x] `query-archive` - 渐进式归档查询
- [x] `complete-feature` - 归档时写入丰富元数据
- [x] `new-feature` - 自动搜索关联归档
- [x] `start-feature` - 自动加载依赖 feature 实现上下文

### Phase 7: Feature 拆分 + 内容充实 ✅ 已完成

- [x] `split-feature` - 大 feature 拆分为子 feature
- [x] `enrich-feature` - 渐进式归档加载充实子 feature 文档
- [x] `config.yaml` - 新增 `auto_enrich` 配置项

## 关键文件位置

| 文件 | 位置 | 说明 |
|------|------|------|
| config.yaml | feature-workflow/ | 项目配置（并行数、命名规则、归档策略） |
| queue.yaml | feature-workflow/ | 调度队列（active/pending/blocked/completed/parents） |
| archive-log.yaml | features/archive/ | 归档索引（渐进式加载的索引层） |
| templates/ | feature-workflow/ | 文档模板（spec.md, task.md, checklist.md） |
| core-lib.md | implementation/ | 共享工具函数、Git 命令参考 |

## 文档规范

每个 Skill 文档包含以下部分：

1. **元信息** - 名称、触发命令、优先级、依赖
2. **功能描述** - 做什么
3. **输入参数** - 接受什么参数
4. **执行流程** - 怎么做（流程图）
5. **输出** - 返回什么
6. **错误码** - 可能的错误
7. **文件变更** - 会修改哪些文件
8. **设计决策** - 关键设计选择及原因
9. **与其他 Skill 的关系** - 上下游依赖
10. **注意事项** - 特殊情况
