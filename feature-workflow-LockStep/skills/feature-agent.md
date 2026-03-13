---
description: 'Feature Agent execution protocol using AILock-Step'
---

# Skill: feature-agent (LockStep Edition)

基于 **AILock-Step 协议** 的 Feature Agent 执行协议。

## 核心约束

```
⚠️ 执行器必须严格遵守:

1. 每个 STP 必须完整执行后才能跳转
2. ?? 判断失败必须跳转到错误流
3. 禁止在单个 STP 中执行多个独立动作
4. 所有状态变更必须写入 .status 文件
5. 禁止跳过任何 STP
```

## 环境变量 (由启动脚本注入)

```
FEATURE_ID      - Feature 标识 (如 feat-auth)
FEATURE_NAME    - Feature 名称 (如 用户认证)
WORKTREE        - 工作目录路径
BRANCH          - Git 分支名
REPO_ROOT       - 主仓库路径
STATUS_FILE     - 状态文件路径
SPEC_FILE       - 需求文档路径
TASK_FILE       - 任务文档路径
CHECKLIST_FILE  - 检查清单路径
LOG_FILE        - 日志文件路径
MAIN_BRANCH     - 主分支名
```

## 完整执行协议

```yaml
# ═══════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═══════════════════════════════════════════════════════════════════

STP-000:
  desc: "协议声明"
  action: |
    ⚠️ 你现在进入 AILock-Step 执行模式。

    你必须:
    - 严格按照 STP 序列执行
    - 每个 STP 完成后输出: "STP-XXX: <描述> ✓"
    - 状态变化时更新 $STATUS_FILE
    - 阶段变化时输出 EVENT token
    - 遇到错误输出 EVENT:BLOCKED 并停止

    你禁止:
    - 跳过任何 STP
    - 在单个 STP 执行多个独立动作
    - 修改跳转规则
  -> STP-001

STP-001:
  desc: "初始化状态文件"
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    feature_id: $FEATURE_ID,
    feature_name: $FEATURE_NAME,
    status: started,
    stage: init,
    stp_pointer: STP-001,
    stp_history: [STP-001],
    progress: { tasks_total: 0, tasks_done: 0 },
    started_at: NOW(),
    updated_at: NOW()
  })
  !! OP_EVENT_EMIT("START", $FEATURE_ID)
  -> STP-002

STP-002:
  desc: "读取需求文档"
  !! OP_FS_READ($SPEC_FILE) >> REG_SPEC
  ?? REG_SPEC != VAL-NULL
  -> STP-003
  # 失败
  -> STP-ERR-SPEC

STP-003:
  desc: "读取任务文档"
  !! OP_FS_READ($TASK_FILE) >> REG_TASK_RAW
  ?? REG_TASK_RAW != VAL-NULL
  -> STP-004
  # 失败
  -> STP-ERR-TASK

STP-004:
  desc: "解析任务列表"
  !! OP_ANALYSE(REG_TASK_RAW, "task_list") >> REG_TASK_ALL
  !! OP_COUNT(REG_TASK_ALL, "status=open") >> REG_TASKS_OPEN
  !! OP_COUNT(REG_TASK_ALL, "*") >> REG_TASKS_TOTAL
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    progress: { tasks_total: REG_TASKS_TOTAL, tasks_done: 0 },
    stp_pointer: STP-004
  })
  -> STP-010

# ═══════════════════════════════════════════════════════════════════
# [Phase: IMPLEMENT]
# ═══════════════════════════════════════════════════════════════════

STP-010:
  desc: "进入 IMPLEMENT 阶段"
  !! OP_EVENT_EMIT("STAGE", $FEATURE_ID, "implement")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: implementing,
    stage: implement,
    stp_pointer: STP-010,
    stp_history: [..., STP-010]
  })
  !! OP_UI_NOTIFY("STP-010: 进入 IMPLEMENT 阶段 ✓")
  -> STP-011

STP-011:
  desc: "获取下一个待完成任务"
  !! OP_GET_TOP(REG_TASK_ALL, "status=open") >> REG_CUR_TASK
  ?? REG_CUR_TASK != VAL-NULL
  -> STP-012
  # 没有待完成任务
  -> STP-100

STP-012:
  desc: "更新当前任务信息"
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    progress: { current_task: REG_CUR_TASK.description },
    stp_pointer: STP-012
  })
  !! OP_UI_NOTIFY("STP-012: 开始任务 - {REG_CUR_TASK.id}: {REG_CUR_TASK.description} ✓")
  -> STP-013

STP-013:
  desc: "实现当前任务代码"
  !! OP_CODE_GEN({
    spec: REG_SPEC,
    task: REG_CUR_TASK,
    worktree: $WORKTREE,
    existing_tasks: REG_TASK_ALL
  }, REG_CUR_TASK.description) >> REG_NEW_CODE
  -> STP-014

STP-014:
  desc: "写入代码文件"
  !! OP_FS_WRITE(REG_CUR_TASK.path, REG_NEW_CODE)
  !! OP_UI_NOTIFY("STP-014: 代码已写入 {REG_CUR_TASK.path} ✓")
  -> STP-015

STP-015:
  desc: "标记任务完成"
  !! OP_TASK_SYNC(REG_CUR_TASK.id, "done")
  !! OP_ANALYSE(REG_TASK_ALL, "update_task_status", {id: REG_CUR_TASK.id, status: done}) >> REG_TASK_ALL
  !! OP_COUNT(REG_TASK_ALL, "status=done") >> REG_TASKS_DONE
  !! OP_EVENT_EMIT("PROGRESS", $FEATURE_ID, "{REG_TASKS_DONE}/{REG_TASKS_TOTAL}")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    progress: { tasks_done: REG_TASKS_DONE },
    stp_pointer: STP-015
  })
  !! OP_UI_NOTIFY("STP-015: 任务 {REG_CUR_TASK.id} 完成 ✓ ({REG_TASKS_DONE}/{REG_TASKS_TOTAL})")
  -> STP-011  # 回旋跳转

# ═══════════════════════════════════════════════════════════════════
# [Phase: VERIFY] - ⚠️ 强制执行，不能跳过
# ═══════════════════════════════════════════════════════════════════

STP-100:
  desc: "验证所有任务已完成"
  !! OP_COUNT(REG_TASK_ALL, "status=open") >> REG_REMAINING
  ?? REG_REMAINING == 0
  -> STP-101
  # 还有未完成任务
  -> STP-ERR-INCOMPLETE

STP-101:
  desc: "进入 VERIFY 阶段"
  !! OP_EVENT_EMIT("STAGE", $FEATURE_ID, "verify")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: verifying,
    stage: verify,
    stp_pointer: STP-101,
    stp_history: [..., STP-101]
  })
  !! OP_UI_NOTIFY("STP-101: 进入 VERIFY 阶段 ✓")
  -> STP-102

STP-102:
  desc: "运行 Lint 检查"
  !! OP_BASH("cd $WORKTREE && npm run lint 2>&1") >> REG_LINT_RESULT
  ?? REG_LINT_RESULT CONTAINS "error" OR REG_LINT_RESULT EXIT_CODE != 0
  -> STP-ERR-LINT
  # 通过
  !! OP_UI_NOTIFY("STP-102: Lint 检查通过 ✓")
  -> STP-103

STP-103:
  desc: "运行测试"
  !! OP_BASH("cd $WORKTREE && npm test 2>&1") >> REG_TEST_RESULT
  ?? REG_TEST_RESULT CONTAINS "FAIL" OR REG_TEST_RESULT EXIT_CODE != 0
  -> STP-ERR-TEST
  # 通过
  !! OP_UI_NOTIFY("STP-103: 测试通过 ✓")
  -> STP-104

STP-104:
  desc: "读取检查清单"
  !! OP_FS_READ($CHECKLIST_FILE) >> REG_CHECKLIST_RAW
  ?? REG_CHECKLIST_RAW != VAL-NULL
  -> STP-105
  # 文件不存在，跳过
  -> STP-110

STP-105:
  desc: "解析检查清单"
  !! OP_ANALYSE(REG_CHECKLIST_RAW, "checklist_items") >> REG_CHECKLIST
  !! OP_COUNT(REG_CHECKLIST, "checked=false") >> REG_UNCHECKED_COUNT
  ?? REG_UNCHECKED_COUNT == 0
  -> STP-110
  # 有未检查项
  -> STP-ERR-CHECKLIST

STP-110:
  desc: "验证阶段完成"
  !! OP_UI_NOTIFY("STP-110: VERIFY 阶段完成 ✓")
  -> STP-200

# ═══════════════════════════════════════════════════════════════════
# [Phase: COMPLETE]
# ═══════════════════════════════════════════════════════════════════

STP-200:
  desc: "进入 COMPLETE 阶段"
  !! OP_EVENT_EMIT("STAGE", $FEATURE_ID, "complete")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: completing,
    stage: complete,
    stp_pointer: STP-200,
    stp_history: [..., STP-200]
  })
  !! OP_UI_NOTIFY("STP-200: 进入 COMPLETE 阶段 ✓")
  -> STP-201

STP-201:
  desc: "检查是否有变更"
  !! OP_BASH("cd $WORKTREE && git status --porcelain") >> REG_GIT_STATUS
  ?? REG_GIT_STATUS != ""
  -> STP-202
  # 没有变更
  !! OP_UI_NOTIFY("STP-201: 没有代码变更需要提交 ✓")
  -> STP-210

STP-202:
  desc: "暂存所有变更"
  !! OP_BASH("cd $WORKTREE && git add .")
  !! OP_UI_NOTIFY("STP-202: 变更已暂存 ✓")
  -> STP-203

STP-203:
  desc: "提交代码"
  !! OP_BASH("cd $WORKTREE && git commit -m 'feat($FEATURE_ID): $FEATURE_NAME'") >> REG_COMMIT_HASH
  !! OP_UI_NOTIFY("STP-203: 已提交 {REG_COMMIT_HASH} ✓")
  -> STP-210

STP-210:
  desc: "标记完成状态"
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: done,
    stp_pointer: STP-END,
    completion: {
      commit: REG_COMMIT_HASH,
      finished_at: NOW()
    }
  })
  !! OP_EVENT_EMIT("COMPLETE", $FEATURE_ID, "done")
  !! OP_UI_NOTIFY("STP-210: Feature $FEATURE_ID 完成 ✓")
  -> STP-END

# ═══════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING]
# ═══════════════════════════════════════════════════════════════════

STP-ERR-SPEC:
  desc: "需求文档不存在"
  !! OP_EVENT_EMIT("ERROR", $FEATURE_ID, "需求文档不存在: $SPEC_FILE")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: error,
    error: { type: file_not_found, file: $SPEC_FILE, stp: STP-002 }
  })
  -> STP-HALT

STP-ERR-TASK:
  desc: "任务文档不存在"
  !! OP_EVENT_EMIT("ERROR", $FEATURE_ID, "任务文档不存在: $TASK_FILE")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: error,
    error: { type: file_not_found, file: $TASK_FILE, stp: STP-003 }
  })
  -> STP-HALT

STP-ERR-INCOMPLETE:
  desc: "存在未完成任务"
  !! OP_EVENT_EMIT("BLOCKED", $FEATURE_ID, "存在 {REG_REMAINING} 个未完成任务")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: blocked,
    blocked: { reason: "任务未完成", remaining: REG_REMAINING, stp: STP-100 }
  })
  -> STP-HALT

STP-ERR-LINT:
  desc: "Lint 检查失败"
  !! OP_EVENT_EMIT("BLOCKED", $FEATURE_ID, "Lint 检查失败")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: blocked,
    blocked: { reason: "Lint 失败", details: REG_LINT_RESULT, stp: STP-102 }
  })
  -> STP-HALT

STP-ERR-TEST:
  desc: "测试失败"
  !! OP_EVENT_EMIT("BLOCKED", $FEATURE_ID, "测试失败")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: blocked,
    blocked: { reason: "测试失败", details: REG_TEST_RESULT, stp: STP-103 }
  })
  -> STP-HALT

STP-ERR-CHECKLIST:
  desc: "检查清单未完成"
  !! OP_EVENT_EMIT("BLOCKED", $FEATURE_ID, "检查清单有 {REG_UNCHECKED_COUNT} 项未完成")
  !! OP_STATUS_UPDATE($STATUS_FILE, {
    status: blocked,
    blocked: { reason: "检查清单未完成", unchecked: REG_UNCHECKED_COUNT, stp: STP-105 }
  })
  -> STP-HALT

STP-HALT:
  desc: "执行停止"
  !! OP_UI_NOTIFY("
⚠️ 执行已停止

Feature: $FEATURE_ID
状态: 请查看 $STATUS_FILE

恢复方法:
1. 解决阻塞问题
2. 运行 /parallel-dev 自动恢复
  ")
  -> END

# ═══════════════════════════════════════════════════════════════════
# [Phase: END]
# ═══════════════════════════════════════════════════════════════════

STP-END:
  desc: "正常结束"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
  ║                    ✅ Feature Agent 完成                              ║
  ╠═══════════════════════════════════════════════════════════════════════╣
  ║                                                                       ║
  ║  Feature: $FEATURE_ID ($FEATURE_NAME)                                 ║
  ║  状态: done                                                           ║
  ║  任务: {REG_TASKS_DONE}/{REG_TASKS_TOTAL}                             ║
  ║  提交: {REG_COMMIT_HASH}                                              ║
  ║                                                                       ║
  ║  主 Agent 将自动处理合并和归档                                        ║
  ╚═══════════════════════════════════════════════════════════════════════╝
  ")
  -> END
```

