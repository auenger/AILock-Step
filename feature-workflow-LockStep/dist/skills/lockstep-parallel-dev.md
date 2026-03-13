---
description: 'Parallel development orchestrator using AILock-Step protocol'
---

# Skill: parallel-dev (LockStep Edition)

基于 **AILock-Step 协议** 的并行开发编排器。

## 核心原则

1. **STP 锁定**：执行指针必须严格按 STP 序列移动
2. **状态持久化**：所有状态写入文件，可随时恢复
3. **原子操作**：每个 STP 执行一个不可拆分的动作
4. **强制跳转**：只有 `->` 是合法的状态演进路径

## Usage

```
/parallel-dev                      # 启动/恢复并行开发
/parallel-dev --status             # 只查看状态
/parallel-dev --resume <stp-id>    # 从指定 STP 恢复
```

## 执行协议

```yaml
# ═══════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═══════════════════════════════════════════════════════════════════

STP-001:
  desc: "读取配置文件"
  !! OP_FS_READ("feature-workflow-LockStep/config.yaml") >> REG_CONFIG
  ?? REG_CONFIG != VAL-NULL
  -> STP-002

STP-002:
  desc: "读取队列文件"
  !! OP_FS_READ("feature-workflow/queue.yaml") >> REG_QUEUE
  ?? REG_QUEUE != VAL-NULL
  -> STP-100

# ═══════════════════════════════════════════════════════════════════
# [Phase: MONITOR LOOP]
# ═══════════════════════════════════════════════════════════════════

STP-100:
  desc: "检查 active features 数量"
  !! OP_COUNT(REG_QUEUE.active, "*") >> REG_ACTIVE_COUNT
  ?? REG_ACTIVE_COUNT > 0
  -> STP-110
  # 否则 (active 为空)
  -> STP-300

STP-110:
  desc: "获取第一个 active feature"
  !! OP_GET_TOP(REG_QUEUE.active, "*") >> REG_CUR_FEATURE
  !! OP_FS_READ("features/active-{REG_CUR_FEATURE.id}/.status") >> REG_STATUS
  -> STP-111

STP-111:
  desc: "根据状态分发"
  ?? REG_STATUS.status == "not_started" OR REG_STATUS == VAL-NULL
  -> STP-120
  ?? REG_STATUS.status IN ["started", "implementing", "verifying", "completing"]
  -> STP-130
  ?? REG_STATUS.status == "done"
  -> STP-200
  ?? REG_STATUS.status == "blocked"
  -> STP-140
  ?? REG_STATUS.status == "error"
  -> STP-150

# --- 状态分支: 启动新 Agent ---
STP-120:
  desc: "启动 Feature Agent"
  !! OP_UI_NOTIFY("启动 Feature Agent: {REG_CUR_FEATURE.id}")
  !! OP_BASH("./scripts/start-feature-agent.sh {REG_CUR_FEATURE.id}")
  -> STP-160

# --- 状态分支: 显示进度 ---
STP-130:
  desc: "显示当前进度"
  !! OP_UI_NOTIFY("Feature {REG_CUR_FEATURE.id}: {REG_STATUS.status} ({REG_STATUS.stage})")
  -> STP-160

# --- 状态分支: 阻塞处理 ---
STP-140:
  desc: "显示阻塞信息"
  !! OP_UI_NOTIFY("⚠️ Feature {REG_CUR_FEATURE.id} 被阻塞: {REG_STATUS.blocked.reason}")
  -> STP-160

# --- 状态分支: 错误处理 ---
STP-150:
  desc: "显示错误信息"
  !! OP_UI_NOTIFY("❌ Feature {REG_CUR_FEATURE.id} 错误: {REG_STATUS.error.message}")
  -> STP-160

# --- 移除已处理的 feature ---
STP-160:
  desc: "从临时列表移除"
  !! OP_REMOVE(REG_QUEUE.active, REG_CUR_FEATURE)
  -> STP-100  # 回旋跳转，处理下一个

# ═══════════════════════════════════════════════════════════════════
# [Phase: COMPLETE HANDLING]
# ═══════════════════════════════════════════════════════════════════

STP-200:
  desc: "调用 complete-feature"
  !! OP_UI_NOTIFY("✅ Feature {REG_CUR_FEATURE.id} 完成，执行归档...")
  !! OP_CALL_SKILL("complete-feature", REG_CUR_FEATURE.id) >> REG_COMPLETE_RESULT
  ?? REG_COMPLETE_RESULT.status == "success"
  -> STP-201
  # 否则
  -> STP-ERR-COMPLETE

STP-201:
  desc: "检查是否自动启动下一个"
  ?? REG_CONFIG.workflow.auto_start_next == true
  -> STP-202
  # 否则
  -> STP-210

STP-202:
  desc: "读取更新后的队列"
  !! OP_FS_READ("feature-workflow/queue.yaml") >> REG_QUEUE
  !! OP_COUNT(REG_QUEUE.pending, "*") >> REG_PENDING_COUNT
  ?? REG_PENDING_COUNT > 0
  -> STP-203
  # 否则 (pending 为空)
  -> STP-300

STP-203:
  desc: "启动下一个 pending feature"
  !! OP_GET_TOP(REG_QUEUE.pending, "*") >> REG_NEXT_FEATURE
  !! OP_UI_NOTIFY("🚀 自动启动: {REG_NEXT_FEATURE.id}")
  !! OP_CALL_SKILL("start-feature", REG_NEXT_FEATURE.id)
  !! OP_BASH("./scripts/start-feature-agent.sh {REG_NEXT_FEATURE.id}")
  -> STP-001  # 重新开始监控循环

# --- 询问用户 ---
STP-210:
  desc: "询问用户是否继续"
  !! OP_UI_ASK("启动下一个 feature?", ["y", "n"]) >> REG_USER_CHOICE
  ?? REG_USER_CHOICE == "y"
  -> STP-202
  # 否则
  -> STP-300

# ═══════════════════════════════════════════════════════════════════
# [Phase: COMPLETION]
# ═══════════════════════════════════════════════════════════════════

STP-300:
  desc: "显示完成汇总"
  !! OP_FS_READ("feature-workflow/queue.yaml") >> REG_QUEUE
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
║                    🎉 并行开发完成!                                    ║
╠═══════════════════════════════════════════════════════════════════════╣
║  已完成: {REG_QUEUE.completed.length} 个 feature                        ║
║  待开发: {REG_QUEUE.pending.length} 个 feature                          ║
╚═══════════════════════════════════════════════════════════════════════╝
  ")
  -> STP-END

# ═══════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING]
# ═══════════════════════════════════════════════════════════════════

STP-ERR-CONFIG:
  desc: "配置文件错误"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取配置文件")
  -> STP-HALT

STP-ERR-QUEUE:
  desc: "队列文件错误"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取队列文件")
  -> STP-HALT

STP-ERR-COMPLETE:
  desc: "完成流程错误"
  !! OP_UI_NOTIFY("❌ 错误: complete-feature 执行失败: {REG_COMPLETE_RESULT.error}")
  -> STP-HALT

STP-HALT:
  desc: "停止执行"
  !! OP_UI_NOTIFY("执行已停止。请检查错误后重试。")
  -> END
```

## 恢复机制

当执行中断时，重新运行 `/parallel-dev` 会自动：

1. 读取所有 `.status` 文件
2. 找到 `stp_pointer` 字段
3. 从该 STP 继续执行

```yaml
# .status 文件中的 STP 指针
stp_pointer: STP-012
stp_history:
  - STP-001
  - STP-002
  - STP-003
  - STP-010
  - STP-011
  - STP-012  # 当前位置
```

## 输出示例

### 正常启动

```
🚀 parallel-dev (LockStep Edition)

STP-001: 读取配置... ✓
STP-002: 读取队列... ✓
STP-100: 检查 active features... 2 个

STP-110: 处理 feat-auth
STP-111: 状态=not_started
STP-120: 启动 Feature Agent... ✓

STP-110: 处理 feat-dashboard
STP-111: 状态=implementing
STP-130: 进度 3/5

STP-100: 继续监控...
```

### 完成后自动调度

```
STP-200: feat-auth 完成，执行归档... ✓
STP-201: auto_start_next=true
STP-202: 检查 pending... 1 个
STP-203: 🚀 自动启动: feat-export
STP-001: 重新开始监控...
```
