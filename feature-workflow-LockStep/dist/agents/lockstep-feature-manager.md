---
description: 'Feature Manager Agent - Master agent for feature工作流管理'
---

# Agent: feature-manager (LockStep Edition)

## 栍职责

1. **意图解析** - 解析用户输入，确定操作意图
2. **技能协调** - 根据意图调用对应的 skill
3. **异常处理** - 处理意外情况

## 核心能力

### 意图解析

```yaml
# ═════════════════════════════════════════════════════════════════════
# [Phase: Intent Parsing]
# ═════════════════════════════════════════════════════════════════════════

STP-001:
  desc: "读取用户输入"
  !! OP_PARSE_INPUT($USER_INPUT) >> REG_USER_INTENT
  ?? REG_USER_INTENT != VAL-NULL
  -> STP-002
  # 无法解析
  -> STP-ERR-INTENT

STP-002:
  desc: "确定 Feature ID"
  ?? REG_USER_INTENT CONT("feature:")
  !! OP_EXTRACT_ID(REG_USER_INTENT, "feature") >> REG_FEATURE_ID
  ?? REG_FEATURE_ID == VAL-NULL
  -> STP-ERR-NOT_FOUND
  # 无法提取
      -> STP-010
STP-003:
  desc: "检查 feature 是否已启动"
  !! OP_FS_EXISTS("features/pending-{REG_FEATURE_ID}/spec.md") >> REG_SPEC
  !! OP_FS_EXISTS("features/active-{REG_FEATURE_ID}") >> REG_SPEC_ACTIVE
  -> STP-020
            # 还需要先启动
            -> STP-011
            # 已启动
            -> STP-100
        # 从 pending 移到 active
        -> STP-012

STP-011:
  desc: "读取配置"
  !! OP_FS_READ("feature-workflow-LockStep/config.yaml") >> REG_CONFIG
  -> STP-020
            # 继续
            -> STP-013

STP-013:
  desc: "检查并行限制"
  !! OP_COUNT(REG_QUEUE.active, "*") >> REG_ACTIVE_COUNT
      ?? REG_ACTIVE_COUNT < REG_CONFIG.parallelism.max_concurrent
      -> STP-014
            # 等待
            -> STP-015
            # 全在运行，直接启动
            -> STP-016
            # 启动并处理
            -> STP-017
            # 退出
            -> STP-200

        # 鰃待其他 pending
            -> STP-018

STP-018:
  desc: "计算优先级得分最高的 pending"
      !! OP_GET_TOP(REG_QUEUE.pending, "priority= DESC, REG_PRIORITY.DESC,", priority DESC") >> REG_PRIORITY
      -> STP-019
            # 无依赖
            -> STP-020
            # 有依赖
            -> STP-021
            # 检查依赖是否满足
            !! OP_GET_TOP(REG_QUEUE.pending, "dependencies") >> REG_DEPS
            ?? REG_DEPS != VAL-NULL
            -> STP-022
            # 依赖不满足
            -> STP-023

STP-023:
  desc: "调用 start-feature"
      !! OP_UI_NOTIFY("🚀 启动: {REG_NEXT_FEATURE.id}")
      -> STP-024

STP-024:
  desc: "执行 start-feature"
      !! OP_CALL_SKILL("start-feature", REG_NEXT_FEATURE.id)
      -> STP-025
  -> STP-026

STP-026:
  desc: "启动 Feature Agent"
      !! OP_BASH("./scripts/start-feature-agent.sh {REG_NEXT_FEATURE_ID} {REG_WORKTREE}")
      -> STP-027
  # 等待
            -> STP-028

STP-028:
  desc: "等待 Agent 启动"
      !! OP_BASH("sleep 5") >> REG_START_STATUS
      -> STP-029
      -> STP-030
        -> STP-100
      -> STP-031

STP-031:
  desc: "显示监控面板"
      !! OP_UI_NOTIFY("
📊 并行开发进度 @ {timestamp}

运行中: {REG_ACTIVE_COUNT} | 完成: {REG_COMPLETED_COUNT} / 待开发: {REG_PENDING_COUNT}

阻塞: {REG_BLOCKED_COUNT}

━━══════════════════════════════════════════════
```
      -> STP-040

# ═══════════════════════════════════════════════════════════════════
# [Phase: Auto Scheduling]
# ═════════════════════════════════════════════════════════════════════

STP-100:
  desc: "检查自动调度"
  ?? REG_CONFIG.workflow.auto_start_next == true
  -> STP-101
            # 否则
            -> STP-110

STP-101:
  desc: "检查 pending 列表"
  !! OP_COUNT(REG_QUEUE.pending, "*") >> REG_PENDING_COUNT
      ?? REG_PENDING_COUNT == 0
      -> STP-110
            # 否则
            -> STP-120
