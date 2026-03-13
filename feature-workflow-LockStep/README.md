# Feature Workflow - LockStep Edition

基于 **AILock-Step 运行协议** 的特性开发工作流系统。

## 核心设计理念

### 为什么选择 LockStep 协议？

传统 AI 工作流存在以下问题：

| 问题 | 传统方案 | LockStep 方案 |
|------|----------|---------------|
| **幻觉性跳步** | AI 看到 `for task in tasks` 会自动简化中间步骤 | 通过 `STP-XXX -> STP-YYY` 物理跳转，强迫 AI 保持 100% 步骤完整性 |
| **状态不可追溯** | 中断后难以恢复 | 每个 STP 节点都关联 REG_ 寄存器和物理存盘点 |
| **语义噪声** | AI 容易被感性描述影响 | 冷门符号逻辑 (`??`, `!!`, `>>`) 触发"指令解析模式" |
| **依赖管理松散** | 可能跳过前置条件 | `??` 判断算子充当逻辑哨兵，硬性锁死执行路径 |

## 协议语法

```
STP-[XXX]     - 状态唯一标识符，执行指针必须停留在此处
?? [Condition] - 逻辑门控，条件为假时跳转错误流
!! [Operator]  - 原子算子，不可拆分的物理动作
>> [Target]    - 数据流向，将输出压入寄存器
-> [Target_STP] - 强制跳转，唯一合法的逻辑演进路径
```

## 目录结构

```
feature-workflow-LockStep/
├── README.md                 # 本文档
├── PROTOCOL.md              # 完整协议说明书
├── config.yaml              # 配置文件
├── skills/
│   ├── parallel-dev.md      # 并行开发编排器 (STP 版)
│   ├── feature-agent.md     # Feature Agent 执行协议 (STP 版)
│   ├── start-feature.md     # 启动 Feature
│   └── complete-feature.md  # 完成 Feature
├── scripts/
│   └── start-feature-agent.sh
└── templates/
    └── status.yaml          # 状态文件模板
```

## 核心工作流

### 1. 并行开发 (parallel-dev)

```
[Phase: Initialization]
STP-001: 读取队列 → STP-002
STP-002: 检查 active features → STP-100

[Phase: Monitor Loop]
STP-100: 检查每个 .status 文件 → STP-101/STP-200/STP-300
STP-101: 状态=not_started → 启动 Agent → STP-100
STP-200: 状态=done → 调用 complete → STP-201
STP-201: 检查 auto_start_next → STP-202/STP-300
STP-202: 启动下一个 feature → STP-100
STP-300: 所有完成 → 退出
```

### 2. Feature Agent (feature-agent)

```
[Phase: IMPLEMENT]
STP-001: 输出 EVENT:START → STP-002
STP-002: 读取 spec.md → STP-003
STP-003: 读取 task.md → STP-010

[Phase: IMPLEMENT Loop]
STP-010: 检查未完成任务 → STP-011/STP-100
STP-011: 实现当前任务 → STP-012
STP-012: 更新进度 → STP-010

[Phase: VERIFY]
STP-100: ?? 所有任务完成 → STP-101/STP-ERR
STP-101: 输出 EVENT:STAGE verify → STP-102
STP-102: !! npm run lint → STP-103
STP-103: !! npm test → STP-104
STP-104: !! 检查 checklist → STP-200

[Phase: COMPLETE]
STP-200: !! git commit → STP-201
STP-201: !! 更新 status=done → STP-202
STP-202: !! EVENT:COMPLETE → END
```

## 使用方法

```bash
# 1. 创建新 feature
/new-feature 用户认证

# 2. 启动 feature 开发环境
/start-feature feat-auth

# 3. 启动并行开发 (LockStep 模式)
/parallel-dev

# 系统将严格按照 STP 步骤执行，不会跳过任何验证
```

## 状态文件格式

```yaml
# features/active-{id}/.status
feature_id: feat-auth
status: started | implementing | verifying | completing | done | blocked | error
stage: init | implement | verify | complete
stp_pointer: STP-010    # 当前执行到的状态锚点
progress:
  tasks_total: 5
  tasks_done: 3
  current_task: "实现登录 API"
registers:
  REG_CUR_TASK: "task-003"
  REG_SPEC: "..."
started_at: 2026-03-05T10:00:00Z
updated_at: 2026-03-05T10:30:00Z
```

## 断点恢复

由于每个 STP 都有明确的状态锚点和寄存器快照：

1. 读取 `.status` 文件
2. 定位 `stp_pointer` 字段
3. 从该 STP 继续执行

```bash
# 恢复执行
/parallel-dev --resume
```

## 与原版对比

| 特性 | 原版 feature-workflow | LockStep 版 |
|------|----------------------|-------------|
| 执行模式 | 自然语言指令 | STP 状态机 |
| 跳步风险 | 中等 | 极低 |
| 断点恢复 | 依赖 .status | STP 指针精确恢复 |
| 验证强制 | 靠 prompt 强调 | `??` 门控硬性检查 |
| 可追溯性 | 日志 + EVENT | REG_ 寄存器快照 |
