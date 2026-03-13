---
description: 'Complete feature lifecycle workflow using AILock-Step protocol'
---

# Workflow: feature-lifecycle (LockStep Edition)

完整的特性生命周期工作流，从创建到归档到完成。

将## Usage

```
/feature-lifecycle                      # 交互式执行完整生命周期
/feature-lifecycle --resume <feature-id>    # 从指定 STP 恢复
/feature-lifecycle --status               # 只查看状态
```

## 执行协议

```yaml
# ═════════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═════════════════════════════════════════════════════════════════════

STP-001:
  desc: "读取配置"
  !! OP_FS_READ("feature-workflow-LockStep/config.yaml") >> REG_CONFIG
  -> STP-002

STP-002:
  desc: "读取队列"
  !! OP_FS_READ("feature-workflow-LockStep/queue.yaml") >> REG_QUEUE
  -> STP-003
STP-003:
  desc: "显示当前状态"
  !! OP_UI_NOTIFY("
📊 Feature 生命周期状态

━━══════════━━━━━━━━══════════━━━━
Active:    {count}
Pending:   {count}
Completed:  {count}
Blocked:   {count}

━━══════════━━━━━━━━══━━━━━━━━
最近更新: {last_updated}
""")
      -> STP-010

# ═════════════════════════════════════════════════════════════════════
# [Phase: STATUS CHECK]
# ═══════════════════════════════════════════════════════════════════

STP-010:
  desc: "检查 active features"
  !! OP_COUNT(REG_QUEUE.active, "*") >> REG_ACTIVE_COUNT
      ?? REG_ACTIVE_COUNT > 0
      -> STP-020
      # 没有 active features
      -> STP-030
STP-020:
  desc: "检查 pending features"
  !! OP_COUNT(REG_QUEUE.pending, "*") >> REG_PENDING_COUNT
      ?? REG_PENDING_COUNT > 0
      -> STP-040
      # 有 pending features，自动启动
      -> STP-050
      # 没有待处理
      -> STP-100

STP-030:
  desc: "检查 blocked features"
  !! OP_COUNT(REG_QUEUE.blocked, "*") >> REG_BLOCKed_COUNT
      ?? REG_BLOCKED_COUNT > 0
      -> STP-040
      # 有阻塞需要处理
      -> STP-035
      # 没有 blocked
      -> STP-036
    # 有 blocked features
    !! OP_UI_NOTIFY("
⚠️ 被阻塞的 Features:
────────────────────────────────────────────────
{REG_BLOCKED_LIST}

建议手动处理或使用 /unblock-feature 命")
    ")

# ═════════════════════════════════════════════════════════════════════
STP-035:
  desc: "询问是否自动调度"
  ?? REG_CONFIG.workflow.auto_start_next == true
  -> STP-036
      # 否则
      -> STP-037
  !! OP_UI_ASK("自动调度下一个 pending feature?", ["y", "n"]) >> REG_CHOICE
      -> STP-038
        # 自动调度
        -> STP-039
          # 启动
          -> STP-040
        # 手动处理
        -> STP-041
          # 等待
          -> STP-100
      # 手动处理
      -> STP-042
        # 退出
      -> STP-043
          # 显示状态并退出
      -> STP-045

    # 等待
    -> STP-046
      # 超时后重试
      -> STP-047
        # 尝试解决
        -> STP-048
          # 有未满足依赖的 feature
          -> STP-049
            # 显示列表
            -> STP-050
              # 尝试处理
              -> STP-051
                # 跳过
                -> STP-052
              # 尝试下一个
                -> STP-053
              # 如果所有依赖都满足
                -> STP-054
                  # 启动第一个
                  -> STP-055
                    # 等待 5 秷新重试...
                    -> STP-056
                      # 超时后重试
                      -> STP-057
                    # 跳过
                    -> STP-058
                      # 如果有未满足依赖的，
                        -> STP-059
                          # 尝试下一个
                          -> STP-060
                        # 启动 Feature Agent
                        -> STP-061
                          # 调用 complete-feature
                          -> STP-062
                        # 等待完成
                        -> STP-063
                          # 执行 complete-feature
                          -> STP-064
                          # 显示最终汇总
                          -> STP-065
                        # 没有待处理的 pending feature
                          -> STP-066
                          # 有阻塞需要处理
                          -> STP-067
                            # 显示阻塞列表
                          -> STP-068
                              # 等待处理
                              -> STP-069
                                # 尝试解决
                              -> STP-070
                              # 有未解决的阻塞
                                -> STP-071
                              !! OP_UI_ASK("是否标记为已解决? [y/n]") >> REG_CHOICE
                              -> STP-072
                            # 已解决
                            -> STP-073
                          # 尝试下一个
                          -> STP-074
                            # 跳过
                        -> STP-075
                          # 启动下一个
                          -> STP-076
                        # 已启动下一个
                        -> STP-077
                          # 所有 feature 已处理
                          -> STP-078
                        # 无 pending feature
                          -> STP-079
                          # 显示最终汇总
                          -> STP-080
                        # 显示阻塞汇总 (如果有)
                          -> STP-081
                            # 显示列表
                          -> STP-082
                          # 显示统计
                          -> STP-083
                        # 没有待处理
                          -> STP-084
                      # 有阻塞
                          -> STP-085
                        # 显示阻塞详情
                        -> STP-086
                      # 如果用户确认继续
                        -> STP-087
                          # 继续处理
                          -> STP-088
                        # 重新进入循环
                        -> STP-089
                          # 无阻塞
                          -> STP-090
                        # 无 pending
                          -> STP-091
                          # 显示最终汇总
                          -> STP-092
                        # 显示阻塞汇总 (如果有)
                          -> STP-093
                          # 如果有阻塞
                          -> STP-094
                            # 检查每个 feature 的阻塞状态
                            !! OP_UI_NOTIFY("检查结果: {REG_BLOCKED_CHECK}")
                            # 尝试手动处理
                          -> STP-095
                        # 跳过
                      -> STP-096
                      # 如果所有阻塞都解决
                        -> STP-097
                          # 显示最终汇总
                          -> STP-098
                      !! OP_UI_NOTIFY("
╔═════════════════════════════════════════════════════════════════════════╗
  ║                    🎉 Feature 生命周期完成!                                ║
  ╠═════════════════════════════════════════════════════════════════════════════╝
  ║  Active:    {REG_ACTIVE_COUNT}                                              ║
  ║  Pending:   {REG_PENDING_COUNT}                                              ║
  ║  Blocked:   {REG_BLOCKED_COUNT}                                              ║
  ║  Completed: {REG_COMPLETED_COUNT}                                            ║
  ╚═════════════════════════════════════════════════════════════════════════════╝
            -> STP-091
          # 有未完成
          -> STP-092
            # 显示最终汇总
            -> STP-093
          # 无
            -> STP-094
              # 显示完成汇总
              -> STP-095
          -> STP-END
      -> STP-096
        # 有 pending features
        -> STP-097
          # 尝试处理
          -> STP-098
            # 无 pending features
            -> STP-099
              # 恭喜! 所有 feature 已开发完成。
              -> STP-100
          -> STP-100:
  desc: "显示最终汇总"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════════╗
  ║                    🎉 Feature Lifecycle 完成!                                ║
  ║  总计: {REG_TOTAL_STATS}                                             ║
  ╚═════════════════════════════════════════════════════════════════════════════╝
```
      -> STP-END
  -> END
