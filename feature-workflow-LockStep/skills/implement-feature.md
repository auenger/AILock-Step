---
description: 'Implement feature code using AILock-Step protocol'
---

# Skill: implement-feature (LockStep Edition)

基于 **AILock-Step 协议** 的 feature 实现流程。读取规范、分析任务、在 worktree 中编写代码。

## Usage

```
/implement-feature <id>                # 实现指定 feature
/implement-feature <id> --task=<n>     # 只实现特定任务
/implement-feature <id> --dry-run      # 仅分析，不实现
```

## 执行协议

```yaml
# ═══════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═══════════════════════════════════════════════════════════════════

STP-001:
  desc: "解析参数"
  !! REG_FEATURE_ID := EXTRACT_FEATURE_ID($ARGS)
  !! REG_TASK_INDEX := EXTRACT_ARG($ARGS, "--task=")
  !! REG_DRY_RUN := HAS_ARG($ARGS, "--dry-run")
  ?? REG_FEATURE_ID != VAL-NULL
  -> STP-002
  -> STP-ERR-NO_ID

STP-002:
  desc: "读取配置和队列"
  !! OP_BASH("git rev-parse --show-toplevel") >> REG_REPO_ROOT
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/queue.yaml") >> REG_QUEUE
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/config.yaml") >> REG_CONFIG
  ?? REG_QUEUE != VAL-NULL AND REG_CONFIG != VAL-NULL
  -> STP-003
  -> STP-ERR-CONFIG

STP-003:
  desc: "查找 Feature 信息"
  !! OP_GET_TOP(REG_QUEUE.active, "id={REG_FEATURE_ID}") >> REG_FEATURE
  ?? REG_FEATURE != VAL-NULL
  -> STP-010
  -> STP-ERR-NOT_ACTIVE

# ═══════════════════════════════════════════════════════════════════
# [Phase: DOCUMENT READING]
# ═══════════════════════════════════════════════════════════════════

STP-010:
  desc: "读取 Feature 文档"
  !! OP_FS_READ("{REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/spec.md") >> REG_SPEC
  !! OP_FS_READ("{REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/task.md") >> REG_TASK
  !! OP_FS_READ("{REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/.status") >> REG_STATUS
  ?? REG_SPEC != VAL-NULL AND REG_TASK != VAL-NULL
  -> STP-011
  -> STP-ERR-DOCS

STP-011:
  desc: "提取 Feature 名称"
  !! REG_FEATURE_NAME := EXTRACT_TITLE(REG_SPEC)
  !! OP_UI_NOTIFY("📋 正在分析: {REG_FEATURE_ID} ({REG_FEATURE_NAME})")
  -> STP-020

# ═══════════════════════════════════════════════════════════════════
# [Phase: TASK ANALYSIS]
# ═══════════════════════════════════════════════════════════════════

STP-020:
  desc: "解析任务列表"
  !! OP_ANALYSE(REG_TASK, "task_list") >> REG_TASK_LIST
  ?? REG_TASK_LIST != VAL-NULL
  -> STP-021
  -> STP-ERR-TASK_PARSE

STP-021:
  desc: "过滤未完成任务"
  !! OP_FILTER(REG_TASK_LIST, "status != done") >> REG_PENDING_TASKS
  !! REG_PENDING_COUNT := LENGTH(REG_PENDING_TASKS)
  ?? REG_PENDING_COUNT > 0
  -> STP-022
  -> STP-ERR-ALL_DONE

STP-022:
  desc: "分析任务依赖关系"
  !! OP_ANALYSE(REG_PENDING_TASKS, "dependencies") >> REG_TASK_DEPS
  !! OP_ANALYSE(REG_PENDING_TASKS, "suggested_order") >> REG_SUGGESTED_ORDER
  -> STP-023

STP-023:
  desc: "提取参考代码路径"
  !! OP_ANALYSE(REG_SPEC, "reference_code") >> REG_REF_CODE
  !! OP_ANALYSE(REG_SPEC, "reference_docs") >> REG_REF_DOCS
  -> STP-030

# ═══════════════════════════════════════════════════════════════════
# [Phase: PLAN DISPLAY]
# ═══════════════════════════════════════════════════════════════════

STP-030:
  desc: "生成实施计划"
  !! REG_IS_DRY_RUN := (REG_DRY_RUN == VAL-SET)
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
║                    📋 分析完成                                         ║
╠═══════════════════════════════════════════════════════════════════════╣
║  Feature:     {REG_FEATURE_ID} ({REG_FEATURE_NAME})                    ║
║                                                                       ║
║  待完成任务:   {REG_PENDING_COUNT}                                      ║
║  建议顺序:                                                           ║
  ")
  !! OP_FOREACH(REG_SUGGESTED_ORDER, "display_task", REG_PENDING_TASKS)
  !! OP_UI_NOTIFY("
║                                                                       ║
║  参考代码:                                                            ║
  ")
  !! OP_FOREACH(REG_REF_CODE, "display_path")
  !! OP_UI_NOTIFY("
║                                                                       ║
║  执行模式:     {REG_IS_DRY_RUN ? 'DRY-RUN (仅分析)' : 'IMPLEMENT (实现)'}    ║
╚═══════════════════════════════════════════════════════════════════════╝
  ")
  -> STP-031

STP-031:
  desc: "确认开始实施"
  ?? REG_DRY_RUN == VAL-SET
  -> STP-100
  !! OP_UI_ASK("是否开始实施? (y/n/edit)", ["y", "n", "edit"]) >> REG_CHOICE
  ?? REG_CHOICE == "y"
  -> STP-040
  ?? REG_CHOICE == "n"
  -> STP-HALT
  ?? REG_CHOICE == "edit"
  -> STP-032
  -> STP-HALT

STP-032:
  desc: "编辑计划"
  !! OP_UI_NOTIFY("💡 提示: 使用 /edit-feature-task {id} 修改任务列表")
  -> STP-HALT

# ═══════════════════════════════════════════════════════════════════
# [Phase: WORKTREE SWITCH]
# ═══════════════════════════════════════════════════════════════════

STP-040:
  desc: "获取 worktree 路径"
  !! REG_WORKTREE := REG_FEATURE.worktree
  ?? REG_WORKTREE != VAL-NULL
  -> STP-041
  -> STP-ERR-WORKTREE

STP-041:
  desc: "验证 worktree 存在"
  !! OP_FS_EXISTS(REG_WORKTREE) >> REG_WORKTREE_EXISTS
  ?? REG_WORKTREE_EXISTS == VAL-SET
  -> STP-042
  -> STP-ERR-WORKTREE_NOT_FOUND

STP-042:
  desc: "读取项目上下文"
  !! OP_FS_READ("{REG_REPO_ROOT}/features/project-context.md") >> REG_PROJECT_CONTEXT
  -> STP-050

# ═══════════════════════════════════════════════════════════════════
# [Phase: TASK LOOP - INIT]
# ═══════════════════════════════════════════════════════════════════

STP-050:
  desc: "准备任务循环"
  !! REG_TASK_INDEX := 0
  !! REG_TASK_TOTAL := LENGTH(REG_SUGGESTED_ORDER)
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: implementing,
    stage: implement,
    stp_pointer: STP-050,
    updated_at: NOW()
  })
  -> STP-051

# ═══════════════════════════════════════════════════════════════════
# [Phase: TASK LOOP - ITERATE]
# ═══════════════════════════════════════════════════════════════════

STP-051:
  desc: "检查是否还有任务"
  ?? REG_TASK_INDEX < REG_TASK_TOTAL
  -> STP-052
  -> STP-090

STP-052:
  desc: "获取当前任务"
  !! REG_CUR_TASK_ID := REG_SUGGESTED_ORDER[REG_TASK_INDEX]
  !! OP_FIND(REG_PENDING_TASKS, "id", REG_CUR_TASK_ID) >> REG_CUR_TASK
  ?? REG_CUR_TASK != VAL-NULL
  -> STP-053
  -> STP-051

STP-053:
  desc: "显示当前任务"
  !! OP_UI_NOTIFY("
┌─────────────────────────────────────────────────────────────────────┐
│  任务 [{REG_TASK_INDEX + 1}/{REG_TASK_TOTAL}]: {REG_CUR_TASK.title}              │
│  ID: {REG_CUR_TASK.id}                                              │
│  描述: {REG_CUR_TASK.description}                                    │
└─────────────────────────────────────────────────────────────────────┘
  ")
  -> STP-054

STP-054:
  desc: "检查任务依赖"
  !! REG_TASK_DEPS := REG_CUR_TASK.dependencies
  ?? REG_TASK_DEPS == VAL-NULL OR LENGTH(REG_TASK_DEPS) == 0
  -> STP-055
  !! OP_FOREACH(REG_TASK_DEPS, "check_dep_done", REG_TASK_LIST) >> REG_DEP_CHECK
  ?? REG_DEP_CHECK.all_done == true
  -> STP-055
  -> STP-ERR-TASK_DEPS

STP-055:
  desc: "收集上下文"
  !! REG_CTX_SPEC := REG_SPEC
  !! REG_CTX_PROJECT := REG_PROJECT_CONTEXT
  !! REG_CTX_REFS := REG_REF_CODE
  !! REG_CTX_TASK := REG_CUR_TASK
  -> STP-060

# ═══════════════════════════════════════════════════════════════════
# [Phase: CODE GENERATION]
# ═══════════════════════════════════════════════════════════════════

STP-060:
  desc: "生成代码"
  !! OP_CODE_GEN({
    spec: REG_CTX_SPEC,
    task: REG_CTX_TASK,
    project: REG_CTX_PROJECT,
    refs: REG_CTX_REFS
  }, "implement_task") >> REG_IMPLEMENTATION
  ?? REG_IMPLEMENTATION != VAL-NULL
  -> STP-061
  -> STP-ERR-CODE_GEN

STP-061:
  desc: "分析实施结果"
  !! OP_ANALYSE(REG_IMPLEMENTATION, "files") >> REG_FILES_CREATED
  !! OP_ANALYSE(REG_IMPLEMENTATION, "files_modified") >> REG_FILES_MODIFIED
  -> STP-062

STP-062:
  desc: "写入代码到 worktree"
  ?? REG_FILES_CREATED != VAL-NULL AND LENGTH(REG_FILES_CREATED) > 0
  !! OP_FOREACH(REG_FILES_CREATED, "write_file", REG_WORKTREE)
  -> STP-063
  -> STP-063

STP-063:
  desc: "更新任务状态"
  !! OP_TASK_SYNC(REG_CUR_TASK.id, "done")
  !! REG_TASK_INDEX := (REG_TASK_INDEX + 1)
  -> STP-051

# ═══════════════════════════════════════════════════════════════════
# [Phase: SELF-TEST]
# ═══════════════════════════════════════════════════════════════════

STP-090:
  desc: "所有任务完成，开始自测"
  !! OP_UI_NOTIFY("🧪 开始自测...")
  -> STP-091

STP-091:
  desc: "检查是否有测试命令"
  !! REG_TEST_CMD := REG_CONFIG.testing.test_command
  ?? REG_TEST_CMD != VAL-NULL AND REG_TEST_CMD != ""
  -> STP-092
  -> STP-093

STP-092:
  desc: "运行测试"
  !! OP_BASH("cd {REG_WORKTREE} && {REG_TEST_CMD} 2>&1") >> REG_TEST_RESULT
  !! OP_UI_NOTIFY("测试结果:\n{REG_TEST_RESULT}")
  -> STP-093

STP-093:
  desc: "手动验证"
  !! OP_UI_NOTIFY("
📋 自测清单:
  □ 代码已写入 worktree
  □ 任务状态已更新
  □ 无明显语法错误
  ")
  -> STP-100

# ═══════════════════════════════════════════════════════════════════
# [Phase: COMPLETION]
# ═══════════════════════════════════════════════════════════════════

STP-100:
  desc: "生成实施报告"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
║                    ✅ 实施完成                                        ║
╠═══════════════════════════════════════════════════════════════════════╣
║  Feature:     {REG_FEATURE_ID} ({REG_FEATURE_NAME})                    ║
║                                                                       ║
║  完成任务:     {REG_TASK_TOTAL}/{REG_TASK_TOTAL}                             ║
║  新增文件:     {COUNT(REG_FILES_CREATED)}                               ║
║  修改文件:     {COUNT(REG_FILES_MODIFIED)}                              ║
║                                                                       ║
║  下一步:                                                               ║
║    cd {REG_WORKTREE}                 # 进入工作目录                     ║
║    /verify-feature {REG_FEATURE_ID}  # 验证 feature                     ║
║    或                                                                  ║
║    /complete-feature {REG_FEATURE_ID} # 完成 feature                     ║
╚═══════════════════════════════════════════════════════════════════════╝
  ")
  -> STP-101

STP-101:
  desc: "更新状态文件"
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: implemented,
    stage: verify,
    stp_pointer: STP-END,
    updated_at: NOW(),
    implementation: {
      tasks_completed: REG_TASK_TOTAL,
      files_created: COUNT(REG_FILES_CREATED),
      files_modified: COUNT(REG_FILES_MODIFIED)
    }
  })
  -> STP-END

# ═══════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING]
# ═══════════════════════════════════════════════════════════════════

STP-ERR-NO_ID:
  desc: "没有指定 Feature ID"
  !! OP_UI_NOTIFY("❌ 错误: 请指定 Feature ID")
  -> STP-HALT

STP-ERR-CONFIG:
  desc: "配置读取失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取配置文件")
  -> STP-HALT

STP-ERR-NOT_ACTIVE:
  desc: "Feature 不在 active 列表"
  !! OP_UI_NOTIFY("❌ 错误: Feature '{REG_FEATURE_ID}' 不在 active 列表")
  !! OP_UI_NOTIFY("💡 提示: 使用 /start-feature {REG_FEATURE_ID} 先启动 feature")
  -> STP-HALT

STP-ERR-DOCS:
  desc: "文档读取失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取 feature 文档")
  !! OP_UI_NOTIFY("💡 提示: 确保 features/active-{REG_FEATURE_ID}/ 目录存在")
  -> STP-HALT

STP-ERR-TASK_PARSE:
  desc: "任务解析失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法解析 task.md")
  -> STP-HALT

STP-ERR-ALL_DONE:
  desc: "所有任务已完成"
  !! OP_UI_NOTIFY("✅ 所有任务已完成，无需实施")
  -> STP-END

STP-ERR-WORKTREE:
  desc: "Worktree 路径未配置"
  !! OP_UI_NOTIFY("❌ 错误: Feature 配置中缺少 worktree 路径")
  -> STP-HALT

STP-ERR-WORKTREE_NOT_FOUND:
  desc: "Worktree 不存在"
  !! OP_UI_NOTIFY("❌ 错误: Worktree {REG_WORKTREE} 不存在")
  !! OP_UI_NOTIFY("💡 提示: 使用 /start-feature {REG_FEATURE_ID} 创建 worktree")
  -> STP-HALT

STP-ERR-TASK_DEPS:
  desc: "任务依赖未满足"
  !! OP_UI_NOTIFY("❌ 错误: 任务 {REG_CUR_TASK.id} 的依赖未满足")
  !! OP_UI_NOTIFY("依赖: {REG_DEP_CHECK.unsatisfied}")
  -> STP-HALT

STP-ERR-CODE_GEN:
  desc: "代码生成失败"
  !! OP_UI_NOTIFY("❌ 错误: 代码生成失败")
  -> STP-HALT

STP-HALT:
  desc: "停止执行"
  -> END

STP-END:
  desc: "正常结束"
  -> END
```

