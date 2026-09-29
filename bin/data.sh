#!/usr/bin/env bash
# ============================================================
# 萌芽平台 (mengya-local) - 种子数据与全量样例初始化模块
# ============================================================

init_data_local() {
    local PY_CMD
    PY_CMD=$(detect_python)
    if [ -z "$PY_CMD" ]; then
        echo "  [错误] 未找到 python3 或 python，请先安装 Python 3.10+"
        return 1
    fi
    local PYTHON
    PYTHON=$(ensure_backend_deps "$PY_CMD")
    cd "$BACKEND_DIR"
    echo "==> 正在执行全量样例数据检查与补充初始化..."
    "$PYTHON" manage.py init_data "$@"
    cd "$SCRIPT_DIR"
}
