#!/usr/bin/env bash
#
# ask-external-agent.sh - Delegate a read-only question to an external CLI agent.
#
# Claude Code calls this through the Bash tool so that Codex, Gemini, and Qwen
# are reachable behind one allowlisted path with a consistent contract:
# read-only, time-boxed, and loud on failure.
#
# Usage:
#   ./ask-external-agent.sh <codex|gemini|qwen> "<prompt>"
#
# Environment:
#   AGENT_TIMEOUT   Seconds before the call is aborted (default: 120)
#   CODEX_MODEL     Override the Codex model
#   GEMINI_MODEL    Override the Gemini model
#   QWEN_MODEL      Override the Qwen model
#
# Exit codes:
#   0   Agent answered
#   1   Bad usage
#   2   Requested CLI is not installed
#   124 Timed out (from `timeout`)
#   *   Whatever the underlying CLI returned

set -euo pipefail

AGENT_TIMEOUT="${AGENT_TIMEOUT:-120}"

usage() {
    echo "Usage: $0 <codex|gemini|qwen> \"<prompt>\"" >&2
    echo >&2
    echo "Sends a read-only question to an external CLI agent and prints the answer." >&2
}

if [ "$#" -ne 2 ]; then
    usage
    exit 1
fi

agent="$1"
prompt="$2"

if [ -z "${prompt// /}" ]; then
    echo "Error: prompt is empty." >&2
    exit 1
fi

require_cli() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: '$1' is not installed or not on PATH." >&2
        echo "Install it, authenticate it, and verify it standalone before" >&2
        echo "delegating to it from Claude Code." >&2
        exit 2
    fi
}

# Appended to every prompt. The sandbox flags below are the real enforcement;
# this is belt-and-braces against an agent that talks itself into editing.
readonly GUARD="

Constraints: This is a read-only review request. Do not modify, create, or
delete any files. Do not run commands that change state. Answer concisely."

case "$agent" in
    codex)
        require_cli codex
        set -- codex exec --sandbox read-only
        [ -n "${CODEX_MODEL:-}" ] && set -- "$@" --model "$CODEX_MODEL"
        exec timeout "$AGENT_TIMEOUT" "$@" "${prompt}${GUARD}"
        ;;

    gemini)
        require_cli gemini
        set -- gemini --approval-mode default
        [ -n "${GEMINI_MODEL:-}" ] && set -- "$@" --model "$GEMINI_MODEL"
        exec timeout "$AGENT_TIMEOUT" "$@" -p "${prompt}${GUARD}"
        ;;

    qwen)
        require_cli qwen
        set -- qwen --approval-mode default
        [ -n "${QWEN_MODEL:-}" ] && set -- "$@" --model "$QWEN_MODEL"
        exec timeout "$AGENT_TIMEOUT" "$@" -p "${prompt}${GUARD}"
        ;;

    *)
        echo "Error: unknown agent '$agent'." >&2
        usage
        exit 1
        ;;
esac