## 输出示例

### 成功实施

```
STP-001: 解析参数... ✓
STP-002: 读取配置... ✓
STP-003: 查找 feat-auth... ✓
STP-010: 读取文档... ✓
STP-011: 提取名称... ✓
STP-020: 解析任务列表... ✓
STP-021: 过滤未完成任务... ✓ (4 tasks pending)
STP-022: 分析依赖关系... ✓
STP-023: 提取参考代码... ✓
STP-030: 生成实施计划... ✓

╔═══════════════════════════════════════════════════════════════════════╗
║                    📋 分析完成                                         ║
╠═══════════════════════════════════════════════════════════════════════╣
║  Feature:     feat-auth (用户认证)                                    ║
║                                                                       ║
║  待完成任务:   4                                                      ║
║  建议顺序:                                                           ║
║    1. 实现注册 API                                                    ║
║    2. 实现登录 API                                                    ║
║    3. 实现登出 API                                                    ║
║    4. 添加认证中间件                                                  ║
║                                                                       ║
║  参考代码:                                                            ║
║    - src/models/user.ts                                               ║
║    - src/middleware/                                                  ║
║                                                                       ║
║  执行模式:     IMPLEMENT (实现)                                        ║
╚═══════════════════════════════════════════════════════════════════════╝

STP-031: 确认开始实施... ✓
STP-040: 获取 worktree 路径... ✓
STP-041: 验证 worktree 存在... ✓
STP-042: 读取项目上下文... ✓
STP-050: 准备任务循环... ✓
STP-051: 检查任务... ✓
STP-052: 获取当前任务... ✓
STP-053: 显示任务 1/4... ✓
STP-054: 检查依赖... ✓
STP-055: 收集上下文... ✓
STP-060: 生成代码... ✓
STP-061: 分析结果... ✓
STP-062: 写入代码... ✓
STP-063: 更新任务状态... ✓
[... 重复 STP-051 -> STP-063 循环直到所有任务完成 ...]
STP-090: 所有任务完成，开始自测... ✓
STP-091: 检查测试命令... ✓
STP-092: 运行测试... ✓ (12 passed, 0 failed)
STP-093: 手动验证... ✓
STP-100: 生成实施报告... ✓
STP-101: 更新状态文件... ✓

╔═══════════════════════════════════════════════════════════════════════╗
║                    ✅ 实施完成                                        ║
╠═══════════════════════════════════════════════════════════════════════╣
║  Feature:     feat-auth (用户认证)                                    ║
║                                                                       ║
║  完成任务:     4/4                                                    ║
║  新增文件:     3                                                      ║
║  修改文件:     2                                                      ║
║                                                                       ║
║  下一步:                                                               ║
║    cd .worktrees/feat-auth           # 进入工作目录                     ║
║    /verify-feature feat-auth         # 验证 feature                     ║
║    或                                                                  ║
║    /complete-feature feat-auth       # 完成 feature                     ║
╚═══════════════════════════════════════════════════════════════════════╝
```

