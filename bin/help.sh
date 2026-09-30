#!/usr/bin/env bash
# ============================================================
# 萌芽平台 (mengya-local) - 命令行帮助文档与使用指南模块
# ============================================================

show_cli_help() {
        echo ""
        echo "萌芽（mengya-local）本地模式管理命令："
        echo "  ./run.sh start [选项]        启动本地一体化服务（前端合并至Django，零Node常驻）"
        echo "  ./run.sh stop                停止本地一体化服务"
        echo "  ./run.sh restart [选项]      重启本地一体化服务（前端合并至Django，零Node常驻）"
        echo "  ./run.sh status              查看运行状态与端口占用"
        echo "  ./run.sh add_nginx [选项]    生成基于 SNI 443 端口的 Nginx SSL 反向代理配置"
        echo "  ./run.sh init_data [选项]    检查并补齐全量样例数据（食谱/胎教/百科/周历/清单/商品/品牌）"
        echo "  ./run.sh reconfig            交互式重新配置数据库存储方式（并自动更新 .env）"
        echo "  ./run.sh help                查看帮助"
        echo ""
        echo "常用自定义选项（支持在 start / restart / add_nginx 时追加，自动持久化至 .env）："
        echo "  -p, --port <PORT>            自定义前端内部访问端口（默认 5173）"
        echo "  -u, --admin <USER>           自定义超级管理员账号/手机号（默认 admin）"
        echo "  -P, --password <PASS>        自定义超级管理员登录密码（默认 admin123）"
        echo "  -n, --nickname <NAME>        自定义管理员昵称（默认 管理员）"
        echo "  -d, --domain <DOMAIN>        自定义绑定的 SNI 域名（默认 mengya.local localhost）"
        echo "  -m, --mode <MODE>            显式指定数据库模式 (sqlite | shared | dedicated)"
        echo "  --reconfig, --reconfig-db    重新唤起数据库决策向导，交互式切换数据库存储模式
  --db-user <USER>             自定义 PostgreSQL 用户名（默认 mengya_local）
  --db-pass <PASS>             自定义 PostgreSQL 密码（默认 mengya123）
  --db-name <DB>               自定义 PostgreSQL 数据库名/实例名（默认 mengya_local）
  --db-port <PORT>             自定义 PostgreSQL 连接端口（默认 5432/5433）
  --db-host <HOST>             自定义 PostgreSQL 主机地址（默认 127.0.0.1）
  --database-url <URL>         直接指定完整 DATABASE_URL 连接串"
        echo "  --shared-pg <CONTAINER>      指定共享模式下的宿主机 PostgreSQL 容器名称"
        echo "  -y, --yes                    非交互式模式，免去任何等待（Cron / 重启自动采用推荐值）"
        echo ""
        echo "实用启动示例："
        echo "  ./run.sh start                                 # 默认启动（端口 5173，管理员 admin / admin123）"
        echo "  ./run.sh start -p 5175                         # 自定义以 5175 端口启动"
        echo "  ./run.sh --reconfig                            # 直接唤醒交互式数据库模式选择向导
  ./run.sh start --reconfig                      # 重新选择数据库模式（SQLite / 共享PG / 独立PG）
  ./run.sh start --db-user myuser --db-pass mypass # 自定义数据库连接账号与密码启动"
        echo "  ./run.sh start -m sqlite                       # 直接以 SQLite 本地单文件模式启动并保存至 .env"
        echo "  ./run.sh start -m shared                       # 直接以共享宿主机已有 PG 模式启动并保存至 .env"
        echo "  ./run.sh start -p 5173 -u superadmin -P Pass123 # 自定义端口与管理员账密启动"
        echo "  ./run.sh restart -p 5175                       # 重启并变更为 5175 端口"
        echo "  ./run.sh add_nginx -d mengya.myhost.com        # 为指定域名生成独立反代配置"
        echo ""
        show_db_reconfig_guide
}
