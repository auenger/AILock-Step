---
description: 'List all features using AILock-Step protocol'
---

# Skill: list-features (LockStep Edition)

列出所有 features 及其状态。

## Usage

```
/list-features                    # 列出所有 features
/list-features --status           # 只显示状态
```

## 执行协议

```yaml
# ═════════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═══════════════════════════════════════════════════════════════════════

STP-001:
  desc: "读取配置"
  !! OP_FS_READ("feature-workflow-LockStep/config.yaml") >> REG_CONFIG
  -> STP-002

STP-002:
  desc: "读取队列"
  !! OP_FS_READ("feature-workflow-LockStep/queue.yaml") >> REG_QUEUE
  ?? REG_QUEUE != VAL-NULL
  -> STP-003
  # 失败
  -> STP-ERR-QUEUE

STP-003:
  desc: "解析队列数据"
  !! OP_ANALYSE(REG_QUEUE, "structure") >> REG_PARSED_QUEUE
  -> STP-010

            # 继续解析
            -> STP-011

STP-011:
  desc: "统计各列表"
  !! OP_COUNT(REG_PARSED_QUEUE.active, "*") >> REG_ACTIVE_COUNT
  !! OP_COUNT(REG_PARSED_QUEUE.pending, "*") >> REG_PENDING_COUNT
  !! OP_COUNT(REG_PARSED_QUEUE.completed, "*") >> REG_COMPLETED_COUNT
  !! OP_COUNT(REG_PARSED_QUEUE.blocked, "*") >> REG_BLOCKed_COUNT
  -> STP-020

            # 继续统计
            -> STP-021

STP-021:
  desc: "显示统计面板"
  !! OP_UI_NOTIFY("
╔══════════════════════════════════════════════════════════════════════
║  状态        │ 数量   │ 说明                              │
├──────────┼─────────┼────────────────────────────┤
│ active       │ {REG_ACTIVE_COUNT}    │ 正在开发中               │
├──────────┼─────────┼────────────────────────────┤
│ pending     │ {REG_PENDING_COUNT}    │ 等待开发               │
├──────────┼─────────┼────────────────────────────┤
│ blocked    │ {REG_BLOCKED_COUNT}    │ 预期/阻塞              │
├──────────┼─────────┼────────────────────────────┤
│ completed  │ {REG_COMPLETED_COUNT}    │ 已完成               │
╚════════════════════════════════════════════════════════════════════

💡 操作:
   [c] 继续监控
   [s] 立即刷新
   [q] 退出
   [l] 查看日志
```
