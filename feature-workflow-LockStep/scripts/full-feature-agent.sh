#!/bin/bash
#
# full-feature-agent.sh - 端到端 Feature 开发 Agent (LockStep 协议)
#
# 用法: ./full-feature-agent.sh <feature-id> [start-at-phase]
#
# 合并四个 skill 的完整流程:
#   Phase 1: START    (start-feature)    - 创建 worktree 和分支
#   Phase 2: IMPLEMENT (implement-feature) - 实现代码
#   Phase 3: VERIFY   (verify-feature)   - 验证代码
#   Phase 4: COMPLETE (complete-feature)  - 提交、合并、归档
#
# LockStep 特性:
# - 单一协议驱动整个生命周期
# - 支持从任意阶段恢复
# - 严格的状态锚点和事件输出
#

set -o pipefail

# ═══════════════════════════════════════════════════════════════════
# 参数解析
# ═══════════════════════════════════════════════════════════════════

FEATURE_ID="${1:-}"
START_PHASE="${2:-START}"

if [ -z "$FEATURE_ID" ]; then
    echo "用法: $0 <feature-id> [start-at-phase]"
    echo ""
    echo "参数:"
    echo "  feature-id      Feature ID (如: feat-auth)"
    echo "  start-at-phase  开始阶段: START|IMPLEMENT|VERIFY|COMPLETE (默认: START)"
    echo ""
    echo "示例:"
    echo "  $0 feat-auth              # 从头开始完整流程"
    echo "  $0 feat-auth IMPLEMENT    # 从 IMPLEMENT 阶段开始"
    echo "  $0 feat-auth VERIFY       # 从 VERIFY 阶段开始"
    exit 1
fi

# 验证阶段参数
case "$START_PHASE" in
    START|IMPLEMENT|VERIFY|COMPLETE)
        ;;
    *)
        echo "❌ 错误: 无效的阶段 '$START_PHASE'"
        echo "有效阶段: START, IMPLEMENT, VERIFY, COMPLETE"
        exit 1
        ;;
esac

# ═══════════════════════════════════════════════════════════════════
# 路径配置
# ═══════════════════════════════════════════════════════════════════

# 确定仓库根目录
if [ -d "feature-workflow-LockStep" ]; then
    REPO_ROOT="$(pwd)"
elif [ -d "../feature-workflow-LockStep" ]; then
    REPO_ROOT="$(cd .. && pwd)"
elif [ -d "feature-workflow" ]; then
    REPO_ROOT="$(pwd)"
elif [ -d "../feature-workflow" ]; then
    REPO_ROOT="$(cd .. && pwd)"
else
    REPO_ROOT="$(pwd)"
fi

# 路径定义
FEATURE_DIR="$REPO_ROOT/features/active-$FEATURE_ID"
PENDING_DIR="$REPO_ROOT/features/pending-$FEATURE_ID"
STATUS_FILE="$FEATURE_DIR/.status"
LOG_FILE="$FEATURE_DIR/.log"
SPEC_FILE="$FEATURE_DIR/spec.md"
TASK_FILE="$FEATURE_DIR/task.md"
CHECKLIST_FILE="$FEATURE_DIR/checklist.md"

# 配置文件
CONFIG_FILE="$REPO_ROOT/feature-workflow-LockStep/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="$REPO_ROOT/feature-workflow/config.yaml"
fi

# 读取配置
MAIN_BRANCH="main"
WORKTREE_BASE=".worktrees"
MAX_CONCURRENT=2
GIT_REMOTE="origin"
MERGE_STRATEGY="--no-ff"

if [ -f "$CONFIG_FILE" ]; then
    MAIN_BRANCH=$(grep 'main_branch:' "$CONFIG_FILE" | awk '{print $2}' || echo "main")
    WORKTREE_BASE=$(grep 'worktree_base:' "$CONFIG_FILE" | awk '{print $2}' || echo ".worktrees")
    MAX_CONCURRENT=$(grep 'max_concurrent:' "$CONFIG_FILE" | awk '{print $2}' || echo "2")
    GIT_REMOTE=$(grep 'remote:' "$CONFIG_FILE" | awk '{print $2}' || echo "origin")
    MERGE_STRATEGY=$(grep 'merge_strategy:' "$CONFIG_FILE" | sed 's/merge_strategy: //' || echo "--no-ff")
fi

# 生成路径
BRANCH="feature/${FEATURE_ID#feat-}"
WORKTREE="$WORKTREE_BASE/$FEATURE_ID"
ARCHIVE_DATE=$(date +%Y%m%d)
ARCHIVE_DIR="$REPO_ROOT/features/archive/done-$FEATURE_ID-$ARCHIVE_DATE"

