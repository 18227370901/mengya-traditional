#!/usr/bin/env bash
# ============================================================
# 萌芽（mengya）平台 - 本地传统模式管理脚本 (mengya-local)
#
# 架构模型：
#   - 外部访问：直连 FRONTEND_PORT（默认 5173），或通过 Nginx 统一反代（HTTPS SNI 443 唯一安全入口）
#   - 服务模型：Django 单体一体化服务，监听 0.0.0.0:$FRONTEND_PORT（统一托管前端 SPA 页面、静态资源与后端 API）
#   - 前端架构：前端生产静态产物已合并入 Django (templates/ & static/)，彻底移除 Node.js 常驻运行时，解决内存高占用
#   - 数据库：本地 SQLite (db.sqlite3)，轻量独立
#
# 支持命令：
#   ./run.sh start      启动本地前后端服务
#   ./run.sh stop       停止本地前后端服务
#   ./run.sh restart    重启本地前后端服务
#   ./run.sh status     查看运行状态与端口占用
#   ./run.sh add_nginx  生成基于 SNI 443 端口的 Nginx SSL 反代配置及证书
#   ./run.sh help       查看帮助信息
#
# 环境变量配置项（均有默认值，可按需覆盖）：
#   PORT              外部访问端口（默认 443，等同于 EXTERNAL_PORT）
#   EXTERNAL_PORT     外部 HTTPS 访问端口（默认 443）
#   SERVER_NAME       SNI 匹配域名（默认 mengya.local localhost）
#   FRONTEND_PORT     前端内部服务端口（默认 5173，仅供内部反代）
#   FRONTEND_PORT     一体化服务访问端口（默认 5173，托管前端静态与后端 API）
#   ADMIN_USERNAME    管理员账号（默认 admin）
#   ADMIN_PASSWORD    管理员密码（默认 admin123）
#   ADMIN_NICKNAME    管理员昵称（默认 管理员）
#   NGINX_CONF_DIR    Nginx 额外配置目录（默认 /opt/service/nginx/conf.d）
#   NGINX_CERT_DIR    Nginx SSL 证书目录（默认当前项目 ssl 目录）
#   ENABLE_HTTP_REDIRECT 是否生成 80 转 443 重定向规则（1=开启，0=关闭，默认 1）
# ============================================================

set -e

export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
# 若当前通过 sh / dash 启动，且系统存在 bash，自动无缝重入为 bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
fi

SCRIPT_SOURCE="${BASH_SOURCE:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE" 2>/dev/null || echo ".")" && pwd)"
cd "$SCRIPT_DIR"

# 1. 自动环境自愈检查：若 .env 不存在，优先从 .env.example 复制初始化
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo -e "\033[1;33m[提示] 未找到 .env 配置文件，自动从 .env.example 复制初始化...\033[0m"
        cp ".env.example" ".env"
    else
        touch ".env"
    fi
fi

if [ -f ".env" ]; then
    # 自动修复 .env 中带空格但未加引号的值（避免 bash source .env 时报 command not found）
    sed -i.bak -E 's/^([A-Za-z0-9_]+)=([^"#][^#]*[[:space:]][^#]*)$/\1="\2"/' ".env" 2>/dev/null && rm -f ".env.bak"
    set -a
    # shellcheck disable=SC1091
    . ./.env 2>/dev/null || true
    set +a
fi


# 2. 依次动态载入 bin/ 目录下所有模块
for mod in env config python process db nginx data help; do
    mod_file="$SCRIPT_DIR/bin/${mod}.sh"
    if [ -f "$mod_file" ]; then
        # shellcheck disable=SC1090
        . "$mod_file"
    else
        echo -e "\033[1;31m[错误] 缺失核心组件: bin/${mod}.sh，请检查项目完整性！\033[0m" >&2
        exit 1
    fi
done

# 3. 初始化默认变量、解析命令行参数、持久化自定义配置与导出环境变量
init_default_configs
parse_cli_args "$@"
apply_and_save_configs
export_runtime_vars

# 4. 命令调度分发
case "$CMD" in
    start)
        start_service
        ;;
    stop)
        stop_all
        ;;
    restart)
        restart_service
        ;;
    status)
        show_status
        ;;
    add_nginx)
        gen_ssl_cert
        gen_nginx_config
        ;;
    init_data|seed)
        # shellcheck disable=SC2086
        init_data_local $EXTRA_ARGS
        ;;
    reconfig|reconfig_db)
        RECONFIG_DB=1
        setup_db_for_mode
        echo -e "\033[0;32m[完成] 数据库模式已重新配置并保存至 .env (当前模式: $DB_MODE)\033[0m"
        ;;
    help)
        show_cli_help
        ;;
    *)
        echo "未知命令: $CMD"
        echo "支持的子命令: start | stop | restart | status | add_nginx | init_data | help"
        exit 1
        ;;
esac
