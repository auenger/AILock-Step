---
description: 'Fully automated parallel development orchestrator - zero interaction, auto-complete all features'
---

# Skill: parallel-dev (LockStep Edition - 全自动版)

基于 **AILock-Step 协议** 的**完全自动化**并行开发编排器。

## 设计理念

> **"一键启动，自动完成，无需干预"**

- ✅ 自动调度：根据依赖和并行限制自动启动 features
- ✅ 自动监控：持续监控所有运行中的 features
- ✅ 自动恢复：阻塞的 features 记录但不停止整体流程
- ✅ 自动完成：所有 features 完成后自动输出报告
- ❌ 无需交互：全程无需用户确认或选择

## Usage

```
/parallel-dev                      # 启动全自动编排器
/parallel-dev --status             # 仅查看当前状态
```

## 执行协议

```yaml
# ═══════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═══════════════════════════════════════════════════════════════════

STP-001:
  desc: "读取配置和队列"
  !! OP_BASH("git rev-parse --show-toplevel") >> REG_REPO_ROOT
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/queue.yaml") >> REG_QUEUE
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow-LockStep/config.yaml") >> REG_CONFIG
  ?? REG_QUEUE != VAL-NULL AND REG_CONFIG != VAL-NULL
  -> STP-002
  -> STP-ERR-CONFIG

STP-002:
  desc: "读取配置参数"
  !! REG_MAX_CONCURRENT := REG_CONFIG.parallelism.max_concurrent
  ?? REG_MAX_CONCURRENT == VAL-NULL
  !! REG_MAX_CONCURRENT := 2
  !! REG_MONITOR_INTERVAL := REG_CONFIG.parallelism.monitor_interval
  ?? REG_MONITOR_INTERVAL == VAL-NULL
  !! REG_MONITOR_INTERVAL := 30
  -> STP-003

STP-003:
  desc: "显示启动信息"
  !! OP_COUNT(REG_QUEUE.pending, "*") >> REG_INITIAL_PENDING
  !! OP_COUNT(REG_QUEUE.completed, "*") >> REG_INITIAL_COMPLETED
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
║  🚀 parallel-dev - 全自动编排器启动                                 ║
╠═══════════════════════════════════════════════════════════════════════╣
║  并行上限:     {REG_MAX_CONCURRENT}                                   ║
║  监控间隔:     {REG_MONITOR_INTERVAL} 秒                              ║
║  待完成:       {REG_INITIAL_PENDING} 个 feature                       ║
║  已完成:       {REG_INITIAL_COMPLETED} 个 feature                     ║
║                                                                       ║
║  ⚡ 全自动运行中... 无需干预                                          ║
╚═══════════════════════════════════════════════════════════════════════╝
  ")
  !! OP_LOG("parallel-dev started at {NOW}")
  -> STP-100

# ═══════════════════════════════════════════════════════════════════
# [Phase: AUTO SCHEDULING LOOP - 自动调度循环]
# ═══════════════════════════════════════════════════════════════════

STP-100:
  desc: "刷新队列状态"
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/queue.yaml") >> REG_QUEUE
  !! OP_COUNT(REG_QUEUE.active, "*") >> REG_ACTIVE_COUNT
  !! OP_COUNT(REG_QUEUE.pending, "*") >> REG_PENDING_COUNT
  !! OP_COUNT(REG_QUEUE.completed, "*") >> REG_COMPLETED_COUNT
  !! OP_COUNT(REG_QUEUE.blocked, "*") >> REG_BLOCKED_COUNT
  -> STP-101

STP-101:
  desc: "显示当前状态"
  !! OP_UI_NOTIFY("
📊 [{NOW}]
  运行中: {REG_ACTIVE_COUNT} | 待启动: {REG_PENDING_COUNT} | 已完成: {REG_COMPLETED_COUNT} | 阻塞: {REG_BLOCKED_COUNT}
  ")
  -> STP-102

STP-102:
  desc: "检查是否全部完成"
  ?? REG_ACTIVE_COUNT == 0 AND REG_PENDING_COUNT == 0
  -> STP-200  # 全部完成，生成最终报告
  -> STP-110  # 继续处理

# ═══════════════════════════════════════════════════════════════════
# [Phase: SCHEDULING - 自动启动新 features]
# ═══════════════════════════════════════════════════════════════════

STP-110:
  desc: "检查是否可以启动新 feature"
  !! REG_AVAILABLE_SLOTS := REG_MAX_CONCURRENT - REG_ACTIVE_COUNT
  ?? REG_AVAILABLE_SLOTS > 0 AND REG_PENDING_COUNT > 0
  -> STP-111  # 有空位且有待启动的
  -> STP-120  # 没有空位或没有待启动的，跳过调度

STP-111:
  desc: "查找可启动的 features (满足依赖)"
  !! OP_FIND_SCHEDULABLE(REG_QUEUE.pending, REG_QUEUE.completed) >> REG_CANDIDATES
  !! OP_COUNT(REG_CANDIDATES, "*") >> REG_CANDIDATE_COUNT
  ?? REG_CANDIDATE_COUNT > 0
  -> STP-112
  -> STP-120  # 没有可启动的

STP-112:
  desc: "批量启动 features (最多启动 AVAILABLE_SLOTS 个)"
  !! REG_TO_START_COUNT := MIN(REG_CANDIDATE_COUNT, REG_AVAILABLE_SLOTS)
  !! OP_UI_NOTIFY("🚀 自动启动 {REG_TO_START_COUNT} 个 feature...")
  !! REG_START_INDEX := 0
  -> STP-113

STP-113:
  desc: "启动循环 - 获取下一个要启动的"
  ?? REG_START_INDEX < REG_TO_START_COUNT
  -> STP-114
  -> STP-120  # 全部启动完成

STP-114:
  desc: "启动单个 feature agent"
  !! OP_GET_TOP_N(REG_CANDIDATES, REG_START_INDEX + 1) >> REG_FEATURE_TO_START
  !! REG_CUR_FEATURE := OP_GET_AT(REG_FEATURE_TO_START, REG_START_INDEX)
  !! OP_UI_NOTIFY("   → 启动 {REG_CUR_FEATURE.id} (完整生命周期)")
  !! OP_BASH("{REG_REPO_ROOT}/feature-workflow-LockStep/scripts/full-feature-agent.sh {REG_CUR_FEATURE.id} START >> {REG_REPO_ROOT}/features/active-{REG_CUR_FEATURE.id}/.agent.log 2>&1 &") >> REG_START_RESULT
  !! OP_LOG("Started agent for {REG_CUR_FEATURE.id}: PID={REG_START_RESULT.pid}")
  !! REG_START_INDEX := (REG_START_INDEX + 1)
  -> STP-113  # 循环启动下一个

# ═══════════════════════════════════════════════════════════════════
# [Phase: MONITORING - 自动监控运行中的 features]
# ═══════════════════════════════════════════════════════════════════

STP-120:
  desc: "检查是否有运行中的 features"
  ?? REG_ACTIVE_COUNT > 0
  -> STP-121  # 有运行中的，需要监控
  -> STP-140  # 没有运行中的，检查是否需要等待

STP-121:
  desc: "遍历所有 active features"
  !! REG_PROCESS_LIST := COPY(REG_QUEUE.active)
  !! REG_MONITOR_INDEX := 0
  -> STP-122

STP-122:
  desc: "获取下一个待监控的 feature"
  !! OP_GET_AT(REG_PROCESS_LIST, REG_MONITOR_INDEX) >> REG_CUR_FEATURE
  ?? REG_CUR_FEATURE != VAL-NULL
  -> STP-123
  -> STP-140  # 遍历完成

STP-123:
  desc: "读取 feature 状态文件"
  !! OP_FS_READ("{REG_REPO_ROOT}/features/active-{REG_CUR_FEATURE.id}/.status") >> REG_STATUS
  ?? REG_STATUS != VAL-NULL
  -> STP-124
  # 状态文件不存在，可能是刚启动
  -> STP-130

STP-124:
  desc: "根据状态分类处理"
  ?? REG_STATUS.status == "archived" OR REG_STATUS.status == "done"
  -> STP-125  # 已完成
  ?? REG_STATUS.status == "blocked"
  -> STP-126  # 被阻塞
  ?? REG_STATUS.status == "error"
  -> STP-127  # 错误
  # 其他状态 (started, implementing, verifying, completing)
  -> STP-128  # 运行中

STP-125:
  desc: "Feature 已完成"
  !! OP_LOG("✅ {REG_CUR_FEATURE.id} 完成: {REG_STATUS.status}")
  !! OP_UI_NOTIFY("   ✅ {REG_CUR_FEATURE.id} 完成")
  !! REG_MONITOR_INDEX := (REG_MONITOR_INDEX + 1)
  -> STP-122

STP-126:
  desc: "Feature 被阻塞 (记录但继续)"
  !! OP_LOG("⚠️ {REG_CUR_FEATURE.id} 阻塞: {REG_STATUS.blocked.reason}")
  !! OP_UI_NOTIFY("   ⚠️ {REG_CUR_FEATURE.id} 阻塞 - {REG_STATUS.blocked.reason}")
  !! REG_MONITOR_INDEX := (REG_MONITOR_INDEX + 1)
  -> STP-122

STP-127:
  desc: "Feature 错误 (记录但继续)"
  !! OP_LOG("❌ {REG_CUR_FEATURE.id} 错误: {REG_STATUS.error.message}")
  !! OP_UI_NOTIFY("   ❌ {REG_CUR_FEATURE.id} 错误 - 查看 .log")
  !! REG_MONITOR_INDEX := (REG_MONITOR_INDEX + 1)
  -> STP-122

STP-128:
  desc: "Feature 运行中"
  !! OP_LOG("🔄 {REG_CUR_FEATURE.id}: {REG_STATUS.stage} ({REG_STATUS.progress.tasks_done}/{REG_STATUS.progress.tasks_total})")
  # 每隔几次才显示，避免刷屏
  !! REG_MONITOR_COUNT := (REG_MONITOR_COUNT + 1)
  ?? (REG_MONITOR_COUNT % 5) == 0 OR REG_MONITOR_INDEX == 0
  !! OP_UI_NOTIFY("   🔄 {REG_CUR_FEATURE.id}: {REG_STATUS.stage} - {REG_STATUS.progress.tasks_done}/{REG_STATUS.progress.tasks_total}")
  !! REG_MONITOR_INDEX := (REG_MONITOR_INDEX + 1)
  -> STP-122

STP-130:
  desc: "状态文件不存在 (刚启动)"
  !! OP_LOG("⏳ {REG_CUR_FEATURE.id}: 初始化中...")
  !! REG_MONITOR_INDEX := (REG_MONITOR_INDEX + 1)
  -> STP-122

# ═══════════════════════════════════════════════════════════════════
# [Phase: WAIT - 等待下次监控周期]
# ═══════════════════════════════════════════════════════════════════

STP-140:
  desc: "检查是否还有待处理的"
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/queue.yaml") >> REG_QUEUE
  !! OP_COUNT(REG_QUEUE.pending, "*") >> REG_PENDING_COUNT
  !! OP_COUNT(REG_QUEUE.active, "*") >> REG_ACTIVE_COUNT
  ?? REG_ACTIVE_COUNT > 0 OR REG_PENDING_COUNT > 0
  -> STP-141  # 还有任务，等待后继续
  -> STP-200  # 全部完成

STP-141:
  desc: "等待监控间隔"
  !! OP_SLEEP(REG_MONITOR_INTERVAL)
  -> STP-100  # 回到主循环

# ═══════════════════════════════════════════════════════════════════
# [Phase: COMPLETION - 生成最终报告]
# ═══════════════════════════════════════════════════════════════════

STP-200:
  desc: "最终状态读取"
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/queue.yaml") >> REG_QUEUE
  !! OP_COUNT(REG_QUEUE.completed, "*") >> REG_FINAL_COMPLETED
  !! OP_COUNT(REG_QUEUE.blocked, "*") >> REG_FINAL_BLOCKED
  !! OP_BASH("date -u +'%Y-%m-%dT%H:%M:%SZ'") >> REG_END_TIME
  -> STP-201

STP-201:
  desc: "生成详细完成报告"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
║                    🎉 并行开发完成!                                   ║
╠═══════════════════════════════════════════════════════════════════════╣
║  完成时间:     {REG_END_TIME}                                         ║
║                                                                       ║
║  📊 统计:                                                            ║
║    已完成:     {REG_FINAL_COMPLETED} 个 feature                        ║
║    被阻塞:     {REG_FINAL_BLOCKED} 个 feature                          ║
║                                                                       ║
║  📁 归档位置:                                                         ║
║    features/archive/done-*                                            ║
║                                                                       ║
║  📋 查看详情:                                                         ║
║    完成的 features: cat feature-workflow/queue.yaml | grep completed   ║
║    阻塞的 features: cat feature-workflow/queue.yaml | grep blocked     ║
║    日志文件:       find features/active-* -name '.log' 2>/dev/null     ║
╚═══════════════════════════════════════════════════════════════════════╝
  ")
  -> STP-202

STP-202:
  desc: "如果有阻塞的 features，显示详细信息"
  ?? REG_FINAL_BLOCKED > 0
  -> STP-203
  -> STP-205

STP-203:
  desc: "显示阻塞 features 列表"
  !! OP_FOREACH(REG_QUEUE.blocked, "display_blocked_feature") >> REG_BLOCKED_DETAILS
  !! OP_UI_NOTIFY("
⚠️  以下 features 被阻塞:

{REG_BLOCKED_DETAILS}

请手动处理后重新运行 /parallel-dev
  ")
  -> STP-205

STP-205:
  desc: "记录完成日志"
  !! OP_LOG("parallel-dev completed at {REG_END_TIME}")
  !! OP_LOG("Total completed: {REG_FINAL_COMPLETED}, Blocked: {REG_FINAL_BLOCKED}")
  -> STP-END

# ═══════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING]
# ═══════════════════════════════════════════════════════════════════

STP-ERR-CONFIG:
  desc: "配置读取失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取配置文件")
  !! OP_UI_NOTIFY("   请检查 feature-workflow-LockStep/config.yaml")
  -> STP-HALT

STP-HALT:
  desc: "停止执行"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
║  ❌ 编排器异常停止                                                    ║
╠═══════════════════════════════════════════════════════════════════════╣
║  请检查错误后重新运行 /parallel-dev                                    ║
╚═══════════════════════════════════════════════════════════════════════╝
  ")
  -> END

STP-END:
  desc: "正常结束"
  -> END
```

