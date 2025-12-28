#!/bin/bash

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Banner
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║        🚀 EDGARD HOME INSTALLER - AUTO SETUP 🚀          ║"
    echo "║                                                           ║"
    echo "║         Alles wird automatisch installiert!               ║"
    echo "║         + AdGuard Home Integration                        ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

# Fehlerbehandlung
set -e
trap 'log_error "Setup fehlgeschlagen bei Zeile $LINENO"; exit 1' ERR

# Installation Directory
INSTALL_DIR="$HOME/edgard-installer"

show_banner

log_step "1/8 - Prüfe Systemvoraussetzungen..."
sleep 1

# Root-Check
if [ "$EUID" -eq 0 ]; then
    log_error "Bitte führen Sie dieses Script NICHT als root aus!"
    exit 1
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
    log_success "Betriebssystem: $NAME $VERSION"
else
    log_warning "Konnte OS nicht identifizieren, fahre trotzdem fort..."
fi

log_step "2/8 - Installiere System-Abhängigkeiten..."
sleep 1

log_info "Aktualisiere Paketliste..."
sudo apt update -qq

log_info "Installiere benötigte Pakete..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    git \
    net-tools \
    wget \
    tar \
    &> /dev/null

log_success "System-Abhängigkeiten installiert"

log_step "3/8 - Erstelle Projektverzeichnis..."
sleep 1

if [ -d "$INSTALL_DIR" ]; then
    log_warning "Verzeichnis existiert bereits: $INSTALL_DIR"
    read -p "Möchten Sie es neu erstellen? [j/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        log_info "Erstelle Backup..."
        mv "$INSTALL_DIR" "${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        log_success "Backup erstellt"
    else
        log_info "Verwende bestehendes Verzeichnis"
    fi
fi

mkdir -p "$INSTALL_DIR/templates"
cd "$INSTALL_DIR"
log_success "Verzeichnis erstellt: $INSTALL_DIR"

log_step "4/8 - Erstelle Python Virtual Environment..."
sleep 1

python3 -m venv venv
source venv/bin/activate
log_success "Virtual Environment erstellt und aktiviert"

log_step "5/8 - Installiere Python-Pakete..."
sleep 1

log_info "Erstelle requirements.txt..."
cat > requirements.txt << 'EOL'
flask==3.0.0
flask-cors==4.0.0
requests==2.31.0
EOL

log_info "Installiere Flask & Flask-CORS & Requests..."
pip install -q -r requirements.txt
log_success "Python-Pakete installiert"

log_step "6/8 - Erstelle Backend-Server (server.py)..."
sleep 1

cat > server.py << 'EOFPYTHON'
#!/usr/bin/env python3
"""
Edgard Home Installer - Web Interface Backend
"""

import os
import subprocess
import threading
import time
import platform
import requests
from flask import Flask, render_template, jsonify, request
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

installation_status = {
    'running': False,
    'paused': False,
    'current_step': 0,
    'steps': [],
    'logs': []
}

installation_lock = threading.Lock()

STEP_MAPPING = {
    'check_root': {'id': 'check_root', 'name': 'Benutzerrechte prüfen'},
    'check_internet': {'id': 'check_internet', 'name': 'Internetverbindung prüfen'},
    'check_os': {'id': 'check_os', 'name': 'Betriebssystem prüfen'},
    'check_disk_space': {'id': 'check_disk', 'name': 'Speicherplatz prüfen'},
    'update_system': {'id': 'update_system', 'name': 'System aktualisieren'},
    'install_docker': {'id': 'install_docker', 'name': 'Docker installieren'},
    'install_docker_compose': {'id': 'install_compose', 'name': 'Docker Compose installieren'},
    'install_adguard': {'id': 'install_adguard', 'name': 'AdGuard Home installieren'},
    'setup_edgard_home': {'id': 'setup_edgard', 'name': 'Edgard Home einrichten'},
    'setup_auto_update': {'id': 'setup_cron', 'name': 'Auto-Update konfigurieren'}
}

def add_log(log_type, message):
    with installation_lock:
        timestamp = time.strftime('%H:%M:%S')
        installation_status['logs'].append({
            'type': log_type,
            'message': message,
            'timestamp': timestamp
        })
        print(f"[{log_type.upper()}] {message}")

