#!/bin/bash

# ============================================================================
# EDGARD HOME INSTALLER - UNIVERSAL SETUP (macOS + Linux)
# ============================================================================
# Kopiert alle Dateien aus dem Repository in die Zielstruktur
# Verwendung: ./setup.sh
# ============================================================================

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# GitHub Repository URLs
GITHUB_RAW="https://raw.githubusercontent.com/momo1212221/adauto/refs/heads/main"
INDEX_HTML_URL="${GITHUB_RAW}/index.html"
INSTALL_SCRIPT_URL="${GITHUB_RAW}/install_edgard.sh"
REQUIREMENTS_URL="${GITHUB_RAW}/requirements.txt"
SERVER_PY_URL="${GITHUB_RAW}/server.py"

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║        🚀 EDGARD HOME INSTALLER - GITHUB SETUP 🚀         ║"
    echo "║                                                           ║"
    echo "║         Direct Download from Repository                   ║"
    echo "║              macOS & Linux Support                        ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

set -e
trap 'log_error "Setup fehlgeschlagen bei Zeile $LINENO"; exit 1' ERR

# Verzeichnisse
INSTALL_DIR="$HOME/edgard-installer"

show_banner

log_info "GitHub Repository: momo1212221/adauto"
log_info "Zielverzeichnis: $INSTALL_DIR"
echo

log_step "1/9 - Prüfe Systemvoraussetzungen..."

# OS Detection
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
    log_success "Betriebssystem: macOS"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_success "Betriebssystem: $NAME $VERSION"
    else
        log_success "Betriebssystem: Linux"
    fi
else
    log_error "Nicht unterstütztes Betriebssystem: $OSTYPE"
    exit 1
fi

# Root-Check
if [ "$EUID" -eq 0 ]; then
    log_warning "Script läuft als root!"
    USE_SUDO=""
else
    USE_SUDO="sudo"
fi
log_success "Benutzerrechte OK"

# Internet-Check
if ping -c 1 8.8.8.8 &> /dev/null; then
    log_success "Internetverbindung OK"
else
    log_error "Keine Internetverbindung!"
    exit 1
fi

log_step "2/9 - Installiere System-Abhängigkeiten..."

if [ "$OS_TYPE" == "macos" ]; then
    # macOS - Homebrew verwenden
    if ! command -v brew &> /dev/null; then
        log_info "Homebrew wird installiert..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        log_success "Homebrew installiert"
    else
        log_success "Homebrew bereits installiert"
    fi
    
    log_info "Installiere Pakete via Homebrew..."
    brew install python3 wget git tree 2>&1 | grep -v "already installed" || true
    log_success "macOS Abhängigkeiten installiert"
    
elif [ "$OS_TYPE" == "linux" ]; then
    # Linux - apt verwenden
    log_info "Aktualisiere Paketliste..."
    $USE_SUDO apt update -qq
    
    log_info "Installiere Pakete..."
    $USE_SUDO DEBIAN_FRONTEND=noninteractive apt install -y \
        python3 python3-pip python3-venv curl git wget tar tree \
        &> /dev/null
    log_success "Linux Abhängigkeiten installiert"
fi

log_step "3/9 - Erstelle Zielverzeichnis..."

# Backup falls vorhanden
if [ -d "$INSTALL_DIR" ]; then
    log_warning "Verzeichnis existiert bereits: $INSTALL_DIR"
    read -p "Backup erstellen und neu aufsetzen? [j/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        mv "$INSTALL_DIR" "$BACKUP_DIR"
        log_success "Backup: $BACKUP_DIR"
    else
        log_error "Installation abgebrochen"
        exit 0
    fi
fi

# Verzeichnisstruktur erstellen
mkdir -p "$INSTALL_DIR"/{templates,static/{css,js},scripts,config,logs}
log_success "Verzeichnisstruktur erstellt"

log_step "4/9 - Lade Dateien von GitHub..."

# Funktion zum Download
download_file() {
    local url=$1
    local target=$2
    local description=$3
    
    log_info "Lade $description..."
    if curl -fsSL "$url" -o "$target"; then
        log_success "$description → $target"
        return 0
    else
        log_error "Download fehlgeschlagen: $description"
        return 1
    fi
}

# server.py herunterladen
download_file "$SERVER_PY_URL" "$INSTALL_DIR/server.py" "server.py" || {
    log_warning "server.py Download fehlgeschlagen - Erstelle Platzhalter"
    cat > "$INSTALL_DIR/server.py" << 'EOF'
#!/usr/bin/env python3
from flask import Flask
app = Flask(__name__)

@app.route('/')
def index():
    return "Server läuft - Bitte vollständige server.py von GitHub laden!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
}
chmod +x "$INSTALL_DIR/server.py"

