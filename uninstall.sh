#!/bin/bash
# =================================================================
# Xingó Defense Security
# SOC Package Uninstall (Hardened)
# =================================================================

ROOT_DIR="$(pwd)"

echo -e "\e[1;31m[AVISO] Este script destruirá TODOS os dados, containers, regras de firewall e volumes do Xingó Defense.\e[0m"
read -r -p "Você tem certeza absoluta? (s/N): " confirm
if [[ ! $confirm =~ ^[Ss]$ ]]; then
    echo "Operação cancelada."
    exit 0
fi

echo -e "\n\e[1;33mParando containers...\e[0m"
[[ -d "$ROOT_DIR/wazuh-docker/single-node" ]] && sudo docker compose -f "$ROOT_DIR/wazuh-docker/single-node/docker-compose.yml" down -v
[[ -d "$ROOT_DIR/shuffle" ]] && sudo docker compose -f "$ROOT_DIR/shuffle/docker-compose.yml" down -v
[[ -d "$ROOT_DIR/iris-web" ]] && sudo docker compose -f "$ROOT_DIR/iris-web/docker-compose.yml" down -v
[[ -d "$ROOT_DIR/misp-docker" ]] && sudo docker compose -f "$ROOT_DIR/misp-docker/docker-compose.yml" down -v

echo -e "\e[1;33mRemovendo volumes e orfãos...\e[0m"
sudo docker ps -a | grep -E "wazuh|shuffle|iris|misp" | awk '{print $1}' | xargs -r sudo docker rm -f
sudo docker volume prune -f

echo -e "\e[1;33mRemovendo regras de Firewall...\e[0m"
sudo iptables -D DOCKER-USER -p tcp -m multiport --dports 443,1443,8443,3001 -j DROP 2>/dev/null
sudo netfilter-persistent save > /dev/null 2>&1

echo -e "\e[1;33mDesinstalando Wazuh Agent local...\e[0m"
if systemctl list-unit-files | grep -q "^wazuh-agent"; then
    sudo systemctl stop wazuh-agent
    sudo apt-get remove --purge -y wazuh-agent
    sudo rm -rf /var/ossec
fi

echo -e "\e[1;33mRemovendo rotina de Retenção (Cold Storage)...\e[0m"
sudo crontab -l | grep -v "/opt/xingo/xingo_retention.sh" | sudo crontab -
sudo rm -rf /opt/xingo

echo -e "\e[1;33mLimpando arquivos locais de configuração...\e[0m"
rm -f "$ROOT_DIR/.xingo_credentials"
sudo rm -rf "$ROOT_DIR/certs"
sudo rm -rf "$ROOT_DIR/wazuh-docker" "$ROOT_DIR/shuffle" "$ROOT_DIR/iris-web" "$ROOT_DIR/misp-docker"

echo -e "\e[1;32m[OK] Desinstalação concluída. O ambiente está limpo.\e[0m"