def parse_log_line(line):
    line = line.strip()
    if '[INFO]' in line:
        return 'info', line.split('[INFO]', 1)[1].strip()
    elif '[SUCCESS]' in line or '[✓]' in line:
        return 'success', line.split('[SUCCESS]', 1)[1].strip() if '[SUCCESS]' in line else line.split('[✓]', 1)[1].strip()
    elif '[WARNING]' in line or '[!]' in line:
        return 'warning', line.split('[WARNING]', 1)[1].strip() if '[WARNING]' in line else line.split('[!]', 1)[1].strip()
    elif '[ERROR]' in line or '[✗]' in line:
        return 'error', line.split('[ERROR]', 1)[1].strip() if '[ERROR]' in line else line.split('[✗]', 1)[1].strip()
    else:
        return 'info', line

def update_step_status(function_name, status):
    if function_name in STEP_MAPPING:
        step_id = STEP_MAPPING[function_name]['id']
        with installation_lock:
            for i, step in enumerate(installation_status['steps']):
                if step['id'] == step_id:
                    installation_status['steps'][i]['status'] = status
                    if status == 'running':
                        installation_status['current_step'] = i
                    print(f"[STEP] {step['name']} -> {status}")

def get_adguard_download_url():
    """Ermittelt die richtige AdGuard Home Download-URL für das System"""
    machine = platform.machine().lower()
    system = platform.system().lower()
    
    # Architektur ermitteln
    if machine in ['x86_64', 'amd64']:
        arch = 'amd64'
    elif machine in ['aarch64', 'arm64']:
        arch = 'arm64'
    elif machine.startswith('arm'):
        arch = 'armv7'
    else:
        arch = 'amd64'  # Fallback
    
    # Betriebssystem
    if system == 'linux':
        os_type = 'linux'
    elif system == 'darwin':
        os_type = 'darwin'
    else:
        os_type = 'linux'  # Fallback
    
    # Neueste Version von GitHub holen
    try:
        response = requests.get('https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest')
        latest_version = response.json()['tag_name'].lstrip('v')
        url = f"https://github.com/AdguardTeam/AdGuardHome/releases/download/v{latest_version}/AdGuardHome_{os_type}_{arch}.tar.gz"
        return url, latest_version
    except:
        # Fallback auf bekannte Version
        version = "0.107.43"
        url = f"https://github.com/AdguardTeam/AdGuardHome/releases/download/v{version}/AdGuardHome_{os_type}_{arch}.tar.gz"
        return url, version

def install_adguard(install_path):
    """Installiert AdGuard Home"""
    try:
        add_log('info', 'Starte AdGuard Home Installation...')
        update_step_status('install_adguard', 'running')
        
        adguard_dir = os.path.join(os.path.expanduser(install_path), 'adguard')
        os.makedirs(adguard_dir, exist_ok=True)
        
        # Download-URL ermitteln
        download_url, version = get_adguard_download_url()
        add_log('info', f'Lade AdGuard Home v{version} herunter...')
        add_log('info', f'URL: {download_url}')
        
        # Download
        tar_file = os.path.join(adguard_dir, 'AdGuardHome.tar.gz')
        subprocess.run(['wget', '-O', tar_file, download_url], check=True, capture_output=True)
        add_log('success', 'Download abgeschlossen')
        
        # Entpacken
        add_log('info', 'Entpacke AdGuard Home...')
        subprocess.run(['tar', '-xzf', tar_file, '-C', adguard_dir], check=True)
        os.remove(tar_file)
        add_log('success', 'AdGuard Home entpackt')
        
        # Executable-Rechte setzen
        adguard_binary = os.path.join(adguard_dir, 'AdGuardHome', 'AdGuardHome')
        os.chmod(adguard_binary, 0o755)
        
        # Systemd Service erstellen
        service_content = f"""[Unit]
Description=AdGuard Home
After=network.target

[Service]
Type=simple
User={os.getenv('USER')}
WorkingDirectory={os.path.join(adguard_dir, 'AdGuardHome')}
ExecStart={adguard_binary} -w {os.path.join(adguard_dir, 'AdGuardHome')}
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
"""
        
        service_file = os.path.join(adguard_dir, 'adguardhome.service')
        with open(service_file, 'w') as f:
            f.write(service_content)
        
        add_log('info', 'Installiere Systemd Service...')
        subprocess.run(['sudo', 'cp', service_file, '/etc/systemd/system/adguardhome.service'], check=True)
        subprocess.run(['sudo', 'systemctl', 'daemon-reload'], check=True)
        subprocess.run(['sudo', 'systemctl', 'enable', 'adguardhome'], check=True)
        subprocess.run(['sudo', 'systemctl', 'start', 'adguardhome'], check=True)
        
        add_log('success', 'AdGuard Home erfolgreich installiert!')
        add_log('info', 'Web-Interface: http://localhost:3000')
        add_log('info', 'DNS-Server: Port 53')
        update_step_status('install_adguard', 'success')
        
    except Exception as e:
        add_log('error', f'AdGuard Installation fehlgeschlagen: {str(e)}')
        update_step_status('install_adguard', 'error')
        raise