### Dry-Run 模式

```
用户: /implement-feature feat-auth --dry-run

Agent:
STP-001: 解析参数... ✓ (DRY-RUN 模式)
STP-002: 读取配置... ✓
[... 分析流程 ...]
STP-030: 生成实施计划... ✓
STP-031: 检测到 DRY-RUN 模式... 跳过实施
STP-100: 生成分析报告... ✓

╔═══════════════════════════════════════════════════════════════════════╗
║                    📋 分析完成 (DRY-RUN)                              ║
║  执行模式:     DRY-RUN (仅分析)                                        ║
╚═══════════════════════════════════════════════════════════════════════╝
```

## 状态文件格式

```yaml
# features/active-{id}/.status
feature_id: feat-auth
feature_name: 用户认证
status: implemented
stage: verify
stp_pointer: STP-END
stp_history:
  - STP-001
  - STP-002
  ...
  - STP-END
implementation:
  tasks_completed: 4
  files_created: 3
  files_modified: 2
started_at: 2026-03-05T10:00:00Z
updated_at: 2026-03-05T12:00:00Z
```

## 辅助函数

### EXTRACT_FEATURE_ID

从参数中提取 Feature ID:

```python
def EXTRACT_FEATURE_ID(args):
    if args and args[0] and not args[0].startswith("--"):
        return args[0]
    return VAL_NULL
```

### EXTRACT_ARG

提取特定参数:

```python
def EXTRACT_ARG(args, prefix):
    for arg in args:
        if arg.startswith(prefix):
            return arg[len(prefix):]
    return VAL_NULL
```

### HAS_ARG

检查是否存在特定参数:

```python
def HAS_ARG(args, flag):
    return flag in args
```

### EXTRACT_TITLE

从 spec.md 提取标题:

```python
def EXTRACT_TITLE(spec_content):
    for line in spec_content.split('\n'):
        if line.startswith('# '):
            return line[2:].strip()
    return "Unknown"
```
