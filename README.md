适合序列器节点迁移，默认拉取最新版本，当前为2.0.3，经过我观察旧同步数据好像暂时没用了，这一点在选项升级中可自行抉择


<img width="440" height="354" alt="image" src="https://github.com/user-attachments/assets/efcf237c-89e5-4fbe-a3ed-53a3d44fa44d" />


主菜单 (main_menu)
├── 1. 安装并启动 Aztec 节点
│   ├── 检查 root 权限
│   ├── 安装 Docker
│   ├── 安装 Docker Compose
│   ├── 获取用户输入
│   │   ├── L1 执行客户端 RPC URL
│   │   ├── L1 共识客户端 RPC URL
│   │   ├── 验证者私钥
│   │   ├── COINBASE 地址
│   │   └── 公共 IP 地址
│   ├── 创建配置文件
│   │   ├── 创建 .env 文件
│   │   └── 创建 docker-compose.yml 文件
│   ├── 显示防火墙配置说明
│   ├── 拉取最新镜像
│   └── 启动节点
│
├── 2. 查看节点日志
│   └── 显示最后100条日志并实时跟随
│
├── 3. 调整日志级别
│   ├── 选择日志级别 (error/warn/info/debug)
│   ├── 更新 .env 文件
│   ├── 更新 docker-compose.yml
│   └── 可选重启节点
│
├── 4. 升级节点容器
│   ├── 检查配置文件存在
│   ├── 检查容器运行状态
│   ├── 停止并删除当前容器
│   ├── 选择数据保留策略
│   │   ├── 保留同步数据（推荐）
│   │   └── 清空同步数据（重新同步）
│   ├── 删除旧镜像
│   ├── 更新配置文件（版本迁移）
│   ├── 拉取最新镜像
│   ├── 启动新容器
│   └── 验证启动状态
│
├── 5. 查看节点状态
│   ├── 容器状态检查
│   ├── 同步状态检查
│   │   ├── 当前区块高度
│   │   └── 最新区块高度
│   ├── P2P 网络连接数
│   ├── P2P 服务状态
│   └── 节点 ID 显示
│
├── 6. 彻底删除节点
│   ├── 确认删除操作
│   ├── 停止并删除容器
│   ├── 删除配置文件
│   ├── 删除数据目录
│   ├── 可选删除镜像
│   └── 清理 Docker 系统
│
└── 7. 退出
    └── 退出脚本

    
wget -O aztec2.0.sh https://raw.githubusercontent.com/acxcr/aztec2.0/refs/heads/main/aztec2.0.sh && sed -i 's/\r$//' aztec2.0.sh && chmod +x aztec2.0.sh && ./aztec2.0.sh  
