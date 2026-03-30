# dev-agent SubAgent 架构 — 实施变更计划

> 日期: 2026-03-30
> 基于: `dev-agent-subagent-optimization.md` 设计方案 v2
> 状态: 待确认

---

## 变更分析总览

### 影响范围

| 类型 | 数量 |
|------|------|
| 新增文件 | 4 |
| 修改文件 | 6 |
| 保持不变 | 7 |
| 标记废弃 | 2 |
| 设计版更新 | 2 |
| 文档更新 | 2 |

---

## 一、需要新增的文件 (4个)

### 1. `implementation/agents/mate-agent.md` (设计版)

**说明**: MateAgent 的设计文档，定义纯调度器的完整规范。

**核心内容**:
- 职责边界定义（只管调度，不写代码）
- 调度主循环伪代码
- 批量启动逻辑（run_in_background 策略）
- 自动循环调度逻辑
- 依赖链分析规则
- 错误处理策略（SubAgent error → 记录、跳过、继续）
- Prompt 结构模板

### 2. `implementation/agents/dev-subagent.md` (设计版)

**说明**: DevSubAgent 的设计文档，定义完整执行器的规范。

**核心内容**:
- 完整生命周期定义 (start → implement → verify → complete)
- 环境信息注入规范
- 全自动原则详细定义
- Rebase 冲突自动解决流程 (8步)
- 测试失败自动修复重试逻辑
- 结构化输出格式 (JSON)
- 工具权限白名单

### 3. `implementation/agents-implemented/mate-agent.md` (实现版)

**说明**: MateAgent 的完整可执行 prompt，Claude Code 直接加载使用。

**核心内容**:
- 从设计版转化而来的完整 prompt
- 包含具体的文件路径、YAML 读取格式
- Agent Tool 调用参数规范
- TaskOutput 结果收集流程
- 汇总报告输出格式

### 4. `implementation/agents-implemented/dev-subagent.md` (实现版)

**说明**: DevSubAgent 的完整可执行 prompt，由 MateAgent 通过 Agent Tool 调用。

**核心内容**:
- 从设计版转化而来的完整 prompt
- 每个阶段的详细操作步骤（精确到命令）
- 冲突解决的具体操作指令
- 自动修复的触发条件和操作
- 返回值格式规范

---

## 二、需要修改的文件 (6个)

### 1. `agents-implemented/dev-agent.md` — 重构为入口角色

**当前问题**:

| 行号 | 问题 | 影响 |
|------|------|------|
| 1-416 | dev-agent 在当前会话中串行执行，不支持并行 | 不符合新架构 |
| 152-158 | `handle_error` 直接 `wait_for_user_action()` | 与全自动原则冲突 |
| 334-349 | `.dev-progress.yaml` 状态持久化与 Agent Tool 返回值重叠 | 机制冗余 |

**改动方向**:

```
旧: dev-agent = 在当前会话中顺序执行 start→implement→verify→complete
新: dev-agent = 入口解析器 → 启动 MateAgent / 直接启动 SubAgent
```

具体改动:
- 保留 `/dev-agent` 命令入口定义
- 核心逻辑改为:
  - `/dev-agent feat-xxx` → 直接启动单个 SubAgent (run_in_background=false)
  - `/dev-agent` (无参数) → 启动 MateAgent 批量调度
  - `/dev-agent --resume` → 启动 MateAgent 从断点恢复
- 移除 `wait_for_user_action()`，改为全自动或错误上报
- 简化状态持久化，依赖 `queue.yaml` + Agent Tool 返回值
- 移除 `.dev-progress.yaml` 相关内容

---

### 2. `agents-implemented/feature-manager.md` — 缩减调度职责

**当前问题**:

| 行号 | 问题 | 影响 |
|------|------|------|
| 88-113 | `auto_schedule` 逻辑与 MateAgent 重叠 | 职责冲突 |
| 296-314 | Architecture 图中 feature-manager 直接调度 Skills | 不符合新架构 |

**改动方向**:

```
保留: 用户交互、意图解析 (自然语言 → Skill 调用)
迁移: auto_schedule → MateAgent
迁移: 批量调度逻辑 → MateAgent
```

具体改动:
- 保留自然语言意图解析能力
- 将 `auto_schedule` 伪代码标记为 "已迁移至 MateAgent"
- 更新 Architecture 图，MateAgent 取代 feature-manager 的调度位置
- feature-manager 退化为"用户交互层"

---

### 3. `skills-implemented/complete-feature.md` — 改动最大

**当前问题**:

| 行号 | 问题 | 影响 |
|------|------|------|
| 104-129 | `Step 4.4: Handle Rebase Conflict` — 提示用户手动解决 | 与全自动原则冲突 |
| 450-467 | `Rebase Conflict Resolution` — 人工解决流程 | SubAgent 无法自动执行 |
| 46-54 | `Step 2: Check Checklist` — `Continue anyway? (y/n)` | SubAgent 不应有交互确认 |

**改动方向**:

新增 **自动冲突解决模式** (Auto-Resolve Mode):

```
当 SubAgent 调用 complete-feature 时，启用自动模式:

1. git diff --name-only --diff-filter=U → 获取冲突文件列表
2. 逐个读取冲突文件，分析 <<<< ==== >>>> 标记
3. 结合 spec.md 需求意图和 project-context.md 项目约定，智能合并:
   - 理解两边代码的功能目的
   - 保留两边的有效变更
   - 消除重复或矛盾的代码
4. 写入解决后的文件: git add <file>
5. 继续下一个冲突文件
6. 全部解决后: git rebase --continue
7. 重新运行验证 (回到 verify 阶段的测试部分)
8. 验证通过后继续 merge
```

