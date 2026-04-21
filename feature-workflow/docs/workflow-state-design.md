# Workflow State 协议设计与实现方案

> 解决 P0 问题 1（stop hook 循环）和 P0 问题 2（features 目录并发冲突）
>
> 日期：2026-04-21

---

## 一、背景

当前 feature-workflow 的调度协调依赖三个脆弱机制：

1. **`.loop-active` marker 文件** — 只有开/关两个状态，无法区分"等待 SubAgent"和"正在派发"
2. **目录名表达状态** — `mv pending-{id} active-{id}` 不是原子操作，并行时可能竞态
3. **hook 盲猜** — `on-stop-check.sh` 不知道当前有多少 SubAgent 在跑，只能输出模糊的"不许停"

### 触发的具体问题

**问题 1：stop hook 循环**
dev-agent 派发后台 SubAgent 后主上下文空闲，Claude 尝试停止，hook 用 `exit 2` 阻止但不知道该让 Claude 干什么，形成循环。

**问题 2：features 目录并发冲突**
多个 SubAgent 并发写 `queue.yaml` 和 `archive-log.yaml`，后者覆盖前者。`complete-feature` 中途失败时 `features/active-{id}/` 残留。

---

## 二、设计目标

1. 替代 `.loop-active` marker，提供精确的循环状态
2. 跟踪活跃 SubAgent，让 hook 能给出明确指令
3. 提供文件级写锁，防止并发写冲突
4. 原子写入保证，不会出现半写状态
5. 不被 git 跟踪，不受 worktree 影响

---

## 三、状态文件设计

### 3.1 文件位置

```
~/.claude/projects/-{project-path}/workflow-state.json
```

**路径计算方式**（hook 和 SubAgent 统一）：

```bash
# 方法 1：直接用已知的 Claude Code 项目目录
STATE_FILE="$HOME/.claude/projects/$(echo "$CLAUDE_PROJECT_DIR" | sed 's|/|-|g')/workflow-state.json"

# 实际路径示例：
# /Users/ryan/.claude/projects/-Users-ryan-mycode-AILock-Step/workflow-state.json
```

**为什么选这个位置**：
- 在 git 树之外，永远不会被 git 跟踪或 merge 影响
- Claude Code 已有 `~/.claude/projects/` 目录结构，约定俗成
- 所有 worktree 的 SubAgent 通过 `$CLAUDE_PROJECT_DIR` 计算出的路径完全一致，指向同一个物理文件

### 3.2 文件结构

```json
{
  "version": 1,
  "loop": {
    "active": true,
    "status": "waiting_subagents",
    "started_at": "2026-04-21T10:00:00",
    "iteration": 3
  },
  "agents": {
    "feat-context-shuttle": {
      "status": "running",
      "stage": "implement-feature",
      "started_at": "2026-04-21T10:01:00",
      "pid": null
    },
    "feat-session-concurrency": {
      "status": "running",
      "stage": "start-feature",
      "started_at": "2026-04-21T10:01:05",
      "pid": null
    }
  },
  "locks": {
    "queue.yaml": null,
    "archive-log.yaml": null
  }
}
```

### 3.3 字段定义

#### `loop` — 主循环状态

| 字段 | 类型 | 说明 |
|------|------|------|
| `active` | boolean | 循环是否激活 |
| `status` | string | 当前阶段（见下表） |
| `started_at` | string | ISO 8601 时间戳 |
| `iteration` | number | 当前第几轮（用于调试） |

**loop.status 枚举**：

| status | 含义 | hook 指令 |
|--------|------|----------|
| `dispatching` | 正在派发 SubAgent | "继续调度" |
| `waiting_subagents` | 等待后台 SubAgent 完成 | "等待 SubAgent 返回，不要派发新的" |
| `evaluating` | 收到结果，评估下一步 | "继续评估" |
| `stopping` | 循环正常结束 | 允许停止 |

#### `agents` — 活跃 SubAgent 跟踪

