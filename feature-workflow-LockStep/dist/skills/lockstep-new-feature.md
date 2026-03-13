---
description: 'Create new feature using AILock-Step protocol'
---

# Skill: new-feature (LockStep Edition)

基于 **AILock-Step 协议** 的特性创建流程。

## Usage

```
/new-feature <name>              # 通过名称创建
/new-feature --from-file <path>  # 从文件创建
```

## 执行协议

```yaml
# ═══════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═══════════════════════════════════════════════════════════════════

STP-001:
  desc: "解析用户输入"
  !! OP_PARSE_INPUT($USER_INPUT) >> REG_FEATURE_NAME
  ?? REG_FEATURE_NAME != VAL-NULL
  -> STP-002
  # 否则
  -> STP-ERR-INPUT

STP-002:
  desc: "生成 Feature ID"
  !! OP_GENERATE_ID(REG_FEATURE_NAME, "feat") >> REG_FEATURE_ID
  ?? REG_FEATURE_ID IS UNIQUE
  -> STP-003
  # 否则 (ID 冲突)
  -> STP-ERR-ID_CONFLICT

STP-003:
  desc: "读取配置"
  !! OP_FS_READ("config.yaml") >> REG_CONFIG
  ?? REG_CONFIG != VAL-NULL
  -> STP-010
  # 否则
  -> STP-ERR-CONFIG

# ═══════════════════════════════════════════════════════════════════
# [Phase: INTERACTIVE REQUIREMENTS]
# ═══════════════════════════════════════════════════════════════════

STP-010:
  desc: "询问需求详情"
  !! OP_UI_ASK("请描述 {REG_FEATURE_NAME} 的详细需求:", {
    type: "multiline",
    placeholder: "描述功能需求、用户场景、技术要求..."
  }) >> REG_REQUIREMENTS
  ?? REG_REQUIREMENTS != VAL-NULL
  -> STP-011
  # 跳过
  -> STP-020

STP-011:
  desc: "询问技术方案"
  !! OP_UI_ASK("技术方案 (可选，按回车跳过):", {
    type: "multiline",
    placeholder: "描述技术实现方案..."
  }) >> REG_TECH_SPEC
  -> STP-012

STP-012:
  desc: "询问验收标准"
  !! OP_UI_ASK("验收标准 (可选，按回车跳过):", {
    type: "multiline",
    placeholder: "- [ ] 用户可以...\n- [ ] 系统应该..."
  }) >> REG_ACCEPTANCE
  -> STP-013

STP-013:
  desc: "询问依赖"
  !! OP_UI_ASK("依赖其他 feature? (可选，按回车跳过):", {
    type: "text",
    placeholder: "feat-auth, feat-user"
  }) >> REG_DEPENDENCIES
  -> STP-014

STP-014:
  desc: "询问优先级"
  !! OP_UI_ASK("优先级 (1-100，默认 50):", {
    type: "number",
    default: 50
  }) >> REG_PRIORITY
  -> STP-020

# ═══════════════════════════════════════════════════════════════════
# [Phase: DOCUMENT GENERATION]
# ═══════════════════════════════════════════════════════════════════

STP-020:
  desc: "创建 feature 目录"
  !! OP_BASH("mkdir -p features/pending-{REG_FEATURE_ID}")
  -> STP-021

STP-021:
  desc: "生成 spec.md"
  !! OP_CODE_GEN({
    template: "spec",
    feature_id: REG_FEATURE_ID,
    feature_name: REG_FEATURE_NAME,
    requirements: REG_REQUIREMENTS,
    tech_spec: REG_TECH_SPEC,
    acceptance: REG_ACCEPTANCE,
    dependencies: REG_DEPENDENCIES,
    priority: REG_PRIORITY
  }) >> REG_SPEC_CONTENT
  !! OP_FS_WRITE("features/pending-{REG_FEATURE_ID}/spec.md", REG_SPEC_CONTENT)
  -> STP-022

STP-022:
  desc: "生成 task.md"
  !! OP_CODE_GEN({
    template: "task",
    spec: REG_SPEC_CONTENT
  }) >> REG_TASK_CONTENT
  !! OP_FS_WRITE("features/pending-{REG_FEATURE_ID}/task.md", REG_TASK_CONTENT)
  -> STP-023

STP-023:
  desc: "生成 checklist.md"
  !! OP_CODE_GEN({
    template: "checklist",
    spec: REG_SPEC_CONTENT,
    tasks: REG_TASK_CONTENT
  }) >> REG_CHECKLIST_CONTENT
  !! OP_FS_WRITE("features/pending-{REG_FEATURE_ID}/checklist.md", REG_CHECKLIST_CONTENT)
  -> STP-024

STP-024:
  desc: "创建 .status 文件"
  !! OP_STATUS_INIT("features/pending-{REG_FEATURE_ID}/.status", {
    feature_id: REG_FEATURE_ID,
    feature_name: REG_FEATURE_NAME,
    status: pending,
    priority: REG_PRIORITY,
    dependencies: REG_DEPENDENCIES
  })
  -> STP-030

# ═══════════════════════════════════════════════════════════════════
# [Phase: QUEUE UPDATE]
# ═══════════════════════════════════════════════════════════════════

STP-030:
  desc: "读取队列文件"
  !! OP_FS_READ("feature-workflow-LockStep/queue.yaml") >> REG_QUEUE
  ?? REG_QUEUE != VAL-NULL
  -> STP-031
  # 队列文件不存在
  -> STP-032

STP-031:
  desc: "添加到 pending 列表"
  !! OP_QUEUE_ADD(REG_QUEUE, "pending", {
    id: REG_FEATURE_ID,
    name: REG_FEATURE_NAME,
    priority: REG_PRIORITY,
    dependencies: REG_DEPENDENCIES,
    created_at: NOW()
  })
  -> STP-033

STP-032:
  desc: "创建队列文件"
  !! OP_QUEUE_CREATE({
    pending: [{
      id: REG_FEATURE_ID,
      name: REG_FEATURE_NAME,
      priority: REG_PRIORITY,
      dependencies: REG_DEPENDENCIES,
      created_at: NOW()
    }]
  })
  -> STP-033

STP-033:
  desc: "保存队列文件"
  !! OP_FS_WRITE("feature-workflow-LockStep/queue.yaml", REG_QUEUE)
  -> STP-100

# ═══════════════════════════════════════════════════════════════════
# [Phase: COMPLETION]
# ═══════════════════════════════════════════════════════════════════

STP-100:
  desc: "显示创建结果"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
  ║                    ✅ Feature 创建完成                                 ║
  ╠═══════════════════════════════════════════════════════════════════════╣
  ║                                                                       ║
  ║  ID:          {REG_FEATURE_ID}                                        ║
  ║  名称:        {REG_FEATURE_NAME}                                      ║
  ║  优先级:      {REG_PRIORITY}                                          ║
  ║  依赖:        {REG_DEPENDENCIES}                                      ║
  ║                                                                       ║
  ║  📁 文件:                                                               ║
  ║     features/pending-{REG_FEATURE_ID}/                               ║
  ║       ├── spec.md                                                    ║
  ║       ├── task.md                                                    ║
  ║       ├── checklist.md                                               ║
  ║       └── .status                                                    ║
  ║                                                                       ║
  ║  下一步:                                                                ║
  ║    /start-feature {REG_FEATURE_ID}    # 启动开发                        ║
  ╚═══════════════════════════════════════════════════════════════════════╝
  ")
  -> STP-END

# ═══════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING]
# ═══════════════════════════════════════════════════════════════════

STP-ERR-INPUT:
  desc: "输入无效"
  !! OP_UI_NOTIFY("❌ 错误: 请提供 feature 名称")
  -> STP-HALT

STP-ERR-ID_CONFLICT:
  desc: "ID 冲突"
  !! OP_UI_NOTIFY("❌ 错误: Feature ID '{REG_FEATURE_ID}' 已存在")
  -> STP-HALT

STP-ERR-CONFIG:
  desc: "配置读取失败"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取配置文件")
  -> STP-HALT

STP-HALT:
  desc: "停止执行"
  -> END
```

## 输出示例

```
STP-001: 解析用户输入... ✓
STP-002: 生成 Feature ID: feat-user-auth ✓
STP-003: 读取配置... ✓

STP-010: 询问需求详情...
[用户输入需求描述]

STP-011: 询问技术方案...
[用户输入技术方案]

STP-012: 询问验收标准...
[用户输入验收标准]

STP-013: 询问依赖...
[用户输入依赖]

STP-014: 询问优先级...
[用户输入: 80]

STP-020: 创建 feature 目录... ✓
STP-021: 生成 spec.md... ✓
STP-022: 生成 task.md... ✓
STP-023: 生成 checklist.md... ✓
STP-024: 创建 .status 文件... ✓

STP-030: 读取队列文件... ✓
STP-031: 添加到 pending 列表... ✓
STP-033: 保存队列文件... ✓

STP-100: 显示创建结果 ✓

✅ Feature 创建完成!
```