# ═══════════════════════════════════════════════════════════════════
# 预检查
# ═══════════════════════════════════════════════════════════════════

echo "═══════════════════════════════════════════════════════════════════════"
echo "🚀 端到端 Feature 开发 Agent (LockStep 协议)"
echo "═══════════════════════════════════════════════════════════════════════"
echo "Feature ID:    $FEATURE_ID"
echo "开始阶段:      $START_PHASE"
echo "主分支:        $MAIN_BRANCH"
echo "Worktree 基础: $WORKTREE_BASE"
echo "═══════════════════════════════════════════════════════════════════════"

# 检查是否从头开始
if [ "$START_PHASE" = "START" ]; then
    # 检查 pending 目录
    if [ ! -d "$PENDING_DIR" ]; then
        echo "❌ 错误: Pending 目录不存在: $PENDING_DIR"
        echo "请先使用 /new-feature 创建 feature"
        exit 1
    fi

    # 检查 worktree 是否已存在
    if [ -d "$REPO_ROOT/$WORKTREE" ]; then
        echo "⚠️  警告: Worktree 已存在: $WORKTREE"
        echo "将尝试从现有 worktree 恢复..."
        START_PHASE="IMPLEMENT"
    fi
else
    # 从中间阶段开始，检查必要文件
    if [ ! -d "$FEATURE_DIR" ]; then
        echo "❌ 错误: Feature 目录不存在: $FEATURE_DIR"
        echo "请从 START 阶段开始"
        exit 1
    fi

    if [ ! -f "$STATUS_FILE" ]; then
        echo "❌ 错误: 状态文件不存在: $STATUS_FILE"
        exit 1
    fi
fi

# 获取 feature 名称
if [ -f "$SPEC_FILE" ]; then
    FEATURE_NAME=$(grep '^# ' "$SPEC_FILE" 2>/dev/null | head -1 | sed 's/^# //' || echo "$FEATURE_ID")
elif [ -f "$PENDING_DIR/spec.md" ]; then
    FEATURE_NAME=$(grep '^# ' "$PENDING_DIR/spec.md" 2>/dev/null | head -1 | sed 's/^# //' || echo "$FEATURE_ID")
else
    FEATURE_NAME="$FEATURE_ID"
fi

# ═══════════════════════════════════════════════════════════════════
# 初始化状态文件
# ═══════════════════════════════════════════════════════════════════

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if [ "$START_PHASE" = "START" ] || [ ! -f "$STATUS_FILE" ]; then
    cat > "$STATUS_FILE" << EOF
# LockStep Feature Status
# 此文件记录执行状态，用于断点恢复

feature_id: $FEATURE_ID
feature_name: $FEATURE_NAME
status: initialized
stage: $START_PHASE
stp_pointer: STP-000
stp_history:
  - STP-000
progress:
  phase: $START_PHASE
  tasks_total: 0
  tasks_done: 0
  current_task: null
configuration:
  main_branch: $MAIN_BRANCH
  worktree: $WORKTREE
  branch: $BRANCH
  archive_dir: $ARCHIVE_DIR
started_at: $NOW
updated_at: $NOW

# LockStep 检查点
checkpoint:
  last_stp: STP-000
  timestamp: $NOW
  registers: {}
EOF
    echo "✅ 状态文件已初始化 (STP-000, 阶段: $START_PHASE)"
else
    echo "📋 现有状态文件: $STATUS_FILE"
    echo "   当前阶段: $(grep 'stage:' "$STATUS_FILE" | awk '{print $2}')"
    echo "   当前 STP: $(grep 'stp_pointer:' "$STATUS_FILE" | awk '{print $2}')"
fi

# ═══════════════════════════════════════════════════════════════════
# 初始化日志文件
# ═══════════════════════════════════════════════════════════════════

cat >> "$LOG_FILE" << EOF

# ========================================
# Session Started: $NOW
# Start Phase: $START_PHASE
# Feature: $FEATURE_ID ($FEATURE_NAME)
# ========================================

EVENT:INIT $FEATURE_ID $START_PHASE
EOF

echo "✅ 日志文件已更新"

# ═══════════════════════════════════════════════════════════════════
# 构建 LockStep 协议
# ═══════════════════════════════════════════════════════════════════