| 字段 | 类型 | 说明 |
|------|------|------|
| `{feature_id}.status` | string | `running` / `completed` / `error` |
| `{feature_id}.stage` | string | 当前在哪个 skill（start/implement/verify/complete） |
| `{feature_id}.started_at` | string | 开始时间 |
| `{feature_id}.pid` | number/null | 预留，用于超时检测 |

#### `locks` — 文件写锁

| 字段 | 类型 | 说明 |
|------|------|------|
| `{filename}` | string/null | 持有锁的 feature ID，null 表示未锁定 |

### 3.4 生命周期

```
/dev-agent 启动
│
├─ 写入 .state.json
│  { loop: { active: true, status: "dispatching", ... }, agents: {}, locks: {} }
│
├─ 派发 SubAgent A
│  更新: agents.feat-a = { status: "running", stage: "start-feature", ... }
│  更新: loop.status = "waiting_subagents"
│
├─ ...主上下文空闲...
│  hook 读到 status == "waiting_subagents" → 告诉 Claude "等待 SubAgent 返回"
│
├─ SubAgent A 进入 implement-feature
│  更新: agents.feat-a.stage = "implement-feature"
│  （SubAgent 自己更新自己的条目）
│
├─ SubAgent A 完成
│  SubagentStop hook 触发 → 更新 agents.feat-a.status = "completed"
│  → dev-agent 主循环收到结果
│
├─ 评估 → 还有 pending → 派发下一批
│  更新: loop.status = "dispatching", loop.iteration++
│  移除: agents.feat-a
│  添加: agents.feat-b
│
├─ ...循环继续...
│
└─ 所有 pending 完成
   更新: loop.status = "stopping", loop.active = false
   删除 .state.json（或清空为 inactive 状态供 --resume 使用）
```

---

## 四、原子操作机制

### 4.1 写入协议

所有对 `workflow-state.json` 的修改必须通过 **tmp + mv** 保证原子性：

```bash
STATE_FILE="$(compute_state_path)"
TMP_FILE="${STATE_FILE}.tmp"

# 1. 读取当前状态
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')

# 2. 修改（用 python/jq）
echo "$CURRENT" | python3 -c "
import sys, json
state = json.load(sys.stdin)
state['loop']['status'] = 'waiting_subagents'
json.dump(state, sys.stdout, indent=2)
" > "$TMP_FILE"

# 3. 原子替换
mv "$TMP_FILE" "$STATE_FILE"
```

`mv` 在同一文件系统上是 POSIX 保证的原子操作。

### 4.2 文件锁协议

SubAgent 写 `queue.yaml` 或 `archive-log.yaml` 前：

```
1. 读 workflow-state.json → 检查 locks["queue.yaml"]
2. 如果被其他 feature 持有 → 等待 1s → 重试（最多 30 次）
3. 如果为 null → 加锁（设为自己的 feature_id）→ 写入 → 解锁（设为 null）
4. 每次加锁/解锁都是完整的 tmp+mv 原子操作
```

锁超时保护：如果锁持有时间 > 5 分钟（检查 `started_at`），视为 stale lock，强制释放。

### 4.3 状态更新方

| 谁 | 更新什么 | 时机 |
|----|---------|------|
| dev-agent (主上下文) | `loop.*`, 添加/移除 `agents` 条目 | 每轮循环开始/结束 |
| SubAgent | 自己的 `agents.{id}.stage` | 进入新 stage 时 |
| SubAgent | `locks.*` | 写文件前/后 |
| SubagentStop hook | `agents.{id}.status` → completed | SubAgent 完成时 |
| Stop hook | 只读，不写入 | — |

---

## 五、Hook 改造方案

### 5.1 on-stop-check.sh（改造后）

