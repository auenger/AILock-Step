# dev-agent SubAgent 架构优化方案

> 日期: 2026-03-30
> 状态: 设计定稿 (v2)

---

## 1. 现状分析

### 1.1 当前架构

目前 dev-agent 有三种运行方式：

```
方式 1: 用户手动逐步调用 Skills
  /new-feature → /start-feature → /implement-feature → /verify-feature → /complete-feature

方式 2: 用户手动执行完整流程
  /dev-feature feat-auth
  (在当前 Claude Code 会话中顺序执行所有阶段)

方式 3: Shell 脚本启动独立进程
  ./scripts/start-feature-agent.sh feat-auth ../AnyClaw-feat-auth
  (通过 claude --print 非交互模式启动独立 Agent 进程)
```

### 1.2 核心痛点

| 痛点 | 描述 | 影响程度 |
|------|------|---------|
| **主会话阻塞** | 方式 2 在当前会话中串行执行，整个会话被占用 | 高 |
| **进程黑盒** | 方式 3 用 `claude --print` 启动后台进程，无法实时交互 | 高 |
| **监控困难** | 方式 3 只能通过轮询 `.status` 文件获取进度，延迟大 | 高 |
| **无法干预** | 方式 3 进程启动后无法暂停、修改、恢复，只能等完成或 kill | 高 |
| **无并行能力** | 方式 2 只能串行处理一个 feature | 中 |
| **上下文浪费** | 方式 2 在主会话中执行，开发代码的细节会污染主会话上下文 | 中 |
| **恢复不灵活** | 方式 3 崩溃后需要手动检查日志和状态文件 | 中 |
| **资源无控制** | 方式 3 无法限制并发进程数或优先级 | 低 |

### 1.3 start-feature-agent.sh 脚本的问题

```bash
# 当前方式: 启动独立的 claude --print 进程
claude --print \
    --allowed-tools "Bash,Read,Write,Edit,Glob,Grep" \
    --append-system-prompt "$SYSTEM_PROMPT" \
    "$USER_PROMPT" \
    >> "$LOG_FILE" 2>&1 &
```

**问题清单:**

1. **无状态感知** - 脚本只是启动进程，不感知队列和配置变更
2. **Event 机制简陋** - 通过日志文件中的 EVENT token 通信，解析困难
3. **错误传播差** - 进程错误只能通过检查 `.status` 文件发现
4. **缺乏调度** - 主 Agent 无法主动调度多个 SubAgent
5. **进程管理原始** - 使用 `&` 和 PID 管理，没有优雅退出
6. **无法复用** - 每个 feature 启动一个全新的 claude 进程，无缓存共享

---

## 2. 目标架构

### 2.1 核心思路

**用 Claude Code 的 Agent Tool (SubAgent) 替代 `claude --print` 进程，职责严格分离。**

```
用户 → MateAgent (纯调度器)
         │
         ├─ 读取 config.yaml / queue.yaml
         ├─ 分析 pending features，检查依赖和并行限制
         ├─ 批量启动 SubAgent (N = max_concurrent)
         │
         ├─ Agent Tool → SubAgent-1 (feat-auth)
         │                  ├─ start-feature   (分支 + worktree)
         │                  ├─ implement       (写代码)
         │                  ├─ verify          (测试 + 验收)
         │                  ├─ complete        (commit → merge → tag → 归档 → 清理)
         │                  └─ 返回结果
         │
         ├─ Agent Tool → SubAgent-2 (feat-dashboard)
         │                  └─ ...同上，完整生命周期...
         │
         ├─ 收集结果 → 自动拉下一批 pending
         └─ 遇到阻塞/错误 → 暂停等用户决策
```

### 2.2 职责分离原则

```
┌─────────────────────────────────────────────────────────────────┐
│ MateAgent (调度器)          │  DevSubAgent (执行器)              │
├─────────────────────────────┼───────────────────────────────────┤
│ 读取 config.yaml            │  读取 spec.md / task.md           │
│ 读取 queue.yaml             │  读取 project-context.md          │
│ 分析依赖关系                │  start-feature (创建分支+worktree)│
│ 检查并行限制                │  implement (在 worktree 中写代码) │
│ 决定启动哪些 feature        │  verify (运行测试+验收)           │
│ 启动 SubAgent               │  complete (merge+tag+归档+清理)  │
│ 收集 SubAgent 结果          │  更新 queue.yaml                  │
│ 自动调度下一批              │  更新 archive-log.yaml            │
│ 遇错暂停等用户              │  返回结构化结果                   │
│ 汇总报告                    │                                   │
└─────────────────────────────┴───────────────────────────────────┘

MateAgent 不写代码、不跑测试、不做 merge
SubAgent 不决定调度顺序、不管理队列、不启动其他 SubAgent
```

