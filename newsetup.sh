#!/bin/bash

# =========================
# Xingó Defense Security
# SOC Package Setup - Production Ready
# Version 1.3
# =========================

XINGO_VERSION="1.3-Production"
ROOT_DIR="$(pwd)"

print_step_header() {
    echo -e "\n\e[1;36m=================================================================\e[0m"
    echo -e "\e[1;36m  Xingó Defense Security — $1 \e[0m"
    echo -e "\e[1;35m  Versão ${XINGO_VERSION}\e[0m"
    echo -e "\e[1;36m=================================================================\e[0m\n"
}

die()  { echo -e "\e[1;31m[ERRO]\e[0m $*" >&2; exit 1; }
info() { echo -e "\e[1;34m[INFO]\e[0m $*"; }
warn() { echo -e "\e[1;33m[AVISO]\e[0m $*"; }
ok()   { echo -e "\e[1;32m[OK]\e[0m $*"; }

generate_password() { LC_ALL=C tr -dc 'A-Za-z0-9!@#%^*()_+=' < /dev/urandom | head -c "${1:-20}"; }
generate_alphanum_password() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${1:-20}"; }
generate_api_key() { openssl rand -base64 64 | tr -d '\n'; }

get_latest_github_version() {
    curl -s "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/' || echo "$2"
}

get_latest_wazuh_agent_version() {
    curl -s "https://packages.wazuh.com/4.x/apt/dists/stable/main/binary-amd64/Packages" | awk '/^Package: wazuh-agent/{p=1} p&&/^Version:/{print $2; exit}' | cut -d'-' -f1 || echo "4.10.1"
}

update_install_pre() {
    print_step_header "Atualizar sistema e Hardening de SO"
    info "Ajustando limites do kernel (sysctl) para Elasticsearch/OpenSearch..."
    sudo sysctl -w vm.max_map_count=262144
    echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
    
    sudo apt-get update -y
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y wget curl nano git unzip nodejs jq openssl iptables-persistent certbot

    if ! command -v docker > /dev/null; then
        info "Instalando Docker via repositório APT oficial..."
        sudo apt-get install -y docker.io docker-compose-v2
        sudo systemctl enable docker.service
        ok "Docker instalado."
    fi
}

install_module() {
    print_step_header "Instalar pacote SOC Xingó Defense"
    IP_ADDRESS=$(curl -s ip.me -4 || hostname -I | awk '{print $1}')
    BASE_URL="$IP_ADDRESS"

    echo -e "\n\e[1;33m[PRODUÇÃO] Configuração de SSL\e[0m"
    read -p "Deseja utilizar Let's Encrypt para gerar um SSL válido? (s/N): " use_le
    CERT_DIR="${ROOT_DIR}/certs/xingo"
    mkdir -p "$CERT_DIR"
    
    if [[ "$use_le" =~ ^[Ss]$ ]]; then
        read -p "Informe o domínio (ex: soc.xingo.com.br): " DOMAIN
        read -p "Informe um e-mail para registro no Let's Encrypt: " EMAIL
        sudo certbot certonly --standalone -d "$DOMAIN" -m "$EMAIL" --agree-tos -n || die "Falha ao gerar SSL."
        sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "${CERT_DIR}/server.crt"
        sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "${CERT_DIR}/server.key"
        BASE_URL="$DOMAIN"
    else
        openssl req -x509 -newkey rsa:4096 -nodes -keyout "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.crt" -days 365 -subj "/C=BR/ST=SE/L=Aracaju/O=Xingo Defense/CN=${BASE_URL}" -addext "subjectAltName=IP:${IP_ADDRESS},DNS:${BASE_URL}" 2>/dev/null
    fi

    echo -e "\n\e[1;33m[PRODUÇÃO] Configuração de Firewall (Docker-User)\e[0m"
    read -p "Deseja restringir o acesso web/painéis apenas a IPs administrativos? (s/N): " use_fw
    if [[ "$use_fw" =~ ^[Ss]$ ]]; then
        read -p "Informe o IP ou bloco CIDR permitido (ex: 10.0.0.0/8): " ADMIN_IP
        sudo iptables -I DOCKER-USER -p tcp -m multiport --dports 443,1443,8443,3001 -j DROP
        sudo iptables -I DOCKER-USER -s "$ADMIN_IP" -p tcp -m multiport --dports 443,1443,8443,3001 -j RETURN
        sudo netfilter-persistent save > /dev/null 2>&1
    fi

    CREDS_FILE="${ROOT_DIR}/.xingo_credentials"
    WAZUH_ADMIN=$(generate_password); WAZUH_KIBANA=$(generate_password); WAZUH_API=$(generate_password)
    IRIS_ADM=$(generate_password); IRIS_API=$(generate_api_key); IRIS_SEC=$(generate_password); IRIS_DB=$(generate_alphanum_password)
    MISP_DB=$(generate_alphanum_password); MISP_ROOT=$(generate_alphanum_password)

    cat > "$CREDS_FILE" <<EOF
[WAZUH] Dashboard: https://${BASE_URL} | User: admin | Pass: ${WAZUH_ADMIN}
[IRIS] URL: https://${BASE_URL}:8443 | User: administrator | Pass: ${IRIS_ADM}
[MISP] URL: https://${BASE_URL}:1443 | DB Root: ${MISP_ROOT}
EOF
    chmod 600 "$CREDS_FILE"

    info "Clonando repositórios base..."
    git clone https://github.com/wazuh/wazuh-docker.git
    git clone https://github.com/Shuffle/Shuffle.git shuffle
    git clone https://github.com/dfir-iris/iris-web.git
    git clone https://github.com/MISP/misp-docker.git

    info "Subindo Wazuh..."
    cd "$ROOT_DIR/wazuh-docker/single-node"
    sed -i "s|INDEXER_PASSWORD=.*|INDEXER_PASSWORD=${WAZUH_ADMIN}|g; s|DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${WAZUH_KIBANA}|g; s|API_PASSWORD=.*|API_PASSWORD=${WAZUH_API}|g" docker-compose.yml
    sudo docker compose -f generate-indexer-certs.yml run --rm generator
    sudo docker compose up -d

    info "Subindo Shuffle..."
    cd "$ROOT_DIR/shuffle"
    mkdir -p shuffle-database && sudo chown -R 1000:1000 shuffle-database
    sudo docker compose up -d

    info "Subindo DFIR-IRIS..."
    cd "$ROOT_DIR/iris-web"
    cp .env.model .env
    sed -i "s|IRIS_ADM_PASSWORD=.*|IRIS_ADM_PASSWORD=${IRIS_ADM}|; s|IRIS_ADM_API_KEY=.*|IRIS_ADM_API_KEY=${IRIS_API}|; s|SECRET_KEY=.*|SECRET_KEY=${IRIS_SEC}|; s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${IRIS_DB}|" .env
    sudo docker compose pull && sudo docker compose up -d

    info "Subindo MISP..."
    cd "$ROOT_DIR/misp-docker"
    sed -i "s|BASE_URL=.*|BASE_URL='https://$BASE_URL:1443'|" template.env
    cp template.env .env
    sudo docker compose pull && sudo docker compose up -d

    echo -e "\n\e[1;32m[OK] Implantação concluída! Leia o .xingo_credentials.\e[0m"
}

update_install_pre
install_module