```bash
#!/bin/bash
# on-stop-check.sh — 读取 workflow-state.json 决定是否阻止停止

STATE_FILE="$HOME/.claude/projects/$(echo "$CLAUDE_PROJECT_DIR" | sed 's|/|-|g')/workflow-state.json"

# 无状态文件 → 允许停止
[ -f "$STATE_FILE" ] || exit 0

# 读取 loop 状态
LOOP_STATUS=$(python3 -c "
import json, sys
try:
    state = json.load(open('$STATE_FILE'))
    print(state.get('loop', {}).get('status', 'stopped'))
except:
    print('stopped')
" 2>/dev/null)

case "$LOOP_STATUS" in
    dispatching|evaluating)
        echo "[STOP BLOCKED] dev-agent is ${LOOP_STATUS}. Continue immediately." >&2
        exit 2
        ;;
    waiting_subagents)
        # 检查是否还有 running 的 SubAgent
        RUNNING=$(python3 -c "
import json
state = json.load(open('$STATE_FILE'))
agents = state.get('agents', {})
running = [k for k, v in agents.items() if v.get('status') == 'running']
print(len(running))
" 2>/dev/null || echo "0")

        if [ "$RUNNING" -gt 0 ]; then
            echo "[STOP BLOCKED] Waiting for ${RUNNING} SubAgent(s) to complete. Do NOT dispatch new work. Just wait." >&2
            exit 2
        else
            # SubAgent 都完成了但 loop 还在 → 提示继续评估
            echo "[STOP BLOCKED] SubAgents completed. Continue the loop to evaluate results." >&2
            exit 2
        fi
        ;;
    stopping|*)
        exit 0
        ;;
esac
```

**关键改进**：
- 旧版：只有 "不许停"，没有具体指令
- 新版：区分"等待 SubAgent"和"继续评估"，给出精确指令

### 5.2 on-subagent-complete.sh（改造后）

```bash
#!/bin/bash
# on-subagent-complete.sh — SubAgent 完成时更新状态

STATE_FILE="$HOME/.claude/projects/$(echo "$CLAUDE_PROJECT_DIR" | sed 's|/|-|g')/workflow-state.json"

[ -f "$STATE_FILE" ] || exit 0

# 从 Agent Tool 的输出中提取 feature_id（通过环境变量或参数传递）
# SubagentStop hook 的 stdin 会包含 SubAgent 的返回信息
FEATURE_ID="${CLAUDE_AGENT_FEATURE_ID:-}"

if [ -n "$FEATURE_ID" ]; then
    python3 -c "
import json
state = json.load(open('$STATE_FILE'))
if '$FEATURE_ID' in state.get('agents', {}):
    state['agents']['$FEATURE_ID']['status'] = 'completed'
    with open('${STATE_FILE}.tmp', 'w') as f:
        json.dump(state, f, indent=2)
import os
os.rename('${STATE_FILE}.tmp', '$STATE_FILE')
" 2>/dev/null
fi

# 检查是否还有 pending → 输出提示
QUEUE_FILE="feature-workflow/queue.yaml"
if [ -f "$QUEUE_FILE" ]; then
    PENDING=$(python3 -c "
import yaml
q = yaml.safe_load(open('$QUEUE_FILE'))
print(len(q.get('pending', [])))
" 2>/dev/null || echo "0")

    if [ "$PENDING" -gt 0 ]; then
        echo "[AUTO-LOOP] SubAgent completed. ${PENDING} pending features remain. Continue the loop."
    fi
fi

exit 0
```

**注意**：`CLAUDE_AGENT_FEATURE_ID` 环境变量需要 dev-agent 在派发 SubAgent 时通过 prompt 约定传递，因为 hook 无法直接知道刚完成的是哪个 feature。替代方案：SubAgent 在退出前自己更新 `.state.json`（更可靠）。

---

## 六、Features 目录冲突解决方案

### 6.1 核心变更

**SubAgent 写 `queue.yaml` 的安全协议**：

```
implement-feature/verify-feature/complete-feature 中写 queue.yaml 时：

1. 调用 acquire_lock("queue.yaml", feature_id)
   - 读 state.json → 检查 locks["queue.yaml"]
   - 如果被占用 → 等待 + 重试
   - 如果空闲 → 加锁

2. 写入 queue.yaml

3. 调用 release_lock("queue.yaml")
   - 设置 locks["queue.yaml"] = null
```