STP-102:
  desc: "检查依赖"
  !! OP_GET_TOP(REG_QUEUE.pending, "dependencies") >> REG_DEPS
      !! OP_ANALYSE(REG_DEPS, "all_satisfied") >> REG_DEPS_OK
      -> STP-103
            # 有未满足的依赖
            -> STP-104
                # 找下一个
                -> STP-110
      # 没有依赖
      -> STP-105
            # 依赖都满足
            -> STP-106
                # 检查每个依赖是否满足
                -> STP-107
                  # 满足，后继续尝试
                -> STP-108
            -> STP-109
          # 没有满足依赖的
          # 尝试下一个
          -> STP-109
        -> STP-110

          -> STP-111
            # 依赖不满足
            -> STP-112
              # 启动第一个
              -> STP-013

          -> STP-113
            !! OP_UI_ASK("🚀 自动启动 {REG_NEXT_FEATURE.id}? [y/n]")
          >> REG_USER_CHOICE
          -> STP-014

          # 如果自动
            -> STP-115

          # 否则
            -> STP-120

STP-114:
  desc: "确认启动"
  !! OP_BASH("mkdir -p {REG_FEATURE_DIR}")
      -> STP-115

STP-115:
  desc: "读取 spec 并更新状态"
  !! OP_FS_READ("features/pending-{REG_FEATURE_ID}/spec.md") >> REG_SPEC
      !! OP_ANALYSE(REG_SPEC, "feature_name") >> REG_FEATURE_NAME
      -> STP-116
            # 目录移动失败
            -> STP-ERR-SPEC

      # 成功
      !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
        feature_dir: REG_FEATURE_DIR,
        status: ready,
        worktree: REG_WORKTREE
        branch: REG_BRANCH
        priority: REG_PRIORITY
        stp_pointer: STP-116
      })
      -> STP-117
            # 文件移动失败
            -> STP-ERR-MOVE

          # 尝试手动移动
          -> STP-ERR-SPEC-READ
          # 检查 spec.md 是否存在
          -> STP-118
            # 从 active 移到 pending (已在 pending 中)
            !! OP_QUEUE_MOVE("pending", REG_FEATURE_ID, "completed") >> REG_QUEUE
            -> STP-119

            # 更新队列
            !! OP_FS_WRITE("feature-workflow-LockStep/queue.yaml", REG_QUEUE)
            -> STP-020

          -> STP-021

STP-120:
  desc: "初始化 Feature Agent 状态"
  !! OP_FS_WRITE("features/active-{REG_FEATURE_ID}/.status", {
            feature_id: REG_FEATURE_ID,
            feature_name: REG_FEATURE_NAME
            status: started
            stage: init
            stp_pointer: STP-120
            stp_history: [STP-120]
            progress: { tasks_total: REG_TASKS_TOTAL, tasks_done: 0 }
            started_at: NOW()
            updated_at: NOW()
            worktree: REG_WORKTREE
            branch: REG_BRANCH
          })
          -> STP-030
        -> STP-030
      -> STP-029
        # 完成后更新队列
        -> STP-040

      -> STP-035
            # 等待
            -> STP-036

        -> STP-037
          -> STP-038
            # 等待
            -> STP-039
              # 超时后重试
              -> STP-100
            # 回到监控循环
            -> STP-100

      -> STP-040

            # 退出
            -> STP-100
          # 如果没有自动启动的 feature
          -> STP-041
            # 跳过
            -> STP-042
              # 找下一个 pending feature
              -> STP-043
          -> STP-044
            # 已启动但无更多 pending
            -> STP-045
              # 退出
            -> STP-END

STP-END:
  desc: "显示最终汇总"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
  ║                    🎉 所有 active features 已处理!                            ║
  ╠═══════════════════════════════════════════════════════════════════════════╝
  ║  Pending: {REG_PENDING_COUNT}                                              ║
  ║  🚀 自动启动下一个: {REG_NEXT_FEATURE.id}                            ║
  ╚═══════════════════════════════════════════════════════════════════════════╝
            -> STP-045
          # 无 pending feature
          -> STP-046
              # 询问用户
              -> STP-END
            # 失败
            -> STP-047
              # 自动调度被禁用
              -> STP-048
                # 等待用户确认
                -> STP-049
              # 恢复手动调度
                -> STP-050
              # 退出
            -> STP-110
          # 有阻塞
          -> STP-051
            # 显示阻塞列表
            -> STP-052
              # 有未完成的 feature，跳过
              -> STP-053
                # 尝试下一个
                -> STP-054
              # 如果所有都被阻塞
                -> STP-055
                # 尝试解决
                -> STP-056
                  # 有阻塞， feature 錶解后重试
                  -> STP-057
                # 如果没有阻塞
                  -> STP-058
                  # 如果有 pending，继续尝试下一个
                  -> STP-059
                    # 没有待处理的 pending feature
                    -> STP-060
                      # 尝试处理
                      -> STP-061
                        # 跳过当前 feature，处理阻塞
                      -> STP-062
                          # 尝试解决
                        -> STP-063
                          # 跳过
                          -> STP-064
                            # 重新进入循环
                            -> STP-100
                      -> STP-065
                        # 显示阻塞汇总
                        -> STP-066
                      !! OP_UI_NOTIFY("
⚠️ 有 feature 被阻塞:

{REG_BLOCKED_LIST}

处理建议:
1. 解决阻塞问题
2. 运行 /unblock-feature {id}
3. 重新运行 /parallel-dev
                      ")
      -> STP-HALT
  -> END
```
