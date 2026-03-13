#!/bin/bash
# test-basic-flow.sh - 测试 LockStep 工作流的基本功能
#
# 测试流程:
# 1. 检查文件结构
# 2. 检查协议定义
# 3. 模拟并行开发流程
#

echo "═══════════════════════════════════════════════════════════════════════"
echo "LockStep 工作流基本功能测试"
echo "═══════════════════════════════════════════════════════════════════════"

# 检查文件结构
echo ""
echo "1. 检查文件结构..."
ls -la /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/ 2>/dev/null | head -20

echo ""
echo "2. 检查协议定义..."
if [ -f /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/PROTOCOL.md ]; then
    echo "   ✅ PROTOCOL.md 存在"
    head -30 /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/PROTOCOL.md
else
    echo "   ❌ PROTOCOL.md 不不存在"
fi

echo ""
echo "3. 检查 skills 目录..."
if [ -d /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/skills ]; then
    echo "   Skills 文件:"
    ls /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/skills/
else
    echo "   ❌ skills 目录不存在"
fi
echo ""
echo "4. 检查 agents 目录..."
if [ -d /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/agents ]; then
    echo "   Agents 文件:"
    ls /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/agents/
else
    echo "   ❌ agents 目录不存在"
fi
echo ""
echo "5. 检查 workflows 目录..."
if [ -d /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/workflows ]; then
    echo "   Workflows 文件:"
    ls /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/workflows/
else
    echo "   ❌ workflows 目录不存在"
fi
echo ""
echo "6. 检查 scripts 目录..."
if [ -d /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/scripts ]; then
    echo "   Scripts 文件:"
    ls /Users/ryan/mycode/OA_Tool/feature-workflow-LockStep/scripts/
else
    echo "   ❌ scripts 目录不存在"
fi
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "✅ 基本结构测试完成"
echo "═══════════════════════════════════════════════════════════════════════"
