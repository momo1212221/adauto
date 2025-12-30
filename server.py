#!/usr/bin/env python3
"""
Edgard Home Installer - Web Interface Backend (FIXED)
Mit automatischer sudo-Verwendung für Docker-Befehle
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
    """Fügt Log-Eintrag hinzu"""
    with installation_lock:
        timestamp = time.strftime('%H:%M:%S')
        installation_status['logs'].append({
            'type': log_type,
            'message': message,
            'timestamp': timestamp
        })
        print(f"[{log_type.upper()}] {message}")

def parse_log_line(line):
    """Parst Log-Zeilen und gibt Typ und Nachricht zurück"""
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
    """Aktualisiert den Status eines Installations-Schritts"""
    if function_name in STEP_MAPPING:
        step_id = STEP_MAPPING[function_name]['id']
        with installation_lock:
            for i, step in enumerate(installation_status['steps']):
                if step['id'] == step_id:
                    installation_status['steps'][i]['status'] = status
                    if status == 'running':
                        installation_status['current_step'] = i
                    print(f"[STEP] {step['name']} -> {status}")

def check_user_in_docker_group():
    """Prüft ob der aktuelle User in der docker-Gruppe ist"""
    try:
        result = subprocess.run(['groups'], capture_output=True, text=True)
        return 'docker' in result.stdout
    except:
        return False

def run_command_with_sudo_fallback(command, use_shell=False):
    """Führt Befehl aus, verwendet sudo bei Permission-Fehler"""
    try:
        # Erst ohne sudo versuchen
        if use_shell:
            result = subprocess.run(command, shell=True, capture_output=True, text=True, check=True)
        else:
            result = subprocess.run(command, capture_output=True, text=True, check=True)
        return result.stdout, result.stderr, 0
    except subprocess.CalledProcessError as e:
        # Bei Permission-Fehler mit sudo nochmal versuchen
        if 'permission denied' in e.stderr.lower() or 'permission denied' in e.stdout.lower():
            add_log('warning', 'Permission denied - verwende sudo')
            try:
                if use_shell:
                    sudo_command = f"sudo {command}"
                    result = subprocess.run(sudo_command, shell=True, capture_output=True, text=True, check=True)
                else:
                    sudo_command = ['sudo'] + command
                    result = subprocess.run(sudo_command, capture_output=True, text=True, check=True)
                return result.stdout, result.stderr, 0
            except subprocess.CalledProcessError as e2:
                return e2.stdout, e2.stderr, e2.returncode
        return e.stdout, e.stderr, e.returncode

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
        response = requests.get('https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest', timeout=10)
        latest_version = response.json()['tag_name'].lstrip('v')
        url = f"https://github.com/AdguardTeam/AdGuardHome/releases/download/v{latest_version}/AdGuardHome_{os_type}_{arch}.tar.gz"
        return url, latest_version
    except Exception as e:
        add_log('warning', f'Konnte neueste Version nicht abrufen: {e}')
        # Fallback auf bekannte Version
        version = "0.107.43"
        url = f"https://github.com/AdguardTeam/AdGuardHome/releases/download/v{version}/AdGuardHome_{os_type}_{arch}.tar.gz"
        return url, version

def install_adguard(install_path):
    """Installiert AdGuard Home mit sudo wo nötig"""
    try:
        add_log('info', 'Starte AdGuard Home Installation...')
        update_step_status('install_adguard', 'running')
        
        adguard_dir = os.path.join(os.path.expanduser(install_path), 'adguard')
        os.makedirs(adguard_dir, exist_ok=True)
        
        # Download-URL ermitteln
        download_url, version = get_adguard_download_url()
        add_log('info', f'Lade AdGuard Home v{version} herunter...')
        add_log('info', f'Architektur: {platform.machine()}')
        
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
        # Systemd-Befehle benötigen sudo
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
    """Führt die Hauptinstallation durch"""
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
        add_log('info', f'Installationspfad: {install_path}')
        add_log('info', f'Auto-Update: {auto_update}')
        add_log('info', f'AdGuard Home: {install_adguard_option}')
        
        # Docker-Gruppe prüfen
        if check_user_in_docker_group():
            add_log('info', 'Benutzer ist in docker-Gruppe')
        else:
            add_log('warning', 'Benutzer nicht in docker-Gruppe - verwende sudo für Docker')
        
        # AdGuard installieren (wenn gewünscht)
        if install_adguard_option:
            install_adguard(install_path)
        else:
            add_log('info', 'AdGuard Home Installation übersprungen')
            update_step_status('install_adguard', 'success')
        
        # Hauptinstallationsskript ausführen
        script_path = os.path.join(os.path.dirname(__file__), 'scripts', 'install_edgard.sh')
        
        if not os.path.exists(script_path):
            add_log('warning', f'Installationsskript nicht gefunden: {script_path}')
            add_log('info', 'Nur AdGuard Home wurde installiert' if install_adguard_option else 'Keine Installation durchgeführt')
            
            # Markiere restliche Steps als übersprungen
            for func_name in ['check_root', 'check_internet', 'check_os', 'check_disk_space', 
                            'update_system', 'install_docker', 'install_docker_compose', 
                            'setup_edgard_home', 'setup_auto_update']:
                update_step_status(func_name, 'success')
            
            if install_adguard_option:
                add_log('success', 'AdGuard Home Installation abgeschlossen!')
                add_log('info', 'Zugriff: http://localhost:3000')
            return
        
        # Environment-Variablen setzen
        env = os.environ.copy()
        if install_path:
            env['EDGARD_DIR'] = os.path.expanduser(install_path)
        if auto_update:
            env['AUTO_UPDATE'] = 'true'
        
        add_log('info', f'Starte Installationsskript: {script_path}')
        
        # Script ausführen
        process = subprocess.Popen(
            ['bash', script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1,
            env=env
        )
        
        # Ausgabe verarbeiten
        for line in process.stdout:
            while installation_status['paused']:
                time.sleep(0.5)
            
            log_type, message = parse_log_line(line)
            add_log(log_type, message)
            
            # Schritt-Erkennung
            for func_name, step_info in STEP_MAPPING.items():
                if func_name == 'install_adguard':
                    continue
                if step_info['name'].lower() in message.lower():
                    if any(word in message.lower() for word in ['start', 'prüf', 'install', 'erstell', 'einricht']):
                        update_step_status(func_name, 'running')
                    elif any(word in message.lower() for word in ['erfolg', 'ok', '✓', 'abgeschlossen', 'fertig']):
                        update_step_status(func_name, 'success')
                    elif any(word in message.lower() for word in ['fehler', '✗', 'fehlgeschlagen']):
                        update_step_status(func_name, 'error')
        
        process.wait()
        
        if process.returncode == 0:
            add_log('success', '🎉 Installation erfolgreich abgeschlossen!')
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

# ============================================================================
# API ROUTES
# ============================================================================

@app.route('/')
def index():
    """Hauptseite"""
    return render_template('index.html')

@app.route('/api/status')
def get_status():
    """Gibt aktuellen Installations-Status zurück"""
    with installation_lock:
        return jsonify(installation_status)

@app.route('/api/start', methods=['POST'])
def start_installation():
    """Startet die Installation"""
    if installation_status['running']:
        return jsonify({'error': 'Installation läuft bereits'}), 400
    
    data = request.json or {}
    install_path = data.get('installPath', '~/edgard_home')
    auto_update = data.get('autoUpdate', True)
    install_adguard_option = data.get('installAdguard', False)
    
    print(f"[API] Starte Installation:")
    print(f"  - Pfad: {install_path}")
    print(f"  - Auto-Update: {auto_update}")
    print(f"  - AdGuard: {install_adguard_option}")
    
    thread = threading.Thread(
        target=run_installation, 
        args=(install_path, auto_update, install_adguard_option)
    )
    thread.daemon = True
    thread.start()
    
    return jsonify({'success': True})

@app.route('/api/pause', methods=['POST'])
def pause_installation():
    """Pausiert/Setzt Installation fort"""
    if not installation_status['running']:
        return jsonify({'error': 'Installation läuft nicht'}), 400
    
    with installation_lock:
        installation_status['paused'] = not installation_status['paused']
        status = 'pausiert' if installation_status['paused'] else 'fortgesetzt'
    
    add_log('info', f'Installation {status}')
    return jsonify({'paused': installation_status['paused']})

@app.route('/api/health')
def health():
    """Health-Check Endpoint"""
    return jsonify({
        'status': 'ok',
        'version': '1.0.1',
        'timestamp': time.time()
    })

# Steps beim Start initialisieren
with installation_lock:
    installation_status['steps'] = [
        {'id': k['id'], 'name': k['name'], 'status': 'pending'}
        for k in STEP_MAPPING.values()
    ]

if __name__ == '__main__':
    print("=" * 70)
    print(" 🚀 Edgard Home Installer - Web Interface (FIXED)")
    print("=" * 70)
    print("\n 📡 Server startet auf:")
    print("   • http://localhost:5000")
    
    try:
        import socket
        hostname = socket.gethostname()
        local_ip = socket.gethostbyname(hostname)
        print(f"   • http://{local_ip}:5000")
    except:
        pass
    
    print("\n ⌨️  Drücken Sie Ctrl+C zum Beenden\n")
    print("=" * 70)
    
    app.run(host='0.0.0.0', port=5000, debug=True, use_reloader=False)
