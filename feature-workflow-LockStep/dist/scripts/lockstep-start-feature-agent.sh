#!/bin/bash
#
# start-feature-agent.sh - 启动 LockStep Feature Agent
#
# 用法: ./start-feature-agent.sh <feature-id> <worktree-path> [branch-name]
#
# LockStep 特性:
# - 初始化 .status 文件，包含 stp_pointer
# - 注入完整的执行协议到 System Prompt
# - 使用 claude --print 启动后台进程
#

set -o pipefail

# 参数检查
FEATURE_ID="${1:-}"
WORKTREE="${2:-}"
BRANCH="${3:-feature/${FEATURE_ID#feat-}}"

if [ -z "$FEATURE_ID" ] || [ -z "$WORKTREE" ]; then
    echo "用法: $0 <feature-id> <worktree-path> [branch-name]"
    echo ""
    echo "示例:"
    echo "  $0 feat-auth ../OA_Tool-feat-auth"
    exit 1
fi

# 确定仓库根目录
if [ -d "feature-workflow-LockStep" ]; then
    REPO_ROOT="$(pwd)"
elif [ -d "../feature-workflow-LockStep" ]; then
    REPO_ROOT="$(cd .. && pwd)"
elif [ -d "../feature-workflow" ]; then
    REPO_ROOT="$(cd .. && pwd)"
else
    REPO_ROOT="$(pwd)"
fi

# 路径定义
FEATURE_DIR="$REPO_ROOT/features/active-$FEATURE_ID"
STATUS_FILE="$FEATURE_DIR/.status"
LOG_FILE="$FEATURE_DIR/.log"
SPEC_FILE="$FEATURE_DIR/spec.md"
TASK_FILE="$FEATURE_DIR/task.md"
CHECKLIST_FILE="$FEATURE_DIR/checklist.md"

# 检查 feature 目录
if [ ! -d "$FEATURE_DIR" ]; then
    echo "❌ 错误: Feature 目录不存在: $FEATURE_DIR"
    echo "请先运行 /start-feature $FEATURE_ID"
    exit 1
fi

# 检查 worktree
if [ ! -d "$WORKTREE" ]; then
    echo "❌ 错误: Worktree 不存在: $WORKTREE"
    echo "请先运行 /start-feature $FEATURE_ID"
    exit 1
fi

# 获取 feature 名称
FEATURE_NAME=$(grep '^# ' "$SPEC_FILE" 2>/dev/null | head -1 | sed 's/^# //' || echo "$FEATURE_ID")

# 获取任务数量
TASKS_TOTAL=$(grep -c '^\s*- \[' "$TASK_FILE" 2>/dev/null || echo "0")

# 读取配置
CONFIG_FILE="$REPO_ROOT/feature-workflow-LockStep/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
    CONFIG_FILE="$REPO_ROOT/feature-workflow/config.yaml"
fi
MAIN_BRANCH="main"
if [ -f "$CONFIG_FILE" ]; then
    MAIN_BRANCH=$(grep 'main_branch:' "$CONFIG_FILE" | awk '{print $2}' || echo "main")
fi

echo "═══════════════════════════════════════════════════════════════════════"
echo "🚀 启动 LockStep Feature Agent"
echo "═══════════════════════════════════════════════════════════════════════"
echo "Feature ID:    $FEATURE_ID"
echo "Feature Name:  $FEATURE_NAME"
echo "Worktree:      $WORKTREE"
echo "Branch:        $BRANCH"
echo "Tasks:         $TASKS_TOTAL"
echo "Protocol:      AILock-Step v1.0"
echo "═══════════════════════════════════════════════════════════════════════"

# 初始化状态文件 (LockStep 格式)
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
cat > "$STATUS_FILE" << EOF
# LockStep Feature Status
# 此文件记录执行状态，用于断点恢复

feature_id: $FEATURE_ID
feature_name: $FEATURE_NAME
status: initialized
stage: init
stp_pointer: STP-000
stp_history:
  - STP-000
progress:
  tasks_total: $TASKS_TOTAL
  tasks_done: 0
  current_task: null
started_at: $NOW
updated_at: $NOW

# LockStep 检查点
checkpoint:
  last_stp: STP-000
  timestamp: $NOW
  registers: {}
EOF

echo "✅ 状态文件已初始化 (STP-000)"

# 初始化日志文件
cat > "$LOG_FILE" << EOF
# LockStep Feature Agent Log: $FEATURE_ID
# Protocol: AILock-Step v1.0
# Started: $NOW
# ========================================

EVENT:STP $FEATURE_ID STP-000 initialized
EOF

echo "✅ 日志文件已初始化"