### 2.3 关键优势

| 优势 | 说明 |
|------|------|
| **职责清晰** | 调度和执行完全分离，各自独立 |
| **原生集成** | Agent Tool 是 Claude Code 内置能力，无需外部脚本 |
| **实时通信** | SubAgent 完成后直接返回结果给 MateAgent，无需轮询 |
| **上下文隔离** | SubAgent 在独立上下文中运行，不污染主会话 |
| **可并行** | 多个 Agent Tool 调用可以在同一消息中并行发起 |
| **全生命周期** | SubAgent 包含 complete，一个 feature 从头到尾一个 SubAgent 搞定 |
| **可恢复** | MateAgent 读取 queue.yaml 即可恢复状态 |

### 2.4 与现有方案的对比

| 维度 | Shell 脚本方式 | SubAgent 方式 |
|------|---------------|--------------|
| 启动方式 | `claude --print &` | Agent Tool |
| 执行范围 | implement + verify (不含 complete) | start + implement + verify + complete (全包) |
| 进程管理 | 操作系统 PID | Claude Code 内部管理 |
| 通信机制 | 文件 + EVENT token | 直接返回值 |
| 监控方式 | 轮询 `.status` 文件 | 通知/轮询 TaskOutput |
| merge 归档 | 由主 Agent 或用户手动 | SubAgent 自行完成 |
| 上下文 | 完全独立的新进程 | 共享项目上下文 |
| 交互能力 | 无（--print 非交互） | 可配置允许的工具 |
| 错误处理 | 手动检查日志 | 自动返回错误信息 |
| 并行控制 | 手动管理 PID | `run_in_background` 参数 |
| 可恢复性 | 重启脚本 + 检查文件 | 读取 queue.yaml |

---

## 3. 详细设计

### 3.1 MateAgent 设计 (纯调度器)

MateAgent 替代当前的 `parallel-dev` skill 和 `feature-manager` agent，**只负责调度，不执行任何 feature 的具体操作**。

#### 职责边界

```yaml
MateAgent 负责:
  - 读取并解析配置 (config.yaml)
  - 分析队列状态 (queue.yaml)
  - 检查并行限制和依赖关系
  - 决定启动哪些 feature 的 SubAgent
  - 通过 Agent Tool 启动 SubAgent
  - 收集 SubAgent 返回结果
  - 汇总报告
  - 遇到阻塞/错误时暂停，等待用户决策
  - 自动循环调度下一批 pending

MateAgent 不负责:
  - 代码实现 (SubAgent)
  - 测试执行 (SubAgent)
  - Git 操作 (SubAgent)
  - 队列更新 (SubAgent 在 complete 阶段自行更新)
  - 归档操作 (SubAgent)
```

#### 调度主循环

