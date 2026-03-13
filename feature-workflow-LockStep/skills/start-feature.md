---
description: 'Start feature development using AILock-Step protocol'
---

# Skill: start-feature (LockStep Edition)

基于 **AILock-Step 协议** 的特性启动流程。创建 worktree 和分支。

## Usage

```
/parallel-dev                      # 自动调度启动
/start-feature <id>                # 启动指定 feature
/start-feature --next              # 启动下一个优先级最高的 pending feature
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
# [Phase: INITIALIZATION]
# ═══════════════════════════════════════════════════════════════════

STP-001:
  desc: "解析参数"
  !! REG_FEATURE_ID := $ARGS
  ?? REG_FEATURE_ID != VAL-NULL AND REG_FEATURE_ID != "--next"
  -> STP-010
  ?? REG_FEATURE_ID == "--next"
  -> STP-003
  # 否则
  -> STP-ERR-NO_ID

STP-003:
  desc: "获取下一个 pending feature"
  !! OP_FS_READ("feature-workflow/queue.yaml") >> REG_QUEUE
  ?? REG_QUEUE != VAL-NULL
  -> STP-004
  -> STP-ERR-QUEUE

STP-004:
  desc: "选择优先级最高且依赖满足的 feature"
  !! OP_FIND_SCHEDULABLE(REG_QUEUE.pending, REG_QUEUE.completed) >> REG_CANDIDATES
  ?? REG_CANDIDATES != VAL-NULL AND LENGTH(REG_CANDIDATES) > 0
  -> STP-005
  -> STP-ERR-NO_PENDING

STP-005:
  desc: "设置 Feature ID"
  !! REG_FEATURE_ID := REG_CANDIDATES[0].id
  !! OP_UI_NOTIFY("🚀 自动选择: {REG_FEATURE_ID}")
  -> STP-010

# ═══════════════════════════════════════════════════════════════════
# [Phase: VALIDATION]
# ═══════════════════════════════════════════════════════════════════

STP-010:
  desc: "读取配置文件，获取主仓库根目录"
  !! OP_BASH("git rev-parse --show-toplevel") >> REG_REPO_ROOT
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/config.yaml") >> REG_CONFIG
  ?? REG_CONFIG != VAL-NULL
  -> STP-011
  # 失败
  -> STP-ERR-CONFIG

STP-011:
  desc: "读取队列"
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/queue.yaml") >> REG_QUEUE
  ?? REG_QUEUE != VAL-NULL
  -> STP-012
  -> STP-ERR-QUEUE

STP-012:
  desc: "检查 feature 是否在 pending 列表"
  !! OP_FIND(REG_QUEUE.pending, "id", REG_FEATURE_ID) >> REG_FEATURE_ENTRY
  ?? REG_FEATURE_ENTRY != VAL-NULL
  -> STP-013
  -> STP-ERR-NOT_PENDING

STP-013:
  desc: "检查依赖是否满足"
  !! REG_DEPENDENCIES := REG_FEATURE_ENTRY.dependencies
  ?? REG_DEPENDENCIES == VAL-NULL OR LENGTH(REG_DEPENDENCIES) == 0
  -> STP-020
  # 需要检查依赖
  -> STP-014

STP-014:
  desc: "验证每个依赖"
  !! OP_FOREACH(REG_DEPENDENCIES, "check_completed", REG_QUEUE.completed) >> REG_DEP_RESULT
  ?? REG_DEP_RESULT.all_satisfied == true
  -> STP-020
  -> STP-ERR-DEPS_NOT_MET

STP-015:
  desc: "检查并行限制"
  !! REG_MAX_CONCURRENT := REG_CONFIG.parallelism.max_concurrent
  ?? REG_MAX_CONCURRENT == VAL-NULL
  !! REG_MAX_CONCURRENT := 2
  !! REG_CURRENT_ACTIVE := LENGTH(REG_QUEUE.active)
  ?? REG_CURRENT_ACTIVE < REG_MAX_CONCURRENT
  -> STP-020
  -> STP-ERR-LIMIT_EXCEEDED

# ═══════════════════════════════════════════════════════════════════
# [Phase: PREPARATION]
# ═══════════════════════════════════════════════════════════════════

STP-020:
  desc: "生成路径名称"
  !! REG_BRANCH := "feature/{REG_FEATURE_ID#feat-}"
  !! REG_WORKTREE_BASE := REG_CONFIG.paths.worktree_base
  ?? REG_WORKTREE_BASE == VAL-NULL OR REG_WORKTREE_BASE == ""
  !! REG_WORKTREE_BASE := ".worktrees"
  !! REG_WORKTREE := "{REG_WORKTREE_BASE}/{REG_FEATURE_ID}"
  !! REG_PENDING_DIR := "{REG_REPO_ROOT}/features/pending-{REG_FEATURE_ID}"
  !! REG_ACTIVE_DIR := "{REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}"
  !! OP_UI_NOTIFY("STP-020: 生成分支 {REG_BRANCH}, worktree {REG_WORKTREE}")
  -> STP-021

STP-021:
  desc: "检查 worktree 是否已存在"
  !! OP_FS_EXISTS(REG_WORKTREE) >> REG_WORKTREE_EXISTS
  ?? REG_WORKTREE_EXISTS == VAL-NULL
  -> STP-022
  -> STP-ERR-WORKTREE_EXISTS

STP-022:
  desc: "检查 pending 目录是否存在"
  !! OP_FS_EXISTS(REG_PENDING_DIR) >> REG_PENDING_EXISTS
  ?? REG_PENDING_EXISTS != VAL-NULL
  -> STP-023
  -> STP-ERR-PENDING_NOT_FOUND

STP-023:
  desc: "读取 feature 信息"
  !! OP_FS_READ("{REG_PENDING_DIR}/spec.md") >> REG_SPEC
  !! OP_FS_READ("{REG_PENDING_DIR}/task.md") >> REG_TASK
  !! REG_FEATURE_NAME := EXTRACT_TITLE(REG_SPEC)
  !! OP_UI_NOTIFY("STP-023: Feature 名称: {REG_FEATURE_NAME}")
  -> STP-030

# ═══════════════════════════════════════════════════════════════════
# [Phase: GIT OPERATIONS]
# ═══════════════════════════════════════════════════════════════════

STP-030:
  desc: "检查分支是否已存在"
  !! OP_BASH("git branch --list {REG_BRANCH}") >> REG_BRANCH_CHECK
  ?? REG_BRANCH_CHECK == ""
  -> STP-031
  # 分支已存在，直接创建 worktree
  -> STP-035

STP-031:
  desc: "创建分支"
  !! OP_BASH("git branch {REG_BRANCH}") >> REG_BRANCH_RESULT
  ?? REG_BRANCH_RESULT.exit_code == 0
  -> STP-035
  -> STP-ERR-BRANCH_CREATE

STP-035:
  desc: "检查 worktree 是否已注册"
  !! OP_BASH("git worktree list") >> REG_WORKTREE_LIST
  ?? REG_WORKTREE_LIST NOT_CONTAINS REG_WORKTREE
  -> STP-036
  # worktree 已存在，跳过创建
  -> STP-ERR-WORKTREE_EXISTS

STP-036:
  desc: "创建 worktree"
  !! OP_BASH("git worktree add {REG_WORKTREE} {REG_BRANCH}") >> REG_WORKTREE_RESULT
  ?? REG_WORKTREE_RESULT.exit_code == 0
  -> STP-037
  -> STP-ERR-WORKTREE_CREATE

STP-037:
  desc: "验证 worktree 创建成功"
  !! OP_BASH("git worktree list") >> REG_WORKTREE_LIST
  ?? REG_WORKTREE_LIST CONTAINS REG_WORKTREE
  -> STP-040
  -> STP-ERR-WORKTREE_VERIFY

# ═══════════════════════════════════════════════════════════════════
# [Phase: FILE MIGRATION]
# ═══════════════════════════════════════════════════════════════════

STP-040:
  desc: "移动 feature 目录到 active"
  !! OP_BASH("mv {REG_PENDING_DIR} {REG_ACTIVE_DIR}")
  !! OP_UI_NOTIFY("STP-040: 目录已移动 pending -> active")
  -> STP-041

STP-041:
  desc: "创建 .status 文件"
  !! NOW := TIMESTAMP()
  !! OP_FS_WRITE("{REG_ACTIVE_DIR}/.status", "
feature_id: {REG_FEATURE_ID}
feature_name: {REG_FEATURE_NAME}
status: started
stage: init
branch: {REG_BRANCH}
worktree: {REG_WORKTREE}
stp_pointer: STP-041
stp_history:
  - STP-041
progress:
  tasks_total: 0
  tasks_done: 0
  current_task: null
started_at: {NOW}
updated_at: {NOW}
  ")
  !! OP_UI_NOTIFY("STP-041: 状态文件已创建")
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
    name: REG_FEATURE_NAME,
    branch: REG_BRANCH,
    worktree: REG_WORKTREE,
    started: NOW
  })
  -> STP-052

STP-052:
  desc: "保存队列"
  !! OP_FS_WRITE("{REG_REPO_ROOT}/feature-workflow/queue.yaml", REG_QUEUE)
  !! OP_UI_NOTIFY("STP-052: 队列已更新")
  -> STP-100

# ═══════════════════════════════════════════════════════════════════
# [Phase: COMPLETION]
# ═══════════════════════════════════════════════════════════════════

STP-100:
  desc: "显示启动结果"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
║                    ✅ Feature 已启动                                   ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                       ║
║  Feature:     {REG_FEATURE_ID} ({REG_FEATURE_NAME})                   ║
║  分支:        {REG_BRANCH}                                            ║
║  Worktree:    {REG_WORKTREE}                                          ║
║                                                                       ║
║  📁 文件位置:                                                          ║
║     {REG_ACTIVE_DIR}/                                                 ║
║                                                                       ║
║  下一步:                                                                ║
║    cd {REG_WORKTREE}                  # 进入工作目录                    ║
║    /feature-agent {REG_FEATURE_ID}    # 启动 Feature Agent            ║
║    或                                                                 ║
║    /parallel-dev                       # 并行开发监控                   ║
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
  !! OP_UI_NOTIFY("❌ 错误: 没有满足依赖条件的 pending feature")
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

STP-ERR-LIMIT_EXCEEDED:
  desc: "已达并行上限"
  !! OP_UI_NOTIFY("❌ 错误: 已达并行上限 ({REG_CURRENT_ACTIVE}/{REG_MAX_CONCURRENT})")
  -> STP-HALT

STP-ERR-CONFIG:
  desc: "配置读取失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取配置文件")
  -> STP-HALT

STP-ERR-WORKTREE_EXISTS:
  desc: "Worktree 已存在"
  !! OP_UI_NOTIFY("❌ 错误: Worktree 已存在: {REG_WORKTREE}")
  !! OP_UI_NOTIFY("💡 提示: 使用 'git worktree remove {REG_WORKTREE}' 清理后重试")
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

STP-END:
  desc: "正常结束"
  -> END
```

## 返回值

成功时返回:

```yaml
status: success
feature_id: feat-xxx
feature_name: Feature 名称
branch: feature/xxx
worktree: ../feat-xxx
active_dir: features/active-feat-xxx
```

失败时返回:

```yaml
status: error
error: 错误信息
```

## 辅助函数

### EXTRACT_TITLE

从 spec.md 提取标题:

```python
def EXTRACT_TITLE(spec_content):
    for line in spec_content.split('\n'):
        if line.startswith('# '):
            return line[2:].strip()
    return "Unknown"
```

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
    return result
```
