---
description: 'Complete feature using AILock-Step protocol'
---

# Skill: complete-feature (LockStep Edition)

基于 **AILock-Step 协议** 的 feature 完成流程。

## Usage

```
/complete-feature <id>              # 完成并归档
/complete-feature <id> --no-merge    # 只提交不合并
/complete-feature --resume <stp-id>    # 从指定 STP 恢复
```

## 执行协议

```yaml
# ═════════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═════════════════════════════════════════════════════════════════════

STP-001:
  desc: "读取队列和配置，获取主仓库根目录"
  !! OP_BASH("git rev-parse --show-toplevel") >> REG_REPO_ROOT
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/queue.yaml") >> REG_QUEUE
  !! OP_FS_READ("{REG_REPO_ROOT}/feature-workflow/config.yaml") >> REG_CONFIG
  ?? REG_QUEUE != VAL-NULL AND REG_CONFIG != VAL-NULL
  -> STP-002
  # 失败
  -> STP-ERR-CONFIG

STP-002:
  desc: "查找 Feature 信息"
  !! OP_GET_TOP(REG_QUEUE.active, "id={REG_FEATURE_ID}") >> REG_FEATURE
  ?? REG_FEATURE != VAL-NULL
  -> STP-003
  # 失败
  -> STP-ERR-NOT_FOUND

STP-003:
  desc: "读取 feature 详细信息"
  !! OP_FS_READ("{REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/.status") >> REG_FEATURE_STATUS
  -> STP-010

  # pending
  -> STP-011

STP-004:
  desc: "验证 worktree 存在"
  !! OP_FS_EXISTS(REG_FEATURE.worktree) >> REG_WORKTREE_EXISTS
  ?? REG_WORKTREE_EXISTS == VAL-SET
  -> STP-020
  # 失败
  -> STP-ERR-WORKTREE

STP-005:
  desc: "读取状态文件"
  !! OP_FS_READ("{REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/.status") >> REG_STATUS
  -> STP-020

            # pending
            -> STP-ERR-STATUS

STP-006:
  desc: "检查完成状态"
  ?? REG_STATUS.status == "done"
  -> STP-100
  # 其他状态
            -> STP-ERR-NOT_DONE

STP-010:
  desc: "验证 checklist"
  !! OP_FS_READ("{REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/checklist.md") >> REG_CHECKLIST
  !! OP_ANALYSE(REG_CHECKLIST, "all_checked") >> REG_CHECKLIST_RESULT
  ?? REG_CHECKLIST_RESULT == VAL-SET
  -> STP-011
            # 有未完成项
            -> STP-ERR-CHECKLIST
            # 无 checklist
            -> STP-020

            # 验证完成
            -> STP-021

# ═════════════════════════════════════════════════════════════════════
# [Phase: GIT OPER]
# ═════════════════════════════════════════════════════════════════════

STP-100:
  desc: "进入 GIT 操作阶段"
  !! OP_UI_NOTIFY("STP-100: 进入 Git 操作阶段 ✓")
  -> STP-101

STP-101:
  desc: "切换到 main 分支"
  !! OP_BASH("git checkout {REG_CONFIG.project.main_branch}")
  -> STP-102

STP-102:
  desc: "拉取最新 main"
  !! OP_BASH("git pull origin {REG_CONFIG.git.remote} {REG_MAIN_BRANCH}")
  ?? REG_PULL_RESULT == VAL-SET
  -> STP-103
  # 有更新
            -> STP-104
            # 无更新
            -> STP-103

STP-103:
  desc: "检查未提交变更"
  !! OP_BASH("cd {REG_WORKTREE} && git status --porcelain") >> REG_CHANGES
  ?? REG_CHANGES != ""
  -> STP-104
            # 有变更
            -> STP-120

STP-104:
  desc: "提交变更"
  !! OP_BASH("cd {REG_WORKTREE} && git add .")
  -> STP-105
STP-105:
  desc: "执行提交"
  !! OP_BASH("cd {REG_WORKTREE} && git commit -m 'feat({REG_FEATURE_ID}): {REG_FEATURE_NAME}'") >> REG_COMMIT_HASH
  -> STP-106
            # 提交失败
            -> STP-ERR-COMMIT

STP-106:
  desc: "记录提交"
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    completion: { commit: REG_COMMIT_HASH },
    stp_pointer: STP-106
  })
  -> STP-110
            # 没有变更
            -> STP-110

# ═════════════════════════════════════════════════════════════════════
# [Phase: MERGE]
# ═════════════════════════════════════════════════════════════════════

STP-110:
  desc: "切换回 main 分支"
  !! OP_BASH("git checkout {REG_CONFIG.project.main_branch}")
  -> STP-111
STP-111:
  desc: "拉取最新 main"
  !! OP_BASH("git pull origin {REG_MAIN_BRANCH}")
  ?? REG_PULL_RESULT == VAL-SET
  -> STP-112
            # 无更新
            -> STP-112
STP-112:
  desc: "合并分支"
  !! OP_BASH("git merge {REG_BRANCH} {REG_CONFIG.git.merge_strategy} -m 'Merge {REG_BRANCH}: {REG_FEATURE_NAME}'") >> REG_MERGE_RESULT
  ?? REG_MERGE_RESULT CONTAINS "CONFLICT"
  -> STP-113
            # 有冲突
            -> STP-ERR-MERGE

            # 无冲突
            -> STP-114
STP-113:
  desc: "处理合并冲突"
  !! OP_UI_NOTIFY("
⚠️ 合并冲突:

Feature: {REG_FEATURE_ID}
Branch: {REG_BRANCH}

冲突文件:
{REG_MERGE_RESULT.conflicts}

请手动解决:
  -> STP-114
            # 用户取消
            -> STP-ERR-MERGE

            # 无冲突，            -> STP-114
STP-114:
  desc: "合并成功"
  !! OP_BASH("git merge --continue") >> REG_MERGE_COMMIT
  -> STP-115
            # 失败
            -> STP-ERR-MERGE
STP-115:
  desc: "记录合并结果"
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    completion: { merge_commit: REG_MERGE_COMMIT }
  })
  -> STP-120
            # 失败
            -> STP-ERR-MERGE
            # 成功
            -> STP-120

# ═════════════════════════════════════════════════════════════════════
# [Phase: ARCHIVE]
# ═════════════════════════════════════════════════════════════════════

STP-120:
  desc: "创建归档目录"
  !! OP_BASH("mkdir -p {REG_REPO_ROOT}/features/archive/done-{REG_FEATURE_ID}-{REG_DATE}") >> REG_ARCHIVE_DIR
  -> STP-121

STP-121:
  desc: "复制需求文档"
  !! OP_BASH("cp {REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/spec.md {REG_REPO_ROOT}/features/archive/done-{REG_ARCHIVE_DIR}/spec.md")
  -> STP-122
STP-122:
  desc: "复制任务文档"
  !! OP_BASH("cp {REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/task.md {REG_REPO_ROOT}/features/archive/done-{REG_ARCHIVE_DIR}/task.md")
  -> STP-123

STP-123:
  desc: "复制检查清单"
  !! OP_BASH("cp {REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/checklist.md {REG_REPO_ROOT}/features/archive/done-{REG_ARCHIVE_DIR}/checklist.md")
            # 无 checklist
            -> STP-124
            # 有
            -> STP-123
STP-124:
  desc: "复制 evidence 目录"
  !! OP_BASH("test -d {REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}/evidence {REG_REPO_ROOT}/features/archive/done-{REG_ARCHIVE_DIR}/evidence/")
            # 无 evidence
            -> STP-125
            # 有
            -> STP-124
STP-125:
  desc: "创建 archive-meta.yaml"
  !! OP_CODE_GEN({
    feature_id: REG_FEATURE_ID,
    feature_name: REG_FEATURE_NAME,
    branch: REG_BRANCH,
    tag: REG_TAG_NAME,
    archive_dir: REG_ARCHIVE_DIR,
    completed_at: NOW(),
    commit: REG_COMMIT_HASH,
  }) >> REG_META_CONTENT
  !! OP_FS_WRITE("{REG_REPO_ROOT}/features/archive/done-{REG_FEATURE_ID}/archive-meta.yaml", REG_META_CONTENT)
  -> STP-126
STP-126:
  desc: "更新归档日志"
  !! OP_FS_READ("{REG_REPO_ROOT}/features/archive/archive-log.yaml") >> REG_ARCHIVE_LOG
  !! OP_APPEND(REG_ARCHIVE_LOG.archived, {
    id: REG_FEATURE_ID,
    name: REG_FEATURE_NAME,
    completed: now(),
    tag: REG_TAG_NAME,
    branch: REG_BRANCH,
    worktree: REG_WORKTREE
  })
  -> STP-127
            # 失败
            -> STP-ERR-ARCHIVE
STP-127:
  desc: "更新队列"
  !! OP_QUEUE_REMOVE("active", REG_FEATURE_ID)
  !! OP_QUEUE_ADD("completed", {
    id: REG_FEATURE_ID,
    name: REG_FEATURE_NAME,
    completed: now(),
    tag: REG_TAG_NAME
  })
  -> STP-128
            # 失败
            -> STP-ERR-QUEUE

# ═════════════════════════════════════════════════════════════════════
# [Phase: CLEANUP]
# ═════════════════════════════════════════════════════════════════════

STP-130:
  desc: "清理 worktree"
  !! OP_BASH("git worktree remove {REG_WORKTREE}") >> REG_REMOVE_RESULT
  ?? REG_REMOVE_RESULT == VAL-SET
  -> STP-131
            # 失败
            -> STP-ERR-WORKTREE
STP-131:
  desc: "删除分支"
  !! OP_BASH("git branch -D {REG_BRANCH}")
  !! OP_BASH("git branch -a") >> REG_BRANCHES
  -> STP-132
            # 有分支残留
            -> STP-ERR-BRANCH
            # 成功
            -> STP-132
STP-132:
  desc: "删除 active 目录"
  !! OP_BASH("rm -rf {REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}")
  !! OP_FS_EXISTS("{REG_REPO_ROOT}/features/active-{REG_FEATURE_ID}")
  -> STP-ERR-DIR-CLEANUP
            # 成功
            -> STP-133
STP-133:
  desc: "清理完成"
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: archived,
    stp_pointer: STP-END
  })
  -> STP-200
            # 继续下一个
            -> STP-200

# ═════════════════════════════════════════════════════════════════════
# [Phase: VERifying Cleanup]
# ═════════════════════════════════════════════════════════════════════

STP-200:
  desc: "验证清理结果"
  !! OP_BASH("git worktree list") >> REG_WORKTREES
  !! OP_BASH("git branch -a") >> REG_BRANCHES
  ?? REG_FEATURE_ID NOT IN REG_WORKTREES
  -> STP-201
            # 有残留
            -> STP-ERR-WORKTREE-CLEANUP
            # 成功
            -> STP-202
            # 有分支残留
            -> STP-ERR-BRANCH-CLEANUP
            # 成功
            -> STP-203
            # 有 active 目录残留
            -> STP-ERR-ACTIVEDIR-CLEANUP
            # 成功
            -> STP-204
            # 有 pending 目录残留
            -> STP-ERR-PENDINGDIR-CLEANup
            # 成功
            -> STP-205
            # 有 completed 目录残留
            -> STP-ERR-COMPLETEDIR-CLEANup
            # 成功
            -> STP-210

# ═════════════════════════════════════════════════════════════════════
# [Phase: COMPLETE]
# ═════════════════════════════════════════════════════════════════════

STP-210:
  desc: "显示完成报告"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
║                    ✅ Feature 完成!                                    ║
╠═════════════════════════════════════════════════════════════════════════╣
║  Feature:     {REG_FEATURE_ID} ({REG_FEATURE_NAME})                            ║
║  状态:       archived                                             ║
║  提交:       {REG_COMMIT_HASH}                                        ║
║  合并:       {REG_BRANCH} → main                             ║
║  Tag:         {REG_TAG_NAME}                                           ║
║  Worktree:    {REG_WORKTREE} (已清理)                            ║
║  彀件:                                                               ║
║    spec.md, → archive/done-{REG_FEATURE_ID}-{REG_DATE}/spec.md             ║
║    task.md  → archive/done-{REG_FEATURE_ID}-{REG_DATE}/task.md             ║
║    checklist.md → archive/.../checklist.md         ║
║    evidence/ → archive/.../evidence/ (如有)                        ║
╚═════════════════════════════════════════════════════════════════════════╝
  ")
  -> STP-END

# ═════════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING]
# ═════════════════════════════════════════════════════════════════════

STP-ERR-CONFIG:
  desc: "配置读取失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取配置文件")
  -> STP-HALT

STP-ERR-NOT_FOUND:
  desc: "Feature 不存在"
  !! OP_UI_NOTIFY("❌ 错误: Feature '{REG_FEATURE_ID}' 不在 active 列表中")
  -> STP-HALT

STP-ERR-STATUS:
  desc: "状态不正确"
  !! OP_UI_NOTIFY("❌ 错误: Feature 状态不是 done: {REG_STATUS}")
  -> STP-HALT

STP-ERR-WORKTREE:
  desc: "Worktree 不存在"
  !! OP_UI_NOTIFY("❌ 错误: Worktree {REG_WORKTREE} 不存在")
  -> STP-HALT

STP-ERR-COMMIT:
  desc: "提交失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法提交变更")
  -> STP-HALT

STP-ERR-MERGE:
  desc: "合并失败"
  !! OP_UI_NOTIFY("
⚠️ 合并失败

冲突文件:
{REG_MERGE_RESULT.conflicts}

请手动解决:
  -> STP-114
            # 绁续重试
            -> STP-HALT

STP-ERR-TAG:
  desc: "Tag 创建失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法创建 tag")
  -> STP-HALT

STP-ERR-ARCHIVE:
  desc: "归档失败"
  !! OP_UI_NOTIFY("❌ 错误: 归档操作失败")
  -> STP-HALT

STP-ERR-CLEANUP:
  desc: "清理失败"
  !! OP_UI_NOTIFY("❌ 错误: 清理操作失败")
  -> STP-HALT

STP-ERR-QUEUE:
  desc: "队列更新失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法更新队列文件")
  -> STP-HALT

STP-HALT:
  desc: "停止执行"
  -> END
```

