适合序列器节点迁移，默认拉取最新版本，当前为2.0.3，经过我观察旧同步数据好像暂时没用了，建议直接重新部署序列器
建议备份ID文件 p2p-private-key
启动脚本选择 安装并启动 Aztec 节点
自行把旧ID文件导入至 /root/.aztec/testnet/data#  (因为我把脚本放在了root目录)

<img width="410" height="239" alt="image" src="https://github.com/user-attachments/assets/a5a8a2ba-837f-4c0e-a324-ea624858ddde" />




    
wget -O aztec2.0.sh https://raw.githubusercontent.com/acxcr/aztec2.0/refs/heads/main/aztec2.0.sh && sed -i 's/\r$//' aztec2.0.sh && chmod +x aztec2.0.sh && ./aztec2.0.sh  
