# Hooks Implementation — Auto-Loop Enforcement

> 备份位置: `feature-workflow/implementation/hooks/`
> 部署位置: `.claude/hooks/` + `.claude/settings.json`

## 概述

Hooks 是 dev-agent 自动循环的**第三层防御**，从机制层面阻止 Claude 停下来问用户。

三层防御体系：
1. **Prompt 硬性指令** — dev-agent.md 顶部 SYSTEM RULE
2. **SubAgent 返回值** — `next_pending` 字段驱动循环
3. **Hooks 拦截** — SubagentStop + Stop 事件，硬性阻止停止

## 文件清单

| 文件 | Hook 事件 | 作用 |
|------|-----------|------|
| `on-subagent-complete.sh` | `SubagentStop` | SubAgent 完成时，检查 queue.yaml 是否有 pending，注入续跑指令 |
| `on-stop-check.sh` | `Stop` | Claude 尝试停止时，检查 pending 是否非空，exit 2 阻止停止 |
| `settings.json.example` | — | hooks 配置模板，安装时复制到 `.claude/settings.json` |

## 工作原理

### on-subagent-complete.sh (SubagentStop)

```
SubAgent 完成 → hook 触发
  → 读 config.yaml: auto_start_next == true?
  → 读 queue.yaml: pending 非空?
  → 两个条件都满足 → 输出 "[AUTO-LOOP HOOK] ... Continue immediately"
  → Claude 读到这段文字，继续循环
```

### on-stop-check.sh (Stop)

```
Claude 准备停止 → hook 触发
  → 读 config.yaml: auto_start_next == true?
  → 读 queue.yaml: pending 有可执行的 feature?
  → 有 → 输出 "[STOP BLOCKED] ... pending features remain" 到 stderr + exit 2
  → exit 2 = 阻止停止，Claude 继续
  → 没有 → exit 0 = 允许停止
```

> **注意**: exit 2 才是 Claude Code hooks 中"阻止操作"的正确退出码。exit 1 会被视为脚本错误（显示 "Failed with non-blocking status code"），不会真正阻止停止。

## settings.json 格式

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "Agent",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/on-subagent-complete.sh\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/on-stop-check.sh\""
          }
        ]
      }
    ]
  }
}
```

## 注意事项

1. 纯 bash 实现，不依赖 python
2. 用 awk 简单解析 YAML（检查 pending 块中的 `- id:` 行）
3. hooks 通过 `install-plugin.sh` 自动安装
4. 如果 settings.json 已存在，安装脚本不会覆盖（需手动合并）
5. `CLAUDE_PROJECT_DIR` 是 Claude Code 注入的环境变量
6. 脚本使用 `$CLAUDE_PROJECT_DIR` 拼接绝对路径，不依赖工作目录（`cd` 不可靠）
7. on-stop-check.sh 阻止消息输出到 stderr（`>&2`），hook 系统通过 stderr 捕获输出
8. **退出码**: exit 0 = 允许，exit 2 = 阻止（exit 1 会被当作脚本错误，不会阻止操作）