# 构建完整的 LockStep System Prompt
LOCKSTEP_PROMPT="# AILock-Step Feature Agent 协议

你现在是一个严格遵循 **AILock-Step 协议** 的 Feature Agent。

## 协议约束

1. **状态锚点 (STP)**: 你必须停留在当前 STP，直到所有动作完成
2. **逻辑门控 (??)**: 如果条件为假，必须跳转到错误流
3. **原子算子 (!!)**: 每个动作不可拆分
4. **强制跳转 (->)**: 只有 \`-> STP-XXX\` 是合法的状态演进

## 禁止行为

- ❌ 禁止跳过任何 STP
- ❌ 禁止在单个 STP 执行多个独立动作
- ❌ 禁止修改跳转规则
- ❌ 禁止使用 Task 或 Skill 工具

## 必须行为

- ✅ 每个 STP 完成后输出: \`STP-XXX: <描述> ✓\`
- ✅ 状态变化时更新 \$STATUS_FILE
- ✅ 阶段变化时输出 EVENT token
- ✅ 遇到错误输出 EVENT:BLOCKED 并停止

## 环境变量

- FEATURE_ID: $FEATURE_ID
- FEATURE_NAME: $FEATURE_NAME
- WORKTREE: $WORKTREE
- BRANCH: $BRANCH
- REPO_ROOT: $REPO_ROOT
- STATUS_FILE: $STATUS_FILE
- SPEC_FILE: $SPEC_FILE
- TASK_FILE: $TASK_FILE
- CHECKLIST_FILE: $CHECKLIST_FILE
- LOG_FILE: $LOG_FILE
- MAIN_BRANCH: $MAIN_BRANCH

## 执行协议

从 STP-000 开始，严格按以下序列执行:

### [Phase: INITIALIZATION]

**STP-000**: 协议声明
- 输出: \"STP-000: 进入 AILock-Step 执行模式 ✓\"
- 输出 EVENT:START $FEATURE_ID
- -> STP-001

**STP-001**: 初始化状态文件
- !! 更新 \$STATUS_FILE: status=started, stage=init, stp_pointer=STP-001
- !! 追加 stp_history: [..., STP-001]
- -> STP-002

**STP-002**: 读取需求文档
- !! 读取 \$SPEC_FILE >> REG_SPEC
- ?? 如果文件不存在 -> STP-ERR-SPEC
- -> STP-003

**STP-003**: 读取任务文档
- !! 读取 \$TASK_FILE >> REG_TASK_RAW
- ?? 如果文件不存在 -> STP-ERR-TASK
- -> STP-004

**STP-004**: 解析任务列表
- !! 解析任务，统计 total 和 open
- !! 更新 \$STATUS_FILE: progress.tasks_total, stp_pointer=STP-004
- -> STP-010

### [Phase: IMPLEMENT]

**STP-010**: 进入 IMPLEMENT 阶段
- !! 输出 EVENT:STAGE $FEATURE_ID implement
- !! 更新 \$STATUS_FILE: status=implementing, stage=implement
- -> STP-011

**STP-011**: 获取下一个待完成任务
- !! 从任务列表取第一个 status=open 的任务 >> REG_CUR_TASK
- ?? 如果没有待完成任务 -> STP-100
- -> STP-012

**STP-012**: 更新当前任务
- !! 更新 \$STATUS_FILE: progress.current_task
- -> STP-013

**STP-013**: 实现当前任务
- !! 基于 REG_SPEC 和 REG_CUR_TASK 编写代码
- -> STP-014

**STP-014**: 写入代码文件
- !! 将代码写入 worktree
- -> STP-015

**STP-015**: 标记任务完成
- !! 更新任务状态为 done
- !! 输出 EVENT:PROGRESS $FEATURE_ID {done}/{total}
- !! 更新 \$STATUS_FILE: progress.tasks_done++
- -> STP-011 (回旋跳转)

### [Phase: VERIFY] - ⚠️ 强制执行

**STP-100**: 验证所有任务完成
- ?? 如果还有 status=open 的任务 -> STP-ERR-INCOMPLETE
- -> STP-101

**STP-101**: 进入 VERIFY 阶段
- !! 输出 EVENT:STAGE $FEATURE_ID verify
- !! 更新 \$STATUS_FILE: status=verifying, stage=verify
- -> STP-102

**STP-102**: 运行 Lint
- !! cd \$WORKTREE && npm run lint
- ?? 如果失败 -> STP-ERR-LINT
- -> STP-103

**STP-103**: 运行测试
- !! cd \$WORKTREE && npm test
- ?? 如果失败 -> STP-ERR-TEST
- -> STP-104

**STP-104**: 读取检查清单
- !! 读取 \$CHECKLIST_FILE
- ?? 如果不存在 -> STP-110 (跳过)
- -> STP-105

**STP-105**: 验证检查清单
- ?? 如果有未勾选项 -> STP-ERR-CHECKLIST
- -> STP-110

**STP-110**: VERIFY 完成
- -> STP-200

### [Phase: COMPLETE]

**STP-200**: 进入 COMPLETE 阶段
- !! 输出 EVENT:STAGE $FEATURE_ID complete
- !! 更新 \$STATUS_FILE: status=completing, stage=complete
- -> STP-201

**STP-201**: 检查变更
- !! git status --porcelain
- ?? 如果没有变更 -> STP-210
- -> STP-202

**STP-202**: 暂存变更
- !! git add .
- -> STP-203

**STP-203**: 提交代码
- !! git commit -m \"feat(\$FEATURE_ID): \$FEATURE_NAME\"
- -> STP-210

**STP-210**: 标记完成
- !! 更新 \$STATUS_FILE: status=done, stp_pointer=STP-END
- !! 输出 EVENT:COMPLETE $FEATURE_ID done
- -> STP-END

### [Phase: ERROR HANDLING]

**STP-ERR-SPEC**: 需求文档不存在
- !! 输出 EVENT:ERROR $FEATURE_ID \"需求文档不存在\"
- !! 更新 \$STATUS_FILE: status=error
- -> STP-HALT

**STP-ERR-TASK**: 任务文档不存在
- !! 输出 EVENT:ERROR $FEATURE_ID \"任务文档不存在\"
- !! 更新 \$STATUS_FILE: status=error
- -> STP-HALT

**STP-ERR-INCOMPLETE**: 任务未完成
- !! 输出 EVENT:BLOCKED $FEATURE_ID \"存在未完成任务\"
- !! 更新 \$STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-LINT**: Lint 失败
- !! 输出 EVENT:BLOCKED $FEATURE_ID \"Lint 检查失败\"
- !! 更新 \$STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-TEST**: 测试失败
- !! 输出 EVENT:BLOCKED $FEATURE_ID \"测试失败\"
- !! 更新 \$STATUS_FILE: status=blocked
- -> STP-HALT

**STP-ERR-CHECKLIST**: 检查清单未完成
- !! 输出 EVENT:BLOCKED $FEATURE_ID \"检查清单未完成\"
- !! 更新 \$STATUS_FILE: status=blocked
- -> STP-HALT

**STP-HALT**: 执行停止
- !! 输出恢复说明
- -> END

**STP-END**: 正常结束
- !! 输出完成报告
- -> END

## 状态文件更新格式

每次更新 \$STATUS_FILE 时，使用 Edit 或 Write 工具，保持 YAML 格式:

\`\`\`yaml
feature_id: $FEATURE_ID
status: <status>
stage: <stage>
stp_pointer: <current_stp>
stp_history:
  - STP-001
  - STP-002
  - ...
progress:
  tasks_total: <n>
  tasks_done: <n>
  current_task: <desc>
updated_at: <ISO8601>
\`\`\`

## 开始执行

现在从 STP-000 开始执行!"

# 构建用户 prompt
USER_PROMPT="请执行 feature **$FEATURE_ID** ($FEATURE_NAME) 的 LockStep 开发流程。

## 开始执行

从 STP-000 开始，严格按照协议定义的 STP 序列执行。

记住:
- 每个 STP 完成后输出: \`STP-XXX: <描述> ✓\`
- 状态变化时更新 $STATUS_FILE
- 阶段变化时输出 EVENT token"

# 启动 claude --print
echo ""
echo "🚀 启动 claude --print (LockStep 模式)..."

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
    echo "✅ LockStep Feature Agent 已启动"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "PID:          $PID"
    echo "状态文件:     $STATUS_FILE"
    echo "日志文件:     $LOG_FILE"
    echo ""
    echo "监控命令:"
    echo "  查看状态:     cat $STATUS_FILE"
    echo "  查看日志:     tail -f $LOG_FILE"
    echo "  查看 STP:     grep 'STP-' $LOG_FILE | tail -20"
    echo "  查看 EVENT:   grep '^EVENT:' $LOG_FILE | tail -10"
    echo ""
    echo "💡 主 Agent 通过读取 .status 文件的 stp_pointer 监控进度"
    echo "═══════════════════════════════════════════════════════════════════════"
    exit 0
else
    echo "❌ 后台进程启动失败"
    echo "请检查日志: $LOG_FILE"
    exit 1
fi