```
            -> STP-ERR-NO-features
            -> STP-ERR-INTERNAL
              !! OP_UI_NOTIFY("❌ 内部错误， 请检查日志")
              -> STP-HALT
          -> END
        -> STP-ERR-INTERNAL
          -> STP-ERR-NOT_FEATURE_MANAGER
            -> STP-ERR-CONFIG
          -> STP-ERR-QUEUE
          -> STP-ERR-STATUS
          -> STP-ERR-COUNT_ACTIVE
          -> STP-ERR-COUNT_PENDING
          -> STP-ERR-COUNT_BLOCKED
          -> STP-ERR-COUNT_COMPLETED
          -> STP-ERR-GET_TOP_ACTIVE
          -> STP-ERR-GET_TOP_PENDING
          -> STP-ERR-GET_TOP_BLOCKED
          -> STP-ERR-GET_TOP_COMPLETED
          -> STP-ERR-UPDATE_QUEUE
          -> STP-ERR-WORKTREE_EXISTS
          -> STP-ERR-BRANCH_EXISTS
          -> STP-ERR-CHECKLIST_INCOMPLETE
          -> STP-ERR-CHECKLIST_PARSE
          -> STP-ERR-COUNT_OPEN
          -> STP-ERR-COUNT_DONE
          -> STP-ERR-COUNT_BLOCKED
          -> STP-ERR-COUNT_COMPLETED
          -> STP-ERR-NOT_IN_ACTIVE
          -> STP-ERR-NOT_IN_PENDING
          -> STP-ERR-NOT_IN_BLOCKED
          -> STP-ERR-NOT_IN_COMPLETED
          -> STP-ERR-NO_PENDING
          -> STP-ERR-NO_ACTIVE
          -> STP-ERR-NO_BLOCKED
          -> STP-ERR-NO_COMPLETED
          -> STP-ERR-USER_CANCEL
          -> STP-HALT
```
    }
  }
}