def run_installation(install_path, auto_update, install_adguard_option):
    try:
        with installation_lock:
            installation_status['running'] = True
            installation_status['paused'] = False
            installation_status['logs'] = []
            installation_status['steps'] = [
                {'id': k['id'], 'name': k['name'], 'status': 'pending'}
                for k in STEP_MAPPING.values()
            ]
        
        add_log('info', 'Starte Installation...')
        
        # AdGuard installieren (wenn gewünscht)
        if install_adguard_option:
            install_adguard(install_path)
        else:
            add_log('info', 'AdGuard Home Installation übersprungen')
            update_step_status('install_adguard', 'success')
        
        # Hauptinstallationsskript ausführen (optional)
        script_path = os.path.join(os.path.dirname(__file__), 'install_edgard.sh')
        
        if not os.path.exists(script_path):
            add_log('warning', f'Installationsskript nicht gefunden: {script_path}')
            add_log('info', 'Nur AdGuard Home wurde installiert')
            
            # Markiere restliche Steps als übersprungen
            for func_name in ['check_root', 'check_internet', 'check_os', 'check_disk_space', 
                            'update_system', 'install_docker', 'install_docker_compose', 
                            'setup_edgard_home', 'setup_auto_update']:
                update_step_status(func_name, 'success')
            
            if install_adguard_option:
                add_log('success', 'AdGuard Home Installation abgeschlossen!')
                add_log('info', 'Zugriff auf: http://localhost:3000')
                add_log('info', 'Für vollständige Edgard Home Installation:')
                add_log('info', f'  1. Kopieren Sie install_edgard.sh nach {os.path.dirname(__file__)}/')
                add_log('info', '  2. Starten Sie die Installation erneut')
            else:
                add_log('error', 'Keine Installation durchgeführt - kein Script gefunden')
            return
        
        env = os.environ.copy()
        if install_path:
            env['EDGARD_DIR'] = os.path.expanduser(install_path)
        if auto_update:
            env['AUTO_UPDATE'] = 'true'
        
        add_log('info', f'Starte Script: {script_path}')
        
        process = subprocess.Popen(
            ['bash', script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1,
            env=env
        )
        
        for line in process.stdout:
            while installation_status['paused']:
                time.sleep(0.5)
            
            log_type, message = parse_log_line(line)
            add_log(log_type, message)
            
            # Schritt-Erkennung
            for func_name, step_info in STEP_MAPPING.items():
                if func_name == 'install_adguard':
                    continue  # AdGuard wurde bereits behandelt
                if step_info['name'].lower() in message.lower():
                    if any(word in message.lower() for word in ['start', 'prüf', 'install', 'erstell', 'einricht']):
                        update_step_status(func_name, 'running')
                    elif any(word in message.lower() for word in ['erfolg', 'ok', '✓', 'abgeschlossen', 'fertig']):
                        update_step_status(func_name, 'success')
                    elif any(word in message.lower() for word in ['fehler', '✗', 'fehlgeschlagen']):
                        update_step_status(func_name, 'error')
        
        process.wait()
        
        if process.returncode == 0:
            add_log('success', 'Installation erfolgreich abgeschlossen!')
            add_log('info', 'Edgard Home: http://localhost:8080')
            if install_adguard_option:
                add_log('info', 'AdGuard Home: http://localhost:3000')
        else:
            add_log('error', f'Installation fehlgeschlagen (Exit Code: {process.returncode})')
    
    except Exception as e:
        add_log('error', f'Fehler: {str(e)}')
        import traceback
        traceback.print_exc()
    
    finally:
        with installation_lock:
            installation_status['running'] = False

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    with installation_lock:
        return jsonify(installation_status)

@app.route('/api/start', methods=['POST'])
def start_installation():
    if installation_status['running']:
        return jsonify({'error': 'Installation läuft bereits'}), 400
    
    data = request.json or {}
    install_path = data.get('installPath', '~/edgard_home')
    auto_update = data.get('autoUpdate', True)
    install_adguard_option = data.get('installAdguard', False)
    
    print(f"[API] Starte Installation: path={install_path}, auto={auto_update}, adguard={install_adguard_option}")
    
    thread = threading.Thread(target=run_installation, args=(install_path, auto_update, install_adguard_option))
    thread.daemon = True
    thread.start()
    
    return jsonify({'success': True})

@app.route('/api/pause', methods=['POST'])
def pause_installation():
    if not installation_status['running']:
        return jsonify({'error': 'Installation läuft nicht'}), 400
    
    with installation_lock:
        installation_status['paused'] = not installation_status['paused']
        status = 'pausiert' if installation_status['paused'] else 'fortgesetzt'
    
    add_log('info', f'Installation {status}')
    return jsonify({'paused': installation_status['paused']})

# Steps beim Start initialisieren
with installation_lock:
    installation_status['steps'] = [
        {'id': k['id'], 'name': k['name'], 'status': 'pending'}
        for k in STEP_MAPPING.values()
    ]

if __name__ == '__main__':
    print("=" * 60)
    print(" 🚀 Edgard Home Installer - Web Interface")
    print("=" * 60)
    print("\n Öffnen Sie im Browser:")
    print("   http://localhost:5000")
    import socket
    hostname = socket.gethostname()
    local_ip = socket.gethostbyname(hostname)
    print(f"   http://{local_ip}:5000")
    print("\n Drücken Sie Ctrl+C zum Beenden\n")
    
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
EOFPYTHON

chmod +x server.py
log_success "Backend-Server erstellt"

log_step "7/8 - Erstelle Frontend (templates/index.html)..."
sleep 1

cat > templates/index.html << 'EOFHTML'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Edgard Home Installation</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        @keyframes spin { to { transform: rotate(360deg); } }
        .animate-spin { animation: spin 1s linear infinite; }
        .gradient-bg { background: linear-gradient(135deg, #1e293b 0%, #1e40af 50%, #1e293b 100%); }
    </style>
</head>
<body class="gradient-bg min-h-screen p-6">
    <div class="max-w-6xl mx-auto">
        <div class="text-center mb-8">
            <div class="inline-flex items-center justify-center w-20 h-20 bg-blue-500 rounded-2xl mb-4 shadow-lg">
                <svg class="w-10 h-10 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 12h14M5 12a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v4a2 2 0 01-2 2M5 12a2 2 0 00-2 2v4a2 2 0 002 2h14a2 2 0 002-2v-4a2 2 0 00-2-2m-2-4h.01M17 16h.01"></path>
                </svg>
            </div>
            <h1 class="text-4xl font-bold text-white mb-2">Edgard Home Installation</h1>
            <p class="text-blue-200">Automatisierte Einrichtung mit AdGuard Home Integration</p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div class="lg:col-span-1 space-y-6">
                <div class="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20">
                    <h2 class="text-xl font-semibold text-white mb-4">Konfiguration</h2>
                    <div class="space-y-4">
                        <div>
                            <label class="block text-sm font-medium text-blue-200 mb-2">Installationspfad</label>
                            <input type="text" id="installPath" value="~/edgard_home" class="w-full px-3 py-2 bg-white/10 border border-white/20 rounded-lg text-white placeholder-blue-300 focus:outline-none focus:ring-2 focus:ring-blue-500"/>
                        </div>
                        <div class="flex items-center">
                            <input type="checkbox" id="autoUpdate" checked class="w-4 h-4 text-blue-500 rounded focus:ring-blue-500"/>
                            <label for="autoUpdate" class="ml-2 text-sm text-blue-200">Automatische Updates (täglich 03:00)</label>
                        </div>
                        <div class="border-t border-white/20 pt-4 mt-4">
                            <div class="flex items-center mb-2">
                                <input type="checkbox" id="installAdguard" class="w-4 h-4 text-green-500 rounded focus:ring-green-500"/>
                                <label for="installAdguard" class="ml-2 text-sm font-medium text-green-300">AdGuard Home installieren</label>
                            </div>
                            <p class="text-xs text-blue-300 ml-6">DNS-Adblocker & Privacy-Schutz</p>
                            <div class="mt-2 ml-6 text-xs text-blue-200 space-y-1">
                                <div>• Web-Interface: Port 3000</div>
                                <div>• DNS-Server: Port 53</div>
                                <div>• Blockiert Werbung & Tracker</div>
                            </div>
                        </div>
                    </div>
                </div>

                <div class="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20">
                    <h2 class="text-xl font-semibold text-white mb-4">Steuerung</h2>
                    <div class="space-y-3">
                        <button id="startBtn" class="w-full flex items-center justify-center gap-2 px-4 py-3 bg-blue-500 hover:bg-blue-600 text-white font-semibold rounded-lg transition-colors shadow-lg">
                            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20"><path d="M6.3 2.841A1.5 1.5 0 004 4.11V15.89a1.5 1.5 0 002.3 1.269l9.344-5.89a1.5 1.5 0 000-2.538L6.3 2.84z"></path></svg>
                            Installation starten
                        </button>
                        <button id="pauseBtn" disabled class="w-full flex items-center justify-center gap-2 px-4 py-3 bg-yellow-500 hover:bg-yellow-600 disabled:bg-gray-500 text-white font-semibold rounded-lg transition-colors disabled:cursor-not-allowed">
                            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 20 20"><path d="M5.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75A.75.75 0 007.25 3h-1.5zM12.75 3a.75.75 0 00-.75.75v12.5c0 .414.336.75.75.75h1.5a.75.75 0 00.75-.75V3.75a.75.75 0 00-.75-.75h-1.5z"></path></svg>
                            <span id="pauseBtnText">Pausieren</span>
                        </button>
                    </div>
                    <div id="progressContainer" class="mt-4 hidden">
                        <div class="flex justify-between text-sm text-blue-200 mb-2">
                            <span>Fortschritt</span>
                            <span id="progressPercent">0%</span>
                        </div>
                        <div class="w-full h-2 bg-white/20 rounded-full overflow-hidden">
                            <div id="progressBar" class="h-full bg-gradient-to-r from-blue-500 to-green-500 transition-all duration-500" style="width: 0%"></div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="lg:col-span-2 space-y-6">
                <div class="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20">
                    <h2 class="text-xl font-semibold text-white mb-4">Installationsschritte</h2>
                    <div id="stepsContainer" class="space-y-3"></div>
                </div>

                <div class="bg-white/10 backdrop-blur-lg rounded-xl p-6 border border-white/20">
                    <h2 class="text-xl font-semibold text-white mb-4">Installation Log</h2>
                    <div class="bg-black/30 rounded-lg p-4 h-64 overflow-y-auto font-mono text-sm" id="logsContainer">
                        <div class="text-gray-400 text-center py-8">Bereit zur Installation...</div>
                    </div>
                </div>
            </div>
        </div>

        <div class="mt-6 text-center space-y-2">
            <p class="text-sm text-blue-200">Nach erfolgreicher Installation:</p>
            <div class="flex flex-wrap justify-center gap-4 text-sm">
                <span class="font-mono text-white bg-blue-500/30 px-3 py-1 rounded">Edgard Home: http://localhost:8080</span>
                <span id="adguardInfo" class="hidden font-mono text-white bg-green-500/30 px-3 py-1 rounded">AdGuard Home: http://localhost:3000</span>
            </div>
        </div>
    </div>

    <script>
        const API_URL = window.location.origin + '/api';
        let isRunning = false;
        let isPaused = false;
        let pollInterval = null;

        const icons = {
            pending: '<div class="w-5 h-5 rounded-full border-2 border-gray-300"></div>',
            running: '<svg class="w-5 h-5 text-blue-500 animate-spin" fill="none" viewBox="0 0 24 24"><circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle><path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path></svg>',
            success: '<svg class="w-5 h-5 text-green-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path></svg>',
            error: '<svg class="w-5 h-5 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path></svg>'
        };

        const logIcons = {
            info: '<svg class="w-4 h-4 text-blue-500" fill="currentColor" viewBox="0 0 20 20"><path d="M2 5a2 2 0 012-2h7a2 2 0 012 2v4a2 2 0 01-2 2H9l-3 3v-3H4a2 2 0 01-2-2V5z"></path></svg>',
            success: '<svg class="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"></path></svg>',
            warning: '<svg class="w-4 h-4 text-yellow-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"></path></svg>',
            error: '<svg class="w-4 h-4 text-red-500" fill="currentColor" viewBox="0 0 20 20"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"></path></svg>'
        };

        // AdGuard Checkbox Event
        document.getElementById('installAdguard').addEventListener('change', function() {
            const adguardInfo = document.getElementById('adguardInfo');
            if (this.checked) {
                adguardInfo.classList.remove('hidden');
            } else {
                adguardInfo.classList.add('hidden');
            }
        });

        document.getElementById('startBtn').addEventListener('click', startInstallation);
        document.getElementById('pauseBtn').addEventListener('click', pauseInstallation);

        async function startInstallation() {
            const installPath = document.getElementById('installPath').value;
            const autoUpdate = document.getElementById('autoUpdate').checked;
            const installAdguard = document.getElementById('installAdguard').checked;

            try {
                const response = await fetch(`${API_URL}/start`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ installPath, autoUpdate, installAdguard })
                });

                if (response.ok) {
                    isRunning = true;
                    document.getElementById('startBtn').disabled = true;
                    document.getElementById('pauseBtn').disabled = false;
                    document.getElementById('progressContainer').classList.remove('hidden');
                    document.getElementById('installPath').disabled = true;
                    document.getElementById('autoUpdate').disabled = true;
                    document.getElementById('installAdguard').disabled = true;
                    startPolling();
                    
                    if (installAdguard) {
                        document.getElementById('adguardInfo').classList.remove('hidden');
                    }
                } else {
                    const data = await response.json();
                    alert('Fehler: ' + (data.error || 'Unbekannter Fehler'));
                }
            } catch (error) {
                console.error('Fehler:', error);
                alert('Fehler: Konnte keine Verbindung zum Server herstellen!');
            }
        }

        async function pauseInstallation() {
            try {
                const response = await fetch(`${API_URL}/pause`, { method: 'POST' });
                const data = await response.json();
                isPaused = data.paused;
                document.getElementById('pauseBtnText').textContent = isPaused ? 'Fortsetzen' : 'Pausieren';
            } catch (error) {
                console.error('Fehler beim Pausieren:', error);
            }
        }

        function startPolling() {
            pollInterval = setInterval(updateStatus, 1000);
        }

        function stopPolling() {
            if (pollInterval) {
                clearInterval(pollInterval);
                pollInterval = null;
            }
        }

        async function updateStatus() {
            try {
                const response = await fetch(`${API_URL}/status`);
                const data = await response.json();

                updateSteps(data.steps);
                updateLogs(data.logs);
                updateProgress(data.current_step, data.steps.length);

                if (!data.running && isRunning) {
                    isRunning = false;
                    document.getElementById('startBtn').disabled = false;
                    document.getElementById('pauseBtn').disabled = true;
                    document.getElementById('installPath').disabled = false;
                    document.getElementById('autoUpdate').disabled = false;
                    document.getElementById('installAdguard').disabled = false;
                    stopPolling();
                }
            } catch (error) {
                console.error('Fehler beim Abrufen des Status:', error);
            }
        }

        function updateSteps(steps) {
            const container = document.getElementById('stepsContainer');
            if (!steps || steps.length === 0) return;
            container.innerHTML = steps.map(step => `
                <div class="flex items-center gap-3 p-3 rounded-lg transition-all ${
                    step.status === 'running' ? 'bg-blue-500/20 border border-blue-500/50' :
                    step.status === 'success' ? 'bg-green-500/10 border border-green-500/30' :
                    step.status === 'error' ? 'bg-red-500/10 border border-red-500/30' :
                    'bg-white/5 border border-white/10'
                }">
                    ${icons[step.status] || icons.pending}
                    <span class="text-white flex-1">${step.name}</span>
                    ${step.status === 'running' ? '<span class="text-xs text-blue-300 animate-pulse">Läuft...</span>' : ''}
                </div>
            `).join('');
        }

        function updateLogs(logs) {
            const container = document.getElementById('logsContainer');
            if (logs.length === 0) return;

            container.innerHTML = logs.slice(-50).map(log => `
                <div class="flex items-start gap-2 mb-2">
                    ${logIcons[log.type] || logIcons.info}
                    <span class="text-gray-400 text-xs">${log.timestamp}</span>
                    <span class="flex-1 ${
                        log.type === 'success' ? 'text-green-400' :
                        log.type === 'error' ? 'text-red-400' :
                        log.type === 'warning' ? 'text-yellow-400' :
                        'text-blue-300'
                    }">${log.message}</span>
                </div>
            `).join('');

            container.scrollTop = container.scrollHeight;
        }

        function updateProgress(current, total) {
            if (total === 0) return;
            const percent = Math.round((current / total) * 100);
            document.getElementById('progressPercent').textContent = `${percent}%`;
            document.getElementById('progressBar').style.width = `${percent}%`;
        }

        // Initial laden der Steps
        updateStatus();
    </script>
