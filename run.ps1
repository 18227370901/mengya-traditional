# ============================================================
# 萌芽（mengya）平台 - Windows 本地服务管理脚本 (mengya-local)
#
# 支持命令：
#   .\run.ps1 start      启动本地前后端服务
#   .\run.ps1 stop       停止本地前后端服务
#   .\run.ps1 restart    重启本地前后端服务
#   .\run.ps1 status     查看运行状态与端口占用
#   .\run.ps1 help       查看帮助
# ============================================================

param (
    [Parameter(Position = 0)]
    [string]$Command = 'help'
)

$SCRIPT_DIR = $PSScriptRoot
if (-not $SCRIPT_DIR) { $SCRIPT_DIR = (Get-Location).Path }

$BACKEND_PORT = if ($env:BACKEND_PORT) { [int]$env:BACKEND_PORT } else { 8000 }
$FRONTEND_PORT = if ($env:FRONTEND_PORT) { [int]$env:FRONTEND_PORT } else { 5173 }
$ADMIN_USERNAME = if ($env:ADMIN_USERNAME) { $env:ADMIN_USERNAME } else { 'admin' }
$ADMIN_PASSWORD = if ($env:ADMIN_PASSWORD) { $env:ADMIN_PASSWORD } else { 'admin123' }
$ADMIN_NICKNAME = if ($env:ADMIN_NICKNAME) { $env:ADMIN_NICKNAME } else { '管理员' }

$LOG_DIR = Join-Path $SCRIPT_DIR 'logs'
if (-not (Test-Path -LiteralPath $LOG_DIR)) {
    New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
}

$BACKEND_PID_FILE = Join-Path $LOG_DIR 'backend.pid'
$FRONTEND_PID_FILE = Join-Path $LOG_DIR 'frontend.pid'

function Test-PortInUse([int]$Port) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $success = $iar.AsyncWaitHandle.WaitOne(800, $false)
        if ($success -and $client.Connected) {
            $client.EndConnect($iar)
            $client.Close()
            return $true
        }
        $client.Close()
    } catch {}
    return $false
}

function Get-PortPids([int]$Port) {
    $pids = @()
    try {
        $lines = netstat -ano | Select-String ":$Port\s+.*LISTENING"
        foreach ($line in $lines) {
            if ($line.Line -match '\s+(\d+)$') {
                $foundPid = [int]$matches[1]
                if ($foundPid -gt 0 -and $pids -notcontains $foundPid) {
                    $pids += $foundPid
                }
            }
        }
    } catch {}
    return $pids
}

function Stop-ByPidFile([string]$PidFile, [string]$ServiceName, [int]$Port) {
    $stopped = $false

    # 1. 停止记录在 PID 文件的进程
    if (Test-Path -LiteralPath $PidFile) {
        $pidText = (Get-Content -LiteralPath $PidFile -ErrorAction SilentlyContinue | Out-String).Trim()
        if ($pidText -match '^[0-9]+$') {
            $targetPid = [int]$pidText
            try {
                $proc = Get-Process -Id $targetPid -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Host ('  ==> 停止 ' + $ServiceName + ' (PID: ' + $targetPid + ')') -ForegroundColor Yellow
                    Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
                    $stopped = $true
                }
            } catch {}
        }
        Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    }

    # 2. 清理占用该端口的所有进程
    $portPids = Get-PortPids -Port $Port
    foreach ($p in $portPids) {
        Write-Host ('  ==> 释放占用端口 ' + $Port + ' 的进程 (PID: ' + $p + ')') -ForegroundColor Yellow
        Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
        $stopped = $true
    }

    # 3. 循环等待端口释放（最多 5 秒）
    $waited = 0
    while ((Test-PortInUse -Port $Port) -and $waited -lt 10) {
        Start-Sleep -Milliseconds 500
        $waited++
    }

    if ($stopped) {
        Write-Host ('  ' + $ServiceName + ' 已停止') -ForegroundColor Green
    } else {
        Write-Host ('  ' + $ServiceName + ' 未在运行') -ForegroundColor Gray
    }
}

