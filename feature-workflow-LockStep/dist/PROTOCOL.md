# AILock-Step 运行协议 & 算子说明书

## 1. 协议声明 (Protocol Declaration)

本协议定义了一种基于**状态锚点（STP）**的线性执行逻辑。执行器（AI）必须严格遵守 `[编号] [判断] [动作] [跳转]` 的单步逻辑，严禁在未收到 `-> STP-NEXT` 指令前进行跨步预测或语义扩充。

## 2. 语法解析定义 (Syntax Definitions)

| 符号 | 名称 | 描述 |
|------|------|------|
| `STP-[XXX]` | 状态锚点 | 状态唯一标识符。执行指针必须停留在此处，直到动作完成。 |
| `?? [Condition]` | 逻辑门控 | 如果条件为 `VAL-NULL`（假），停止执行当前行并跳转至错误流。 |
| `!! [Operator]` | 原子算子 | 代表一个不可拆分的物理动作。 |
| `>> [Target]` | 数据流向 | 将左侧算子的输出压入右侧寄存器（`REG_`）。 |
| `-> [Target_STP]` | 强制跳转 | 唯一合法的逻辑演进路径。 |

## 3. 标准算子集 (Instruction Set)

### 文件系统算子

| 算子 | 参数 | 描述 |
|------|------|------|
| `OP_FS_READ` | `(PATH)` | 物理读取文件系统内容。若路径不存在，返回 `VAL-NULL`。 |
| `OP_FS_WRITE` | `(PATH, CONTENT)` | 写入/覆盖指定路径文件。 |
| `OP_FS_EXISTS` | `(PATH)` | 检查路径是否存在，返回 `VAL-SET` 或 `VAL-NULL`。 |
| `OP_FS_DELETE` | `(PATH)` | 删除指定文件或目录。 |

### Git 算子

| 算子 | 参数 | 描述 |
|------|------|------|
| `OP_GIT_STATUS` | `()` | 获取当前 git 状态。 |
| `OP_GIT_COMMIT` | `(MSG)` | 提交当前变更。 |
| `OP_GIT_MERGE` | `(BRANCH)` | 合并指定分支。 |
| `OP_GIT_WORKTREE_ADD` | `(PATH, BRANCH)` | 创建 worktree。 |
| `OP_GIT_WORKTREE_REMOVE` | `(PATH)` | 删除 worktree。 |
| `OP_GIT_TAG` | `(NAME, MSG)` | 创建 tag。 |

### 数据处理算子

| 算子 | 参数 | 描述 |
|------|------|------|
| `OP_ANALYSE` | `(DATA, RULE)` | 结构化解析。将非结构化文档转化为 `REG_` 可识别的 Key-Value。 |
| `OP_GET_TOP` | `(LIST, FILTER)` | 从列表寄存器中取出第一个符合过滤条件的项。 |
| `OP_COUNT` | `(LIST, FILTER)` | 统计符合条件的项目数量。 |
| `OP_CODE_GEN` | `(CTX, TASK)` | 调用核心能力，基于上下文（CTX）实现具体任务（TASK）的代码。 |

### 状态同步算子

| 算子 | 参数 | 描述 |
|------|------|------|
| `OP_STATUS_UPDATE` | `(PATH, DATA)` | 更新 .status 文件。 |
| `OP_TASK_SYNC` | `(ID, STATUS)` | 物理同步 `task.md` 状态。标记特定任务 ID 为 `done` 或 `open`。 |
| `OP_EVENT_EMIT` | `(TYPE, ID, DATA)` | 输出 EVENT token 到日志。 |

### UI 交互算子

| 算子 | 参数 | 描述 |
|------|------|------|
| `OP_UI_NOTIFY` | `(MSG)` | 向用户界面输出状态报告或询问确认。 |
| `OP_UI_ASK` | `(MSG, OPTIONS)` | 向用户询问并等待响应。 |

## 4. 寄存器约定 (Register Conventions)

| 寄存器 | 用途 |
|--------|------|
| `REG_QUEUE` | 队列数据 |
| `REG_FEATURE_ID` | 当前 Feature ID |
| `REG_SPEC` | 需求文档内容 |
| `REG_TASK_ALL` | 所有任务列表 |
| `REG_CUR_TASK` | 当前任务 |
| `REG_STATUS` | 状态数据 |
| `REG_ERROR` | 错误信息 |

## 5. 状态值约定 (Status Values)

| 值 | 含义 |
|----|------|
| `VAL-SET` | 真 / 存在 / 成功 |
| `VAL-NULL` | 假 / 不存在 / 失败 |
| `VAL-EMPTY` | 空值 |

## 6. 执行规则 (Execution Rules)

### 6.1 单步执行
- 每次只执行一个 STP
- 必须完成当前 STP 的所有动作才能跳转
- 跳转必须通过 `->` 符号

### 6.2 条件判断
- `??` 后的条件必须求值为 `VAL-SET` 或 `VAL-NULL`
- 如果为 `VAL-NULL`，立即跳转到错误处理或指定分支
- 不允许"隐式继续"

### 6.3 原子性
- `!!` 标记的算子是原子的
- 算子执行要么完全成功，要么完全失败
- 失败时保留当前 REG_ 快照

## 7. 异常处理 (Error Handling)

当任何 `??` 判断失败，且未定义错误路径时，执行器必须立即：

1. **停止所有物理写入操作**
2. **输出 `STATUS: ERROR` 并保留当前所有 `REG_` 寄存器快照**
3. **更新 .status 文件：status=error, stp_pointer=当前STP**
4. **等待人工 `RESUME` 指令**