</body>
</html>
EOFHTML

log_success "Frontend erstellt"

log_step "8/8 - Kopiere Ihr Installationsskript..."
sleep 1

# Prüfe ob install_edgard.sh im gleichen Verzeichnis liegt
SOURCE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install_edgard.sh"

if [ -f "$SOURCE_SCRIPT" ]; then
    cp "$SOURCE_SCRIPT" "$INSTALL_DIR/install_edgard.sh"
    chmod +x "$INSTALL_DIR/install_edgard.sh"
    log_success "Installationsskript kopiert"
else
    log_warning "install_edgard.sh nicht gefunden!"
    log_info "Bitte kopieren Sie Ihr install_edgard.sh nach: $INSTALL_DIR/"
    echo
    echo "Führen Sie dann aus:"
    echo "  cd $INSTALL_DIR"
    echo "  chmod +x install_edgard.sh"
fi

echo
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║              ✅ SETUP ERFOLGREICH ABGESCHLOSSEN! ✅         ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo
log_info "Installation Details:"
echo "  📁 Verzeichnis: $INSTALL_DIR"
echo "  🐍 Python venv: Aktiviert"
echo "  📦 Pakete: Flask, Flask-CORS, Requests"
echo "  🌐 Server: server.py"
echo "  🎨 Frontend: templates/index.html"
echo "  🛡️  AdGuard: Optional installierbar"
echo

