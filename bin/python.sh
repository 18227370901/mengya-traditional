#!/usr/bin/env bash
# ============================================================
# 萌芽平台 (mengya-local) - Python 运行时探测与虚拟环境依赖校验模块
# ============================================================

detect_python() {
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
    elif command -v python >/dev/null 2>&1; then
        echo "python"
    else
        echo ""
    fi
}

ensure_backend_deps() {
    local SYS_PY="$1"
    local VENV_DIR="$BACKEND_DIR/.venv"
    local VENV_PY="$VENV_DIR/bin/python"

    if [ ! -f "$VENV_PY" ] && [ -f "$VENV_DIR/Scripts/python.exe" ]; then
        VENV_PY="$VENV_DIR/Scripts/python.exe"
    fi

    if [ ! -f "$VENV_PY" ]; then
        echo "  [环境] 未检测到后端虚拟环境，正在创建 ($VENV_DIR)..." >&2
        "$SYS_PY" -m venv "$VENV_DIR" >&2
        if [ ! -f "$VENV_PY" ] && [ -f "$VENV_DIR/Scripts/python.exe" ]; then
            VENV_PY="$VENV_DIR/Scripts/python.exe"
        fi
    fi

    local need_install=0
    local HASH_FILE="$VENV_DIR/.req_hash"
    local REQ_FILE="$BACKEND_DIR/requirements.txt"
    local CURR_HASH=""

    if command -v md5sum >/dev/null 2>&1; then
        CURR_HASH=$(md5sum "$REQ_FILE" 2>/dev/null | cut -d" " -f1)
    elif command -v md5 >/dev/null 2>&1; then
        CURR_HASH=$(md5 -q "$REQ_FILE" 2>/dev/null)
    fi

    if [ ! -f "$HASH_FILE" ] || [ "$CURR_HASH" != "$(cat "$HASH_FILE" 2>/dev/null)" ]; then
        need_install=1
    fi

    if [ "$need_install" = "1" ]; then
        echo "  [依赖] 正在同步后端依赖 (pip install -r requirements.txt)..." >&2
        (cd "$BACKEND_DIR" && "$VENV_PY" -m pip install -r requirements.txt >&2)
        [ -n "$CURR_HASH" ] && echo "$CURR_HASH" > "$HASH_FILE"
    fi

    echo "$VENV_PY"
}

ensure_frontend_deps() {
    return 0
}

start_frontend() {
    # 前端静态产物已合并至 Django (templates/ & static/)
    # 彻底消除 Node.js / Vite 进程常驻与高内存占用
    return 0
}
