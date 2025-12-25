#!/bin/bash
# lib/config.sh - Configuration management for Homeboi

# Configuration file paths
HOMEBOI_CONFIG_FILE="$HOMEBOI_HOME/settings.env"

# Check if configuration exists
config_exists() {
    [[ -f "$HOMEBOI_CONFIG_FILE" ]]
}

# Run initial setup
run_initial_setup() {
    echo -e "${UI_PRIMARY}Running Homeboi configuration setup...${UI_RESET}"
    echo -e "${UI_MUTED}Use the setup wizard to configure your media stack${UI_RESET}"
    echo
    
    # Call the setup wizard directly
    run_minimal_wizard
    
    return 0
}

# View current configuration
view_configuration() {
    if ! config_exists; then
        echo -e "${UI_WARNING}! Configuration file not found${UI_RESET}"
        echo -e "${UI_MUTED}Run 'Initial Setup' to create configuration${UI_RESET}"
        return 1
    fi
    
    echo -e "${UI_BOLD}Current Homeboi Configuration:${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    
    # Display the settings.env file with syntax highlighting for active settings
    grep -E "^[^#]" "$HOMEBOI_CONFIG_FILE" | while IFS='=' read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
            printf "  ${UI_SUCCESS}%-20s${UI_RESET} = ${UI_PRIMARY}%s${UI_RESET}\n" "$key" "$value"
        fi
    done
    
    echo
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo -e "${UI_MUTED}Showing active settings only. Edit ${HOMEBOI_CONFIG_FILE} to view all options.${UI_RESET}"
}

# Edit configuration
edit_configuration() {
    if ! config_exists; then
        echo -e "${UI_WARNING}! Configuration file not found${UI_RESET}"
        echo -e "${UI_MUTED}Run 'Initial Setup' to create configuration first${UI_RESET}"
        return 1
    fi
    
    local editor="${EDITOR:-nano}"
    
    echo -e "${UI_PRIMARY}Opening configuration in $editor...${UI_RESET}"
    
    if "$editor" "$HOMEBOI_CONFIG_FILE"; then
        echo -e "${UI_SUCCESS}✓ Configuration saved${UI_RESET}"
        return 0
    else
        echo -e "${UI_ERROR}✗ Failed to edit configuration${UI_RESET}"
        return 1
    fi
}

# Reset configuration
reset_configuration() {
    if ! config_exists; then
        echo -e "${UI_WARNING}! No configuration to reset${UI_RESET}"
        return 0
    fi
    
    echo -e "${UI_WARNING}This will delete your current configuration.${UI_RESET}"
    
    if confirm_prompt "Are you sure you want to reset configuration?"; then
        if rm -f "$HOMEBOI_CONFIG_FILE"; then
            echo -e "${UI_SUCCESS}✓ Configuration reset successfully${UI_RESET}"
            return 0
        else
            echo -e "${UI_ERROR}✗ Failed to reset configuration${UI_RESET}"
            return 1
        fi
    else
        echo -e "${UI_MUTED}Configuration reset cancelled${UI_RESET}"
        return 0
    fi
}

# Get configuration value
get_config_value() {
    local key="$1"
    local default_value="${2:-}"
    
    if ! config_exists; then
        echo "$default_value"
        return 1
    fi
    
    # Parse settings.env file format (KEY=value)
    local value
    case "$key" in
        "server.ip")
            value=$(grep "^SERVER_IP=" "$HOMEBOI_CONFIG_FILE" | cut -d'=' -f2 2>/dev/null)
            ;;
        "auth.username")
            value=$(grep "^HOMEBOI_USERNAME=" "$HOMEBOI_CONFIG_FILE" | cut -d'=' -f2 2>/dev/null)
            ;;
        "storage.base_path")
            value=$(grep "^DOWNLOADS_PATH=" "$HOMEBOI_CONFIG_FILE" | cut -d'=' -f2 2>/dev/null)
            ;;
        *)
            value=""
            ;;
    esac
    
    echo "${value:-$default_value}"
}

# Display configuration summary
show_config_summary() {
    if ! config_exists; then
        echo -e "${UI_WARNING}Configuration Status: Not configured${UI_RESET}"
        return 1
    fi
    
    local server_ip=$(get_config_value "server.ip" "Not set")
    local username=$(get_config_value "auth.username" "Not set")
    local base_path=$(get_config_value "storage.base_path" "Not set")
    
    echo -e "${UI_BOLD}Configuration Summary:${UI_RESET}"
    echo -e "  Server IP: ${server_ip}"
    echo -e "  Username: ${username}"
    echo -e "  Storage: ${base_path}"
    
    return 0
}

# Show service URLs from config
show_service_urls() {
    if ! config_exists; then
        echo -e "${UI_WARNING}! Configuration not found. Run setup first.${UI_RESET}"
        return 1
    fi
    
    local server_ip=$(get_config_value "server.ip" "localhost")
    
    echo -e "${UI_BOLD}Service URLs:${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    
    # Display service URLs
    for service in "${HOMEBOI_SERVICES[@]}"; do
        local port="${SERVICE_PORTS[$service]}"
        local path=""
        local icon=""
        
        # Service-specific formatting
        case "$service" in
            "plex") 
                path="/web"
                icon="📺"
                ;;
            "overseerr") 
                icon="🎬"
                ;;
            "sabnzbd") 
                icon="📥"
                ;;
            "prowlarr") 
                icon="🔍"
                ;;
            "sonarr") 
                icon="📺"
                ;;
            "radarr") 
                icon="🎞️"
                ;;
            "bazarr") 
                icon="💬"
                ;;
        esac
        
        local status=$(get_service_status "$service")
        local status_icon=""
        
        case "$status" in
            "running") status_icon="${UI_SUCCESS}●${UI_RESET}" ;;
            "stopped") status_icon="${UI_ERROR}●${UI_RESET}" ;;
            "starting") status_icon="${UI_WARNING}●${UI_RESET}" ;;
            *) status_icon="${UI_MUTED}●${UI_RESET}" ;;
        esac
        
        printf "  %s %s %-12s %s http://%s:%s%s\n" \
            "$status_icon" "$icon" "${service^}:" "$UI_MUTED" \
            "$server_ip" "$port" "$path${UI_RESET}"
    done
    
    echo
    echo -e "${UI_MUTED}Server: ${server_ip}${UI_RESET}"
}