## 辅助函数

### OP_FIND_SCHEDULABLE

查找满足依赖的 features:

```python
def OP_FIND_SCHEDULABLE(pending_list, completed_list):
    completed_ids = {f['id'] for f in completed_list}
    result = []
    for feature in pending_list:
        deps = feature.get('dependencies', [])
        if not deps or all(d in completed_ids for d in deps):
            result.append(feature)
    # 按优先级排序
    result.sort(key=lambda f: f.get('priority', 0), reverse=True)
    return result
```

### display_blocked_feature

显示阻塞 feature 的详细信息:

```python
def display_blocked_feature(feature):
    status_file = f"features/active-{feature['id']}/.status"
    status = read_yaml(status_file)
    return f"""
  - {feature['id']}
    阻塞原因: {status['blocked']['reason']}
    阶段: {status['blocked']['stage']}
    查看日志: tail -f features/active-{feature['id']}/.log
"""
```

## 执行流程图

```
┌────────────────────────────────────────────────────────────────┐
│                   parallel-dev 启动                            │
└────────────────────────────────────────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │ 读取配置和队列         │
              └───────────┬───────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │ 全部完成?              │
              └────┬──────────────┬───┘
                   │是             │否
                   ▼               ▼
            ┌─────────────┐  ┌─────────────────┐
            │ 生成最终报告 │  │ 自动调度循环     │
            └─────────────┘  └────────┬────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
                    ▼                  ▼                  ▼
            ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
            │有空位且有   │    │ 监控运行中  │    │ 等待间隔    │
            │pending?     │    │ 的 features │    │ (30秒)      │
            └─────┬───────┘    └──────┬──────┘    └──────┬──────┘
                  │是                  │                   │
                  ▼                    │                   │
          ┌───────────────┐            │                   │
          │ 批量启动      │            │                   │
          │ full-feature  │            │                   │
          │ -agent.sh     │            │                   │
          └───────────────┘            │                   │
                  │                    │                   │
                  └────────────────────┴───────────────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │ 回到"全部完成?"  │
                              └─────────────────┘
```