具体改动:
- 新增 `--auto-resolve` 参数控制是否启用自动冲突解决
- 新增 "Auto-Resolve Mode" 章节，详细描述 8 步流程
- 保留手动解决流程作为 fallback
- 弱化交互确认（SubAgent 模式下不暂停等用户）
- 冲突解决后自动重新验证

---

### 4. `skills-implemented/verify-feature.md` — 增加自动修复+重试

**当前问题**:

| 行号 | 问题 | 影响 |
|------|------|------|
| 711-763 | Failure 输出直接让用户 "Fix these issues before completing" | 无自动修复 |
| 全文 | 没有自动修复和重试机制 | SubAgent 无法自动处理 |

**改动方向**:

新增 **自动修复流程**:

```
测试失败 → 分析失败原因 → 修复代码 → 重跑测试 (最多 2 次)

具体场景:
- 单元测试失败 → 分析断言/错误 → 修改实现代码 → 重跑
- Lint 报错 → 分析 lint 规则 → 修改代码 → 重跑
- Import 错误 → 检查依赖 → 安装/修复 → 重跑
```

具体改动:
- 新增 `--auto-fix` 参数控制是否启用自动修复
- 新增 "Auto-Fix Workflow" 章节
- 定义最大重试次数 (2次)
- 修复失败时记录详细诊断信息但**不阻塞**（按设计报告继续推进）
- 新增重试计数和诊断输出

---

### 5. `skills-implemented/implement-feature.md` — 小改

**当前问题**:

| 行号 | 问题 | 影响 |
|------|------|------|
| 58-63 | `Step 3: Confirm Plan` — 要求用户确认 | SubAgent 不应有交互 |
| 108-112 | `Step 6: Generate Report` — 输出手动操作提示 | SubAgent 自动衔接 |

**改动方向**:

- 新增 `--auto` 参数跳过确认（SubAgent 模式）
- SubAgent 模式下:
  - 跳过 "Start implementation? (y/n)" 确认
  - 自动衔接 verify → complete，不输出 "Run /verify-feature" 提示
  - 减少冗余的格式化输出

---

### 6. `skills-implemented/start-feature.md` — 最小改动

**改动方向**:

- 基本无需改动，流程已足够自动化
- 可选: 增加 `--quiet` 参数减少输出信息

---

## 三、保持不变的文件 (7个)

| 文件 | 原因 |
|------|------|
| `skills-implemented/new-feature.md` | 用户手动创建需求，不涉及 SubAgent |
| `skills-implemented/list-features.md` | 状态查看工具，不涉及自动执行 |
| `skills-implemented/block-feature.md` | 用户手动阻塞操作 |
| `skills-implemented/unblock-feature.md` | 用户手动解除阻塞操作 |
| `skills-implemented/feature-config.md` | 配置修改工具，不涉及自动执行 |
| `skills-implemented/cleanup-features.md` | MateAgent 可能调用，但逻辑本身不变 |
| `agents-implemented/pm-agent.md` | 项目上下文管理，完全独立 |

---

## 四、标记废弃的文件 (2个)

| 文件 | 处理方式 | 原因 |
|------|---------|------|
| `scripts/start-feature-agent.sh` | 添加 `# DEPRECATED` 头部注释，保留文件 | 被 Agent Tool (DevSubAgent) 替代 |
| `implementation/agents/dev-agent.md` (设计版) | 标记为新架构替代，保留文件 | 被 mate-agent.md + dev-subagent.md 替代 |

---

## 五、设计版文件更新 (2个)

| 文件 | 改动 |
|------|------|
| `implementation/agents/dev-agent.md` (设计版) | 更新为新架构设计（入口角色），或标记废弃 |
| `implementation/agents/feature-manager.md` (设计版) | 缩减调度职责，更新 Architecture 图 |

---

## 六、文档更新 (2个)

| 文件 | 改动 |
|------|------|
| `feature-workflow/CLAUDE.md` | 更新 Agents 部分，新增 MateAgent / DevSubAgent 条目 |
| `feature-workflow/DOCUMENTATION.md` | 更新命令参考，新增 `/dev-agent` 用法 |

---

## 实施优先级

### Phase 1: 核心 MVP

```
优先级  改动项                          预估复杂度
─────  ───────────────────────────────  ──────────
 P0    新增 dev-subagent.md (实现版)     高
 P0    新增 mate-agent.md (实现版)       高
 P0    修改 complete-feature.md          高 (自动冲突解决)
 P0    修改 verify-feature.md            中 (自动修复+重试)
 P1    修改 dev-agent.md (实现版)        中 (重构为入口)
 P1    修改 implement-feature.md         低 (跳过确认)
```

### Phase 2: 文档+清理

```
优先级  改动项                          预估复杂度
─────  ───────────────────────────────  ──────────
 P2    新增设计版文件                    低
 P2    更新 feature-manager.md          低
 P2    标记废弃 start-feature-agent.sh  低
 P2    更新 CLAUDE.md                   低
 P2    更新 DOCUMENTATION.md            低
```

---

## 关键设计决策回顾

以下决策已在上一次讨论中确认，本次实施严格遵循:

1. **SubAgent 全包** — start → implement → verify → complete 全部由 SubAgent 执行
2. **MateAgent 纯调度** — 只管选谁跑、跑几个、什么时候跑下一批
3. **批量启动+自动循环** — 多个 SubAgent 通过 `run_in_background` 并行启动
4. **SubAgent 自行 merge** — 每个 SubAgent 独立完成 merge 到 main
5. **全自动原则** — 测试失败重跑、冲突智能合并，多次重试失败才返回 error
6. **不阻塞循环** — 单个 feature error 不影响其他 feature 的调度
