#!/bin/bash

# Aztec 节点部署脚本 - 完全基于官方资料
# 参考项目方文档和GitHub社区资料
# 保留用户脚本的菜单逻辑结构

set -euo pipefail

# 配置
AZTEC_DIR="/root/aztec"
DATA_DIR="/root/.aztec/alpha-testnet/data"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 打印函数
print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 智能加载环境变量（可选，不强制要求）
if [ -f "$AZTEC_DIR/.env" ]; then
    print_info "从配置文件加载环境变量..."
    source "$AZTEC_DIR/.env"
    print_info "环境变量加载完成"
fi

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "本脚本必须以 root 权限运行。"
        exit 1
    fi
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        local version
        version=$(docker --version | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
        print_info "Docker 已安装，版本 $version"
        return 0
    fi
    
    print_info "正在安装 Docker..."
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl start docker
    systemctl enable docker
    print_info "Docker 安装完成"
}

# 安装 Docker Compose
install_docker_compose() {
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_info "Docker Compose 已安装"
        return 0
    fi
    
    print_info "正在安装 Docker Compose..."
    apt-get update
    apt-get install -y docker-compose-plugin
    print_info "Docker Compose 安装完成"
}

# 获取用户输入
get_user_input() {
    print_step "请输入 Aztec 节点配置信息："
    echo
    
    # L1 执行客户端 RPC URL
    while true; do
        echo "L1 执行客户端（EL）RPC URL 说明："
        echo "  1. 在 https://dashboard.alchemy.com/ 获取 Sepolia 的 RPC (http://xxx)"
        echo "  2. 在 https://drpc.org/ 获取 Sepolia 的 RPC (http://xxx)"
        echo
        read -p "请输入 L1 执行客户端（EL）RPC URL： " ETHEREUM_HOSTS
        
        if [[ "$ETHEREUM_HOSTS" =~ ^https?:// ]]; then
            break
        else
            print_error "URL 格式无效，必须以 http:// 或 https:// 开头。"
        fi
    done
    
    echo
    
    # L1 共识客户端 RPC URL
    while true; do
        echo "L1 共识（CL）RPC URL 说明："
        echo "  1. 在 https://drpc.org/ 获取 Beacon Chain Sepolia 的 RPC (http://xxx)"
        echo "  2. 在 https://www.ankr.com/rpc/ 获取 Beacon Chain Sepolia 的 RPC (http://xxx)"
        echo
        read -p "请输入 L1 共识（CL）RPC URL： " L1_CONSENSUS_HOST_URLS
        
        if [[ "$L1_CONSENSUS_HOST_URLS" =~ ^https?:// ]]; then
            break
        else
            print_error "URL 格式无效，必须以 http:// 或 https:// 开头。"
        fi
    done
    
    echo
    
    # 验证者私钥
    while true; do
        echo "验证者私钥说明："
        echo "  1. 必须是 0x 开头的 64 位十六进制字符串"
        echo "  2. 该钱包需要持有 Sepolia ETH 用于支付 Gas 费用"
        echo "  3. 建议使用新创建的钱包，不要使用主网钱包"
        echo
        read -p "请输入验证者私钥（0x 开头的 64 位十六进制）： " VALIDATOR_PRIVATE_KEY
        
        if [[ "$VALIDATOR_PRIVATE_KEY" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
            break
        else
            print_error "私钥格式无效，必须是 0x 开头的 64 位十六进制。"
        fi
    done
    
    echo
    
    # COINBASE 地址
    while true; do
        echo "COINBASE 地址说明："
        echo "  1. 接收区块奖励的以太坊地址"
        echo "  2. 建议与验证者地址不同，提高安全性"
        echo "  3. 必须是 0x 开头的 40 位十六进制地址"
        echo
        read -p "请输入 COINBASE 地址： " COINBASE
        
        if [[ "$COINBASE" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
            break
        else
            print_error "地址格式无效，必须是 0x 开头的 40 位十六进制。"
        fi
    done
    
    echo
    
    # 获取公共 IP
    print_info "获取公共 IP 地址..."
    PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipv4.icanhazip.com || echo "127.0.0.1")
    print_info "检测到的公共 IP: $PUBLIC_IP"
    
    read -p "请确认公共 IP 地址是否正确 (y/n): " confirm_ip
    if [[ "$confirm_ip" != "y" && "$confirm_ip" != "Y" ]]; then
        read -p "请输入正确的公共 IP 地址: " PUBLIC_IP
    fi
    
    echo
}

# 创建配置文件 - 严格按照官方资料
create_config_files() {
    print_step "创建配置文件..."
    
    # 创建目录
    mkdir -p "$AZTEC_DIR"
    mkdir -p "$DATA_DIR"
    
    # 创建 .env 文件 - 使用官方环境变量名
    print_info "创建 .env 文件..."
    cat > "$AZTEC_DIR/.env" <<EOF
ETHEREUM_HOSTS=$ETHEREUM_HOSTS
L1_CONSENSUS_HOST_URLS=$L1_CONSENSUS_HOST_URLS
P2P_IP=$PUBLIC_IP
VALIDATOR_PRIVATE_KEY=$VALIDATOR_PRIVATE_KEY
COINBASE=$COINBASE
DATA_DIRECTORY=/data
LOG_LEVEL=info
EOF
    chmod 600 "$AZTEC_DIR/.env"
    
    # 创建 docker-compose.yml 文件 - 严格按照官方资料
    print_info "创建 docker-compose.yml 文件..."
    cat > "$AZTEC_DIR/docker-compose.yml" <<EOF
services:
  aztec-sequencer:
    container_name: aztec-sequencer
    network_mode: host
    image: aztecprotocol/aztec:latest
    restart: unless-stopped
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "3"
    environment:
      ETHEREUM_HOSTS: \${ETHEREUM_HOSTS}
      L1_CONSENSUS_HOST_URLS: \${L1_CONSENSUS_HOST_URLS}
      P2P_IP: \${P2P_IP}
      VALIDATOR_PRIVATE_KEY: \${VALIDATOR_PRIVATE_KEY}
      COINBASE: \${COINBASE}
      DATA_DIRECTORY: \${DATA_DIRECTORY}
      LOG_LEVEL: \${LOG_LEVEL}
    entrypoint: >
      sh -c "node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start 
        --network alpha-testnet 
        --node 
        --archiver 
        --sequencer 
        --l1-rpc-urls \$ETHEREUM_HOSTS 
        --l1-consensus-host-urls \$L1_CONSENSUS_HOST_URLS 
        --l1-chain-id 11155111 
        --sequencer.validatorPrivateKeys \$VALIDATOR_PRIVATE_KEY 
        --sequencer.coinbase \$COINBASE 
        --p2p.p2pIp \$P2P_IP 
        --data-directory /data"
    volumes:
      - $DATA_DIR:/data
EOF
    chmod 644 "$AZTEC_DIR/docker-compose.yml"
    
    print_info "配置文件创建完成"
}

# 防火墙配置提示
show_firewall_info() {
    print_step "防火墙配置说明..."
    
    print_info "请手动配置防火墙开放以下端口："
    print_info "  - 22/tcp   (SSH 访问)"
    print_info "  - 40400/tcp (P2P 网络)"
    print_info "  - 40400/udp (P2P 网络)"
    print_info "  - 8080/tcp  (HTTP API)"
    echo
    print_info "如果使用 ufw，可以运行以下命令："
    print_info "  ufw allow 22/tcp"
    print_info "  ufw allow 40400/tcp"
    print_info "  ufw allow 40400/udp"
    print_info "  ufw allow 8080/tcp"
    echo
    print_warning "注意：防火墙配置失败可能导致节点无法正常工作"
}

# 拉取最新镜像
pull_latest_image() {
    print_step "拉取最新 Aztec 镜像..."
    
    print_info "正在拉取 aztecprotocol/aztec:latest..."
    docker pull aztecprotocol/aztec:latest
    
    # 获取镜像信息
    local image_id
    image_id=$(docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" | grep "aztecprotocol/aztec:latest" | head -1 | awk '{print $2}')
    
    print_info "镜像拉取完成，镜像 ID: $image_id"
}

# 启动节点
start_node() {
    print_step "启动 Aztec 节点..."
    
    cd "$AZTEC_DIR"
    
    # 停止并删除旧容器（如果存在）
    print_info "清理旧容器..."
    docker stop aztec-sequencer 2>/dev/null || true
    docker rm aztec-sequencer 2>/dev/null || true
    
    # 启动新容器
    print_info "启动新容器..."
    if docker compose up -d; then
        print_info "Aztec 节点启动成功！"
        print_info "容器名称: aztec-sequencer"
        print_info "数据目录: $DATA_DIR"
        print_info "配置目录: $AZTEC_DIR"
    else
        print_error "启动失败，请检查配置和日志"
        exit 1
    fi
}

# 彻底删除节点 - 清理所有项目数据
delete_node() {
    print_step "彻底删除 Aztec 节点..."
    
    print_warning "此操作将删除以下所有内容："
    print_warning "  - Docker 容器"
    print_warning "  - 配置文件"
    print_warning "  - 数据目录"
    print_warning "  - 镜像（可选）"
    echo
    
    read -p "确认要彻底删除节点吗？此操作不可恢复！(y/N): " confirm_delete
    if [[ "$confirm_delete" != "y" && "$confirm_delete" != "Y" ]]; then
        print_info "操作已取消"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    
    echo
    print_info "开始删除节点..."
    
    # 1. 停止并删除容器
    print_info "停止并删除容器..."
    docker stop aztec-sequencer 2>/dev/null || true
    docker rm aztec-sequencer 2>/dev/null || true
    
    # 2. 删除配置文件
    print_info "删除配置文件..."
    rm -rf "$AZTEC_DIR" 2>/dev/null || true
    
    # 3. 删除数据目录
    print_info "删除数据目录..."
    rm -rf "$DATA_DIR" 2>/dev/null || true
    
    # 4. 询问是否删除镜像
    read -p "是否删除 Aztec 镜像？(y/N): " delete_image
    if [[ "$delete_image" == "y" || "$delete_image" == "Y" ]]; then
        print_info "删除 Aztec 镜像..."
        docker rmi aztecprotocol/aztec:latest 2>/dev/null || true
    fi
    
    # 5. 清理 Docker 系统
    print_info "清理 Docker 系统..."
    docker system prune -f
    
    print_info "节点删除完成！"
    print_info "已删除的内容："
    print_info "  - 配置目录: $AZTEC_DIR"
    print_info "  - 数据目录: $DATA_DIR"
    print_info "  - Docker 容器: aztec-sequencer"
    if [[ "$delete_image" == "y" || "$delete_image" == "Y" ]]; then
        print_info "  - Docker 镜像: aztecprotocol/aztec:latest"
    fi
    
    echo "按任意键返回主菜单..."
    read -n 1
}

# 升级节点容器
upgrade_node() {
    print_step "升级节点容器..."
    
    if [ ! -f "$AZTEC_DIR/docker-compose.yml" ]; then
        print_error "未找到配置文件，请先安装节点"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    
    # 检查容器是否运行
    if ! docker ps -q -f name=aztec-sequencer | grep -q .; then
        print_error "节点未运行，无法升级"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    
    print_info "开始升级流程（包含版本迁移）..."
    
    # 1. 停止并删除容器
    print_info "1/5: 停止并删除当前容器..."
    cd "$AZTEC_DIR"
    docker compose down
    
    # 2. 更新配置文件 - 版本迁移
    print_info "2/5: 更新配置文件..."
    # 修复镜像版本（修复正则表达式）
    sed -i 's|image: aztecprotocol/aztec:.*|image: aztecprotocol/aztec:2.0.2|' docker-compose.yml
    # 更新网络参数
    sed -i 's|--network alpha-testnet|--network testnet|g' docker-compose.yml
    # 修复环境变量名
    sed -i 's|VALIDATOR_PRIVATE_KEYS|VALIDATOR_PRIVATE_KEY|g' docker-compose.yml
    print_info "配置文件已更新：镜像版本2.0.2，网络testnet"
    
    # 3. 拉取最新镜像
    print_info "3/5: 拉取最新镜像..."
    docker pull aztecprotocol/aztec:2.0.2
    
    # 4. 启动新容器
    print_info "4/5: 启动新容器..."
    docker compose up -d
    
    # 5. 验证启动
    print_info "5/5: 验证启动状态..."
    sleep 5
    if docker ps -q -f name=aztec-sequencer | grep -q .; then
        print_info "✅ 升级成功！节点已重启到版本2.0.2"
        print_info "网络已迁移到testnet"
    else
        print_error "❌ 升级失败，请检查日志"
    fi
    
    echo "按任意键返回主菜单..."
    read -n 1
}

# 调整日志级别
adjust_log_level() {
    print_step "调整日志级别..."
    
    if [ ! -f "$AZTEC_DIR/.env" ]; then
        print_error "未找到配置文件，请先安装节点"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    
    echo "当前日志级别选项："
    echo "1. error   - 只显示错误信息（最少日志）"
    echo "2. warn    - 显示警告和错误"
    echo "3. info    - 显示信息、警告、错误（推荐）"
    echo "4. debug   - 显示所有信息（最多日志）"
    echo
    read -p "请选择日志级别 (1-4): " log_choice
    
    case $log_choice in
        1) LOG_LEVEL="error" ;;
        2) LOG_LEVEL="warn" ;;
        3) LOG_LEVEL="info" ;;
        4) LOG_LEVEL="debug" ;;
        *)
            print_error "无效选择"
            echo "按任意键返回主菜单..."
            read -n 1
            return
            ;;
    esac
    
    # 更新 .env 文件
    sed -i "s/LOG_LEVEL=.*/LOG_LEVEL=$LOG_LEVEL/" "$AZTEC_DIR/.env"
    
    # 更新 docker-compose.yml
    sed -i "s/LOG_LEVEL: .*/LOG_LEVEL: \${LOG_LEVEL}/" "$AZTEC_DIR/docker-compose.yml"
    
    print_info "日志级别已更新为: $LOG_LEVEL"
    
    # 询问是否重启节点
    read -p "需要重启节点使配置生效吗？(y/N): " restart_choice
    if [[ "$restart_choice" == "y" || "$restart_choice" == "Y" ]]; then
        print_info "重启节点..."
        cd "$AZTEC_DIR"
        docker compose restart
        print_info "节点已重启，新日志级别生效"
    else
        print_info "配置已保存，下次重启节点时生效"
    fi
    
    echo "按任意键返回主菜单..."
    read -n 1
}

# 主安装流程
install_and_start_node() {
    print_step "开始安装 Aztec 节点..."
    
    # 检查依赖
    install_docker
    install_docker_compose
    
    # 获取用户输入
    get_user_input
    
    # 创建配置文件
    create_config_files
    
    # 显示防火墙配置说明
    show_firewall_info
    
    # 拉取最新镜像
    pull_latest_image
    
    # 启动节点
    start_node
    
    # 完成
    echo
    print_info "安装和启动完成！"
    print_info "  - 查看日志：docker logs -f aztec-sequencer"
    print_info "  - 配置目录：$AZTEC_DIR"
    print_info "  - 数据目录：$DATA_DIR"
    echo
    print_warning "重要提醒：请确保防火墙已开放必要端口！"
    print_info "  - 22/tcp   (SSH 访问)"
    print_info "  - 40400/tcp (P2P 网络)"
    print_info "  - 40400/udp (P2P 网络)"
    print_info "  - 8080/tcp  (HTTP API)"
}

# 主菜单函数 - 保留用户脚本的逻辑结构
main_menu() {
    while true; do
        clear
        
        # 定义颜色 - 调整为更暗色系
        BORDER_COLOR="\033[38;5;24m"      # 深蓝色边框
        TITLE_COLOR="\033[1;38;5;45m"     # 亮青色标题，加粗
        SUBTITLE_COLOR="\033[38;5;87m"    # 深青色副标题
        OPTION_COLOR="\033[38;5;195m"     # 浅青色选项
        SEPARATOR_COLOR="\033[38;5;31m"   # 深青色分隔线
        HINT_COLOR="\033[38;5;120m"       # 深绿色提示
        RESET="\033[0m"
        
        # 显示美化界面
        echo -e "${BORDER_COLOR}┌─────────────────────────────────────────────────────────┐${RESET}"
        echo -e "${BORDER_COLOR}│                                                         │${RESET}"
        echo -e "${BORDER_COLOR}│              ${TITLE_COLOR}🚀 Aztec 2.0 节点部署脚本 🚀${RESET}${BORDER_COLOR}                 │${RESET}"
        echo -e "${BORDER_COLOR}│                                                         │${RESET}"
        echo -e "${BORDER_COLOR}│           ${SUBTITLE_COLOR}基于官方资料，由 aztec 与 Claude 共同设计${RESET}${BORDER_COLOR}      │${RESET}"
        echo -e "${BORDER_COLOR}│                                                         │${RESET}"
        echo -e "${BORDER_COLOR}└─────────────────────────────────────────────────────────┘${RESET}"
        echo
        echo "                    请选择要执行的操作:"
        echo
        echo -e "${OPTION_COLOR}    1. 安装并启动 Aztec 节点${RESET}"
        echo -e "${OPTION_COLOR}    2. 查看节点日志${RESET}"
        echo -e "${OPTION_COLOR}    3. 调整日志级别${RESET}"
        echo -e "${OPTION_COLOR}    4. 升级节点容器${RESET}"
        echo -e "${OPTION_COLOR}    5. 查看节点状态${RESET}"
        echo -e "${OPTION_COLOR}    6. 彻底删除节点${RESET}"
        echo -e "${OPTION_COLOR}    7. 退出${RESET}"
        echo
        echo -e "${SEPARATOR_COLOR}    ────────────────────────────────────────────────${RESET}"
        echo
        echo -e "${HINT_COLOR}    q. 退出脚本${RESET}"
        echo
        read -p "    请输入选项 [1-7, q]: " choice

        case $choice in
            1)
                install_and_start_node
                echo "按任意键返回主菜单..."
                read -n 1
                ;;
            2)
                if [ -f "$AZTEC_DIR/docker-compose.yml" ]; then
                    print_info "查看节点日志..."
                    print_info "显示最后100条日志并实时跟随..."
                    echo "按 Ctrl+C 退出日志查看"
                    echo "─────────────────────────────────────────"
                    docker logs --tail 100 -f aztec-sequencer
                else
                    print_info "错误：未找到 $AZTEC_DIR/docker-compose.yml 文件，请先安装并启动节点。"
                fi
                echo "按任意键返回主菜单..."
                read -n 1
                ;;
            3)
                adjust_log_level
                ;;
            4)
                upgrade_node
                ;;
            5)
                check_node_status
                ;;
            6)
                delete_node
                ;;
            7|q|Q)
                print_info "感谢使用，再见！"
                exit 0
                ;;
            *)
                print_info "无效选项，请输入 1-7 或 q。"
                echo "按任意键返回主菜单..."
                read -n 1
                ;;
        esac
    done
}