function Start-BackendService {
    Write-Host ('==> 启动后端服务（端口 ' + $BACKEND_PORT + '，本地模式）') -ForegroundColor Cyan

    # 若端口仍被占用，主动释放
    if (Test-PortInUse -Port $BACKEND_PORT) {
        Write-Host ('  [清理] 端口 ' + $BACKEND_PORT + ' 已被占用，正在释放占用进程...') -ForegroundColor Yellow
        $portPids = Get-PortPids -Port $BACKEND_PORT
        foreach ($p in $portPids) {
            Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 800
    }

    $venvPy = Join-Path $SCRIPT_DIR '.venv\Scripts\python.exe'
    $pyCmd = if (Test-Path -LiteralPath $venvPy) { $venvPy } else { 'python' }

    Push-Location $SCRIPT_DIR
    try {
        Write-Host '  执行数据迁移...'
        & $pyCmd manage.py migrate --noinput | Out-Null
        Write-Host '  初始化种子数据...'
        & $pyCmd manage.py init_data --skip-if-exists | Out-Null
        & $pyCmd manage.py init_fetal_stories --skip-if-exists | Out-Null

        Write-Host ('  同步单一管理员账号 (' + $ADMIN_USERNAME + ')...')
        $env:ADMIN_USERNAME = $ADMIN_USERNAME
        $env:ADMIN_PASSWORD = $ADMIN_PASSWORD
        $env:ADMIN_NICKNAME = $ADMIN_NICKNAME

        $venvCa = Join-Path $SCRIPT_DIR '.venv\Lib\site-packages\certifi\cacert.pem'
        if (Test-Path -LiteralPath $venvCa) {
            $env:SSL_CERT_FILE = $venvCa
            $env:REQUESTS_CA_BUNDLE = $venvCa
            $env:CURL_CA_BUNDLE = $venvCa
        }
        & $pyCmd manage.py ensure_admin | Out-Null

        $stdoutLog = Join-Path $LOG_DIR 'backend.log'
        $stderrLog = Join-Path $LOG_DIR 'backend.err.log'

        $bp = Start-Process -FilePath $pyCmd `
            -ArgumentList 'manage.py', 'runserver', ('127.0.0.1:' + $BACKEND_PORT), '--noreload' `
            -WorkingDirectory $SCRIPT_DIR `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -WindowStyle Hidden `
            -PassThru

        $bp.Id | Out-File -FilePath $BACKEND_PID_FILE -Encoding ascii
        Write-Host ('  后端启动中 (PID: ' + $bp.Id + ')...') -ForegroundColor Green

        # 健康探针：循环等待端口 8000 成功监听
        $ready = $false
        for ($i = 0; $i -lt 15; $i++) {
            if (Test-PortInUse -Port $BACKEND_PORT) {
                $ready = $true
                break
            }
            $proc = Get-Process -Id $bp.Id -ErrorAction SilentlyContinue
            if ($null -eq $proc) {
                Write-Host '  [错误] 后端进程异常退出，错误日志：' -ForegroundColor Red
                Get-Content $stderrLog -Tail 15 -ErrorAction SilentlyContinue
                break
            }
            Start-Sleep -Milliseconds 500
        }

        if ($ready) {
            Write-Host ('  后端已就绪 (端口 ' + $BACKEND_PORT + ')') -ForegroundColor Green
        } else {
            Write-Host ('  [警告] 后端尚未监听端口 ' + $BACKEND_PORT + '，请检查日志') -ForegroundColor Yellow
        }
    } finally {
        Pop-Location
    }
}

function Start-FrontendService {
    Write-Host ('==> 启动前端服务（端口 ' + $FRONTEND_PORT + '，本地模式）') -ForegroundColor Cyan

    if (Test-PortInUse -Port $FRONTEND_PORT) {
        Write-Host ('  [清理] 端口 ' + $FRONTEND_PORT + ' 已被占用，正在释放占用进程...') -ForegroundColor Yellow
        $portPids = Get-PortPids -Port $FRONTEND_PORT
        foreach ($p in $portPids) {
            Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 800
    }

    $frontendDir = Join-Path $SCRIPT_DIR 'frontend'
    $stdoutLog = Join-Path $LOG_DIR 'frontend.log'
    $stderrLog = Join-Path $LOG_DIR 'frontend.err.log'

    $fp = Start-Process -FilePath 'node.exe' `
        -ArgumentList 'start_vite.mjs' `
        -WorkingDirectory $frontendDir `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -WindowStyle Hidden `
        -PassThru

    $fp.Id | Out-File -FilePath $FRONTEND_PID_FILE -Encoding ascii
    Write-Host ('  前端启动中 (PID: ' + $fp.Id + ')...') -ForegroundColor Green

    # 健康探针：等待前端端口 5173 监听
    $ready = $false
    for ($i = 0; $i -lt 15; $i++) {
        if (Test-PortInUse -Port $FRONTEND_PORT) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }

    if ($ready) {
        Write-Host ('  前端已就绪 (端口 ' + $FRONTEND_PORT + ')') -ForegroundColor Green
    } else {
        Write-Host ('  [警告] 前端尚未监听端口 ' + $FRONTEND_PORT) -ForegroundColor Yellow
    }
}

function Show-Status {
    Write-Host '============================================' -ForegroundColor Cyan
    Write-Host '  萌芽（mengya-local）本地运行状态' -ForegroundColor Cyan
    Write-Host '============================================' -ForegroundColor Cyan

    $bInUse = Test-PortInUse -Port $BACKEND_PORT
    $fInUse = Test-PortInUse -Port $FRONTEND_PORT

    $bPid = if (Test-Path -LiteralPath $BACKEND_PID_FILE) { (Get-Content $BACKEND_PID_FILE).Trim() } else { '' }
    $fPid = if (Test-Path -LiteralPath $FRONTEND_PID_FILE) { (Get-Content $FRONTEND_PID_FILE).Trim() } else { '' }

    $bStatus = if ($bInUse) { ('运行中 (PID: ' + $bPid + ', 端口 ' + $BACKEND_PORT + ')') } else { '未运行' }
    $fStatus = if ($fInUse) { ('运行中 (PID: ' + $fPid + ', 端口 ' + $FRONTEND_PORT + ')') } else { '未运行' }

    Write-Host ('  后端 Django : ' + $bStatus)
    Write-Host ('  前端 Vite   : ' + $fStatus)
    Write-Host ('  单入口设计 : 前端 http://localhost:' + $FRONTEND_PORT + ' 直达，后端回环 127.0.0.1:' + $BACKEND_PORT + ' 保护中')
    Write-Host ('  日志目录   : ' + $LOG_DIR)
    Write-Host '============================================' -ForegroundColor Cyan
}

switch ($Command.ToLower()) {
    'start' {
        Start-BackendService
        Start-FrontendService
        Start-Sleep -Seconds 1
        Write-Host ''
        Write-Host '============================================' -ForegroundColor Green
        Write-Host '  萌芽（mengya-local）启动完成！' -ForegroundColor Green
        Write-Host ('  访问地址: http://localhost:' + $FRONTEND_PORT + '/') -ForegroundColor Yellow
        Write-Host ('  管理员账号: ' + $ADMIN_USERNAME + ' / ' + $ADMIN_PASSWORD) -ForegroundColor Yellow
        Write-Host '  单入口说明: 后端已绑定 127.0.0.1 回环保护，全部流量走前端 5173 代理'
        Write-Host '============================================' -ForegroundColor Green
    }
    'stop' {
        Write-Host '==> 停止本地服务' -ForegroundColor Yellow
        Stop-ByPidFile -PidFile $BACKEND_PID_FILE -ServiceName '后端 Django' -Port $BACKEND_PORT
        Stop-ByPidFile -PidFile $FRONTEND_PID_FILE -ServiceName '前端 Vite' -Port $FRONTEND_PORT
        Write-Host '  本地服务停止操作完成' -ForegroundColor Green
    }
    'restart' {
        $scriptPath = Join-Path $SCRIPT_DIR 'run.ps1'
        & $scriptPath stop
        Start-Sleep -Seconds 1
        & $scriptPath start
    }
    'status' {
        Show-Status
    }
    default {
        Write-Host ''
        Write-Host '萌芽（mengya-local）本地模式管理命令：' -ForegroundColor Cyan
        Write-Host '  .\run.ps1 start      启动前后端本地服务'
        Write-Host '  .\run.ps1 stop       停止本地前后端服务'
        Write-Host '  .\run.ps1 restart    重启本地前后端服务'
        Write-Host '  .\run.ps1 status     查看运行状态'
        Write-Host '  .\run.ps1 help       查看帮助'
        Write-Host ''
    }
}
