#!/bin/bash
# state-utils.sh — Workflow State 状态文件操作工具函数
# 所有对 workflow-state.json 的操作应通过这些函数完成
#
# 状态文件位置：~/.claude/projects/-{project-path}/workflow-state.json
# 不被 git 跟踪，所有 worktree 共享同一个物理文件

# 获取状态文件路径
state_file() {
    local project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
    local encoded
    encoded=$(echo "$project_dir" | sed 's|/|-|g')
    echo "$HOME/.claude/projects/${encoded}/workflow-state.json"
}

# 确保状态文件目录存在
state_ensure_dir() {
    mkdir -p "$(dirname "$(state_file)")"
}

# 初始化状态文件（dev-agent 启动时调用）
# 用法: state_init
state_init() {
    local sf
    sf=$(state_file)
    state_ensure_dir
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%S")
    python3 -c "
import json, os
sf = '$sf'
state = {
    'version': 1,
    'loop': {
        'active': True,
        'status': 'dispatching',
        'started_at': '$ts',
        'iteration': 1
    },
    'agents': {},
    'locks': {}
}
with open(sf + '.tmp', 'w') as f:
    json.dump(state, f, indent=2)
os.rename(sf + '.tmp', sf)
" 2>/dev/null
}

# 原子更新状态文件
# 用法: state_update "python_expression"
# python_expression 中可用变量: state
# 例: state_update "state['loop']['status'] = 'waiting_subagents'"
state_update() {
    local python_expr="$1"
    local sf
    sf=$(state_file)
    [ -f "$sf" ] || return 1
    python3 -c "
import json, os
sf = '$sf'
state = json.load(open(sf))
${python_expr}
with open(sf + '.tmp', 'w') as f:
    json.dump(state, f, indent=2)
os.rename(sf + '.tmp', sf)
" 2>/dev/null
}

# 读取状态字段
# 用法: state_read "python_expression_returning_value"
# 例: state_read "state.get('loop', {}).get('status', 'stopped')"
state_read() {
    local python_expr="$1"
    local sf
    sf=$(state_file)
    if [ ! -f "$sf" ]; then
        echo ""
        return 1
    fi
    python3 -c "
import json
state = json.load(open('$sf'))
result = ${python_expr}
print(result if result is not None else '')
" 2>/dev/null
}

# 注册 SubAgent（派发时调用）
# 用法: state_agent_register "feat-xxx" "start-feature"
state_agent_register() {
    local feature_id="$1"
    local stage="${2:-start-feature}"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%S")
    state_update "
state.setdefault('agents', {})['${feature_id}'] = {
    'status': 'running',
    'stage': '${stage}',
    'started_at': '${ts}',
    'pid': None
}
"
}

# 更新 SubAgent stage
# 用法: state_agent_stage "feat-xxx" "implement-feature"
state_agent_stage() {
    local feature_id="$1"
    local agent_stage="$2"
    state_update "
if '${feature_id}' in state.get('agents', {}):
    state['agents']['${feature_id}']['stage'] = '${agent_stage}'
"
}

# 标记 SubAgent 完成
# 用法: state_agent_complete "feat-xxx"
state_agent_complete() {
    local feature_id="$1"
    state_update "
if '${feature_id}' in state.get('agents', {}):
    state['agents']['${feature_id}']['status'] = 'completed'
"
}

# 移除 SubAgent 记录
# 用法: state_agent_remove "feat-xxx"
state_agent_remove() {
    local feature_id="$1"
    state_update "
state.get('agents', {}).pop('${feature_id}', None)
"
}

# 获取文件锁
# 用法: state_acquire_lock "queue.yaml" "feat-xxx" [max_retries]
state_acquire_lock() {
    local file="$1"
    local holder="$2"
    local max_retries="${3:-30}"
    local retries=0
    local sf
    sf=$(state_file)

    while [ $retries -lt $max_retries ]; do
        local result
        result=$(python3 -c "
import json, os
sf = '$sf'
if not os.path.exists(sf):
    print('no_state')
    exit()
state = json.load(open(sf))
locks = state.setdefault('locks', {})
current = locks.get('$file')
if current is not None and current != '$holder':
    # Check for stale lock (> 5 minutes)
    import datetime
    for aid, ainfo in state.get('agents', {}).items():
        if aid == current:
            started = ainfo.get('started_at', '')
            if started:
                try:
                    st = datetime.datetime.fromisoformat(started)
                    if (datetime.datetime.now() - st).total_seconds() > 300:
                        locks['$file'] = '$holder'
                        print('acquired')
                        with open(sf + '.tmp', 'w') as f:
                            json.dump(state, f, indent=2)
                        os.rename(sf + '.tmp', sf)
                        exit()
                except:
                    pass
    print('locked')
else:
    locks['$file'] = '$holder'
    print('acquired')
    with open(sf + '.tmp', 'w') as f:
        json.dump(state, f, indent=2)
    os.rename(sf + '.tmp', sf)
" 2>/dev/null)

        if [ "$result" = "acquired" ]; then
            return 0
        elif [ "$result" = "no_state" ]; then
            return 1
        fi

        sleep 1
        retries=$((retries + 1))
    done

    return 1  # Timeout
}

# 释放文件锁
# 用法: state_release_lock "queue.yaml"
state_release_lock() {
    local file="$1"
    state_update "
state.setdefault('locks', {})['$file'] = None
"
}

# 清理状态文件（dev-agent 循环结束时调用）
# 用法: state_cleanup
state_cleanup() {
    local sf
    sf=$(state_file)
    rm -f "$sf"
}

# 设置循环状态
# 用法: state_loop_status "waiting_subagents"
state_loop_status() {
    local loop_status="$1"
    state_update "state['loop']['status'] = '${loop_status}'"
}

# 递增迭代计数
state_loop_iteration() {
    state_update "state['loop']['iteration'] = state['loop'].get('iteration', 0) + 1"
}
