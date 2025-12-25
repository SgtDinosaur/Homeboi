#!/bin/bash
# lib/dashboard.sh - Dashboard generation for Homeboi

# Generate dashboard content (like nodeboi's status display)
generate_dashboard() {
    local output=""
    
    # Check if any services exist
    local has_services=false
    for service in "${HOMEBOI_SERVICES[@]}"; do
        if docker ps -a --format "{{.Names}}" | grep -q "^${service}$" 2>/dev/null; then
            has_services=true
            break
        fi
    done
    
    # Only show services section if services exist
    if [[ "$has_services" == true ]]; then
        output+="Services Status"$'\n'
        output+="---------------"$'\n'
        
        # Show all services in order of user frequency: overseerr, jellyseerr, plex, jellyfin, radarr, sonarr, then the rest
        local services_to_check=("overseerr" "jellyseerr" "plex" "jellyfin" "radarr" "sonarr" "sabnzbd" "prowlarr" "bazarr" "web-dashboard" "home-assistant" "gluetun")
        
        # Service icons mapping
        declare -A SERVICE_ICONS=(
            ["plex"]="📀"
            ["jellyfin"]="🎞️" 
            ["overseerr"]="🎭"
            ["jellyseerr"]="🎭"
            ["sabnzbd"]="📦"
            ["gluetun"]="🛡️"
            ["prowlarr"]="🔍"
            ["sonarr"]="📺"
            ["radarr"]="🎬"
            ["bazarr"]="💬"
            ["transmission"]="📡"
            ["home-assistant"]="🏡"
            ["web-dashboard"]="🌐"
        )
        
        # Custom display names for services that need special formatting
        declare -A SERVICE_DISPLAY_NAMES=(
            ["web-dashboard"]="Homeboi-Web"
            ["home-assistant"]="Home-Assistant"
        )
        
        for service in "${services_to_check[@]}"; do
            local container_name="$service"
            
            # Map service directory names to actual container names where they differ
            case "$service" in
                "web-dashboard")
                    container_name="homeboi-web"
                    ;;
            esac
            
            if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$" 2>/dev/null; then
                continue
            fi
            
            local icon="${SERVICE_ICONS[$service]:-🔸}"
            local display_name="${SERVICE_DISPLAY_NAMES[$service]:-${service^}}"
            local status=$(get_service_status "$service")
            local status_circle=""
            local status_text=""
            
            case "$status" in
                "running")
                    status_circle="🟢"
                    status_text="Running"
                    ;;
                "unstable")
                    status_circle="🟡"
                    status_text="Unstable"
                    ;;
                "unhealthy")
                    status_circle="🔴"
                    status_text="Unhealthy"
                    ;;
                "restarting")
                    status_circle="🟡"
                    status_text="Restarting"
                    ;;
                "crashed")
                    status_circle="🔴"
                    status_text="Crashed"
                    ;;
                "starting")
                    status_circle="🟡"
                    status_text="Starting"
                    ;;
                "stopped")
                    status_circle="🔴"
                    status_text="Stopped"
                    ;;
                "disabled")
                    status_circle="⚫"
                    status_text="Disabled"
                    ;;
                "not_installed")
                    status_circle="⚫"
                    status_text="Not installed"
                    ;;
                *)
                    status_circle="⚫"
                    status_text="Unknown"
                    ;;
            esac
            
            # Get service URL if it has a web interface and is running
            local url_text=""
            if [[ "$status" == "running" ]] || [[ "$status" == "unstable" ]]; then
                local port="${SERVICE_PORTS[$service]}"
                if [[ -n "$port" ]]; then
                    # Get server IP from settings or auto-detect
                    local server_ip
                    if [[ -f "$HOMEBOI_CONFIG_FILE" ]]; then
                        server_ip=$(grep "^SERVER_IP=" "$HOMEBOI_CONFIG_FILE" | cut -d'=' -f2 2>/dev/null)
                    fi
                    
                    # If SERVER_IP is localhost or empty, try to auto-detect actual IP
                    if [[ -z "$server_ip" || "$server_ip" == "localhost" ]]; then
                        # Get the actual network IP
                        server_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "192.168.1.100")
                    fi
                    
                    local path=""
                    # No special paths needed - services work fine without them
                    
                    url_text="http://${server_ip}:${port}${path}"
                fi
            fi
            
            # Format with proper alignment (service name padded to 16 characters)
            local service_display=$(printf "%-16s" "${display_name}:")
            if [[ -n "$url_text" ]]; then
                output+="  ${status_circle} ${icon} ${service_display} ${status_text} - ${url_text}"$'\n'
            else
                output+="  ${status_circle} ${icon} ${service_display} ${status_text}"$'\n'
            fi
        done
        
        
    else
        output+="Services"$'\n'
        output+="--------"$'\n'
        
        # Check if we're in installation wizard mode
        if [[ "${HOMEBOI_WIZARD_MODE:-}" == "true" ]]; then
            output+="  🚀 Installation wizard in progress"$'\n'
            output+="  Follow the prompts to complete setup"$'\n'
        else
            output+="  No services deployed yet"$'\n'
            output+="  Run 'Launch Stack' to deploy"$'\n'
        fi
    fi
    
    
    echo -e "$output"
}

# Update dashboard cache (background process like nodeboi)
update_dashboard_cache() {
    local cache_file="$HOMEBOI_HOME/cache/dashboard.cache"
    local lock_file="$HOMEBOI_HOME/cache/dashboard.lock"
    
    # Create cache directory if it doesn't exist
    mkdir -p "$(dirname "$cache_file")"
    
    # Prevent multiple updates running at once
    if [[ -f "$lock_file" ]]; then
        local lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            return 0  # Already updating
        fi
    fi
    
    # Write PID to lock file
    echo $$ > "$lock_file"
    
    # Generate new dashboard content
    local dashboard_content
    dashboard_content=$(generate_dashboard)
    
    # Write to cache file atomically
    echo -e "$dashboard_content" > "${cache_file}.tmp" && mv "${cache_file}.tmp" "$cache_file"
    
    # Remove lock
    rm -f "$lock_file"
}

# Start background dashboard updates (like nodeboi)
start_dashboard_updates() {
    # Kill any existing background updates
    stop_dashboard_updates
    
    # Start background process
    (
        while true; do
            update_dashboard_cache
            sleep 2  # Update every 2 seconds like nodeboi
        done
    ) >/dev/null 2>&1 &
    
    local bg_pid=$!
    echo "$bg_pid" > "$HOMEBOI_HOME/cache/dashboard_bg.pid"
    
    # Initial update
    update_dashboard_cache
}

# Stop background dashboard updates
stop_dashboard_updates() {
    local pid_file="$HOMEBOI_HOME/cache/dashboard_bg.pid"
    
    if [[ -f "$pid_file" ]]; then
        local bg_pid=$(cat "$pid_file" 2>/dev/null)
        if [[ -n "$bg_pid" ]] && kill -0 "$bg_pid" 2>/dev/null; then
            kill "$bg_pid" 2>/dev/null
        fi
        rm -f "$pid_file"
    fi
    
    # Clean up any orphaned processes
    pkill -f "dashboard.cache" 2>/dev/null || true
}