build_lockstep_protocol() {
    cat << 'LOCKSTEP_PROTOCOL_EOF'
# ═════════════════════════════════════════════════════════════════════
# AILock-Step 端到端 Feature 开发协议 v1.0
# ═════════════════════════════════════════════════════════════════════
#
# 本协议定义了完整的 Feature 生命周期，包含四个阶段:
#   [Phase: START]     - STP-000 ~ STP-099
#   [Phase: IMPLEMENT] - STP-100 ~ STP-199
#   [Phase: VERIFY]    - STP-200 ~ STP-299
#   [Phase: COMPLETE]  - STP-300 ~ STP-399
#
# 执行规则:
# 1. 必须严格按 STP 顺序执行
# 2. 每个 STP 完成后输出: `STP-XXX: <描述> ✓`
# 3. 状态变化时更新 $STATUS_FILE
# 4. 阶段变化时输出 EVENT:STAGE token
# 5. 遇到错误输出 EVENT:BLOCKED 并停止
# ═════════════════════════════════════════════════════════════════════

你现在是一个严格遵循 **AILock-Step 协议** 的 Feature Agent。

## 核心约束

1. **状态锚点 (STP)**: 必须停留在当前 STP，直到所有动作完成
2. **逻辑门控 (??)**: 如果条件为假，必须跳转到错误流
3. **原子算子 (!!)**: 每个动作不可拆分，必须完整执行
4. **强制跳转 (->)**: 只有 `-> STP-XXX` 是合法的状态演进

## 禁止行为

- ❌ 禁止跳过任何 STP
- ❌ 禁止在单个 STP 执行多个独立动作
- ❌ 禁止修改跳转规则
- ❌ 禁止使用 Task 或 Skill 工具
- ❌ 禁止"理解后简化"步骤

## 必须行为

- ✅ 每个 STP 完成后输出: `STP-XXX: <描述> ✓`
- ✅ 状态变化时使用 Edit/Write 工具更新 $STATUS_FILE
- ✅ 阶段变化时输出: `EVENT:STAGE {feature_id} {stage}`
- ✅ 遇到错误输出: `EVENT:BLOCKED {feature_id} {reason}`
- ✅ 阶段完成输出: `EVENT:PHASE_DONE {feature_id} {phase}`

## 环境变量

- FEATURE_ID: ]]$FEATURE_ID[[
- FEATURE_NAME: ]]$FEATURE_NAME[[
- WORKTREE: ]]$WORKTREE[[
- BRANCH: ]]$BRANCH[[
- MAIN_BRANCH: ]]$MAIN_BRANCH[[
- REPO_ROOT: ]]$REPO_ROOT[[
- STATUS_FILE: ]]$STATUS_FILE[[
- SPEC_FILE: ]]$SPEC_FILE[[
- TASK_FILE: ]]$TASK_FILE[[
- CHECKLIST_FILE: ]]$CHECKLIST_FILE[[
- LOG_FILE: ]]$LOG_FILE[[
- ARCHIVE_DIR: ]]$ARCHIVE_DIR[[

## 开始阶段

当前配置从 ]]$START_PHASE[[ 阶段开始。

LOCKSTEP_PROTOCOL_EOF
}

# ═══════════════════════════════════════════════════════════════════
# 添加阶段协议
# ═══════════════════════════════════════════════════════════════════

append_start_phase_protocol() {
    cat << 'START_PROTOCOL_EOF'

# ═════════════════════════════════════════════════════════════════════
# [Phase: START] - 创建 Worktree 和分支
# ═════════════════════════════════════════════════════════════════════

**STP-000**: 进入 START 阶段
- !! 输出: `STP-000: 进入 START 阶段 ✓`
- !! 输出 EVENT:STAGE ]]$FEATURE_ID[[ start
- !! 更新 $STATUS_FILE: stage=start, stp_pointer=STP-000
- -> STP-001

**STP-001**: 读取队列文件
- !! 读取 ]]$REPO_ROOT[[/feature-workflow/queue.yaml >> REG_QUEUE
- ?? 如果文件不存在 -> STP-ERR-QUEUE
- -> STP-002

**STP-002**: 验证 Feature 在 pending 列表
- !! 检查 REG_QUEUE.pending 中存在 id=]]$FEATURE_ID[[
- ?? 如果不存在 -> STP-ERR-NOT_PENDING
- -> STP-003

**STP-003**: 检查依赖是否满足
- !! 获取 FEATURE_ID 的 dependencies >> REG_DEPS
- ?? 如果没有依赖 或 所有依赖都在 completed 列表 -> STP-010
- -> STP-ERR-DEPS

**STP-010**: 创建分支
- !! 执行: git branch ]]$BRANCH[[
- ?? 如果失败 -> STP-ERR-BRANCH
- -> STP-011

**STP-011**: 创建 Worktree
- !! 执行: git worktree add ]]$WORKTREE[[ ]]$BRANCH[[
- ?? 如果失败 -> STP-ERR-WORKTREE
- -> STP-012

**STP-012**: 验证 Worktree 创建成功
- !! 执行: git worktree list
- ?? 如果 ]]$WORKTREE[[ 不在列表中 -> STP-ERR-WORKTREE_VERIFY
- -> STP-013

**STP-013**: 移动目录到 active
- !! 执行: mv ]]$REPO_ROOT[[/features/pending-]]$FEATURE_ID[[ ]]$REPO_ROOT[[/features/active-]]$FEATURE_ID[[
- -> STP-014

**STP-014**: 更新队列 (pending -> active)
- !! 从 REG_QUEUE.pending 移除 ]]$FEATURE_ID[[
- !! 添加到 REG_QUEUE.active: {id: ]]$FEATURE_ID[[, name: ]]$FEATURE_NAME[[, branch: ]]$BRANCH[[, worktree: ]]$WORKTREE[[}
- !! 保存队列文件
- -> STP-015

**STP-015**: START 阶段完成
- !! 输出: `STP-015: START 阶段完成 ✓`
- !! 输出 EVENT:PHASE_DONE ]]$FEATURE_ID[[ START
- !! 更新 $STATUS_FILE: status=started, stage=implement, stp_pointer=STP-015
- -> STP-100 (进入 IMPLEMENT 阶段)

START_PROTOCOL_EOF
}

append_implement_phase_protocol() {
    cat << 'IMPLEMENT_PROTOCOL_EOF'

# ═════════════════════════════════════════════════════════════════════
# [Phase: IMPLEMENT] - 实现代码
# ═════════════════════════════════════════════════════════════════════

**STP-100**: 进入 IMPLEMENT 阶段
- !! 输出: `STP-100: 进入 IMPLEMENT 阶段 ✓`
- !! 输出 EVENT:STAGE ]]$FEATURE_ID[[ implement
- !! 更新 $STATUS_FILE: stage=implement, stp_pointer=STP-100
- -> STP-101

**STP-101**: 读取需求文档
- !! 读取 $SPEC_FILE >> REG_SPEC
- ?? 如果文件不存在 -> STP-ERR-SPEC
- -> STP-102

**STP-102**: 读取任务文档
- !! 读取 $TASK_FILE >> REG_TASK_RAW
- ?? 如果文件不存在 -> STP-ERR-TASK
- -> STP-103

**STP-103**: 解析任务列表
- !! 解析 REG_TASK_RAW，提取任务列表 >> REG_TASK_LIST
- !! 统计 tasks_total 和 未完成任务数量
- !! 更新 $STATUS_FILE: progress.tasks_total
- -> STP-104

**STP-104**: 检查是否有待完成任务
- !! 获取第一个 status!=done 的任务 >> REG_CUR_TASK
- ?? 如果没有待完成任务 -> STP-150 (所有任务完成)
- -> STP-105

**STP-105**: 显示当前任务
- !! 输出任务信息: REG_CUR_TASK.title, REG_CUR_TASK.description
- !! 更新 $STATUS_FILE: progress.current_task
- -> STP-106

**STP-106**: 检查任务依赖
- !! 获取 REG_CUR_TASK.dependencies >> REG_TASK_DEPS
- ?? 如果没有依赖 或所有依赖都已完成 -> STP-107
- -> STP-104 (跳过此任务，处理下一个)

**STP-107**: 收集上下文
- !! 读取项目上下文文件 (如果存在) >> REG_PROJECT_CTX
- !! 收集参考代码路径 >> REG_REF_CODE
- -> STP-108

**STP-108**: 生成代码
- !! 基于 REG_SPEC 和 REG_CUR_TASK 生成代码 >> REG_NEW_CODE
- ?? 如果生成失败 -> STP-ERR-CODE_GEN
- -> STP-109

**STP-109**: 写入代码文件
- !! 将 REG_NEW_CODE 写入 worktree 对应路径
- !! 记录新增/修改的文件
- -> STP-110

**STP-110**: 更新任务状态
- !! 更新 $TASK_FILE 中 REG_CUR_TASK.id 的状态为 done
- !! 更新 $STATUS_FILE: progress.tasks_done++
- !! 输出 EVENT:PROGRESS ]]$FEATURE_ID[[ {done}/{total}
- -> STP-104 (回旋跳转，处理下一个任务)

**STP-150**: 所有任务完成
- !! 输出: `STP-150: 所有任务实现完成 ✓`
- !! 更新 $STATUS_FILE: status=implemented, stp_pointer=STP-150
- -> STP-151

**STP-151**: IMPLEMENT 阶段完成
- !! 输出: `STP-151: IMPLEMENT 阶段完成 ✓`
- !! 输出 EVENT:PHASE_DONE ]]$FEATURE_ID[[ IMPLEMENT
- !! 更新 $STATUS_FILE: stage=verify, stp_pointer=STP-151
- -> STP-200 (进入 VERIFY 阶段)

IMPLEMENT_PROTOCOL_EOF
}

append_verify_phase_protocol() {
    cat << 'VERIFY_PROTOCOL_EOF'

# ═════════════════════════════════════════════════════════════════════
# [Phase: VERIFY] - 验证代码
# ═════════════════════════════════════════════════════════════════════

**STP-200**: 进入 VERIFY 阶段
- !! 输出: `STP-200: 进入 VERIFY 阶段 ✓`
- !! 输出 EVENT:STAGE ]]$FEATURE_ID[[ verify
- !! 更新 $STATUS_FILE: stage=verify, stp_pointer=STP-200
- -> STP-201

**STP-201**: 检查代码完整性
- !! 确认所有任务都已完成
- ?? 如果有未完成任务 -> STP-ERR-INCOMPLETE
- -> STP-202

**STP-202**: 运行 Lint (如果配置)
- !! 检查配置中是否启用 lint
- ?? 如果未启用 -> STP-210
- !! 执行: cd ]]$WORKTREE[[ && npm run lint 2>&1 >> REG_LINT_RESULT
- ?? 如果失败 -> STP-ERR-LINT
- -> STP-203

**STP-203**: 运行测试 (如果配置)
- !! 检查配置中是否启用 test
- ?? 如果未启用 -> STP-210
- !! 执行: cd ]]$WORKTREE[[ && npm test 2>&1 >> REG_TEST_RESULT
- ?? 如果失败 -> STP-ERR-TEST
- -> STP-210

**STP-210**: 检查 checklist
- !! 读取 $CHECKLIST_FILE >> REG_CHECKLIST
- ?? 如果文件不存在 -> STP-220 (跳过)
- -> STP-211

**STP-211**: 验证 checklist
- !! 检查所有项是否都已勾选
- ?? 如果全部勾选 -> STP-220
- -> STP-212

**STP-212**: 显示未完成项
- !! 列出所有未勾选项
- !! 询问是否继续
- ?? 用户选择继续 -> STP-220
- -> STP-ERR-CHECKLIST

**STP-220**: VERIFY 阶段完成
- !! 输出: `STP-220: VERIFY 阶段完成 ✓`
- !! 输出 EVENT:PHASE_DONE ]]$FEATURE_ID[[ VERIFY
- !! 更新 $STATUS_FILE: status=verified, stage=complete, stp_pointer=STP-220
- -> STP-300 (进入 COMPLETE 阶段)

VERIFY_PROTOCOL_EOF
}

append_complete_phase_protocol() {
    cat << 'COMPLETE_PROTOCOL_EOF'

# ═════════════════════════════════════════════════════════════════════
# [Phase: COMPLETE] - 提交、合并、归档
# ═════════════════════════════════════════════════════════════════════

**STP-300**: 进入 COMPLETE 阶段
- !! 输出: `STP-300: 进入 COMPLETE 阶段 ✓`
- !! 输出 EVENT:STAGE ]]$FEATURE_ID[[ complete
- !! 更新 $STATUS_FILE: stage=complete, stp_pointer=STP-300
- -> STP-301

**STP-301**: 检查代码变更
- !! 执行: cd ]]$WORKTREE[[ && git status --porcelain >> REG_CHANGES
- ?? 如果没有变更 -> STP-310 (跳过提交)
- -> STP-302

**STP-302**: 暂存变更
- !! 执行: cd ]]$WORKTREE[[ && git add .
- -> STP-303

**STP-303**: 提交代码
- !! 执行: cd ]]$WORKTREE[[ && git commit -m "feat(]]$FEATURE_ID[[): ]]$FEATURE_NAME[[" >> REG_COMMIT_HASH
- ?? 如果失败 -> STP-ERR-COMMIT
- -> STP-304

**STP-304**: 记录提交信息
- !! 更新 $STATUS_FILE: completion.commit=REG_COMMIT_HASH
- -> STP-310

**STP-310**: 切换到主分支
- !! 执行: git checkout ]]$MAIN_BRANCH[[
- -> STP-311

**STP-311**: 拉取最新主分支
- !! 执行: git pull ]]$GIT_REMOTE[[ ]]$MAIN_BRANCH[[
- -> STP-312

**STP-312**: 合并 feature 分支
- !! 执行: git merge ]]$BRANCH[[ ]]$MERGE_STRATEGY[[ -m "Merge ]]$BRANCH[[: ]]$FEATURE_NAME[[" >> REG_MERGE_RESULT
- ?? 如果包含 CONFLICT -> STP-ERR-MERGE
- -> STP-313

**STP-313**: 合并成功
- !! 获取合并提交 hash >> REG_MERGE_COMMIT
- !! 更新 $STATUS_FILE: completion.merge_commit=REG_MERGE_COMMIT
- -> STP-320

**STP-320**: 创建归档目录
- !! 执行: mkdir -p ]]$ARCHIVE_DIR[[
- -> STP-321

**STP-321**: 复制文档到归档
- !! 执行: cp ]]$SPEC_FILE[[ ]]$ARCHIVE_DIR[[/spec.md
- !! 执行: cp ]]$TASK_FILE[[ ]]$ARCHIVE_DIR[[/task.md
- !! 如果 checklist 存在: cp ]]$CHECKLIST_FILE[[ ]]$ARCHIVE_DIR[[/checklist.md
- -> STP-322

**STP-322**: 创建归档元数据
- !! 生成 archive-meta.yaml 并写入 ]]$ARCHIVE_DIR[[/
- -> STP-323

**STP-323**: 更新归档日志
- !! 追加到 archive-log.yaml
- -> STP-324

**STP-324**: 更新队列 (active -> completed)
- !! 从 active 移除 ]]$FEATURE_ID[[
- !! 添加到 completed: {id: ]]$FEATURE_ID[[, name: ]]$FEATURE_NAME[[, completed: now()}
- !! 保存队列文件
- -> STP-330

**STP-330**: 清理 Worktree
- !! 执行: git worktree remove ]]$WORKTREE[[
- ?? 如果失败 -> STP-ERR-CLEANUP
- -> STP-331

**STP-331**: 删除分支
- !! 执行: git branch -D ]]$BRANCH[[
- -> STP-332

**STP-332**: 删除 active 目录
- !! 执行: rm -rf ]]$REPO_ROOT[[/features/active-]]$FEATURE_ID[[
- -> STP-333

**STP-333**: COMPLETE 阶段完成
- !! 输出: `STP-333: COMPLETE 阶段完成 ✓`
- !! 输出 EVENT:PHASE_DONE ]]$FEATURE_ID[[ COMPLETE
- !! 输出 EVENT:COMPLETE ]]$FEATURE_ID[[ done
- !! 更新 $STATUS_FILE: status=archived, stp_pointer=STP-END
- -> STP-END

COMPLETE_PROTOCOL_EOF
}

append_error_handling_protocol() {
    cat << 'ERROR_PROTOCOL_EOF'

# ═════════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING] - 错误处理
# ═════════════════════════════════════════════════════════════════════

**STP-ERR-QUEUE**: 队列文件读取失败
- !! 输出: `❌ STP-ERR-QUEUE: 队列文件读取失败`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ queue_file_not_found
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-NOT_PENDING**: Feature 不在 pending 列表
- !! 输出: `❌ STP-ERR-NOT_PENDING: Feature 不在 pending 列表`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ not_in_pending
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-DEPS**: 依赖未满足
- !! 输出: `❌ STP-ERR-DEPS: 依赖未满足`
- !! 列出未满足的依赖
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ dependencies_not_met
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-BRANCH**: 分支创建失败
- !! 输出: `❌ STP-ERR-BRANCH: 分支创建失败`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ branch_create_failed
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-WORKTREE**: Worktree 创建失败
- !! 输出: `❌ STP-ERR-WORKTREE: Worktree 创建失败`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ worktree_create_failed
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-WORKTREE_VERIFY**: Worktree 验证失败
- !! 输出: `❌ STP-ERR-WORKTREE_VERIFY: Worktree 未在列表中`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ worktree_verify_failed
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-SPEC**: 需求文档不存在
- !! 输出: `❌ STP-ERR-SPEC: 需求文档不存在`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ spec_not_found
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-TASK**: 任务文档不存在
- !! 输出: `❌ STP-ERR-TASK: 任务文档不存在`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ task_not_found
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-CODE_GEN**: 代码生成失败
- !! 输出: `❌ STP-ERR-CODE_GEN: 代码生成失败`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ code_gen_failed
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-INCOMPLETE**: 任务未完成
- !! 输出: `❌ STP-ERR-INCOMPLETE: 存在未完成任务`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ tasks_incomplete
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-LINT**: Lint 检查失败
- !! 输出: `❌ STP-ERR-LINT: Lint 检查失败`
- !! 输出: `STP-ERR-LINT: 请修复 lint 错误后重新运行`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ lint_failed
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-TEST**: 测试失败
- !! 输出: `❌ STP-ERR-TEST: 测试失败`
- !! 输出: `STP-ERR-TEST: 请修复测试错误后重新运行`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ test_failed
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-CHECKLIST**: 检查清单未完成
- !! 输出: `❌ STP-ERR-CHECKLIST: 检查清单未完成`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ checklist_incomplete
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-COMMIT**: 提交失败
- !! 输出: `❌ STP-ERR-COMMIT: 提交失败`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ commit_failed
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-MERGE**: 合并冲突
- !! 输出: `❌ STP-ERR-MERGE: 合并冲突`
- !! 输出冲突文件列表
- !! 输出: `STP-ERR-MERGE: 请手动解决冲突后重新运行`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ merge_conflict
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-CLEANUP**: 清理失败
- !! 输出: `❌ STP-ERR-CLEANUP: 清理失败`
- !! 输出 EVENT:BLOCKED ]]$FEATURE_ID[[ cleanup_failed
- !! 更新 $STATUS_FILE: status=blocked
- -> STP-HALT

**STP-HALT**: 执行停止
- !! 输出恢复说明:
  ```
  ╔═══════════════════════════════════════════════════════════════════════╗
  ║                    ⚠️  执行已停止                                     ║
  ╠═══════════════════════════════════════════════════════════════════════╣
  ║  Feature: ]]$FEATURE_ID[[                                             ║
  ║  当前 STP: {current_stp}                                             ║
  ║                                                                       ║
  ║  恢复方法:                                                            ║
  ║    1. 解决阻塞问题                                                    ║
  ║    2. 重新运行: ./full-feature-agent.sh ]]$FEATURE_ID[[ {phase}      ║
  ║                                                                       ║
  ║  查看状态: cat ]]$STATUS_FILE[[                                       ║
  ║  查看日志: tail -f ]]$LOG_FILE[[                                      ║
  ╚═══════════════════════════════════════════════════════════════════════╝
  ```
- -> END

**STP-END**: 正常结束
- !! 输出完成报告:
  ```
  ╔═══════════════════════════════════════════════════════════════════════╗
  ║                    ✅ Feature 完成!                                   ║
  ╠═══════════════════════════════════════════════════════════════════════╣
  ║  Feature:     ]]$FEATURE_ID[[ (]]$FEATURE_NAME[[)                     ║
  ║  状态:       archived                                                 ║
  ║  提交:       {commit_hash}                                            ║
  ║  合并:       ]]$BRANCH[[ → ]]$MAIN_BRANCH[[                          ║
  ║  归档:       ]]$ARCHIVE_DIR[[                                        ║
  ╚═══════════════════════════════════════════════════════════════════════╝
  ```
- !! 输出 EVENT:END ]]$FEATURE_ID[[ success
- -> END

ERROR_PROTOCOL_EOF
}

# ═══════════════════════════════════════════════════════════════════
# 构建完整协议
# ═══════════════════════════════════════════════════════════════════

LOCKSTEP_PROMPT_FILE="/tmp/lockstep-protocol-$FEATURE_ID-$$.txt"

{
    build_lockstep_protocol

    # 根据开始阶段添加相应的协议
    case "$START_PHASE" in
        START)
            append_start_phase_protocol
            append_implement_phase_protocol
            append_verify_phase_protocol
            append_complete_phase_protocol
            ;;
        IMPLEMENT)
            append_implement_phase_protocol
            append_verify_phase_protocol
            append_complete_phase_protocol
            ;;
        VERIFY)
            append_verify_phase_protocol
            append_complete_phase_protocol
            ;;
        COMPLETE)
            append_complete_phase_protocol
            ;;
    esac

    append_error_handling_protocol
} > "$LOCKSTEP_PROMPT_FILE"

