#!/usr/bin/env python3
"""
Homeboi Web Dashboard - Simple web interface for managing Homeboi services
"""

import os
import subprocess
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
import re
import docker

def _read_homeboi_version() -> str:
    env_version = os.environ.get("HOMEBOI_VERSION", "").strip()
    if env_version:
        return env_version
    for path in ("/homeboi/VERSION",):
        try:
            with open(path, "r", encoding="utf-8") as f:
                version_raw = f.read().strip()
                if version_raw:
                    return version_raw
        except OSError:
            pass
    return "0.0.1"

def _read_file(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()
    except OSError:
        return ""

def _extract_xml_tag(text: str, tag: str) -> str:
    match = re.search(rf"<{re.escape(tag)}>([^<]+)</{re.escape(tag)}>", text)
    return match.group(1).strip() if match else ""

def _extract_xml_attr(text: str, attr: str) -> str:
    match = re.search(rf'{re.escape(attr)}="([^"]*)"', text)
    return match.group(1).strip() if match else ""

def _parse_env(text: str) -> dict:
    result: dict[str, str] = {}
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'").strip('"')
        if key:
            result[key] = value
    return result

def _http_json(url: str, headers: dict | None = None, timeout: float = 3.0):
    req = Request(url, headers=headers or {})
    with urlopen(req, timeout=timeout) as resp:
        data = resp.read()
        return json.loads(data.decode("utf-8", errors="ignore"))

def _container_http_base(name: str, port: int) -> str | None:
    try:
        client = docker.from_env()
        container = client.containers.get(name)
        networks = (container.attrs.get("NetworkSettings", {}).get("Networks") or {}).values()
        for net in networks:
            ip = (net or {}).get("IPAddress")
            if ip:
                return f"http://{ip}:{port}"
    except Exception:
        return None
    return None

def _best_base(name: str, port: int, fallback_host: str) -> str:
    return _container_http_base(name, port) or f"http://{fallback_host}:{port}"

class HomeBoiHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            self.serve_dashboard()
        elif self.path == '/api/status':
            self.serve_api_status()
        elif self.path == '/api/setup':
            self.serve_api_setup()
        elif self.path.startswith('/api/logs/'):
            service = self.path.split('/')[-1]
            self.serve_logs(service)
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path.startswith('/api/restart/'):
            service = self.path.split('/')[-1]
            self.restart_service(service)
        else:
            self.send_error(404)

    def serve_dashboard(self):
        homeboi_version = f"v{_read_homeboi_version()}"
        html = """
<!DOCTYPE html>
<html>
<head>
    <title>🏠 Homeboi Dashboard</title>
    <meta name="theme-color" content="#1a1a1a">
    <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20viewBox='0%200%2064%2064'%3E%3Crect%20width='64'%20height='64'%20rx='12'%20fill='%231a1a1a'/%3E%3Cg%20fill='%23ff69b4'%3E%3Crect%20x='18'%20y='14'%20width='10'%20height='36'/%3E%3Crect%20x='36'%20y='14'%20width='10'%20height='36'/%3E%3Crect%20x='18'%20y='28'%20width='28'%20height='10'/%3E%3C/g%3E%3C/svg%3E">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { 
            font-family: 'Courier New', monospace; 
            margin: 0; 
            padding: 20px; 
            background: #1a1a1a; 
            color: #ffffff;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        .ascii-header { 
            text-align: center; 
            margin-bottom: 40px; 
            font-family: monospace;
        }
        .ascii-art {
            color: #ff69b4;
            font-size: 14px;
            line-height: 1.2;
            white-space: pre;
            margin-bottom: 20px;
        }
        .subtitle {
            color: #00d1d1;
            font-size: 18px;
            margin-bottom: 10px;
        }
        .version {
            color: #ffeb3b;
            font-size: 16px;
        }
        .services { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); 
            gap: 20px; 
            margin-top: 30px;
        }
        .service { 
            background: #2a2a2a; 
            border: 1px solid #444; 
            border-radius: 8px; 
            padding: 20px; 
            transition: border-color 0.3s;
        }
        .service:hover { border-color: #ff69b4; }
        .service-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        .service-name { 
            font-weight: bold; 
            font-size: 18px;
            color: #ffffff;
        }
        .status { 
            padding: 6px 12px; 
            border-radius: 20px; 
            font-size: 12px; 
            font-weight: bold; 
        }
        .running { background: #28a745; color: white; }
        .stopped { background: #dc3545; color: white; }
        .service-url { margin-top: 15px; }
        .service-url a { 
            color: #00d1d1; 
            text-decoration: none; 
            font-family: monospace;
            padding: 8px 12px;
            border: 1px solid #00d1d1;
            border-radius: 4px;
            display: inline-block;
            transition: all 0.3s;
        }
        .service-url a:hover { 
            background: #00d1d1; 
            color: #1a1a1a; 
        }
        .checklist a {
            color: #00d1d1;
            text-decoration: none;
            border-bottom: 1px dotted #00d1d1;
        }
        .checklist a:hover { text-decoration: underline; }
        .refresh { 
            margin-bottom: 20px; 
            text-align: center; 
        }
        button { 
            background: #ff69b4; 
            color: #1a1a1a; 
            border: none; 
            padding: 12px 24px; 
            border-radius: 4px; 
            cursor: pointer; 
            font-family: monospace;
            font-weight: bold;
            font-size: 14px;
        }
        button:hover { background: #ff1493; }
        .status-section {
            background: #2a2a2a;
            border: 1px solid #444;
            border-radius: 8px;
            padding: 20px;
            margin-bottom: 30px;
        }
        .section-title {
            color: #ff69b4;
            font-size: 20px;
            font-weight: bold;
            margin-bottom: 15px;
            border-bottom: 1px solid #444;
            padding-bottom: 10px;
        }
        .checklist {
            margin: 0;
            padding-left: 18px;
            color: #ddd;
        }
        .checklist li { margin: 8px 0; }
        .todo { color: #ffeb3b; }
        .done { color: #28a745; }
        .muted { color: #aaa; }
    </style>
</head>
<body>
    <div class="container">
        <div class="ascii-header">
            <div class="ascii-art">        ██╗  ██╗ ██████╗ ███╗   ███╗███████╗██████╗  ██████╗ ██╗
        ██║  ██║██╔═══██╗████╗ ████║██╔════╝██╔══██╗██╔═══██╗██║
        ███████║██║   ██║██╔████╔██║█████╗  ██████╔╝██║   ██║██║
        ██╔══██║██║   ██║██║╚██╔╝██║██╔══╝  ██╔══██╗██║   ██║██║
        ██║  ██║╚██████╔╝██║ ╚═╝ ██║███████╗██████╔╝╚██████╔╝██║
        ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝</div>
            <div class="subtitle">HOME MEDIA STACK AUTOMATION</div>
            <div class="muted" style="margin-bottom: 10px;">Status + one-time setup checklist for the stack</div>
            <div class="version">""" + homeboi_version + """</div>
        </div>
        
        <div class="refresh">
            <button onclick="location.reload()">🔄 Refresh Status</button>
        </div>
        
        <div class="status-section">
            <div class="section-title">📊 Services Status</div>
            <div class="services" id="services">
                Loading services...
            </div>
        </div>

        <div class="status-section">
            <div class="section-title">🧭 Setup Checklist</div>
            <ul class="checklist" id="setup">
                Loading setup status...
            </ul>
            <div class="muted" style="margin-top: 10px;">
                Tip: Sonarr/Radarr/Prowlarr/Bazarr use the shared credentials from your Homeboi wizard.
                Find them by running <span style="color:#00d1d1;">homeboi</span> on the server and selecting <span style="color:#00d1d1;">Edit Settings</span>.
            </div>
        </div>
    </div>

    <script>
        let preferences = { primaryMediaServer: 'jellyfin', primaryRequestApp: 'jellyseerr' };

        const services = [
            {name: 'Plex', port: '32400', path: '/web', emoji: '📀', desc: 'Media server (manual sign-in/claim)'},
            {name: 'Jellyfin', port: '8096', path: '', emoji: '🎞', desc: 'Media server (usually auto-initialized)'},
            {name: 'Overseerr', port: '5055', path: '', emoji: '🎭', desc: 'Requests for Plex (first admin is manual)'},
            {name: 'Jellyseerr', port: '5056', path: '', emoji: '🎭', desc: 'Requests for Jellyfin/Plex (first admin is manual)'},
            {name: 'SABnzbd', port: '8080', path: '', emoji: '📦', desc: 'Usenet downloader (used by Sonarr/Radarr)'},
            {name: 'Prowlarr', port: '9696', path: '', emoji: '🔍', desc: 'Indexer manager (feeds Sonarr/Radarr)'},
            {name: 'Sonarr', port: '8989', path: '', emoji: '📺', desc: 'TV automation (talks to Prowlarr + SABnzbd)'},
            {name: 'Radarr', port: '7878', path: '', emoji: '🎬', desc: 'Movie automation (talks to Prowlarr + SABnzbd)'},
            {name: 'Bazarr', port: '6767', path: '', emoji: '💬', desc: 'Subtitle automation (uses Sonarr/Radarr)'}
        ];

        function orderedServices() {
            const primaryMedia = (preferences.primaryMediaServer || 'jellyfin').toLowerCase();
            const primaryRequest = (preferences.primaryRequestApp || 'jellyseerr').toLowerCase();

            const byName = Object.fromEntries(services.map(s => [s.name.toLowerCase(), s]));
            const order = [];

            if (primaryMedia === 'plex') {
                order.push('plex');
                order.push(primaryRequest === 'overseerr' ? 'overseerr' : 'jellyseerr');
                order.push('sonarr', 'radarr', 'prowlarr', 'sabnzbd', 'bazarr');
                order.push('jellyfin');
                order.push(primaryRequest === 'overseerr' ? 'jellyseerr' : 'overseerr');
            } else {
                order.push('jellyfin');
                order.push(primaryRequest === 'jellyseerr' ? 'jellyseerr' : 'overseerr');
                order.push('sonarr', 'radarr', 'prowlarr', 'sabnzbd', 'bazarr');
                order.push('plex');
                order.push(primaryRequest === 'jellyseerr' ? 'overseerr' : 'jellyseerr');
            }

            return order.map(k => byName[k]).filter(Boolean);
        }

        async function loadServices() {
            try {
                const response = await fetch('/api/status');
                const data = await response.json();
                
                const container = document.getElementById('services');
                container.innerHTML = '';
                
                orderedServices().forEach(service => {
                    const containerName = service.name.toLowerCase();
                    const isRunning = data[containerName] || false;
                    const url = `http://${window.location.hostname}:${service.port}${service.path}`;
                    
                    const serviceDiv = document.createElement('div');
                    serviceDiv.className = 'service';
                    serviceDiv.innerHTML = `
                        <div class="service-header">
                            <div class="service-name">${service.emoji} ${service.name}</div>
                            <div class="status ${isRunning ? 'running' : 'stopped'}">
                                ${isRunning ? '🟢 Running' : '🔴 Stopped'}
                            </div>
                        </div>
                        <div class="muted" style="margin-top: 2px;">${service.desc || ''}</div>
                        <div class="service-url">
                            <a href="${url}" target="_blank">🔗 Open ${service.name}</a>
                        </div>
                    `;
                    container.appendChild(serviceDiv);
                });
            } catch (error) {
                document.getElementById('services').innerHTML = 'Error loading services';
            }
        }

        function li(status, html) {
            const cls = status === 'done' ? 'done' : (status === 'todo' ? 'todo' : 'muted');
            return `<li class="${cls}">${html}</li>`;
        }

        async function loadSetup() {
            const container = document.getElementById('setup');
            try {
                const response = await fetch('/api/setup');
                const data = await response.json();
                preferences = data.preferences || preferences;

                const items = [];

                const prefs = data.preferences || {};
                const primaryMedia = (prefs.primaryMediaServer || 'jellyfin').toLowerCase();
                const primaryRequests = (prefs.primaryRequestApp || 'jellyseerr').toLowerCase();

                function jellyfinStep() {
                    if (data.jellyfin?.startupWizardCompleted) {
                        return li('done', `Jellyfin is initialized (server name set).`);
                    } else if (data.jellyfin?.reachable === false) {
                        return li('muted', `Jellyfin not reachable yet.`);
                    } else {
                        return li('todo', `Finish Jellyfin setup at <a href="http://${window.location.hostname}:8096" target="_blank">Jellyfin</a>.`);
                    }
                }

                function plexStep(primary = false) {
                    if (!primary) {
                        return li('muted', `Plex is optional for this setup.`);
                    }
                    if (data.plex?.claimed === true) {
                        return li('done', `Plex is claimed and ready.`);
                    }
                    return li('todo', `Claim Plex: open <a href="http://${window.location.hostname}:32400/web" target="_blank">Plex</a> and complete onboarding.`);
                }

                function overseerrStep(primary = false, dependsOnPlex = false) {
                    const status = data.overseerr?.initialized ? 'done' : (primary ? 'todo' : 'muted');
                    const label = primary ? 'Overseerr' : 'Overseerr (optional)';
                    const howto = dependsOnPlex
                        ? 'first complete Plex onboarding, then sign in with Plex'
                        : 'sign in with Plex';
                    return li(
                        status,
                        `${label}: ${data.overseerr?.initialized ? 'initialized' : 'not initialized'} — open <a href="http://${window.location.hostname}:5055" target="_blank">Overseerr</a> and ${howto} (this creates the first admin).`
                    );
                }

                function jellyseerrStep(primary = false) {
                    const status = data.jellyseerr?.initialized ? 'done' : (primary ? 'todo' : 'muted');
                    const label = primary ? 'Jellyseerr' : 'Jellyseerr (optional)';
                    return li(
                        status,
                        `${label}: ${data.jellyseerr?.initialized ? 'initialized' : 'not initialized'} — open <a href="http://${window.location.hostname}:5056" target="_blank">Jellyseerr</a> and connect it to Jellyfin/Plex (this creates the first admin).`
                    );
                }

                function sonarrStep() {
                    return data.sonarr?.hasSabnzbd
                        ? li('done', `Sonarr is connected to SABnzbd.`)
                        : li('todo', `Sonarr is not connected to SABnzbd yet.`);
                }
                function radarrStep() {
                    return data.radarr?.hasSabnzbd
                        ? li('done', `Radarr is connected to SABnzbd.`)
                        : li('todo', `Radarr is not connected to SABnzbd yet.`);
                }
                function prowlarrStep() {
                    return data.prowlarr?.applicationsConfigured
                        ? li('done', `Prowlarr is connected to Sonarr/Radarr.`)
                        : li('todo', `Prowlarr is not connected to Sonarr/Radarr yet.`);
                }

                function prowlarrIndexersStep() {
                    if (data.prowlarr?.reachable === false) {
                        return li('muted', `Prowlarr not reachable yet.`);
                    }
                    if (data.prowlarr?.hasIndexers === true) {
                        return li('done', `Prowlarr has indexers configured.`);
                    }
                    if (data.prowlarr?.hasIndexers === false) {
                        return li('todo', `No indexers configured — add one in <a href="http://${window.location.hostname}:9696" target="_blank">Prowlarr</a>.`);
                    }
                    return li('muted', `Prowlarr indexer status unknown yet.`);
                }

                // Ordering is based on the primary choice from the wizard.
                if (primaryMedia === 'plex') {
                    items.push(plexStep(true));
                    items.push(overseerrStep(primaryRequests === 'overseerr', true));
                    items.push(jellyfinStep());
                    items.push(jellyseerrStep(primaryRequests === 'jellyseerr'));
                } else {
                    items.push(jellyfinStep());
                    items.push(jellyseerrStep(primaryRequests === 'jellyseerr'));
                    items.push(plexStep(false));
                    items.push(overseerrStep(primaryRequests === 'overseerr', false));
                }

                items.push(sonarrStep());
                items.push(radarrStep());
                items.push(prowlarrStep());
                items.push(prowlarrIndexersStep());

                container.innerHTML = items.join('');
            } catch (e) {
                container.innerHTML = li('muted', 'Error loading setup status.');
            }
        }

        loadSetup();
        loadServices();
        setInterval(loadServices, 30000); // Refresh every 30 seconds
        setInterval(loadSetup, 30000);
    </script>
</body>
</html>"""
        
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())

    def serve_api_status(self):
        try:
            client = docker.from_env()
            containers = client.containers.list(all=True)
            
            status = {}
            for container in containers:
                name = container.name
                status[name] = container.status == 'running'
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(status).encode())
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())

    def serve_api_setup(self):
        """
        Best-effort setup checklist status. Keep this endpoint unauthenticated and avoid secrets.
        """
        result = {
            "preferences": {
                "primaryMediaServer": "jellyfin",
                "primaryRequestApp": "jellyseerr",
            },
            "plex": {"reachable": False, "claimed": None},
            "jellyfin": {"reachable": False, "startupWizardCompleted": None},
            "sonarr": {"reachable": False, "hasSabnzbd": None},
            "radarr": {"reachable": False, "hasSabnzbd": None},
            "prowlarr": {"reachable": False, "applicationsConfigured": None, "hasIndexers": None},
            "overseerr": {"reachable": False, "initialized": None},
            "jellyseerr": {"reachable": False, "initialized": None},
        }

        # Single source of truth: Homeboi root is mounted at /homeboi.
        homeboi_root = "/homeboi"
        env = _parse_env(_read_file(os.path.join(homeboi_root, "settings.env")))
        primary_media = (env.get("PRIMARY_MEDIA_SERVER") or "").strip().lower() or "jellyfin"
        primary_request = (env.get("PRIMARY_REQUEST_APP") or "").strip().lower() or "jellyseerr"
        if primary_media in ("jellyfin", "plex"):
            result["preferences"]["primaryMediaServer"] = primary_media
        if primary_request in ("jellyseerr", "overseerr"):
            result["preferences"]["primaryRequestApp"] = primary_request

        jellyfin_base = _best_base("jellyfin", 8096, "jellyfin")
        plex_base = _best_base("plex", 32400, "plex")
        overseerr_base = _best_base("overseerr", 5055, "overseerr")
        jellyseerr_base = _best_base("jellyseerr", 5056, "jellyseerr")
        sonarr_base = _best_base("sonarr", 8989, "sonarr")
        radarr_base = _best_base("radarr", 7878, "radarr")
        prowlarr_base = _container_http_base("prowlarr", 9696) or _best_base("gluetun", 9696, "gluetun") or "http://prowlarr:9696"

        # Plex identity (no key)
        try:
            req = Request(f"{plex_base}/identity")
            with urlopen(req, timeout=3.0) as resp:
                identity_xml = resp.read().decode("utf-8", errors="ignore")
            claimed = _extract_xml_attr(identity_xml, "claimed")
            result["plex"]["reachable"] = True
            if claimed in ("0", "1"):
                result["plex"]["claimed"] = (claimed == "1")
        except (URLError, HTTPError, ValueError):
            pass

        # Jellyfin public info (no key)
        try:
            jf = _http_json(f"{jellyfin_base}/System/Info/Public")
            result["jellyfin"]["reachable"] = True
            result["jellyfin"]["startupWizardCompleted"] = bool(jf.get("StartupWizardCompleted"))
        except (URLError, HTTPError, ValueError):
            pass

        # Request apps public settings (no key)
        try:
            osr = _http_json(f"{overseerr_base}/api/v1/settings/public")
            result["overseerr"]["reachable"] = True
            result["overseerr"]["initialized"] = bool(osr.get("initialized"))
        except (URLError, HTTPError, ValueError):
            pass
        try:
            jsr = _http_json(f"{jellyseerr_base}/api/v1/settings/public")
            result["jellyseerr"]["reachable"] = True
            result["jellyseerr"]["initialized"] = bool(jsr.get("initialized"))
        except (URLError, HTTPError, ValueError):
            pass

        # API key based checks: read keys from mounted Homeboi configs (no logging)
        sonarr_key = _extract_xml_tag(_read_file(os.path.join(homeboi_root, "configs/sonarr/config.xml")), "ApiKey")
        radarr_key = _extract_xml_tag(_read_file(os.path.join(homeboi_root, "configs/radarr/config.xml")), "ApiKey")
        prowlarr_key = _extract_xml_tag(_read_file(os.path.join(homeboi_root, "configs/prowlarr/config.xml")), "ApiKey")

        if sonarr_key:
            try:
                headers = {"X-Api-Key": sonarr_key}
                clients = _http_json(f"{sonarr_base}/api/v3/downloadclient", headers=headers)
                result["sonarr"]["reachable"] = True
                result["sonarr"]["hasSabnzbd"] = any(c.get("name") == "SABnzbd" for c in (clients or []))
            except (URLError, HTTPError, ValueError):
                pass

        if radarr_key:
            try:
                headers = {"X-Api-Key": radarr_key}
                clients = _http_json(f"{radarr_base}/api/v3/downloadclient", headers=headers)
                result["radarr"]["reachable"] = True
                result["radarr"]["hasSabnzbd"] = any(c.get("name") == "SABnzbd" for c in (clients or []))
            except (URLError, HTTPError, ValueError):
                pass

        if prowlarr_key:
            try:
                headers = {"X-Api-Key": prowlarr_key}
                apps = _http_json(f"{prowlarr_base}/api/v1/applications", headers=headers)
                result["prowlarr"]["reachable"] = True
                names = {a.get("name") for a in (apps or [])}
                result["prowlarr"]["applicationsConfigured"] = ("Sonarr" in names and "Radarr" in names)
            except (URLError, HTTPError, ValueError):
                pass
            try:
                headers = {"X-Api-Key": prowlarr_key}
                indexers = _http_json(f"{prowlarr_base}/api/v1/indexer", headers=headers)
                result["prowlarr"]["reachable"] = True
                result["prowlarr"]["hasIndexers"] = bool(indexers)
            except (URLError, HTTPError, ValueError):
                pass

        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(result).encode())

    def serve_logs(self, service):
        try:
            client = docker.from_env()
            container = client.containers.get(service)
            logs = container.logs(tail=100).decode('utf-8', errors='ignore')
            
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(logs.encode())
            
        except Exception as e:
            self.send_response(404)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(f"Error: {str(e)}".encode())

    def restart_service(self, service):
        try:
            client = docker.from_env()
            container = client.containers.get(service)
            container.restart()
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'restarted'}).encode())
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())

def main():
    port = int(os.environ.get('PORT', 6969))
    server = HTTPServer(('0.0.0.0', port), HomeBoiHandler)
    print(f"🏠 Homeboi Dashboard running on port {port}")
    server.serve_forever()

if __name__ == '__main__':
    main()
