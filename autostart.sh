#!/bin/bash

# ============================================================================
# EDGARD HOME INSTALLER - REPOSITORY SETUP
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

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║        🚀 EDGARD HOME INSTALLER - SETUP 🚀                ║"
    echo "║                                                           ║"
    echo "║         Repository → Installation                         ║"
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
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/edgard-installer"

show_banner

log_info "Repository: $REPO_DIR"
log_info "Ziel: $INSTALL_DIR"
echo

log_step "1/9 - Prüfe Repository-Struktur..."

# Prüfe ob alle erforderlichen Dateien vorhanden sind
REQUIRED_FILES=(
    "src/server.py"
    "src/templates/index.html"
    "src/install_edgard.sh"
    "src/requirements.txt"
)

MISSING_FILES=()
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$REPO_DIR/$file" ]; then
        MISSING_FILES+=("$file")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    log_warning "Folgende Dateien fehlen im Repository:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  ✗ $file"
    done
    log_warning "Setup wird trotzdem fortgesetzt mit Platzhaltern"
else
    log_success "Alle Repository-Dateien gefunden"
fi

log_step "2/9 - Prüfe Systemvoraussetzungen..."

# Root-Check
if [ "$EUID" -eq 0 ]; then
    log_warning "Script läuft als root!"
    USE_SUDO=""
else
    USE_SUDO="sudo"
fi
log_success "Benutzerrechte OK"

# Internet-Check
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    log_error "Keine Internetverbindung!"
    exit 1
fi
log_success "Internetverbindung OK"

# OS-Check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_success "OS: $NAME $VERSION"
fi

log_step "3/9 - Installiere System-Abhängigkeiten..."

log_info "Aktualisiere Paketliste..."
$USE_SUDO apt update -qq

log_info "Installiere Pakete..."
$USE_SUDO DEBIAN_FRONTEND=noninteractive apt install -y \
    python3 python3-pip python3-venv curl git wget tar tree \
    &> /dev/null

log_success "Systemabhängigkeiten installiert"

log_step "4/9 - Erstelle Zielverzeichnis..."

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

log_step "5/9 - Kopiere Repository-Dateien..."

# server.py
if [ -f "$REPO_DIR/src/server.py" ]; then
    cp "$REPO_DIR/src/server.py" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/server.py"
    log_success "server.py → $INSTALL_DIR/"
else
    log_warning "server.py fehlt - Platzhalter wird erstellt"
    cat > "$INSTALL_DIR/server.py" << 'EOF'
#!/usr/bin/env python3
from flask import Flask
app = Flask(__name__)

@app.route('/')
def index():
    return "Server läuft - Bitte vollständige server.py einfügen!"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
    chmod +x "$INSTALL_DIR/server.py"
fi

# index.html
if [ -f "$REPO_DIR/src/templates/index.html" ]; then
    cp "$REPO_DIR/src/templates/index.html" "$INSTALL_DIR/templates/"
    log_success "index.html → $INSTALL_DIR/templates/"
else
    log_warning "index.html fehlt - Platzhalter wird erstellt"
    echo "<h1>Frontend Platzhalter - Bitte index.html einfügen!</h1>" > "$INSTALL_DIR/templates/index.html"
fi

# install_edgard.sh
if [ -f "$REPO_DIR/src/install_edgard.sh" ]; then
    cp "$REPO_DIR/src/install_edgard.sh" "$INSTALL_DIR/scripts/"
    chmod +x "$INSTALL_DIR/scripts/install_edgard.sh"
    log_success "install_edgard.sh → $INSTALL_DIR/scripts/"
else
    log_warning "install_edgard.sh fehlt - Platzhalter wird erstellt"
    cat > "$INSTALL_DIR/scripts/install_edgard.sh" << 'EOF'
#!/bin/bash
echo "Installation läuft..."
echo "Bitte vollständiges install_edgard.sh einfügen!"
EOF
    chmod +x "$INSTALL_DIR/scripts/install_edgard.sh"
fi

# requirements.txt
if [ -f "$REPO_DIR/src/requirements.txt" ]; then
    cp "$REPO_DIR/src/requirements.txt" "$INSTALL_DIR/"
    log_success "requirements.txt → $INSTALL_DIR/"
else
    log_warning "requirements.txt fehlt - Standard wird erstellt"
    cat > "$INSTALL_DIR/requirements.txt" << 'EOF'
flask==3.0.0
flask-cors==4.0.0
requests==2.31.0
EOF
fi

# Optional: CSS/JS Dateien
if [ -d "$REPO_DIR/src/static" ]; then
    cp -r "$REPO_DIR/src/static/"* "$INSTALL_DIR/static/" 2>/dev/null || true
    log_success "Static files kopiert"