## 状态文件格式

```yaml
# features/active-{id}/.status
feature_id: feat-auth
feature_name: 用户认证
status: started | implementing | verifying | completing | done | blocked | error
stage: init | implement | verify | complete
stp_pointer: STP-012           # 当前 STP 指针 (用于恢复)
stp_history:                   # STP 执行历史
  - STP-001
  - STP-002
  - STP-003
  - STP-004
  - STP-010
  - STP-011
  - STP-012    # 当前
progress:
  tasks_total: 5
  tasks_done: 3
  current_task: "实现登录 API"
started_at: 2026-03-05T10:00:00Z
updated_at: 2026-03-05T10:30:00Z

# 完成时
completion:
  commit: abc123
  finished_at: 2026-03-05T12:30:00Z

# 阻塞时
blocked:
  reason: "Lint 检查失败"
  details: "..."
  stp: STP-102    # 阻塞点

# 错误时
error:
  type: file_not_found
  file: spec.md
  stp: STP-002
```

## 恢复机制

当 Feature Agent 中断后恢复：

```yaml
STP-RESUME:
  desc: "恢复执行"
  !! OP_FS_READ($STATUS_FILE) >> REG_SAVED_STATUS
  !! OP_UI_NOTIFY("从 {REG_SAVED_STATUS.stp_pointer} 恢复执行...")
  -> REG_SAVED_STATUS.stp_pointer
```

## 可用工具

```
允许使用: Bash, Read, Write, Edit, Glob, Grep
禁止使用: Task, Skill (避免嵌套执行)
```