**同理适用于 `archive-log.yaml`**。

### 6.2 shared-state 工具函数

在 skill 中增加一个共享的状态操作工具（可作为 skill 内的约定，或提取到公共模块）：

```bash
# 获取状态文件路径
state_file() {
    echo "$HOME/.claude/projects/$(echo "$CLAUDE_PROJECT_DIR" | sed 's|/|-|g')/workflow-state.json"
}

# 原子更新状态
state_update() {
    local python_expr="$1"
    local sf=$(state_file)
    python3 -c "
import json, os
sf = '$sf'
state = json.load(open(sf)) if os.path.exists(sf) else {}
exec('$python_expr')
with open(sf + '.tmp', 'w') as f:
    json.dump(state, f, indent=2)
os.rename(sf + '.tmp', sf)
"
}

# 获取文件锁
acquire_lock() {
    local file="$1" holder="$2"
    local retries=0
    while [ $retries -lt 30 ]; do
        local locked=$(state_update "
lock = state.setdefault('locks', {}).get('$file')
if lock and lock != '$holder':
    result = 'locked'
else:
    state['locks']['$file'] = '$holder'
    result = 'acquired'
")
        [ "$locked" = "acquired" ] && return 0
        sleep 1
        retries=$((retries + 1))
    done
    return 1  # 超时
}

# 释放文件锁
release_lock() {
    local file="$1"
    state_update "state.setdefault('locks', {})['$file'] = None"
}
```

---

## 七、实现步骤

### Phase 1：基础设施（无破坏性）

1. **创建状态文件工具函数**
   - 在 `feature-workflow/implementation/core-lib.md` 中增加 state 操作参考
   - 或创建 `feature-workflow/scripts/state-utils.sh`

2. **改造 hook 脚本**
   - `on-stop-check.sh`：从读 `.loop-active` + awk YAML 改为读 `workflow-state.json`
   - `on-subagent-complete.sh`：从 grep YAML 改为读状态文件
   - 两个脚本增加 python3 fallback（macOS 自带）

3. **改造 dev-agent.md**
   - Pre-flight：创建 `workflow-state.json`（替代 `.loop-active`）
   - 派发 SubAgent：写入 `agents` 条目
   - 收到结果：移除 `agents` 条目
   - 循环中：更新 `loop.status`
   - 结束时：清理状态文件

### Phase 2：并发安全

4. **改造 complete-feature skill**
   - 写 queue.yaml 前后加 acquire_lock / release_lock
   - 写 archive-log.yaml 前后加锁

5. **改造 implement-feature / verify-feature skill**
   - 同样对 queue.yaml 的写入加锁

### Phase 3：清理与迁移

6. **移除旧机制**
   - 删除 `.loop-active` marker 相关逻辑
   - 删除 `on-stop-check.sh` 中 awk 解析 YAML 的代码
   - 更新 `dev-subagent.md`（标记为完全废弃或删除）

7. **更新 config.yaml**
   - 移除 `auto_start` / `auto_start_next`（状态文件替代其语义）
   - 或保留为默认值，状态文件作为运行时覆盖

---

## 八、风险与回退

| 风险 | 缓解 |
|------|------|
| python3 不可用 | macOS 自带；Linux 默认安装；可 fallback 到简单 grep |
| 状态文件损坏 | SubAgent 启动时校验 JSON 结构，损坏则重建 |
| SubAgent 崩溃不释放锁 | 锁超时机制（5 分钟自动释放） |
| 迁移期间新旧机制冲突 | Phase 1 中保留旧 hook 作为 fallback，新 hook 失败时走旧逻辑 |

---

## 九、验证清单

- [ ] hook 正确读取 `workflow-state.json` 并给出精确指令
- [ ] SubAgent 能找到并更新状态文件（不受 worktree 影响）
- [ ] 并发 SubAgent 写 queue.yaml 不丢失数据
- [ ] SubAgent 崩溃后锁自动释放
- [ ] `--resume` 模式能从状态文件恢复
- [ ] 手动 `/start-feature` 等独立 skill 不受影响