# index.html herunterladen
download_file "$INDEX_HTML_URL" "$INSTALL_DIR/templates/index.html" "index.html" || {
    log_warning "index.html Download fehlgeschlagen - Erstelle Platzhalter"
    echo "<h1>Frontend Platzhalter - Bitte index.html von GitHub laden!</h1>" > "$INSTALL_DIR/templates/index.html"
}

# install_edgard.sh herunterladen
download_file "$INSTALL_SCRIPT_URL" "$INSTALL_DIR/scripts/install_edgard.sh" "install_edgard.sh" || {
    log_warning "install_edgard.sh Download fehlgeschlagen - Erstelle Platzhalter"
    cat > "$INSTALL_DIR/scripts/install_edgard.sh" << 'EOF'
#!/bin/bash
echo "Installation läuft..."
echo "Bitte vollständiges install_edgard.sh von GitHub laden!"
EOF
}
chmod +x "$INSTALL_DIR/scripts/install_edgard.sh"

# requirements.txt herunterladen
download_file "$REQUIREMENTS_URL" "$INSTALL_DIR/requirements.txt" "requirements.txt" || {
    log_warning "requirements.txt Download fehlgeschlagen - Erstelle Standard"
    cat > "$INSTALL_DIR/requirements.txt" << 'EOF'
flask==3.0.0
flask-cors==4.0.0
requests==2.31.0
EOF
}

log_step "5/9 - Erstelle Python Virtual Environment..."

cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
log_success "Virtual Environment erstellt"

log_step "6/9 - Installiere Python-Pakete..."

pip install -q --upgrade pip
pip install -q -r requirements.txt
log_success "Python-Pakete installiert"

log_step "7/9 - Erstelle Management-Scripts..."

# start.sh
cat > "$INSTALL_DIR/start.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"

echo "🚀 Starte Edgard Home Installer..."

# Virtual Environment aktivieren
source venv/bin/activate

# Server starten
python3 server.py
EOF
chmod +x start.sh
log_success "start.sh erstellt"

# stop.sh
cat > "$INSTALL_DIR/stop.sh" << 'EOF'
#!/bin/bash
echo "⏹️  Stoppe Edgard Home Installer..."
pkill -f "python3 server.py" && echo "✓ Server gestoppt" || echo "ℹ Kein laufender Server gefunden"
EOF
chmod +x stop.sh
log_success "stop.sh erstellt"

# restart.sh
cat > "$INSTALL_DIR/restart.sh" << 'EOF'
#!/bin/bash
echo "🔄 Starte Edgard Home Installer neu..."
./stop.sh
sleep 2
./start.sh
EOF
chmod +x restart.sh
log_success "restart.sh erstellt"

# update.sh - lädt Dateien neu von GitHub
cat > "$INSTALL_DIR/update.sh" << 'EOFUPDATE'
#!/bin/bash
cd "$(dirname "$0")"

echo "📦 Aktualisiere von GitHub..."

# GitHub URLs
GITHUB_RAW="https://raw.githubusercontent.com/momo1212221/adauto/refs/heads/main"

# Backup erstellen
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Dateien sichern
cp server.py "$BACKUP_DIR/" 2>/dev/null
cp templates/index.html "$BACKUP_DIR/" 2>/dev/null
cp scripts/install_edgard.sh "$BACKUP_DIR/" 2>/dev/null
cp requirements.txt "$BACKUP_DIR/" 2>/dev/null

echo "✓ Backup erstellt: $BACKUP_DIR"

# Neue Dateien laden mit curl (macOS) oder wget (Linux)
if command -v curl &> /dev/null; then
    DOWNLOAD_CMD="curl -fsSL"
elif command -v wget &> /dev/null; then
    DOWNLOAD_CMD="wget -qO-"
else
    echo "❌ Weder curl noch wget gefunden!"
    exit 1
fi

$DOWNLOAD_CMD "${GITHUB_RAW}/server.py" > server.py && echo "✓ server.py aktualisiert"
$DOWNLOAD_CMD "${GITHUB_RAW}/index.html" > templates/index.html && echo "✓ index.html aktualisiert"
$DOWNLOAD_CMD "${GITHUB_RAW}/install_edgard.sh" > scripts/install_edgard.sh && echo "✓ install_edgard.sh aktualisiert"
$DOWNLOAD_CMD "${GITHUB_RAW}/requirements.txt" > requirements.txt && echo "✓ requirements.txt aktualisiert"

chmod +x server.py
chmod +x scripts/install_edgard.sh

# Dependencies aktualisieren
source venv/bin/activate
pip install -q --upgrade -r requirements.txt
echo "✓ Dependencies aktualisiert"

echo ""
echo "🎉 Update abgeschlossen!"
EOFUPDATE
chmod +x update.sh
log_success "update.sh erstellt"

# status.sh
cat > "$INSTALL_DIR/status.sh" << 'EOF'
#!/bin/bash
echo "📊 Edgard Home Installer Status"
echo "================================"