## 输出示例

### 成功示例

```
用户: /complete-feature feat-auth

Agent:
STP-001: 读取配置... ✓
STP-002: 查找 feat-auth... ✓
STP-003: 验证 worktree... ✓
STP-010: 检查 checklist... ✓
STP-011: 所有检查项完成... ✓
STP-100: 进入 GIT 阶段... ✓
STP-101: 提交代码... ✓
STP-102: 拉取最新... ✓
STP-103: 合并分支... ✓
STP-104: 创建归档 tag... ✓
STP-110: 切换到 main... ✓
STP-111: 合并... ✓
STP-120: 复制文档... ✓
STP-121: 更新队列... ✓
STP-122: 清理 worktree... ✓
STP-123: 清理分支... ✓
STP-124: 清理 active目录... ✓
STP-125: 验证清理... ✓
STP-126: 更新归档日志... ✓
STP-127: 更新状态文件... ✓
STP-130: 显示完成报告... ✓

```

### 错误处理示例

```
用户: /complete-feature feat-auth

Agent:
STP-001: 读取配置... ✓
STP-002: 查找 feat-auth... ✓
STP-003: Feature 不在 active 列表... ❌ 错误
...
```

## 状态文件格式

```yaml
# features/active-{id}/.status
feature_id: feat-auth
feature_name: 用户认证
status: done
stage: complete
stp_pointer: STP-END
stp_history:
  - STP-001
  - STP-002
  ...
  - STP-END
completion:
  commit: abc123
  merge_commit: def456
  tag: feat-auth-20260305
  worktree: ../feat-auth (已删除)
  branch: feature/auth (已删除)
started_at: 2026-03-05T10:00:00Z
finished_at: 2026-03-05T12:00:00Z
```