### 恢复流程

```
STP-RESUME:
  !! OP_FS_READ(".status") >> REG_STATUS
  ?? REG_STATUS.stp_pointer IS VALID
  !! OP_UI_NOTIFY("恢复执行从 " + REG_STATUS.stp_pointer)
  -> REG_STATUS.stp_pointer
```

## 8. EVENT Token 规范

```
EVENT:START <feature-id>
EVENT:STAGE <feature-id> <stage>
EVENT:PROGRESS <feature-id> <done>/<total>
EVENT:BLOCKED <feature-id> "<reason>"
EVENT:COMPLETE <feature-id> <tag>
EVENT:ERROR <feature-id> "<message>"
EVENT:STP <feature-id> <stp-id>  # 新增：STP 进入事件
```

## 9. 完整执行范例

### Feature Agent 执行流程

```yaml
# [Phase: INITIALIZATION]

STP-001:
  !! OP_EVENT_EMIT("START", REG_FEATURE_ID)
  !! OP_STATUS_UPDATE(REG_STATUS_PATH, {status: started, stp_pointer: STP-001})
  -> STP-002

STP-002:
  !! OP_FS_READ(REG_SPEC_PATH) >> REG_SPEC
  ?? REG_SPEC != VAL-NULL
  -> STP-003

STP-003:
  !! OP_FS_READ(REG_TASK_PATH) >> REG_TASK_ALL
  ?? REG_TASK_ALL != VAL-NULL
  -> STP-010

# [Phase: IMPLEMENT]

STP-010:
  !! OP_EVENT_EMIT("STAGE", REG_FEATURE_ID, "implement")
  !! OP_STATUS_UPDATE(REG_STATUS_PATH, {status: implementing, stage: implement, stp_pointer: STP-010})
  -> STP-011

STP-011:
  !! OP_GET_TOP(REG_TASK_ALL, "status=open") >> REG_CUR_TASK
  ?? REG_CUR_TASK != VAL-NULL
  -> STP-012
  # 否则 -> STP-100 (所有任务完成)

STP-012:
  !! OP_CODE_GEN(REG_SPEC, REG_CUR_TASK) >> REG_NEW_CODE
  -> STP-013

STP-013:
  !! OP_FS_WRITE(REG_CUR_TASK.path, REG_NEW_CODE)
  -> STP-014

STP-014:
  !! OP_TASK_SYNC(REG_CUR_TASK.id, "done")
  !! OP_EVENT_EMIT("PROGRESS", REG_FEATURE_ID, "{done}/{total}")
  -> STP-011  # 回旋跳转

# [Phase: VERIFY]

STP-100:
  ?? OP_COUNT(REG_TASK_ALL, "status=open") == 0
  !! OP_EVENT_EMIT("STAGE", REG_FEATURE_ID, "verify")
  !! OP_STATUS_UPDATE(REG_STATUS_PATH, {status: verifying, stage: verify, stp_pointer: STP-100})
  -> STP-101

STP-101:
  !! OP_BASH("cd {WORKTREE} && npm run lint") >> REG_LINT_RESULT
  ?? REG_LINT_RESULT == VAL-SET
  -> STP-102
  # 否则 -> STP-ERR-LINT

STP-102:
  !! OP_BASH("cd {WORKTREE} && npm test") >> REG_TEST_RESULT
  ?? REG_TEST_RESULT == VAL-SET
  -> STP-103
  # 否则 -> STP-ERR-TEST

STP-103:
  !! OP_FS_READ(REG_CHECKLIST_PATH) >> REG_CHECKLIST
  !! OP_ANALYSE(REG_CHECKLIST, "all_checked") >> REG_CHECKLIST_RESULT
  ?? REG_CHECKLIST_RESULT == VAL-SET
  -> STP-200
  # 否则 -> STP-ERR-CHECKLIST

# [Phase: COMPLETE]

STP-200:
  !! OP_EVENT_EMIT("STAGE", REG_FEATURE_ID, "complete")
  !! OP_STATUS_UPDATE(REG_STATUS_PATH, {status: completing, stage: complete, stp_pointer: STP-200})
  -> STP-201

STP-201:
  !! OP_GIT_COMMIT("feat({REG_FEATURE_ID}): {REG_FEATURE_NAME}")
  -> STP-202

STP-202:
  !! OP_STATUS_UPDATE(REG_STATUS_PATH, {status: done, stp_pointer: STP-END})
  !! OP_EVENT_EMIT("COMPLETE", REG_FEATURE_ID, "done")
  -> STP-END

# [Phase: ERROR HANDLING]

STP-ERR-LINT:
  !! OP_EVENT_EMIT("BLOCKED", REG_FEATURE_ID, "Lint 失败")
  !! OP_STATUS_UPDATE(REG_STATUS_PATH, {status: blocked, error: {type: lint, stp: STP-101}})
  -> STP-HALT

STP-ERR-TEST:
  !! OP_EVENT_EMIT("BLOCKED", REG_FEATURE_ID, "测试失败")
  !! OP_STATUS_UPDATE(REG_STATUS_PATH, {status: blocked, error: {type: test, stp: STP-102}})
  -> STP-HALT

STP-ERR-CHECKLIST:
  !! OP_EVENT_EMIT("BLOCKED", REG_FEATURE_ID, "检查清单未完成")
  !! OP_STATUS_UPDATE(REG_STATUS_PATH, {status: blocked, error: {type: checklist, stp: STP-103}})
  -> STP-HALT

STP-HALT:
  !! OP_UI_NOTIFY("执行阻塞，请查看 .status 文件")
  -> END
```
