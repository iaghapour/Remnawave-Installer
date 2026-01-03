#!/bin/bash

# ==========================================
#   Remnawave Panel Installer Script
#   Created for Community & YouTube
# ==========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Header Function
show_header() {
    clear
    echo -e "${RED}==========================================================${NC}"
    echo -e "${YELLOW}       Remnawave Auto Installer & Manager                 ${NC}"
    echo -e "${RED}==========================================================${NC}"
    echo -e "${BLUE}   YouTube Channel: https://www.youtube.com/@iAghapour    ${NC}"
    echo -e "${RED}==========================================================${NC}"
    echo ""
}

# Root Check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Please run as root (sudo)${NC}"
  exit 1
fi

# Function to install Docker
install_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${BLUE}Installing Docker...${NC}"
        apt update
        apt install -y curl wget nano git openssl
        curl -fsSL https://get.docker.com | sh
        echo -e "${GREEN}Docker Installed!${NC}"
    else
        echo -e "${GREEN}Docker is already installed.${NC}"
    fi
}

# Main Menu
show_header
echo "Select an option:"
echo "1) Install Panel (Main Server + Caddy)"
echo "2) Install Node (On this server)"
echo "3) Uninstall Panel (Delete everything)"
echo "4) Uninstall Node (Delete node only)"
echo "5) Exit"
echo ""
read -p "Enter choice [1-5]: " choice

case $choice in
    1)
        # ==================== INSTALL PANEL ====================
        show_header
        echo -e "${GREEN}Starting Panel Installation...${NC}"
        
        install_docker

        read -p "Enter your Domain (e.g., panel.example.com): " DOMAIN
        if [ -z "$DOMAIN" ]; then
            echo -e "${RED}Domain cannot be empty!${NC}"
            exit 1
        fi

        mkdir -p /opt/remnawave
        cd /opt/remnawave

        echo -e "${BLUE}Generating secrets and configuration...${NC}"
        
        # Create .env (Updated with METRICS_USER)
        cat <<EOF > .env
FRONT_END_DOMAIN=${DOMAIN}
SUB_PUBLIC_DOMAIN=${DOMAIN}/api/sub
JWT_AUTH_SECRET=$(openssl rand -hex 64)
JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)
METRICS_USER=admin
METRICS_PASS=$(openssl rand -hex 64)
WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=remnawave
DATABASE_URL=postgresql://postgres:postgres@remnawave-db:5432/remnawave?schema=public
REDIS_HOST=remnawave-redis
REDIS_PORT=6379
EOF

        # Create docker-compose.yml
        cat <<EOF > docker-compose.yml
services:
  remnawave-db:
    image: postgres:17.0
    restart: always
    env_file: .env
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
      - TZ=UTC
    volumes:
      - remnawave-db-data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U \$\${POSTGRES_USER} -d \$\${POSTGRES_DB}']
      interval: 3s
      timeout: 10s
      retries: 3

  remnawave:
    image: remnawave/backend:latest
    restart: always
    env_file: .env
    ports:
      - "127.0.0.1:3000:3000"
    depends_on:
      remnawave-db:
        condition: service_healthy
      remnawave-redis:
        condition: service_healthy

  remnawave-redis:
    image: valkey/valkey:8.0-alpine
    restart: always
    volumes:
      - remnawave-redis-data:/data
    healthcheck:
      test: ['CMD', 'valkey-cli', 'ping']
      interval: 3s
      timeout: 10s
      retries: 3

  caddy:
    image: caddy:2-alpine
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
    depends_on:
      - remnawave

volumes:
  remnawave-db-data:
  remnawave-redis-data:
  caddy-data:
EOF

        # Create Caddyfile
        cat <<EOF > Caddyfile
${DOMAIN} {
    reverse_proxy remnawave:3000
}
EOF

        echo -e "${BLUE}Starting services...${NC}"
        docker compose up -d

        echo -e "\n${GREEN}Installation Complete!${NC}"
        echo -e "Access your panel at: https://${DOMAIN}"
        ;;

    2)
        # ==================== INSTALL NODE ====================
        show_header
        echo -e "${GREEN}Setup Node on this server...${NC}"
        
        install_docker
        
        mkdir -p /opt/remnawave-node
        cd /opt/remnawave-node
        
        echo -e "${YELLOW}INSTRUCTIONS:${NC}"
        echo "1. Go to your Panel > Nodes > Create Node."
        echo "2. Copy the 'docker-compose.yml' content shown in the panel."
        echo "3. I will open a text editor now. PASTE that content inside and save (Ctrl+X, Y, Enter)."
        
        read -p "Press Enter to open editor..."
        
        nano docker-compose.yml
        
        if [ -s docker-compose.yml ]; then
            echo -e "${BLUE}Starting Node...${NC}"
            docker compose up -d
            echo -e "${GREEN}Node started successfully!${NC}"
        else
            echo -e "${RED}File was empty. Node installation aborted.${NC}"
        fi
        ;;

    3)
        # ==================== UNINSTALL PANEL ====================
        show_header
        echo -e "${RED}WARNING: This will delete the Panel, Database, and all Users!${NC}"
        read -p "Are you sure? (y/n): " confirm
        if [[ $confirm == "y" || $confirm == "Y" ]]; then
            if [ -d "/opt/remnawave" ]; then
                cd /opt/remnawave
                echo -e "${BLUE}Stopping containers...${NC}"
                docker compose down -v
                cd ..
                echo -e "${BLUE}Removing files...${NC}"
                rm -rf /opt/remnawave
                echo -e "${GREEN}Panel successfully uninstalled.${NC}"
            else
                echo -e "${RED}Panel directory not found!${NC}"
            fi
        else
            echo "Cancelled."
        fi
        ;;

    4)
        # ==================== UNINSTALL NODE ====================
        show_header
        echo -e "${RED}WARNING: This will delete the Node on this server!${NC}"
        read -p "Are you sure? (y/n): " confirm
        if [[ $confirm == "y" || $confirm == "Y" ]]; then
            if [ -d "/opt/remnawave-node" ]; then
                cd /opt/remnawave-node
                echo -e "${BLUE}Stopping node...${NC}"
                docker compose down -v
                cd ..
                echo -e "${BLUE}Removing files...${NC}"
                rm -rf /opt/remnawave-node
                echo -e "${GREEN}Node successfully uninstalled.${NC}"
            else
                echo -e "${RED}Node directory not found!${NC}"
            fi
        else
            echo "Cancelled."
        fi
        ;;

    5)
        exit 0
        ;;
    *)
        echo "Invalid option."
        ;;
esac