# 替换变量占位符
sed -i.bak \
    -e "s/]]$FEATURE_ID[[/$FEATURE_ID/g" \
    -e "s/]]$FEATURE_NAME[[/$FEATURE_NAME/g" \
    -e "s/]]$WORKTREE[[/$WORKTREE/g" \
    -e "s/]]$BRANCH[[/$BRANCH/g" \
    -e "s/]]$MAIN_BRANCH[[/$MAIN_BRANCH/g" \
    -e "s/]]$REPO_ROOT[[/$REPO_ROOT/g" \
    -e "s/]]$STATUS_FILE[[/$STATUS_FILE/g" \
    -e "s/]]$SPEC_FILE[[/$SPEC_FILE/g" \
    -e "s/]]$TASK_FILE[[/$TASK_FILE/g" \
    -e "s/]]$CHECKLIST_FILE[[/$CHECKLIST_FILE/g" \
    -e "s/]]$LOG_FILE[[/$LOG_FILE/g" \
    -e "s/]]$ARCHIVE_DIR[[/$ARCHIVE_DIR/g" \
    -e "s/]]$START_PHASE[[/$START_PHASE/g" \
    "$LOCKSTEP_PROMPT_FILE"

rm -f "$LOCKSTEP_PROMPT_FILE.bak"