log_step "Starte den Web-Server..."
echo
echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo

cd "$INSTALL_DIR"

# Erstelle Start-Script
cat > start.sh << 'EOFSTART'
#!/bin/bash
cd "$(dirname "$0")"
source venv/bin/activate
python3 server.py
EOFSTART

chmod +x start.sh

# Erstelle Systemd Service (optional)
cat > edgard-installer.service << EOFSERVICE
[Unit]
Description=Edgard Home Installer Web UI
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/start.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOFSERVICE

log_success "Start-Script erstellt: $INSTALL_DIR/start.sh"
log_info "Optional: Systemd Service erstellt (noch nicht aktiviert)"
echo

log_info "Nützliche Befehle:"
echo "  Starten:  $INSTALL_DIR/start.sh"
echo "  Oder:     cd $INSTALL_DIR && source venv/bin/activate && python3 server.py"
echo
echo "  Als Service installieren:"
echo "    sudo cp $INSTALL_DIR/edgard-installer.service /etc/systemd/system/"
echo "    sudo systemctl daemon-reload"
echo "    sudo systemctl enable edgard-installer"
echo "    sudo systemctl start edgard-installer"
echo

log_info "AdGuard Home Features:"
echo "  🛡️  DNS-basierte Werbeblocker"
echo "  🔒 Privacy-Schutz & Tracker-Blocking"
echo "  📊 Detaillierte Statistiken"
echo "  ⚙️  Anpassbare Blocklists"
echo "  🌐 Web-Interface: Port 3000"
echo "  📡 DNS-Server: Port 53"
echo

# Server automatisch starten
log_info "Starte Server in 3 Sekunden..."
echo -e "${YELLOW}Hinweis: Drücken Sie Ctrl+C um das Starten abzubrechen${NC}"
echo

sleep 3

source venv/bin/activate
python3 server.py
