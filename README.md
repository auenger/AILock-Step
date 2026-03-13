# AILock-Step

> 基于状态锚点（STP）的严格线性执行协议，消除 AI 幻觉性跳步，确保任务执行的绝对幂等性。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Protocol Version](https://img.shields.io/badge/Protocol-v1.0-blue.svg)](./AILock-Step-运行协议-算子说明书-v1-0.md)

## 📖 什么是 AILock-Step？

**AILock-Step** 是一种创新的 AI 执行协议，它通过**状态锚点（State Anchor Point, STP）**和严格的线性执行逻辑，彻底解决了传统 AI 工作流中的核心问题：

| 问题 | 传统方案 | AILock-Step 方案 |
|------|----------|------------------|
| **幻觉性跳步** | AI 看到 `for task in tasks` 会自动简化中间步骤 | 通过 `STP-XXX -> STP-YYY` 物理跳转，强迫 AI 保持 100% 步骤完整性 |
| **状态不可追溯** | 中断后难以恢复 | 每个 STP 节点都关联 `REG_` 寄存器和物理存盘点 |
| **语义噪声** | AI 容易被感性描述影响 | 冷门符号逻辑 (`??`, `!!`, `>>`) 触发"指令解析模式" |
| **依赖管理松散** | 可能跳过前置条件 | `??` 判断算子充当逻辑哨兵，硬性锁死执行路径 |

## 🚀 核心特性

### 1. 状态锚点（STP）机制

```
STP-[XXX]     - 状态唯一标识符，执行指针必须停留在此处
?? [Condition] - 逻辑门控，条件为假时跳转错误流
!! [Operator]  - 原子算子，不可拆分的物理动作
>> [Target]    - 数据流向，将输出压入寄存器
-> [Target_STP] - 强制跳转，唯一合法的逻辑演进路径
```

### 2. 断点续传能力

每个 STP 都保存完整的寄存器快照，即使执行中断也能精准恢复：

```bash
# 恢复执行
/parallel-dev --resume
```

### 3. 原子算子系统

提供完整的文件系统、Git、数据处理、状态同步和 UI 交互算子：

| 算子 | 描述 |
|------|------|
| `OP_FS_READ/WRITE` | 文件系统读写 |
| `OP_GIT_COMMIT/MERGE` | Git 操作 |
| `OP_CODE_GEN` | 代码生成 |
| `OP_STATUS_UPDATE` | 状态同步 |
| `OP_UI_NOTIFY` | 用户通知 |

## 📁 项目结构

```
AILock-Step/
├── README.md                        # 本文档
├── AILock-Step-运行协议-算子说明书-v1-0.md  # 完整协议说明书（中文）
├── feature-workflow-LockStep/       # LockStep 版工作流实现
│   ├── PROTOCOL.md                  # 协议详细规范
│   ├── config.yaml                  # 配置文件
│   ├── skills/                      # Claude Code 技能
│   │   ├── parallel-dev.md          # 并行开发编排器
│   │   ├── feature-agent.md         # Feature Agent 执行协议
│   │   ├── start-feature.md         # 启动 Feature
│   │   └── complete-feature.md      # 完成 Feature
│   ├── scripts/                     # 辅助脚本
│   ├── templates/                   # 状态文件模板
│   ├── agents/                      # Agent 配置
│   └── tests/                       # 测试用例
└── dist/                            # 构建产物
```

## 🎯 核心工作流

### 并行开发工作流

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

### Feature Agent 工作流

```
[Phase: INITIALIZATION]
STP-001: EVENT:START → STP-002
STP-002: 读取 spec.md → STP-003
STP-003: 读取 task.md → STP-010

[Phase: IMPLEMENT]
STP-010: 检查未完成任务 → STP-011/STP-100
STP-011: 实现当前任务 → STP-012
STP-012: 更新进度 → STP-010

[Phase: VERIFY]
STP-100: 验证所有任务完成 → STP-101
STP-101: npm run lint → STP-102
STP-102: npm test → STP-103
STP-103: 检查 checklist → STP-200

[Phase: COMPLETE]
STP-200: git commit → STP-201
STP-201: 更新 status=done → STP-202
STP-202: EVENT:COMPLETE → END
```

## 🔧 使用方法

### 基础使用

```bash
# 1. 创建新 feature
/new-feature 用户认证

# 2. 启动 feature 开发环境
/start-feature feat-auth

# 3. 启动并行开发 (LockStep 模式)
/parallel-dev

# 系统将严格按照 STP 步骤执行，不会跳过任何验证
```

### 状态文件格式

```yaml
# features/active-{id}/.status
feature_id: feat-auth
status: implementing
stage: implement
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

## 📋 配置选项

详见 [`feature-workflow-LockStep/config.yaml`](./feature-workflow-LockStep/config.yaml)：

```yaml
workflow:
  auto_start_next: true          # 并行开发完成后自动启动下一个
  protocol:
    strict_mode: true             # 严格模式
    emit_stp_events: true         # 输出 STP 进入事件
    checkpoint_interval: 5        # 检查点间隔

verification:
  require_lint: true             # 要求通过 lint
  require_test: true             # 要求通过测试
  require_checklist: true        # 要求完成检查清单

recovery:
  auto_resume: true              # 自动恢复
  max_retries: 3                 # 最大重试次数
```

## 📚 文档

- [完整协议说明书（中文）](./AILock-Step-运行协议-算子说明书-v1-0.md)
- [LockStep 工作流规范](./feature-workflow-LockStep/PROTOCOL.md)
- [原版 feature-workflow 对比](./feature-workflow-LockStep/README.md)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 👤 作者

**Ryan Yang**

---

<div align="center">

**采用 AILock-Step 协议是为了确保任务执行的绝对幂等性。作为一个执行器，不需要理解任务的"宏观意义"，只需确保每一个 STP 的 REG_ 转换准确无误。**

</div>