if pgrep -f "python3 server.py" > /dev/null; then
    echo "Status: 🟢 LÄUFT"
    echo "PID: $(pgrep -f 'python3 server.py')"
    echo "Port: 5000"
    echo "URL: http://localhost:5000"
else
    echo "Status: 🔴 GESTOPPT"
fi

echo ""
echo "Verzeichnis: $(pwd)"
echo "Python: $(source venv/bin/activate && python3 --version)"
echo ""
echo "Dateien:"
ls -lh server.py templates/index.html scripts/install_edgard.sh requirements.txt 2>/dev/null
EOF
chmod +x status.sh
log_success "status.sh erstellt"

# logs.sh
cat > "$INSTALL_DIR/logs.sh" << 'EOF'
#!/bin/bash
LOG_FILE="logs/server.log"
if [ -f "$LOG_FILE" ]; then
    tail -f "$LOG_FILE"
else
    echo "Keine Logs gefunden: $LOG_FILE"
    echo "Starten Sie den Server mit: ./start.sh &> logs/server.log &"
fi
EOF
chmod +x logs.sh
log_success "logs.sh erstellt"

log_step "8/9 - Erstelle Dokumentation..."

# README.md
cat > "$INSTALL_DIR/README.md" << 'EOFREADME'
# 🚀 Edgard Home Installer

Automatisierte Installation von Edgard Home mit Web-Interface.

## 📂 Projektstruktur

```
edgard-installer/
├── server.py                    # Flask Backend
├── requirements.txt             # Python Dependencies
├── venv/                       # Python Virtual Environment
├── templates/
│   └── index.html              # Web-Interface
├── static/                     # CSS/JS (optional)
├── scripts/
│   └── install_edgard.sh       # Hauptinstallation
├── config/                     # Konfiguration
└── logs/                       # Log-Dateien
```

## 🎯 Quick Start

### Server starten
```bash
./start.sh
```

### Browser öffnen
```
http://localhost:5000
```

### Server stoppen
```bash
./stop.sh
```

## 📋 Befehle

| Befehl | Beschreibung |
|--------|--------------|
| `./start.sh` | Server starten |
| `./stop.sh` | Server stoppen |
| `./restart.sh` | Server neu starten |
| `./status.sh` | Status anzeigen |
| `./logs.sh` | Logs anzeigen |
| `./update.sh` | Von GitHub aktualisieren |

## 🔄 Updates von GitHub

Um die neuesten Dateien von GitHub zu laden:
```bash
./update.sh
```

## 💻 Platform Support

- ✅ macOS (Homebrew)
- ✅ Linux (apt)

## 🔧 Entwicklung

### Virtual Environment aktivieren
```bash
source venv/bin/activate
```

### Server manuell starten
```bash
source venv/bin/activate
python3 server.py
```

## 📝 Logs

Logs werden in `logs/server.log` gespeichert:
```bash
./logs.sh
```

EOFREADME

log_success "README.md erstellt"

log_step "9/9 - Abschluss..."

echo
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║              ✅ SETUP ERFOLGREICH! ✅                       ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo

log_info "📊 Installation Summary:"
echo
echo "  📁 Installation: $INSTALL_DIR"
echo "  🌐 GitHub Repo: momo1212221/adauto"
echo "  🐍 Python venv: $INSTALL_DIR/venv"
echo "  💻 Platform: $OS_TYPE"
echo

log_info "📂 Installierte Dateien:"
if command -v tree &> /dev/null; then
    tree -L 2 "$INSTALL_DIR" 2>/dev/null
else
    ls -R "$INSTALL_DIR" | head -30
fi
echo

log_info "🚀 Nächste Schritte:"
echo
echo "  1️⃣  Wechsle ins Verzeichnis:"
echo "     cd $INSTALL_DIR"
echo
echo "  2️⃣  Server starten:"
echo "     ./start.sh"
echo
echo "  3️⃣  Browser öffnen:"
echo "     http://localhost:5000"
echo

log_info "📋 Verfügbare Befehle:"
echo "     ./start.sh    - Server starten"
echo "     ./stop.sh     - Server stoppen"
echo "     ./restart.sh  - Server neu starten"
echo "     ./status.sh   - Status anzeigen"
echo "     ./logs.sh     - Logs verfolgen"
echo "     ./update.sh   - Von GitHub aktualisieren"
echo

# Automatisch starten?
read -p "Server jetzt starten? [j/N]: " -n 1 -r
echo

if [[ $REPLY =~ ^[Jj]$ ]]; then
    log_info "Starte Server..."
    cd "$INSTALL_DIR"
    ./start.sh
else
    log_info "Server nicht gestartet"
    log_info "Starten mit: cd $INSTALL_DIR && ./start.sh"
fi