```
┌─────────────────────────────────────────────────────────────────┐
│ MateAgent 主循环                                                 │
└─────────────────────────────────────────────────────────────────┘

Loop:
│
├── Step 1: 读取状态
│   ├── 读取 feature-workflow/config.yaml
│   ├── 读取 feature-workflow/queue.yaml
│   └── 确定当前 active 和 pending features
│
├── Step 2: 评估可启动的 features
│   ├── 从 pending 列表按优先级排序
│   ├── 检查每个 feature 的依赖是否满足 (dependencies 字段)
│   ├── 检查父需求状态 (parent 字段)
│   ├── 计算可用槽位: slots = max_concurrent - active.count
│   └── 生成待启动列表 (取前 N 个)
│
├── Step 3: 启动 SubAgent
│   ├── 对于待启动列表中的每个 feature:
│   │   └── 通过 Agent Tool 启动 DevSubAgent
│   │       (注入 feature_id, spec_path, config 信息)
│   │
│   ├── 并行策略:
│   │   ├── slots > 1 → 同一条消息中并行发起多个 Agent Tool 调用
│   │   │              使用 run_in_background: true
│   │   └── slots == 1 → 前台等待完成
│   │
│   └── slots == 0 → 跳过，等待当前 active 完成
│
├── Step 4: 等待并收集结果
│   ├── 前台: 直接获取 Agent Tool 返回值
│   ├── 后台: 通过 TaskOutput 获取结果
│   └── 超时检测: 如果 SubAgent 长时间无响应，标记异常
│
├── Step 5: 处理结果
│   ├── SubAgent 返回 success:
│   │   └── feature 已被 SubAgent 完成 (含 merge/tag/归档)
│   │       MateAgent 只需记录日志
│   │
│   ├── SubAgent 返回 blocked:
│   │   ├── 记录阻塞原因
│   │   └── 暂停循环，提示用户处理
│   │
│   └── SubAgent 返回 error:
│       ├── 记录错误信息
│       └── 暂停循环，提示用户处理
│
├── Step 6: 汇总并决定下一步
│   ├── 检查 config.yaml workflow.auto_start_next
│   ├── 如果启用且 pending 不为空:
│   │   └── 回到 Step 1 (继续下一批)
│   ├── 如果 pending 为空:
│   │   └── 输出完成汇总，退出循环
│   └── 如果有 blocked/error:
│       └── 暂停，等待用户决策后继续
```

#### MateAgent Prompt 结构

```
你是 Feature 调度器 (MateAgent)，负责管理和调度多个 feature 的并行开发。

## 职责
你只负责调度，不执行任何代码开发或 Git 操作。
具体开发由 DevSubAgent 通过 Agent Tool 完成。

## 配置文件
- feature-workflow/config.yaml  ← 项目配置
- feature-workflow/queue.yaml   ← 需求队列

## 调度规则
1. 读取 queue.yaml 的 pending 列表
2. 按 priority 降序排列
3. 检查 dependencies 是否满足 (在 completed 列表中)
4. 检查 parallelism.max_concurrent 限制
5. 启动 DevSubAgent (通过 Agent Tool)
6. 收集结果，决定是否继续

## 遇到异常
- SubAgent blocked → 暂停，报告原因，等待用户
- SubAgent error → 暂停，报告错误，等待用户
- 所有 pending 完成 → 输出汇总，退出

## 自动循环
当一批 SubAgent 全部完成后，自动拉取下一批 pending features 继续执行。
遇到阻塞或错误时暂停循环。
```

### 3.2 DevSubAgent 设计 (完整执行器)

DevSubAgent 执行一个 feature 的**完整生命周期**，从 start 到 complete 全包。

#### 生命周期

```
被 MateAgent 通过 Agent Tool 启动
    ↓
[阶段 1] start-feature
    ├── 检查并行限制
    ├── 创建 Git 分支
    ├── 创建 Worktree
    └── 更新 queue.yaml (pending → active)
    ↓
[阶段 2] implement
    ├── 读取 spec.md / task.md / project-context.md
    ├── 在 worktree 中实现代码
    └── 更新 task.md 进度
    ↓
[阶段 3] verify
    ├── 运行 lint (如果存在)
    ├── 运行测试
    ├── 检查 checklist.md
    └── 如果失败 → 返回 blocked
    ↓
[阶段 4] complete
    ├── git commit
    ├── git pull + rebase (处理冲突)
    ├── git merge 到 main
    ├── 创建 archive tag
    ├── 归档文档到 features/archive/
    ├── 清理 worktree 和 branch
    └── 更新 queue.yaml + archive-log.yaml
    ↓
返回结构化结果给 MateAgent
```

#### SubAgent Prompt 结构

