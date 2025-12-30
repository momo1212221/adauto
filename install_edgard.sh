#!/bin/bash

# ============================================================================
# EDGARD HOME - HAUPTINSTALLATION (FIXED)
# ============================================================================

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

set -e
trap 'log_error "Installation fehlgeschlagen"; exit 1' ERR

EDGARD_DIR="${EDGARD_DIR:-$HOME/edgard_home}"
AUTO_UPDATE="${AUTO_UPDATE:-false}"

log_info "Starte Edgard Home Installation..."
log_info "Installationsverzeichnis: $EDGARD_DIR"

# Benutzerrechte prüfen
log_info "Benutzerrechte prüfen..."
if [ "$EUID" -eq 0 ]; then
    log_error "Bitte nicht als root ausführen!"
    exit 1
fi
log_success "Benutzerrechte OK"

# Prüfe ob sudo verfügbar ist
if ! command -v sudo &> /dev/null; then
    log_error "sudo ist nicht installiert!"
    exit 1
fi

# Internetverbindung prüfen
log_info "Internetverbindung prüfen..."
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    log_error "Keine Internetverbindung!"
    exit 1
fi
log_success "Internetverbindung OK"

# Betriebssystem prüfen
log_info "Betriebssystem prüfen..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_success "OS: $NAME $VERSION"
else
    log_warning "OS nicht identifizierbar"
fi

# Speicherplatz prüfen
log_info "Speicherplatz prüfen..."
AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -lt 10 ]; then
    log_error "Nicht genug Speicherplatz! Mindestens 10GB erforderlich."
    exit 1
fi
log_success "Speicherplatz: ${AVAILABLE_SPACE}GB verfügbar"

# System aktualisieren
log_info "System aktualisieren..."
sudo apt update -qq
sudo apt upgrade -y -qq
log_success "System aktualisiert"

# Docker installieren
log_info "Docker installieren..."
if command -v docker &> /dev/null; then
    log_success "Docker bereits installiert ($(docker --version))"
else
    log_info "Installiere Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    log_success "Docker installiert"
    log_warning "Benutzer zu docker-Gruppe hinzugefügt"
fi

# Docker-Berechtigungen prüfen und ggf. Gruppe neu laden
if ! groups | grep -q docker; then
    log_warning "Docker-Gruppe noch nicht aktiv - verwende sudo für Docker-Befehle"
    DOCKER_CMD="sudo docker"
    DOCKER_COMPOSE_CMD="sudo docker compose"
else
    DOCKER_CMD="docker"
    DOCKER_COMPOSE_CMD="docker compose"
fi

# Docker Compose installieren
log_info "Docker Compose installieren..."
if command -v docker-compose &> /dev/null || docker compose version &> /dev/null 2>&1; then
    log_success "Docker Compose bereits installiert"
else
    log_info "Installiere Docker Compose..."
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    log_success "Docker Compose installiert"
fi

# Edgard Home einrichten
log_info "Edgard Home einrichten..."
mkdir -p "$EDGARD_DIR"
cd "$EDGARD_DIR"

# Docker Compose Datei erstellen
log_info "Erstelle docker-compose.yml..."
cat > docker-compose.yml << 'EOFDOCKER'
services:
  edgard-home:
    image: edgard/home:latest
    container_name: edgard-home
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./data:/data
      - ./config:/config
    environment:
      - TZ=Europe/Berlin
      - PUID=1000
      - PGID=1000
    networks:
      - edgard-network

networks:
  edgard-network:
    driver: bridge
EOFDOCKER

log_success "docker-compose.yml erstellt"

# Verzeichnisse erstellen
mkdir -p data config
log_success "Verzeichnisse erstellt"

# Container starten (mit sudo falls nötig)
log_info "Starte Edgard Home Container..."
if ! $DOCKER_COMPOSE_CMD up -d 2>/dev/null; then
    log_info "Verwende sudo für Docker Compose..."
    sudo docker compose up -d
fi
log_success "Edgard Home gestartet!"

# Auto-Update einrichten
if [ "$AUTO_UPDATE" = "true" ]; then
    log_info "Auto-Update konfigurieren..."
    
    UPDATE_SCRIPT="$EDGARD_DIR/update.sh"
    cat > "$UPDATE_SCRIPT" << 'EOFUPDATE'
#!/bin/bash
cd $(dirname "$0")

# Docker-Befehle mit sudo falls nötig
if groups | grep -q docker; then
    docker compose pull
    docker compose up -d
    docker image prune -f
else
    sudo docker compose pull
    sudo docker compose up -d
    sudo docker image prune -f
fi
EOFUPDATE
    
    chmod +x "$UPDATE_SCRIPT"
    
    # Cronjob hinzufügen
    CRON_CMD="0 3 * * * $UPDATE_SCRIPT >> $EDGARD_DIR/update.log 2>&1"
    (crontab -l 2>/dev/null | grep -v "$UPDATE_SCRIPT"; echo "$CRON_CMD") | crontab -
    
    log_success "Auto-Update konfiguriert (täglich 03:00 Uhr)"
else
    log_info "Auto-Update übersprungen"
fi

echo
log_success "==================================="
log_success "Installation erfolgreich!"
log_success "==================================="
echo
log_info "Edgard Home läuft auf: http://localhost:8080"
log_info "Container-Status: $DOCKER_COMPOSE_CMD ps"
log_info "Logs anzeigen: $DOCKER_COMPOSE_CMD logs -f"
log_info "Stoppen: $DOCKER_COMPOSE_CMD down"
echo

if ! groups | grep -q docker; then
    log_warning "WICHTIG: Führen Sie 'newgrp docker' aus oder melden Sie sich neu an,"
    log_warning "um Docker ohne sudo verwenden zu können."
fi