# 查看节点状态
check_node_status() {
    print_step "查看节点状态..."
    
    echo "=== 节点健康检查 ==="
    
    # 1. 容器状态
    if docker ps | grep -q aztec-sequencer; then
        echo "1. 容器状态: ✅ 运行中"
    else
        echo "1. 容器状态: ❌ 已停止"
        echo "按任意键返回主菜单..."
        read -n 1
        return
    fi
    

    
    # 3. 同步状态
    local current_block
    local latest_block
    
    current_block=$(curl -s -X POST -d '{"method": "node_getL2Tips"}' http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")
    latest_block=$(curl -s -X POST -d '{"method": "node_getL2Tips"}' http://localhost:8080 | jq -r ".result.latest.number" 2>/dev/null || echo "")
    
    if [ -n "$current_block" ] && [ "$current_block" != "null" ]; then
        if [ -n "$latest_block" ] && [ "$latest_block" != "null" ]; then
            local diff=$((latest_block - current_block))
            if [ $diff -le 5 ]; then
                echo "3. 同步状态: ✅ 已同步 (当前: $current_block, 最新: $latest_block)"
            elif [ $diff -le 20 ]; then
                echo "3. 同步状态: ⚠️  基本同步 (当前: $current_block, 最新: $latest_block, 差异: $diff)"
            else
                echo "3. 同步状态: 🚀 同步中 (当前: $current_block, 最新: $latest_block, 差异: $diff)"
            fi
        else
            echo "2. 同步状态: ✅ 已同步 (区块: $current_block)"
        fi
    else
        echo "2. 同步状态: ❌ 异常"
    fi
    
    # 3. P2P网络连接数
    local peer_count
    
    # 从日志中提取最新的peer数量
    peer_count=$(docker logs aztec-sequencer 2>&1 | grep "Connected to.*peers" | tail -1 | sed 's/.*Connected to \([0-9]*\) peers.*/\1/' || echo "0")
    
    echo "3. P2P连接数: 🔗 $peer_count"
    
    # 4. P2P服务状态
    local port_check=false
    local node_process_check=false
    
    # 检查端口是否被监听
    if nc -z localhost 40400 2>/dev/null; then
        port_check=true
    fi
    
    # 检查端口是否被node进程占用
    if ss -tlnp | grep ":40400" | grep -q "node"; then
        node_process_check=true
    fi
    
    if [ "$port_check" = true ] && [ "$node_process_check" = true ]; then
            echo "4. P2P服务: ✅ 正常 (Aztec序列器)"
elif [ "$port_check" = true ]; then
    echo "4. P2P服务: ⚠️  端口被占用 (非Aztec服务)"
else
    echo "4. P2P服务: ❌ 异常"
fi

# 5. 节点ID
local node_id
node_id=$(docker logs aztec-sequencer 2>&1 | grep -i "peerId" | grep -o '"peerId":"[^"]*"' | cut -d'"' -f4 | head -n 1 || echo "未知")

echo "5. 节点ID: 🆔 $node_id"

echo "=================="
echo "按任意键返回主菜单..."
read -n 1
}

# 执行主菜单
main_menu