LOCKSTEP_PROMPT=$(cat "$LOCKSTEP_PROMPT_FILE")
rm -f "$LOCKSTEP_PROMPT_FILE"

# ═══════════════════════════════════════════════════════════════════
# 构建用户 Prompt
# ═══════════════════════════════════════════════════════════════════

USER_PROMPT="请执行 feature **$FEATURE_ID** ($FEATURE_NAME) 的端到端开发流程。

## 开始执行

从 **$START_PHASE** 阶段开始，严格按照协议定义的 STP 序列执行。

## 进入点

根据开始阶段，请从以下 STP 开始:
- START:     从 STP-000 开始
- IMPLEMENT: 从 STP-100 开始
- VERIFY:    从 STP-200 开始
- COMPLETE:  从 STP-300 开始

## 执行要求

记住:
- 每个 STP 完成后输出: \`STP-XXX: <描述> ✓\`
- 状态变化时更新 $STATUS_FILE
- 阶段变化时输出 EVENT:STAGE token
- 遇到错误输出 EVENT:BLOCKED 并停止

现在开始执行!"

# ═══════════════════════════════════════════════════════════════════
# 启动 claude --print
# ═══════════════════════════════════════════════════════════════════

echo ""
echo "🚀 启动 claude --print (端到端 LockStep 模式)..."

# 检测平台
OS="$(uname -s)"
case "$OS" in
    Linux*)     PLATFORM="linux" ;;
    Darwin*)    PLATFORM="macos" ;;
    CYGWIN*|MINGW*|MSYS*)    PLATFORM="windows" ;;
    *)          PLATFORM="unknown" ;;
esac

echo "平台: $PLATFORM"

# 启动后台进程
claude --print \
    --allowed-tools "Bash,Read,Write,Edit,Glob,Grep" \
    --append-system-prompt "$LOCKSTEP_PROMPT" \
    "$USER_PROMPT" \
    >> "$LOG_FILE" 2>&1 &

LAUNCH_STATUS=$?
sleep 1

PID=$!
if kill -0 $PID 2>/dev/null; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "✅ 端到端 Feature Agent 已启动"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "PID:          $PID"
    echo "Feature:      $FEATURE_ID ($FEATURE_NAME)"
    echo "开始阶段:      $START_PHASE"
    echo "状态文件:     $STATUS_FILE"
    echo "日志文件:     $LOG_FILE"
    echo ""
    echo "监控命令:"
    echo "  查看状态:     cat $STATUS_FILE"
    echo "  查看日志:     tail -f $LOG_FILE"
    echo "  查看 STP:     grep 'STP-' $LOG_FILE | tail -20"
    echo "  查看 EVENT:   grep '^EVENT:' $LOG_FILE | tail -10"
    echo "  查看阶段:     grep 'PHASE_DONE' $LOG_FILE | tail -5"
    echo ""
    echo "恢复命令 (如果中断):"
    echo "  从 START:     ./full-feature-agent.sh $FEATURE_ID START"
    echo "  从 IMPLEMENT: ./full-feature-agent.sh $FEATURE_ID IMPLEMENT"
    echo "  从 VERIFY:    ./full-feature-agent.sh $FEATURE_ID VERIFY"
    echo "  从 COMPLETE:  ./full-feature-agent.sh $FEATURE_ID COMPLETE"
    echo ""
    echo "💡 Agent 将自动完成从 $START_PHASE 到 COMPLETE 的所有阶段"
    echo "═══════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "❌ 后台进程启动失败"
    echo "请检查日志: $LOG_FILE"
    exit 1
fi
