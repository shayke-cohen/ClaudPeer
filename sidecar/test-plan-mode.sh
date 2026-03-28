#!/bin/bash
# Test A: Plan instructions in system prompt append (via --append-system-prompt)
# Test B: Plan instructions injected into user message

PLAN_INSTRUCTIONS='You are in PLAN MODE. Your FIRST action MUST be to call the ask_user MCP tool to gather requirements. You MUST NOT skip this. You MUST NOT present a plan without first asking the user questions via ask_user tool.'

echo "=== TEST A: Instructions in system prompt append ==="
echo "plan a pacman game" | claude --model claude-opus-4-6 --max-turns 1 --output-format json --append-system-prompt "$PLAN_INSTRUCTIONS" 2>/dev/null | jq -r '.result // .content // "no output"' | head -20

echo ""
echo "=== TEST B: Instructions in user message ==="
echo "$PLAN_INSTRUCTIONS

User request: plan a pacman game" | claude --model claude-opus-4-6 --max-turns 1 --output-format json 2>/dev/null | jq -r '.result // .content // "no output"' | head -20