```
你是一个 Feature 开发 Agent (DevSubAgent)，负责完成一个 feature 的完整开发生命周期。

## 环境信息 (由 MateAgent 注入)
- FEATURE_ID: feat-auth
- FEATURE_NAME: 用户认证
- CONFIG_PATH: feature-workflow/config.yaml
- QUEUE_PATH: feature-workflow/queue.yaml
- SPEC_PATH: features/pending-feat-auth/spec.md
- TASK_PATH: features/pending-feat-auth/task.md
- CHECKLIST_PATH: features/pending-feat-auth/checklist.md
- PROJECT_CONTEXT_PATH: project-context.md (如果存在)

## 执行阶段 (严格按顺序，不可跳过)

### 阶段 1: START
1. 读取 config.yaml 获取:
   - project.main_branch (默认 main)
   - naming.branch_prefix (默认 feature)
   - naming.worktree_prefix (默认项目名)
   - paths.worktree_base (默认 ..)
2. 检查 queue.yaml 并行限制
3. 重命名目录: features/pending-{id} → features/active-{id}
4. 创建 Git 分支: git checkout -b feature/{slug}
5. 创建 Worktree: git worktree add {worktree_base}/{prefix}-{slug} feature/{slug}
6. 更新 queue.yaml: pending → active

### 阶段 2: IMPLEMENT
1. 读取 spec.md 理解需求
2. 读取 task.md 了解任务列表
3. 读取 project-context.md 了解项目约定 (如果存在)
4. 切换到 worktree 目录
5. 逐一实现每个未完成的任务
6. 每完成一个任务更新 task.md 的状态

### 阶段 3: VERIFY
1. 在 worktree 中运行 lint 检查 (如果存在)
2. 运行测试 (pytest / npm test 等)
3. 如果测试失败，尝试自动修复代码并重新运行测试 (最多重试 2 次)
4. 检查 checklist.md 中的每一项
5. 如果仍有无法自动修复的验证问题，记录原因但继续推进

### 阶段 4: COMPLETE
1. 在 worktree 中提交: git add . && git commit -m "feat({id}): {name}"
2. 切换到主仓库，拉取最新 main: git checkout main && git pull
3. Rebase feature 分支到最新 main: git checkout {branch} && git rebase main
4. 如果 rebase 冲突 → **自动解决** (见下方冲突自动解决流程)
5. 合并到 main: git checkout main && git merge {branch}
6. 创建归档 tag: git tag -a {id}-{date} -m "Archive: {name}"
7. 归档文档: cp features/active-{id}/* features/archive/done-{id}-{date}/
8. 清理: git worktree remove + git branch -d
9. 更新 queue.yaml: active → completed
10. 更新 archive-log.yaml

#### Rebase 冲突自动解决流程
当 rebase 遇到冲突时，SubAgent 自动处理，不等待人工:

1. `git diff --name-only --diff-filter=U` 获取冲突文件列表
2. 逐个读取冲突文件，分析 <<<< ==== >>>> 标记
3. 结合 spec.md 中的需求意图和 project-context.md 中的项目约定，智能合并:
   - 理解两边代码的功能目的
   - 保留两边的有效变更
   - 消除重复或矛盾的代码
4. 写入解决后的文件: git add <file>
5. 继续下一个冲突文件
6. 全部解决后: git rebase --continue
7. 重新运行验证 (回到阶段 3 的测试部分)，确认冲突解决没有引入问题
8. 验证通过后继续 merge

## 输出格式 (最终返回给 MateAgent)

{
  "feature_id": "feat-auth",
  "status": "success" | "blocked" | "error",
  "completed_stage": "start" | "implement" | "verify" | "complete",
  "tasks_completed": 5,
  "tasks_total": 5,
  "tests_passed": 12,
  "tests_failed": 0,
  "tag": "feat-auth-20260330",
  "merge_commit": "abc123",
  "duration": "2h 30m",
  "block_reason": null,
  "error_message": null
}

## 并行 Merge 策略
每个 SubAgent 独立完成自己的 merge。
在 merge 前先 git pull 获取最新 main，rebase 后再 merge。
如果 rebase 冲突，SubAgent 自动解决 (读取冲突文件，理解代码意图，智能合并，继续 rebase --continue)。
冲突解决后重新运行验证，确认无回归。

## 全自动原则
SubAgent 的目标是**全程无人值守**。遇到问题先尝试自动解决:
- 测试失败 → 修复代码 → 重跑测试 (最多 2 次)
- Rebase 冲突 → 分析冲突 → 智能合并 → 重新验证
- Lint 报错 → 修复代码 → 重跑 lint
只有经过多次尝试仍无法解决的问题，才返回 error (附带详细诊断信息)。

## 规则
1. 只操作自己的 feature 相关文件和 worktree
2. 必须按 start → implement → verify → complete 顺序执行
3. 遇到问题先尝试自动解决，不轻易返回 blocked/error
4. 所有 Git 操作在对应目录执行
```