fi

# Optional: Config Dateien
if [ -d "$REPO_DIR/src/config" ]; then
    cp -r "$REPO_DIR/src/config/"* "$INSTALL_DIR/config/" 2>/dev/null || true
    log_success "Config files kopiert"
fi

log_step "6/9 - Erstelle Python Virtual Environment..."

cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
log_success "Virtual Environment erstellt"

log_step "7/9 - Installiere Python-Pakete..."

pip install -q --upgrade pip
pip install -q -r requirements.txt
log_success "Python-Pakete installiert"

log_step "8/9 - Erstelle Management-Scripts..."

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

# update.sh
cat > "$INSTALL_DIR/update.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
echo "📦 Aktualisiere Dependencies..."
source venv/bin/activate
pip install -q --upgrade -r requirements.txt
echo "✓ Dependencies aktualisiert"
EOF
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

log_step "9/9 - Erstelle Dokumentation..."

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
| `./update.sh` | Dependencies aktualisieren |

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

### Dependencies hinzufügen
```bash
source venv/bin/activate
pip install paket-name
pip freeze > requirements.txt
```

## 🐳 Als Systemd Service (Optional)

### Service installieren
```bash
sudo cp edgard-installer.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable edgard-installer
sudo systemctl start edgard-installer
```

### Service verwalten
```bash
sudo systemctl status edgard-installer
sudo systemctl restart edgard-installer
sudo systemctl stop edgard-installer
```

## 📝 Logs

Logs werden in `logs/server.log` gespeichert:
```bash
tail -f logs/server.log
# oder
./logs.sh
```

## 🛠️ Troubleshooting

### Port bereits belegt
```bash
# Prüfen welcher Prozess Port 5000 verwendet
sudo lsof -i :5000

# Prozess beenden
kill -9 <PID>
```

### Dependencies-Probleme
```bash
./update.sh
# oder
source venv/bin/activate
pip install --upgrade -r requirements.txt
```

### Virtual Environment neu erstellen
```bash
rm -rf venv/
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## 📦 Repository-Updates

Um Updates aus dem Repository zu holen:
```bash
cd /pfad/zum/repository
git pull
./setup.sh  # Setup erneut ausführen
```

## 🔐 Sicherheit

- Server läuft auf `0.0.0.0` (alle Interfaces)
- Für Produktiv-Umgebungen: Reverse Proxy (nginx/Apache) verwenden
- Firewall-Regeln anpassen
- HTTPS konfigurieren

## 📞 Support

Bei Problemen:
1. Logs prüfen: `./logs.sh`
2. Status prüfen: `./status.sh`
3. Neu starten: `./restart.sh`

EOFREADME

log_success "README.md erstellt"

# Systemd Service
cat > "$INSTALL_DIR/edgard-installer.service" << EOFSERVICE
[Unit]
Description=Edgard Home Installer Web Interface
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start.sh
Restart=always
RestartSec=10
StandardOutput=append:$INSTALL_DIR/logs/server.log
StandardError=append:$INSTALL_DIR/logs/server.log

[Install]
WantedBy=multi-user.target
EOFSERVICE

log_success "edgard-installer.service erstellt"

# .gitignore
cat > "$INSTALL_DIR/.gitignore" << 'EOF'
venv/
*.pyc
__pycache__/
*.log
logs/*.log
config/*.json
!config/*.example.json
*.db
*.sqlite
.DS_Store
EOF

log_success ".gitignore erstellt"

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
echo "  📁 Repository: $REPO_DIR"
echo "  🐍 Python venv: $INSTALL_DIR/venv"
echo

log_info "📂 Kopierte Dateien:"
tree -L 2 "$INSTALL_DIR" 2>/dev/null || find "$INSTALL_DIR" -maxdepth 2 -type f | head -20
echo

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    log_warning "⚠️  Fehlende Dateien - Bitte ergänzen:"
    for file in "${MISSING_FILES[@]}"; do
        echo "     $file → $INSTALL_DIR/${file#src/}"
    done
    echo
fi

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
echo "  4️⃣  Optional - Als Service:"
echo "     sudo cp edgard-installer.service /etc/systemd/system/"
echo "     sudo systemctl enable --now edgard-installer"
echo

log_info "📋 Verfügbare Befehle:"
echo "     ./start.sh    - Server starten"
echo "     ./stop.sh     - Server stoppen"
echo "     ./restart.sh  - Server neu starten"
echo "     ./status.sh   - Status anzeigen"
echo "     ./logs.sh     - Logs verfolgen"
echo "     ./update.sh   - Dependencies aktualisieren"
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
