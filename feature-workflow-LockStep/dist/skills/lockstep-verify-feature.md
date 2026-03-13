---
description: 'Verify feature using AILock-Step protocol'
---

# Skill: verify-feature (LockStep Edition)

基于 **AILock-Step 协议** 的验证流程。

## Usage

```
/verify-feature <id>                # 验证 feature
/verify-feature <id> --skip-lint    # 跳过 lint
/verify-feature <id> --skip-test   # 跳过测试
```

## 执行协议

```yaml
# ═══════════════════════════════════════════════════════════════════
# [Phase: INITIALIZATION]
# ═══════════════════════════════════════════════════════════════════

STP-001:
  desc: "读取配置"
  !! OP_FS_READ("config.yaml") >> REG_CONFIG
  ?? REG_CONFIG != VAL-NULL
  -> STP-002
  # 失败
  -> STP-ERR-CONFIG

STP-002:
  desc: "查找 Feature"
  !! OP_GET_TOP(REG_QUEUE.active, "id={REG_FEATURE_ID}") >> REG_FEATURE
  ?? REG_FEATURE != VAL-NULL
  -> STP-003
  # 不存在
  -> STP-ERR-NOT_FOUND

STP-003:
  desc: "读取 Feature 状态"
  !! OP_FS_READ("features/active-{REG_FEATURE_ID}/.status") >> REG_STATUS
  -> STP-010

# ═══════════════════════════════════════════════════════════════════
# [Phase: PRE-VERIFY]
# ═══════════════════════════════════════════════════════════════════

STP-010:
  desc: "检查代码完整性"
  ?? REG_STATUS.stage == "complete"
  -> STP-020
  # 代码未完成
  -> STP-011

STP-011:
  desc: "更新状态为验证中"
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: verifying,
    stage: verify,
    stp_pointer: STP-011
    updated_at: NOW()
  })
  !! OP_EVENT_EMIT("STAGE", REG_FEATURE_ID, "verify")
  -> STP-012

STP-012:
  desc: "检查是否跳过 Lint"
  ?? REG_CONFIG.verification.require_lint != true
  -> STP-013
  # 跳过
  -> STP-020

STP-013:
  desc: "运行 Lint"
  !! OP_BASH("cd {REG_WORKTREE} && npm run lint 2>&1") >> REG_LINT_RESULT
  ?? REG_LINT_RESULT CONTAINS "error" OR REG_LINT_RESULT EXIT_CODE != 0
  -> STP-ERR-LINT
  # 通过
  -> STP-014

STP-014:
  desc: "记录 Lint 结果"
  !! OP_LOG("Lint 结果: {REG_LINT_RESULT}")
  -> STP-015
  # 跳过或通过
  -> STP-020

# ═══════════════════════════════════════════════════════════════════
# [Phase: TEST]
# ═══════════════════════════════════════════════════════════════════

STP-020:
  desc: "检查是否跳过测试"
  ?? REG_CONFIG.verification.require_test != true
  -> STP-021
  # 跳过
  -> STP-030

STP-021:
  desc: "运行测试"
  !! OP_BASH("cd {REG_WORKTREE} && npm test 2>&1") >> REG_TEST_RESULT
  ?? REG_TEST_RESULT CONTAINS "FAIL" OR REG_TEST_RESULT EXIT_CODE != 0
  -> STP-ERR-TEST
  # 通过
  -> STP-022

STP-022:
  desc: "记录测试结果"
  !! OP_LOG("测试结果: {REG_TEST_RESULT})
  -> STP-023
  # 跳过或通过
  -> STP-030

# ═══════════════════════════════════════════════════════════════════
# [Phase: CHECKLIST]
# ═══════════════════════════════════════════════════════════════════

STP-030:
  desc: "读取检查清单"
  !! OP_FS_READ("features/active-{REG_FEATURE_ID}/checklist.md") >> REG_CHECKLIST
  ?? REG_CHECKLIST != VAL-NULL
  -> STP-031
  # 无检查清单
  -> STP-040

STP-031:
  desc: "解析检查清单"
  !! OP_ANALYSE(REG_CHECKLIST, "checklist_items") >> REG_CHECKLIST_ITEMS
  -> STP-032

STP-032:
  desc: "统计未完成项"
  !! OP_COUNT(REG_CHECKLIST_ITEMS, "checked=false") >> REG_UNCHECKED_COUNT
  ?? REG_UNCHECKED_COUNT == 0
  -> STP-040
  # 有未完成项
  -> STP-033

STP-033:
  desc: "显示未完成项"
  !! OP_UI_NOTIFY("
⚠️ 以下检查项未完成:
  - [ ] {未完成项列表}
  )
  -> STP-034
  # 继续或 -> STP-035

STP-034:
  desc: "询问是否继续"
  ?? REG_CONFIG.verification.require_checklist == true
  -> STP-035
  # 不要求
  -> STP-100
  # 跳过
  -> STP-040

STP-035:
  desc: "确认继续"
  !! OP_UI_ASK("是否跳过检查清单继续?", ["y", "n"]) >> REG_CHOICE
  ?? REG_CHOICE == "y"
  -> STP-036
  # 继续验证
  -> STP-100
  # 跳过
  -> STP-040

STP-036:
  desc: "更新状态为验证通过"
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: verified,
    stp_pointer: STP-036,
    checklist_passed: REG_CHOICE == "y"
  })
  -> STP-037
  # 跳过
  -> STP-040

STP-037:
  desc: "记录跳过原因"
  !! OP_LOG("Checklist 跳过原因: {REG_CHOICE})
  -> STP-040

# ═════════════════════════════════════════════════════════════════════
# [Phase: COMPLETE]
# ═════════════════════════════════════════════════════════════════════

STP-040:
  desc: "验证完成"
  !! OP_UI_NOTIFY("✅ 验证完成")
  -> STP-041

STP-041:
  desc: "更新最终状态"
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: verified_done,
    stp_pointer: STP-END,
    verification: {
      lint_passed: REG_SKIP_LINT,
      test_passed: REG_SKIP_TEST,
      checklist_passed: REG_CHOICE == "y"
    }
  })
  -> STP-042
  # 失败
  -> STP-050

STP-042:
  desc: "输出验证报告"
  !! OP_UI_NOTIFY("
╔═══════════════════════════════════════════════════════════════════════╗
  ║                    ✅ 验证完成                                       ║
  ╠═════════════════════════════════════════════════════════════════════════╣
  ║  Feature: {REG_FEATURE_ID} ({REG_FEATURE_NAME})                 ║
  ║  Lint:    {✅ 跳过 / {跳过}                             ║
  ║  Test:     {✅ 跳过 / {跳过}                              ║
  ║  Checklist: {✅ 完成 / {REG_CHOICE} 跳过}              ║
  ╠═════════════════════════════════════════════════════════════════════════╣
  ║  验证结果已记录到 features/active-{id}/evidence/         ║
  ╚═════════════════════════════════════════════════════════════════════════╝
  ")
  -> STP-END

# ═══════════════════════════════════════════════════════════════════
# [Phase: ERROR HANDLING]
# ═══════════════════════════════════════════════════════════════════

STP-ERR-CONFIG:
  desc: "配置错误"
  !! OP_UI_NOTIFY("❌ 错误: 无法读取配置文件")
  -> STP-HALT

STP-ERR-NOT_FOUND:
  desc: "Feature 不存在"
  !! OP_UI_NOTIFY("❌ 错误: Feature '{REG_FEATURE_ID}' 不存在")
  -> STP-HALT

STP-ERR-LINT:
  desc: "Lint 失败"
  !! OP_EVENT_EMIT("BLOCKED", REG_FEATURE_ID, "Lint 检查失败")
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: blocked,
    blocked: { reason: "Lint 失败", stp: STP-013 }
  })
  -> STP-034
  # 用户选择
  -> STP-HALT

STP-ERR-TEST:
  desc: "测试失败"
  !! OP_EVENT_EMIT("BLOCKED", REG_FEATURE_ID, "测试失败")
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: blocked,
    blocked: { reason: "测试失败", stp: STP-021 }
  })
  -> STP-022
  # 用户选择
  -> STP-HALT

STP-ERR-CHECKLIST:
  desc: "检查清单未完成"
  !! OP_EVENT_EMIT("BLOCKED", REG_FEATURE_ID, "检查清单未完成")
  !! OP_STATUS_UPDATE(REG_STATUS_FILE, {
    status: blocked,
    blocked: { reason: "检查清单未完成", stp: STP-030 }
  })
  -> STP-034
  # 用户选择
  -> STP-HALT

STP-HALT:
  desc: "停止执行"
  !! OP_UI_NOTIFY("
⚠️ 验证停止

请解决阻塞问题后重新运行 /verify-feature
  ")
  -> END
```

## 跳过选项

| 选项 | 说明 |
|------|------|
| `--skip-lint` | 跳过 Lint 检查 |
| `--skip-test` | 跳过测试 |

## 输出示例

### 验证通过

```
STP-040: 验证完成 ✓
  ✅ Lint: 跳过
  ✅ Test: 跳过
  ✅ Checklist: 完成

  📄 验证结果已记录到 features/active-feat-auth/evidence/
```

### 有阻塞

```
STP-013: Lint 检查失败... ⚠️
  请手动修复后重新运行 /verify-feature --resume
```