#### SubAgent 工具权限

```yaml
SubAgent 允许的工具:
  - Bash: 运行测试、lint、git 操作 (commit/merge/rebase/tag/worktree)
  - Read: 读取文件
  - Write: 写入新文件
  - Edit: 编辑已有文件
  - Glob: 搜索文件
  - Grep: 搜索内容

SubAgent 禁止的操作:
  - 修改 config.yaml
  - 修改其他 feature 的文件
  - 启动其他 Agent / SubAgent
  - 推送到远程 (除非 config.yaml 配置了 auto_push)
```

### 3.3 并行调度策略

#### 混合策略（推荐）

```python
def schedule_features(config, queue):
    # 1. 从 pending 中筛选可启动的 features
    candidates = []
    for feature in sorted(queue.pending, key=lambda f: -f.priority):
        # 检查依赖
        if not all_deps_completed(feature.dependencies, queue.completed):
            continue
        # 检查父需求
        if feature.parent and not parent_completed(feature.parent, queue):
            continue
        candidates.append(feature)

    # 2. 计算可用槽位
    slots = config.parallelism.max_concurrent - len(queue.active)

    # 3. 取前 N 个
    batch = candidates[:slots]

    # 4. 启动
    if len(batch) > 1:
        # 并行: 同一条消息中发起多个 Agent Tool
        for feature in batch:
            launch_subagent(feature, run_in_background=True)
    elif len(batch) == 1:
        # 单个: 前台等待
        launch_subagent(batch[0], run_in_background=False)
    else:
        # 无可启动: 等待当前 active 完成
        pass
```

#### 自动循环逻辑

```
MateAgent 自动循环:

while true:
    batch = evaluate_and_pick_features()
    if batch is empty:
        if queue.pending is not empty:
            → 所有 pending 都被阻塞 (依赖未满足)
            → 暂停，提示用户
        else:
            → 所有 feature 已完成
            → 输出汇总，退出
        break

    results = launch_and_wait(batch)

    for result in results:
        if result.status == "error":
            → 记录错误
            → 继续处理其他成功的 feature
            → 该 feature 标记，等待用户后续决策

    # 继续自动拉下一批
```

### 3.4 并行 Merge 安全性

#### 风险分析

```
场景: SubAgent-1 和 SubAgent-2 同时完成，都要 merge 到 main

时间线:
  T1: SubAgent-1: git pull main → main at commit A
  T2: SubAgent-2: git pull main → main at commit A
  T3: SubAgent-1: rebase → merge → main at commit B
  T4: SubAgent-2: git pull main → main at commit B → rebase

结果: SubAgent-2 的 rebase 会包含 SubAgent-1 的变更。
      如果有文件冲突，SubAgent-2 自动解决冲突后继续。
```

#### 自动冲突解决

SubAgent 具备完整的代码理解能力，遇到 rebase 冲突时:

1. 读取冲突文件，分析 `<<<<` / `====` / `>>>>` 标记
2. 理解两边代码的功能意图 (结合 spec.md 和 project-context.md)
3. 智能合并: 保留两边的有效变更，消除重复
4. `git add` → `git rebase --continue`
5. 重新运行测试验证，确认无回归

#### 安全保障

1. **每个 SubAgent merge 前先 pull 最新 main** - 尽量减少冲突概率
2. **冲突后重新验证** - 自动解决冲突后跑测试，确保功能正确
3. **`--no-ff` merge 策略** - 保留 merge commit，便于追踪
4. **tag 归档** - 每个 feature 的代码都可通过 tag 恢复
5. **多次重试** - 如果第一次自动解决后测试失败，再次尝试修复

### 3.5 状态管理

#### 文件状态 (保留，用于恢复和外部监控)

```
features/active-feat-auth/
├── spec.md           # SubAgent 读取
├── task.md           # SubAgent 更新进度
├── checklist.md      # SubAgent 更新
├── .status           # 可选，MateAgent 维护（用于 /dev-agent --resume）
└── .log              # 可选，MateAgent 维护（用于审计）
```

#### 简化通信

