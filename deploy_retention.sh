#!/bin/bash

# =================================================================
# Xingó Defense Security
# Automação de Deploy: Módulo de Retenção PME (Cold Storage)
# =================================================================

ROOT_DIR="/opt/xingo"
SCRIPT_RETENCAO="${ROOT_DIR}/xingo_retention.sh"
ARQUIVO_LOG="/var/log/xingo_retention.log"

echo -e "\e[1;36m=================================================================\e[0m"
echo -e "\e[1;36m  Xingó Defense Security — Deploy de Retenção (Google Drive) \e[0m"
echo -e "\e[1;36m=================================================================\e[0m\n"

if ! command -v rclone &> /dev/null; then
    echo -e "\e[1;34m[INFO]\e[0m Instalando Rclone..."
    sudo -v ; curl -s https://rclone.org/install.sh | sudo bash
fi

sudo mkdir -p "$ROOT_DIR"

sudo cat << 'EOF' > "$SCRIPT_RETENCAO"
#!/bin/bash
DIAS_RETENCAO=30
REMOTE_DESTINO="xingo_crypt:Wazuh_Archives"
DIRETORIO_ALERTS="/var/ossec/logs/alerts"

if systemctl is-active --quiet wazuh-manager; then
    if [ -d "$DIRETORIO_ALERTS" ]; then
        find "$DIRETORIO_ALERTS" -type f -name "*.gz" -mtime +${DIAS_RETENCAO} | while read -r arquivo; do
            pasta=$(echo "$arquivo" | awk -F'/' '{print $(NF-2)"/"$(NF-1)}')
            rclone move "$arquivo" "${REMOTE_DESTINO}/alerts/${pasta}" --transfers 4
        done
        find "$DIRETORIO_ALERTS" -mindepth 1 -type d -empty -delete
    fi
fi
EOF

sudo chmod +x "$SCRIPT_RETENCAO"

CRON_JOB="0 2 * * * $SCRIPT_RETENCAO"
if ! sudo crontab -l 2>/dev/null | grep -q -F "$SCRIPT_RETENCAO"; then
    (sudo crontab -l 2>/dev/null; echo "$CRON_JOB") | sudo crontab -
fi

echo -e "\e[1;32m[OK]\e[0m Automação concluída. Execute 'rclone config' para autenticar o Drive."