## 自动化特性

| 特性 | 说明 |
|------|------|
| **自动启动** | 根据 `max_concurrent` 自动启动多个 features |
| **自动调度** | 检查依赖，按优先级自动启动下一个 |
| **自动监控** | 每 30 秒自动刷新状态 |
| **自动恢复** | 阻塞的 features 不停止整体流程 |
| **自动完成** | 所有 features 完成后自动输出报告 |
| **零交互** | 全程无需用户确认 |

## 配置参数

```yaml
# feature-workflow-LockStep/config.yaml
parallelism:
  max_concurrent: 2        # 同时运行的最大 feature 数量
  monitor_interval: 30     # 监控刷新间隔（秒）
```

## 输出示例

```
╔═══════════════════════════════════════════════════════════════════════╗
║  🚀 parallel-dev - 全自动编排器启动                                 ║
╠═══════════════════════════════════════════════════════════════════════╣
║  并行上限:     2                                                     ║
║  监控间隔:     30 秒                                                ║
║  待完成:       5 个 feature                                         ║
║  已完成:       0 个 feature                                         ║
║                                                                       ║
║  ⚡ 全自动运行中... 无需干预                                          ║
╚═══════════════════════════════════════════════════════════════════════╝

📊 [2026-03-06T10:00:00Z]
  运行中: 0 | 待启动: 5 | 已完成: 0 | 阻塞: 0

🚀 自动启动 2 个 feature...
   → 启动 feat-auth (完整生命周期)
   → 启动 feat-user-mgmt (完整生命周期)

📊 [2026-03-06T10:00:30Z]
  运行中: 2 | 待启动: 3 | 已完成: 0 | 阻塞: 0
   🔄 feat-auth: implement - 1/4
   🔄 feat-user-mgmt: implement - 1/3

[...30秒后自动刷新...]

📊 [2026-03-06T10:01:00Z]
  运行中: 2 | 待启动: 3 | 已完成: 0 | 阻塞: 0
   🔄 feat-auth: implement - 2/4
   🔄 feat-user-mgmt: implement - 2/3

[...自动继续运行...]

📊 [2026-03-06T10:05:00Z]
  运行中: 1 | 待启动: 0 | 已完成: 4 | 阻塞: 0
   ✅ feat-user-mgmt 完成

[...自动继续运行...]

╔═══════════════════════════════════════════════════════════════════════╗
║                    🎉 并行开发完成!                                   ║
╠═══════════════════════════════════════════════════════════════════════╣
║  完成时间:     2026-03-06T10:15:00Z                                   ║
║                                                                       ║
║  📊 统计:                                                            ║
║    已完成:     5 个 feature                                         ║
║    被阻塞:     0 个 feature                                          ║
║                                                                       ║
║  📁 归档位置:                                                         ║
║    features/archive/done-*                                            ║
╚═══════════════════════════════════════════════════════════════════════╝
```

## 与旧版本对比

| 方面 | 旧版本 | 新版本 (全自动) |
|------|--------|-----------------|
| **用户交互** | 每轮询问用户选择 | 完全自动，零交互 |
| **监控方式** | 用户控制刷新 | 定时自动刷新 |
| **阻塞处理** | 停止并询问 | 记录后继续 |
| **完成检测** | 用户决定退出 | 自动检测完成 |
| **适用场景** | 交互式开发 | CI/CD 或批量处理 |

## 日志记录

所有操作都会记录到日志文件：

```
# 主日志
parallel-dev.log

# Feature agent 日志
features/active-{id}/.agent.log
features/active-{id}/.log
```

查看完整日志：
```bash
# 查看编排器日志
tail -f parallel-dev.log

# 查看特定 feature 日志
tail -f features/active-feat-auth/.log
```