```
旧方式:
  SubAgent → .log (EVENT:STAGE, EVENT:PROGRESS)
  MasterAgent → 轮询 .log 解析 EVENT token

新方式:
  SubAgent → Agent Tool 返回值 (结构化 JSON)
  MateAgent → 直接读取返回值

  .status 和 .log 降级为可选的调试/审计用途
```

### 3.6 错误处理与恢复

#### 错误分级

| 级别 | 场景 | 谁处理 | 方式 |
|------|------|--------|------|
| **SubAgent 自动处理** | 测试失败、lint 报错、单个任务失败、rebase 冲突 | SubAgent | 自动修复并重试，不返回 blocked |
| **MateAgent 处理** | SubAgent 返回 error (多次重试仍失败) | MateAgent | 记录错误，跳过该 feature，继续其他 |
| **系统级** | Agent Tool 超时、进程崩溃 | MateAgent | 标记 error，支持 resume |

#### 全自动原则

SubAgent 遇到问题时的处理优先级:

```
问题发生
  ↓
尝试自动解决 (最多 2-3 次)
  ├── 测试失败 → 修复代码 → 重跑测试
  ├── Lint 报错 → 修复代码 → 重跑 lint
  ├── Rebase 冲突 → 分析冲突 → 智能合并 → 重新验证
  └── Import 错误 → 检查依赖 → 安装/修复 → 重跑
  ↓
自动解决成功 → 继续执行
  ↓
多次重试仍失败 → 返回 error (附带详细诊断信息)
  ↓
MateAgent 记录错误，继续处理其他 feature，不阻塞整个循环
```

#### 恢复流程

```
用户运行 /dev-agent --resume
    ↓
MateAgent 读取 queue.yaml
    ↓
发现 active 列表有 feature
    ↓
检查状态:
├── task.md 有未完成任务 → SubAgent 从 implement 继续
├── task.md 全完成但 checklist 未通过 → SubAgent 从 verify 继续
├── 代码已提交但未 merge → SubAgent 从 complete 继续
└── worktree 不存在 → 可能已被手动清理，提示用户确认
```

---

## 4. 与现有系统的兼容性

### 4.1 哪些保留

| 组件 | 处理 |
|------|------|
| config.yaml | 完全保留，MateAgent 和 SubAgent 都读取 |
| queue.yaml | 完全保留，SubAgent 在 start/complete 时更新 |
| archive-log.yaml | 完全保留，SubAgent 在 complete 时更新 |
| spec.md / task.md / checklist.md | 完全保留，SubAgent 读写 |
| project-context.md | 完全保留，SubAgent 读取 |
| 10 个 Skills 文档 | 保留作为参考，SubAgent 内部遵循相同逻辑 |
| templates/ | 完全保留 |

### 4.2 哪些替换

| 旧组件 | 新组件 | 原因 |
|--------|--------|------|
| start-feature-agent.sh | Agent Tool (DevSubAgent) | 原生集成，SubAgent 包含完整生命周期 |
| parallel-dev skill | MateAgent | 更强大的调度能力 |
| EVENT token 机制 | Agent Tool 返回值 | 直接通信，无需文件中转 |
| .status 文件（必须） | 可选（调试用） | Agent Tool 提供实时状态 |
| .log 文件（必须） | 可选（审计用） | 不再是唯一通信渠道 |

### 4.3 哪些新增

| 组件 | 说明 |
|------|------|
| MateAgent prompt | 纯调度器的完整 prompt |
| DevSubAgent prompt | 完整执行器 (start→implement→verify→complete) 的 prompt |
| /dev-agent 命令 | 用户入口命令，启动 MateAgent |

---

## 5. 使用方式设计

### 5.1 单 feature 开发

```
用户: /dev-agent feat-auth

MateAgent:
  1. 读取 queue.yaml，确认 feat-auth 在 pending
  2. 检查依赖和并行限制
  3. 启动 SubAgent
  4. SubAgent 执行: start → implement → verify → complete
  5. 收集结果，报告完成
```

### 5.2 批量并行开发

```
用户: /dev-agent

MateAgent:
  1. 读取 queue.yaml
  2. 按 priority 排序，检查依赖
  3. 取前 N 个 (N = max_concurrent)
  4. 并行启动 SubAgent
  5. 全部完成后自动拉下一批
  6. 循环直到 pending 清空或遇到异常
```

### 5.3 恢复中断的开发

