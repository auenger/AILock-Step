---
description: 'Start feature development using AILock-Step protocol'
---

# Skill: start-feature (LockStep Edition)

基于 **AILock-Step 协议** 的特性启动流程。创建 worktree 和分支。

## Usage

```
/start-feature <id>              # 启动指定 feature
/start-feature --next            # 启动下一个优先级最高的 pending feature
```

## 前置条件

```
?? Feature 存在于 queue.yaml 的 pending 列表
?? Feature 的所有依赖都已在 completed 列表
?? Worktree 目录不存在
```

## 执行协议

```yaml
# ═══════════════════════════════════════════════════════════════════
# [Phase: VALIDATION]
# ═══════════════════════════════════════════════════════════════════

STP-001:
  desc: "解析参数"
  !! OP_PARSE_INPUT($ARGS) >> REG_FEATURE_ID
  ?? REG_FEATURE_ID != VAL-NULL OR $ARGS == "--next"
  -> STP-002
  # 否则
  -> STP-ERR-NO_ID

STP-002:
  desc: "处理 --next 标志"
  ?? $ARGS == "--next"
  -> STP-003
  # 否则
  -> STP-010

STP-003:
  desc: "获取下一个 pending feature"
  !! OP_FS_READ("feature-workflow-LockStep/queue.yaml") >> REG_QUEUE
  !! OP_GET_TOP(REG_QUEUE.pending, "highest_priority") >> REG_FEATURE_INFO
  ?? REG_FEATURE_INFO != VAL-NULL
  -> STP-004
  # 否则 (pending 为空)
  -> STP-ERR-NO_PENDING

STP-004:
  desc: "设置 Feature ID"
  !! REG_FEATURE_ID := REG_FEATURE_INFO.id
  -> STP-010

STP-010:
  desc: "读取队列"
  !! OP_FS_READ("feature-workflow-LockStep/queue.yaml") >> REG_QUEUE
  ?? REG_QUEUE != VAL-NULL
  -> STP-011
  # 否则
  -> STP-ERR-QUEUE

STP-011:
  desc: "检查 feature 是否在 pending 列表"
  !! OP_FIND(REG_QUEUE.pending, "id", REG_FEATURE_ID) >> REG_FEATURE_ENTRY
  ?? REG_FEATURE_ENTRY != VAL-NULL
  -> STP-012
  # 否则
  -> STP-ERR-NOT_PENDING

STP-012:
  desc: "检查依赖是否满足"
  !! REG_FEATURE_ENTRY.dependencies >> REG_DEPENDENCIES
  ?? REG_DEPENDENCIES == VAL-NULL OR REG_DEPENDENCIES IS EMPTY
  -> STP-020
  # 需要检查依赖
  -> STP-013

STP-013:
  desc: "验证每个依赖"
  !! OP_FOREACH(REG_DEPENDENCIES, "check_completed", REG_QUEUE.completed) >> REG_DEP_RESULT
  ?? REG_DEP_RESULT.all_satisfied == true
  -> STP-020
  # 否则
  -> STP-ERR-DEPS_NOT_MET

# ═══════════════════════════════════════════════════════════════════
# [Phase: PREPARATION]
# ═══════════════════════════════════════════════════════════════════

STP-020:
  desc: "读取配置"
  !! OP_FS_READ("feature-workflow-LockStep/config.yaml") >> REG_CONFIG
  ?? REG_CONFIG != VAL-NULL
  -> STP-021
  # 否则
  -> STP-ERR-CONFIG

STP-021:
  desc: "生成路径"
  !! REG_BRANCH := "feature/{REG_FEATURE_ID#feat-}"
  !! REG_WORKTREE := "{REG_CONFIG.paths.worktree_base}/{REG_CONFIG.naming.worktree_prefix}-{REG_FEATURE_ID}"
  !! REG_PENDING_DIR := "features/pending-{REG_FEATURE_ID}"
  !! REG_ACTIVE_DIR := "features/active-{REG_FEATURE_ID}"
  -> STP-022

STP-022:
  desc: "检查 worktree 是否已存在"
  !! OP_FS_EXISTS(REG_WORKTREE) >> REG_WORKTREE_EXISTS
  ?? REG_WORKTREE_EXISTS == VAL-NULL
  -> STP-023
  # 否则 (已存在)
  -> STP-ERR-WORKTREE_EXISTS

STP-023:
  desc: "检查 pending 目录是否存在"
  !! OP_FS_EXISTS(REG_PENDING_DIR) >> REG_PENDING_EXISTS
  ?? REG_PENDING_EXISTS != VAL-NULL
  -> STP-024
  # 否则
  -> STP-ERR-PENDING_NOT_FOUND

STP-024:
  desc: "读取 feature 信息"
  !! OP_FS_READ("{REG_PENDING_DIR}/spec.md") >> REG_SPEC
  !! OP_FS_READ("{REG_PENDING_DIR}/task.md") >> REG_TASK
  !! OP_FS_READ("{REG_PENDING_DIR}/checklist.md") >> REG_CHECKLIST
  -> STP-030

# ═══════════════════════════════════════════════════════════════════
# [Phase: GIT OPERATIONS]
# ═══════════════════════════════════════════════════════════════════

STP-030:
  desc: "创建分支"
  !! OP_BASH("git branch {REG_BRANCH}") >> REG_BRANCH_RESULT
  ?? REG_BRANCH_RESULT.exit_code == 0
  -> STP-031
  # 失败
  -> STP-ERR-BRANCH_CREATE

STP-031:
  desc: "创建 worktree"
  !! OP_BASH("git worktree add {REG_WORKTREE} {REG_BRANCH}") >> REG_WORKTREE_RESULT
  ?? REG_WORKTREE_RESULT.exit_code == 0
  -> STP-032
  # 失败
  -> STP-ERR-WORKTREE_CREATE

STP-032:
  desc: "验证 worktree 创建成功"
  !! OP_BASH("git worktree list") >> REG_WORKTREE_LIST
  ?? REG_WORKTREE_LIST CONTAINS REG_WORKTREE
  -> STP-040
  # 失败
  -> STP-ERR-WORKTREE_VERIFY

# ═══════════════════════════════════════════════════════════════════
# [Phase: FILE MIGRATION]
# ═══════════════════════════════════════════════════════════════════

STP-040:
  desc: "移动 feature 目录到 active"
  !! OP_BASH("mv {REG_PENDING_DIR} {REG_ACTIVE_DIR}")
  -> STP-041

STP-041:
  desc: "更新 .status 文件"
  !! OP_STATUS_UPDATE("{REG_ACTIVE_DIR}/.status", {
    status: started,
    stage: init,
    branch: REG_BRANCH,
    worktree: REG_WORKTREE,
    stp_pointer: STP-041,
    started_at: NOW()
  })
  -> STP-050

# ═══════════════════════════════════════════════════════════════════
# [Phase: QUEUE UPDATE]
# ═══════════════════════════════════════════════════════════════════

STP-050:
  desc: "从 pending 移除"
  !! OP_QUEUE_REMOVE(REG_QUEUE, "pending", REG_FEATURE_ID)
  -> STP-051

STP-051:
  desc: "添加到 active"
  !! OP_QUEUE_ADD(REG_QUEUE, "active", {
    id: REG_FEATURE_ID,
    name: REG_FEATURE_ENTRY.name,
    branch: REG_BRANCH,
    worktree: REG_WORKTREE,
    started: NOW()
  })
  -> STP-052

STP-052:
  desc: "保存队列"
  !! OP_FS_WRITE("feature-workflow-LockStep/queue.yaml", REG_QUEUE)
  -> STP-100

# ═══════════════════════════════════════════════════════════════════
# [Phase: COMPLETION]
# ═══════════════════════════════════════════════════════════════════

STP-100:
  desc: "显示启动结果"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
  ║                    ✅ Feature 已启动                                        ║
  ╠═══════════════════════════════════════════════════════════════════════╣
  ║                                                                       ║
  ║  Feature:     {REG_FEATURE_ID} ({REG_FEATURE_ENTRY.name})              ║
  ║  分支:        {REG_BRANCH}                                           ║
  ║  Worktree:    {REG_WORKTREE}                                         ║
  ║                                                                       ║
  ║  📁 文件位置:                                                          ║
  ║     {REG_ACTIVE_DIR}/                                                 ║
  ║                                                                       ║
  ║  下一步:                                                                ║
  ║    cd {REG_WORKTREE}                  # 进入工作目录                      ║
  ║    /implement-feature {REG_FEATURE_ID}  # 实现代码                        ║
  ║    或                                                                 ║
  ║    /parallel-dev                       # 并行开发                        ║
  ╚═══════════════════════════════════════════════════════════════════════╝
  ")
  -> STP-END

# ═══════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING]
# ═══════════════════════════════════════════════════════════════════

STP-ERR-NO_ID:
  desc: "没有指定 Feature ID"
  !! OP_UI_NOTIFY("❌ 错误: 请指定 Feature ID 或使用 --next")
  -> STP-HALT

STP-ERR-NO_PENDING:
  desc: "没有待开发的 feature"
  !! OP_UI_NOTIFY("❌ 错误: pending 列表为空")
  -> STP-HALT

STP-ERR-QUEUE:
  desc: "队列文件读取失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取队列文件")
  -> STP-HALT

STP-ERR-NOT_PENDING:
  desc: "Feature 不在 pending 列表"
  !! OP_UI_NOTIFY("❌ 错误: Feature '{REG_FEATURE_ID}' 不在 pending 列表")
  -> STP-HALT

STP-ERR-DEPS_NOT_MET:
  desc: "依赖未满足"
  !! OP_UI_NOTIFY("❌ 错误: 依赖未满足: {REG_DEP_RESULT.unsatisfied}")
  -> STP-HALT

STP-ERR-CONFIG:
  desc: "配置读取失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取配置文件")
  -> STP-HALT

STP-ERR-WORKTREE_EXISTS:
  desc: "Worktree 已存在"
  !! OP_UI_NOTIFY("❌ 错误: Worktree 已存在: {REG_WORKTREE}")
  -> STP-HALT

STP-ERR-PENDING_NOT_FOUND:
  desc: "Pending 目录不存在"
  !! OP_UI_NOTIFY("❌ 错误: Feature 目录不存在: {REG_PENDING_DIR}")
  -> STP-HALT

STP-ERR-BRANCH_CREATE:
  desc: "分支创建失败"
  !! OP_UI_NOTIFY("❌ 错误: 分支创建失败: {REG_BRANCH_RESULT.error}")
  -> STP-HALT

STP-ERR-WORKTREE_CREATE:
  desc: "Worktree 创建失败"
  !! OP_UI_NOTIFY("❌ 错误: Worktree 创建失败: {REG_WORKTREE_RESULT.error}")
  -> STP-HALT

STP-ERR-WORKTREE_VERIFY:
  desc: "Worktree 验证失败"
  !! OP_UI_NOTIFY("❌ 错误: Worktree 验证失败，未在列表中找到")
  -> STP-HALT

STP-HALT:
  desc: "停止执行"
  -> END
```