```
用户: /dev-agent --resume

MateAgent:
  1. 读取 queue.yaml
  2. 发现 active 中有未完成的 feature
  3. 检查 task.md 确定进度
  4. 启动 SubAgent 从断点继续
```

### 5.4 仅实现不完成

```
用户: /dev-agent feat-auth --no-complete

MateAgent → SubAgent (只执行 start → implement → verify)
完成后不执行 complete，用户可以手动检查后再处理
```

---

## 6. 实现计划

### Phase 1: MateAgent + 单 SubAgent（核心 MVP）

**目标**: MateAgent 调度单个 SubAgent 完成一个 feature 的完整生命周期。

```
待实现:
  [ ] MateAgent prompt (纯调度逻辑)
  [ ] DevSubAgent prompt (start → implement → verify → complete)
  [ ] /dev-agent 命令入口
  [ ] 结果解析和错误处理
  [ ] 完整的单 feature 流程测试
```

**预计改动:**
- 新增: `implementation/agents/mate-agent.md`
- 新增: `implementation/agents/dev-subagent.md`
- 更新: `implementation/agents-implemented/`
- 保留: `scripts/start-feature-agent.sh` (标记 deprecated)

### Phase 2: 并行调度

```
待实现:
  [ ] 批量启动逻辑 (run_in_background)
  [ ] 自动循环调度
  [ ] 依赖链分析
  [ ] 并行 merge 安全性验证
```

### Phase 3: 增强功能

```
待实现:
  [ ] --resume 断点恢复
  [ ] --no-complete 模式
  [ ] 交互模式 (--interactive)
  [ ] project-context 自动注入
```

### Phase 4: 清理

```
待实现:
  [ ] 标记 start-feature-agent.sh 为 deprecated
  [ ] 简化 .status / .log 为纯可选
  [ ] 更新 DOCUMENTATION.md
  [ ] 更新 PARALLEL-DEV-SPEC.md
  [ ] 更新 CLAUDE.md
```

---

## 7. 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| Agent Tool 并发限制 | 中 | 高 | Phase 1 先实现单 SubAgent，Phase 2 再并行 |
| SubAgent 上下文不足 | 中 | 中 | 注入 project-context.md，精简 prompt |
| 自动冲突解决质量 | 中 | 中 | 冲突后自动重跑测试验证；解决失败才返回 error |
| SubAgent 超时 | 低 | 中 | 支持断点恢复 (--resume) |
| Git worktree 残留 | 低 | 低 | MateAgent 可调用 cleanup-features |
| 回归兼容性 | 低 | 中 | 保留旧脚本和文件格式，渐进迁移 |

---

## 8. 总结

### 核心变更

```
旧: 用户 → 脚本 → claude --print (只做 implement+verify) → 文件通信 → 轮询 → 手动 complete
新: 用户 → MateAgent (调度) → Agent Tool → DevSubAgent (start→implement→verify→complete 全包) → 返回结果
```

### 职责分离

```
MateAgent: 只管调度 (选谁跑、跑几个、什么时候跑下一批)
DevSubAgent: 只管执行 (一个 feature 从头到尾完整搞定，含全自动冲突解决)
```

### 全自动原则

```
SubAgent 遇到问题 → 先尝试自动解决 (测试失败重跑、冲突智能合并)
                    → 多次重试仍失败才返回 error
MateAgent 收到 error → 记录，跳过，继续其他 feature，不阻塞循环
```

### 关键收益

1. **消除外部进程依赖** - 不再需要 `start-feature-agent.sh`
2. **全生命周期自动化** - SubAgent 从 start 到 complete 一条龙
3. **全自动冲突解决** - rebase 冲突由 SubAgent 智能解决，无需人工
4. **不阻塞循环** - 单个 feature 失败不影响其他 feature 的调度
5. **实时结果反馈** - SubAgent 完成即返回，无需轮询
6. **上下文隔离** - 开发细节不污染主会话
7. **原生并行支持** - 利用 Agent Tool 的 `run_in_background`
8. **职责清晰** - 调度和执行完全解耦

### 向后兼容

- 所有现有文件格式 (config.yaml, queue.yaml, spec.md 等) 保持不变
- start-feature-agent.sh 标记为 deprecated 但保留
- 手动调用 Skills 的方式仍然可用
