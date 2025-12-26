#!/bin/bash
# Minimal Installation Wizard - Essential questions only

# Load UI functions
source "${HOMEBOI_HOME}/lib/ui.sh" 2>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

# Minimal wizard configuration storage
declare -A MINIMAL_CONFIG

wizard_cancelled=false

wizard_on_interrupt() {
    wizard_cancelled=true
}

wizard_read_or_back() {
    local prompt="$1"
    local var_name="$2"
    local allow_empty="${3:-false}"

    while true; do
        echo -e "${UI_PRIMARY}${prompt}${UI_RESET}"
        echo -e "${UI_MUTED}Type 'back' to go to the previous question, or 'cancel' to exit the wizard.${UI_RESET}"
        read -r value
        case "${value,,}" in
            back|b)
                return 2
                ;;
            cancel|quit|q)
                return 1
                ;;
        esac
        if [[ "$allow_empty" == "true" || -n "$value" ]]; then
            MINIMAL_CONFIG["$var_name"]="$value"
            return 0
        fi
        echo -e "${UI_WARNING}⚠ Value cannot be empty${UI_RESET}"
    done
}

run_minimal_wizard() {
    clear
    print_header
    
    echo -e "${UI_BOLD}🚀 Homeboi Quick Setup Wizard${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Let's get your media stack running with just a few essential questions!${UI_RESET}"
    echo
    
    local previous_int_trap
    previous_int_trap="$(trap -p INT || true)"
    trap wizard_on_interrupt INT

    # 1. Storage Configuration
    setup_storage || true
    [[ "$wizard_cancelled" == "true" ]] && { eval "$previous_int_trap" 2>/dev/null || trap - INT; echo -e "${UI_MUTED}Setup cancelled${UI_RESET}"; return 2; }
    
    # 2. Authentication
    setup_authentication || true
    [[ "$wizard_cancelled" == "true" ]] && { eval "$previous_int_trap" 2>/dev/null || trap - INT; echo -e "${UI_MUTED}Setup cancelled${UI_RESET}"; return 2; }

    # 3. Primary setup choice
    setup_primary_apps || true
    [[ "$wizard_cancelled" == "true" ]] && { eval "$previous_int_trap" 2>/dev/null || trap - INT; echo -e "${UI_MUTED}Setup cancelled${UI_RESET}"; return 2; }
    
    # 4. Home Assistant
    setup_home_assistant || true
    [[ "$wizard_cancelled" == "true" ]] && { eval "$previous_int_trap" 2>/dev/null || trap - INT; echo -e "${UI_MUTED}Setup cancelled${UI_RESET}"; return 2; }
    
    # 5. Indexers
    setup_indexers || true
    [[ "$wizard_cancelled" == "true" ]] && { eval "$previous_int_trap" 2>/dev/null || trap - INT; echo -e "${UI_MUTED}Setup cancelled${UI_RESET}"; return 2; }
    
    # 6. VPN (with provider list)
    setup_vpn_provider || true
    [[ "$wizard_cancelled" == "true" ]] && { eval "$previous_int_trap" 2>/dev/null || trap - INT; echo -e "${UI_MUTED}Setup cancelled${UI_RESET}"; return 2; }

    # Restore INT trap before confirmation/deploy.
    eval "$previous_int_trap" 2>/dev/null || trap - INT

    # 6. Confirmation
    show_minimal_summary
    
    if confirm_deployment; then
        generate_minimal_config
        return 0
    else
        echo -e "${UI_MUTED}Setup cancelled${UI_RESET}"
        return 2
    fi
}

setup_storage() {
    clear
    print_header
    
    echo -e "${UI_BOLD}💾 Step 1/6: Drive Setup${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Mount any unmounted USB drives so Plex/Jellyfin can find them later?${UI_RESET}"
    echo
    echo -n "Check for USB drives? (y/N): "
    read -r mount_drives
    
    if [[ "$mount_drives" =~ ^[Yy]$ ]]; then
        setup_external_storage
    else
        # Use default paths
        MINIMAL_CONFIG["movies_path"]="${HOME}/media/movies"
        MINIMAL_CONFIG["tv_path"]="${HOME}/media/tv"
        MINIMAL_CONFIG["downloads_path"]="${HOME}/media/downloads"
        echo -e "${UI_SUCCESS}✓ Using default paths${UI_RESET}"
    fi
    
    echo
    press_enter
}

setup_external_storage() {
    echo
    echo -e "${UI_PRIMARY}🔍 Scanning for available drives...${UI_RESET}"
    
    # Detect all drives (both mounted and unmounted)
    local drives=()
    local drive_info=()
    local drive_paths=()
    
    # Find USB drives only
    while read -r device size type mountpoint; do
        # Clean up device name (remove extra spaces)  
        device=$(echo "$device" | awk '{print $1}')
        
        # Check if this is actually a USB drive
        local is_usb=false
        if [[ "$device" =~ ^sd[a-z]$ ]]; then
            # Check if it's connected via USB
            if [ -L "/sys/block/$device" ]; then
                local devpath=$(readlink -f "/sys/block/$device")
                if [[ "$devpath" == *"/usb"* ]]; then
                    is_usb=true
                fi
            fi
        fi
        
        if [[ "$is_usb" == "true" ]]; then
            local full_device="/dev/$device"
            
            # Check if any partitions are mounted
            local mounted_partitions=$(lsblk -ln -o NAME,MOUNTPOINT "$full_device" | grep -v "^$device " | awk '$2 != "" {print $2}')
            
            if [[ -n "$mounted_partitions" ]]; then
                # Drive has mounted partitions
                local first_mount=$(echo "$mounted_partitions" | head -1)
                drives+=("$full_device")
                drive_info+=("$full_device ($size) - mounted at $first_mount")
                drive_paths+=("$first_mount")
            else
                # Check if drive has partitions but they're unmounted
                local partitions=$(lsblk -ln -o NAME "$full_device" 2>/dev/null | tail -n +2 | head -1)
                if [[ -n "$partitions" ]]; then
                    drives+=("$full_device")
                    drive_info+=("$full_device ($size) - unmounted")
                    drive_paths+=("unmounted")
                fi
            fi
        fi
    done < <(lsblk -ln -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk)
    
    if [[ ${#drives[@]} -eq 0 ]]; then
        echo -e "${UI_WARNING}⚠ No USB drives detected${UI_RESET}"
        echo -e "${UI_MUTED}Using default location instead${UI_RESET}"
        echo -e "${UI_MUTED}You can later configure media paths in Plex/Jellyfin${UI_RESET}"
        MINIMAL_CONFIG["movies_path"]="${HOME}/media/movies"
        MINIMAL_CONFIG["tv_path"]="${HOME}/media/tv" 
        MINIMAL_CONFIG["downloads_path"]="${HOME}/media/downloads"
        return
    fi
    
    # Check if we need user selection or can auto-select
    local needs_selection=false
    local mounted_count=0
    local unmounted_count=0
    
    for path in "${drive_paths[@]}"; do
        if [[ "$path" == "unmounted" ]]; then
            ((unmounted_count++))
            needs_selection=true
        else
            ((mounted_count++))
        fi
    done
    
    # If multiple drives or any unmounted drives, show selection menu
    if [[ ${#drives[@]} -gt 1 || $unmounted_count -gt 0 ]]; then
        needs_selection=true
    fi
    
    local drive_choice=1
    if [[ "$needs_selection" == "true" ]]; then
        echo
        echo -e "${UI_PRIMARY}📱 Detected USB drives:${UI_RESET}"
        for i in "${!drive_info[@]}"; do
            echo -e "  ${UI_SUCCESS}[$((i+1))]${UI_RESET} ${drive_info[$i]}"
        done
        echo
        echo -n "Select drive [1-${#drives[@]}]: "
        read -r drive_choice
    else
        # Auto-select the single mounted drive
        echo
        echo -e "${UI_SUCCESS}✓ Found mounted USB drive: ${drive_info[0]}${UI_RESET}"
        drive_choice=1
    fi
    
    if [[ "$drive_choice" -ge 1 && "$drive_choice" -le ${#drives[@]} ]]; then
        local selected_drive="${drives[$((drive_choice-1))]}"
        local selected_path="${drive_paths[$((drive_choice-1))]}"
        
        if [[ "$selected_path" == "unmounted" ]]; then
            # Unmounted drive - offer to mount it
            local mount_point="/mnt/homeboi_media"
            echo -e "${UI_PRIMARY}📁 Mounting ${selected_drive} to ${mount_point}...${UI_RESET}"
            
            # Create mount point and mount
            sudo mkdir -p "$mount_point" 2>/dev/null
            if sudo mount "${selected_drive}1" "$mount_point" 2>/dev/null; then
                MINIMAL_CONFIG["movies_path"]="${mount_point}/movies"
                MINIMAL_CONFIG["tv_path"]="${mount_point}/tv"
                MINIMAL_CONFIG["downloads_path"]="${mount_point}/downloads"
                echo -e "${UI_SUCCESS}✓ External drive mounted successfully${UI_RESET}"
                echo -e "${UI_MUTED}📺 Configure this path in Plex/Jellyfin after deployment${UI_RESET}"
            else
                echo -e "${UI_WARNING}⚠ Failed to mount drive, using default location${UI_RESET}"
                echo -e "${UI_MUTED}📺 You can manually configure drives in Plex/Jellyfin later${UI_RESET}"
                MINIMAL_CONFIG["movies_path"]="${HOME}/media/movies"
                MINIMAL_CONFIG["tv_path"]="${HOME}/media/tv"
                MINIMAL_CONFIG["downloads_path"]="${HOME}/media/downloads"
            fi
        else
            # Already mounted drive - use existing mount point
            MINIMAL_CONFIG["movies_path"]="${selected_path}/movies"
            MINIMAL_CONFIG["tv_path"]="${selected_path}/tv"
            MINIMAL_CONFIG["downloads_path"]="${selected_path}/downloads"
            echo -e "${UI_SUCCESS}✓ Using mounted drive at ${selected_path}${UI_RESET}"
            echo -e "${UI_MUTED}📺 Configure this path in Plex/Jellyfin after deployment${UI_RESET}"
        fi
    else
        echo -e "${UI_WARNING}⚠ Invalid selection, using default location${UI_RESET}"
        echo -e "${UI_MUTED}📺 You can configure external drives in Plex/Jellyfin later${UI_RESET}"
        MINIMAL_CONFIG["movies_path"]="${HOME}/media/movies"
        MINIMAL_CONFIG["tv_path"]="${HOME}/media/tv"
        MINIMAL_CONFIG["downloads_path"]="${HOME}/media/downloads"
    fi
}

setup_custom_storage() {
    echo
    echo -e "${UI_PRIMARY}Enter custom storage path:${UI_RESET}"
    echo -n "Base path: "
    read -r custom_path
    
    if [[ -d "$custom_path" ]] || mkdir -p "$custom_path" 2>/dev/null; then
        MINIMAL_CONFIG["movies_path"]="${custom_path}/movies"
        MINIMAL_CONFIG["tv_path"]="${custom_path}/tv"
        MINIMAL_CONFIG["downloads_path"]="${custom_path}/downloads"
        echo -e "${UI_SUCCESS}✓ Custom path configured${UI_RESET}"
    else
        echo -e "${UI_WARNING}⚠ Invalid path, using default location${UI_RESET}"
        MINIMAL_CONFIG["movies_path"]="${HOME}/media/movies"
        MINIMAL_CONFIG["tv_path"]="${HOME}/media/tv"
        MINIMAL_CONFIG["downloads_path"]="${HOME}/media/downloads"
    fi
}

setup_authentication() {
    clear
    print_header
    
    echo -e "${UI_BOLD}🔐 Step 2/6: Authentication Setup${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Set up shared authentication for all services?${UI_RESET}"
    echo -e "${UI_MUTED}This secures Sonarr, Radarr, Prowlarr, SABnzbd, and Jellyfin${UI_RESET}"
    echo -e "${UI_MUTED}Overseerr/Jellyseerr need an email + password for the initial admin user.${UI_RESET}"
    echo -e "${UI_MUTED}No prior registration is required and no emails are sent (it's just the login identifier).${UI_RESET}"
    echo
    
    echo -e "${UI_PRIMARY}Username:${UI_RESET}"
    read -r username
    MINIMAL_CONFIG["username"]="${username:-admin}"

    local default_email="admin@homeboi.local"
    echo
    echo -e "${UI_PRIMARY}Admin email (Overseerr/Jellyseerr login) [default: ${default_email}]:${UI_RESET}"
    echo -e "${UI_MUTED}Tip: You can use any valid address, e.g. admin@homeboi.local${UI_RESET}"
    while true; do
        read -r email
        email="${email:-$default_email}"
        if [[ "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
            MINIMAL_CONFIG["email"]="$email"
            break
        fi
        echo -e "${UI_ERROR}❌ Please enter a valid email address (example: admin@homeboi.local)${UI_RESET}"
        echo -e "${UI_PRIMARY}Admin email:${UI_RESET}"
    done
    
    echo -e "${UI_MUTED}Password requirements: 8+ chars, 1 uppercase, 1 lowercase, 1 number, 1 symbol${UI_RESET}"
    echo
    while true; do
        echo -e "${UI_PRIMARY}Password:${UI_RESET}"
        read -r password
        
        # Validate password strength
        local has_length=false has_upper=false has_lower=false has_number=false has_symbol=false
        
        [[ ${#password} -ge 8 ]] && has_length=true
        [[ "$password" =~ [A-Z] ]] && has_upper=true
        [[ "$password" =~ [a-z] ]] && has_lower=true
        [[ "$password" =~ [0-9] ]] && has_number=true
        [[ "$password" =~ [^a-zA-Z0-9] ]] && has_symbol=true
        
        if [[ "$has_length" == true && "$has_upper" == true && "$has_lower" == true && "$has_number" == true && "$has_symbol" == true ]]; then
            echo -e "${UI_PRIMARY}Confirm password:${UI_RESET}"
            read -r password_confirm
            if [[ "$password" == "$password_confirm" ]]; then
                echo -e "${UI_SUCCESS}✓ Strong password created${UI_RESET}"
                MINIMAL_CONFIG["password"]="$password"
                break
            else
                echo -e "${UI_ERROR}❌ Passwords don't match, try again${UI_RESET}"
                echo
            fi
        else
            echo -e "${UI_ERROR}❌ Password requirements not met:${UI_RESET}"
            [[ "$has_length" == false ]] && echo -e "   • Must be at least 8 characters long"
            [[ "$has_upper" == false ]] && echo -e "   • Must contain at least 1 uppercase letter (A-Z)"
            [[ "$has_lower" == false ]] && echo -e "   • Must contain at least 1 lowercase letter (a-z)"
            [[ "$has_number" == false ]] && echo -e "   • Must contain at least 1 number (0-9)"
            [[ "$has_symbol" == false ]] && echo -e "   • Must contain at least 1 symbol (!@#\$%^&*)"
            echo
        fi
    done
    
    echo -e "${UI_SUCCESS}✓ Authentication configured${UI_RESET}"
    echo
    press_enter
}

setup_primary_apps() {
    clear
    print_header

    echo -e "${UI_BOLD}🎯 Step 3/6: Primary Setup${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Which setup do you want Homeboi to optimize for?${UI_RESET}"
    echo -e "${UI_MUTED}This only affects the setup checklist ordering and default guidance.${UI_RESET}"
    echo
    echo -e "  ${UI_SUCCESS}[1]${UI_RESET} Jellyfin + Jellyseerr (automated)"
    echo -e "  ${UI_SUCCESS}[2]${UI_RESET} Plex + Overseerr (requires Plex sign-in)"
    echo
    echo -n "Select primary setup [1-2] (default: 1): "
    read -r primary_choice

    case "${primary_choice:-1}" in
        2)
            MINIMAL_CONFIG["primary_media_server"]="plex"
            MINIMAL_CONFIG["primary_request_app"]="overseerr"
            ;;
        *)
            MINIMAL_CONFIG["primary_media_server"]="jellyfin"
            MINIMAL_CONFIG["primary_request_app"]="jellyseerr"
            ;;
    esac

    echo
    echo -e "${UI_SUCCESS}✓ Primary setup selected${UI_RESET}"
    echo
    press_enter
}

setup_home_assistant() {
    clear
    print_header
    
    echo -e "${UI_BOLD}🏡 Step 4/6: Home Assistant${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Include Home Assistant for smart home automation?${UI_RESET}"
    echo -e "${UI_MUTED}Home Assistant lets you control smart devices, lights, sensors, and more${UI_RESET}"
    echo
    echo -n "Install Home Assistant? (y/N): "
    read -r install_ha
    
    if [[ "$install_ha" =~ ^[Yy]$ ]]; then
        MINIMAL_CONFIG["enable_home_assistant"]="true"
        echo -e "${UI_SUCCESS}✓ Home Assistant will be included${UI_RESET}"
    else
        MINIMAL_CONFIG["enable_home_assistant"]="false"
        echo -e "${UI_SUCCESS}✓ Home Assistant skipped${UI_RESET}"
    fi
    
    echo
    press_enter
}

setup_indexers() {
    clear
    print_header
    
    echo -e "${UI_BOLD}📚 Step 5/6: Indexer Setup${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Add indexers for automatic downloads?${UI_RESET}"
    echo
    echo -e "  ${UI_SUCCESS}[1]${UI_RESET} Add private Usenet indexer"
    echo -e "  ${UI_SUCCESS}[2]${UI_RESET} Add free indexers only (1337x, EZTV, YTS) (less secure)"
    echo -e "  ${UI_SUCCESS}[3]${UI_RESET} Skip (manual setup later)"
    echo
    echo -n "Select option [1-3]: "
    read -r indexer_choice
    
    case "$indexer_choice" in
        1)
            setup_private_indexers
            ;;
        2)
            MINIMAL_CONFIG["free_indexers"]="true"
            MINIMAL_CONFIG["private_indexers"]="false"
            echo -e "${UI_SUCCESS}✓ Free indexers will be configured${UI_RESET}"
            ;;
        *)
            MINIMAL_CONFIG["free_indexers"]="false"
            MINIMAL_CONFIG["private_indexers"]="false"
            echo -e "${UI_MUTED}⚠ Skipping indexer setup${UI_RESET}"
            ;;
    esac
    
    echo
    press_enter
}

setup_private_indexers() {
    echo
    echo -e "${UI_PRIMARY}🔒 Private Indexer Configuration${UI_RESET}"
    echo -e "${UI_MUTED}💡 Find API keys in your indexer account settings${UI_RESET}"
    echo
    
    echo -e "${UI_PRIMARY}NZBGeek API Key (leave blank to skip):${UI_RESET}"
    read -r nzbgeek_api
    if [[ -n "$nzbgeek_api" ]]; then
        MINIMAL_CONFIG["nzbgeek_api"]="$nzbgeek_api"
        MINIMAL_CONFIG["private_indexers"]="true"
        echo -e "${UI_SUCCESS}✓ NZBGeek configured${UI_RESET}"
    else
        MINIMAL_CONFIG["private_indexers"]="false"
        echo -e "${UI_MUTED}⚠ No private indexers configured${UI_RESET}"
    fi
}

setup_vpn_provider() {
    clear
    print_header
    
    echo -e "${UI_BOLD}🛡️ Step 6/6: VPN Protection${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Protect downloads with VPN?${UI_RESET}"
    echo -e "${UI_MUTED}Recommended for privacy and security${UI_RESET}"
    echo
    echo -e "  ${UI_SUCCESS}[1]${UI_RESET} ProtonVPN"
    echo -e "  ${UI_SUCCESS}[2]${UI_RESET} NordVPN" 
    echo -e "  ${UI_SUCCESS}[3]${UI_RESET} ExpressVPN"
    echo -e "  ${UI_SUCCESS}[4]${UI_RESET} Mullvad"
    echo -e "  ${UI_SUCCESS}[5]${UI_RESET} Surfshark"
    echo -e "  ${UI_SUCCESS}[6]${UI_RESET} Private Internet Access"
    echo -e "  ${UI_SUCCESS}[7]${UI_RESET} CyberGhost"
    echo -e "  ${UI_SUCCESS}[8]${UI_RESET} IPVanish"
    echo -e "  ${UI_SUCCESS}[9]${UI_RESET} VyprVPN"
    echo -e "  ${UI_SUCCESS}[10]${UI_RESET} Custom VPN"
    echo -e "  ${UI_SUCCESS}[11]${UI_RESET} No VPN (skip)"
    echo
    echo -n "Select VPN provider [1-11] (or 'back' to go back, 'cancel' to exit): "
    read -r vpn_choice
    case "${vpn_choice,,}" in
        back|b)
            return 2
            ;;
        cancel|quit|q)
            wizard_cancelled=true
            return 1
            ;;
    esac
    
    case "$vpn_choice" in
        1)
            MINIMAL_CONFIG["vpn_provider"]="protonvpn"
            while true; do
                setup_openvpn_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        2)
            MINIMAL_CONFIG["vpn_provider"]="nordvpn"
            while true; do
                setup_openvpn_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        3)
            MINIMAL_CONFIG["vpn_provider"]="expressvpn"
            while true; do
                setup_openvpn_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        4)
            MINIMAL_CONFIG["vpn_provider"]="mullvad"
            while true; do
                setup_wireguard_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        5)
            MINIMAL_CONFIG["vpn_provider"]="surfshark"
            while true; do
                setup_openvpn_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        6)
            MINIMAL_CONFIG["vpn_provider"]="private internet access"
            while true; do
                setup_openvpn_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        7)
            MINIMAL_CONFIG["vpn_provider"]="cyberghost"
            while true; do
                setup_openvpn_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        8)
            MINIMAL_CONFIG["vpn_provider"]="ipvanish"
            while true; do
                setup_openvpn_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        9)
            MINIMAL_CONFIG["vpn_provider"]="vyprvpn"
            while true; do
                setup_openvpn_credentials && break
                [[ $? -eq 2 ]] && break
                [[ $? -eq 1 ]] && { wizard_cancelled=true; return 1; }
            done
            ;;
        10)
            setup_custom_vpn
            ;;
        *)
            MINIMAL_CONFIG["vpn_provider"]=""
            echo -e "${UI_MUTED}⚠ Skipping VPN setup${UI_RESET}"
            ;;
    esac
    
    echo
    press_enter
}

setup_openvpn_credentials() {
    echo
    echo -e "${UI_PRIMARY}🔑 Enter ${MINIMAL_CONFIG["vpn_provider"]} credentials:${UI_RESET}"
    echo
    wizard_read_or_back "OpenVPN Username:" "openvpn_user" "false" || return $?
    wizard_read_or_back "OpenVPN Password:" "openvpn_password" "false" || return $?
    
    echo -e "${UI_SUCCESS}✓ VPN credentials configured${UI_RESET}"
}

setup_wireguard_credentials() {
    echo
    echo -e "${UI_PRIMARY}🔑 Enter Mullvad WireGuard credentials:${UI_RESET}"
    echo
    wizard_read_or_back "WireGuard Private Key:" "wireguard_private_key" "false" || return $?
    wizard_read_or_back "WireGuard Addresses:" "wireguard_addresses" "false" || return $?
    
    echo -e "${UI_SUCCESS}✓ WireGuard credentials configured${UI_RESET}"
}

setup_custom_vpn() {
    echo
    echo -e "${UI_PRIMARY}🛠️ Custom VPN Configuration:${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}VPN Provider Name:${UI_RESET}"
    read -r custom_provider
    MINIMAL_CONFIG["vpn_provider"]="$custom_provider"
    
    echo -e "${UI_PRIMARY}VPN Type (openvpn/wireguard):${UI_RESET}"
    read -r vpn_type
    
    if [[ "$vpn_type" == "wireguard" ]]; then
        setup_wireguard_credentials
    else
        setup_openvpn_credentials
    fi
    
    echo -e "${UI_SUCCESS}✓ Custom VPN configured${UI_RESET}"
}

show_minimal_summary() {
    clear
    print_header
    
    echo -e "${UI_BOLD}📋 Deployment Summary${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Ready to deploy your media stack:${UI_RESET}"
    echo
    echo -e "  📁 ${UI_SUCCESS}Storage:${UI_RESET} ${MINIMAL_CONFIG["movies_path"]%/movies}"
    echo -e "  👤 ${UI_SUCCESS}Authentication:${UI_RESET} ${MINIMAL_CONFIG["username"]} (password protected)"
    echo -e "  📧 ${UI_SUCCESS}Admin Email:${UI_RESET} ${MINIMAL_CONFIG["email"]:-admin@homeboi.local}"
    echo -e "  🎯 ${UI_SUCCESS}Primary Setup:${UI_RESET} ${MINIMAL_CONFIG["primary_media_server"]:-jellyfin} + ${MINIMAL_CONFIG["primary_request_app"]:-jellyseerr}"
    
    if [[ "${MINIMAL_CONFIG["enable_home_assistant"]}" == "true" ]]; then
        echo -e "  🏡 ${UI_SUCCESS}Home Assistant:${UI_RESET} Enabled"
    else
        echo -e "  🏡 ${UI_MUTED}Home Assistant:${UI_RESET} Disabled"
    fi
    
    if [[ "${MINIMAL_CONFIG["private_indexers"]}" == "true" ]]; then
        echo -e "  🔍 ${UI_SUCCESS}Indexers:${UI_RESET} Private indexers configured"
    elif [[ "${MINIMAL_CONFIG["free_indexers"]}" == "true" ]]; then
        echo -e "  🔍 ${UI_SUCCESS}Indexers:${UI_RESET} Free indexers only"
    else
        echo -e "  🔍 ${UI_WARNING}Indexers:${UI_RESET} Manual setup required"
    fi
    
    if [[ -n "${MINIMAL_CONFIG["vpn_provider"]}" ]]; then
        echo -e "  🛡️ ${UI_SUCCESS}VPN:${UI_RESET} ${MINIMAL_CONFIG["vpn_provider"]}"
    else
        echo -e "  🛡️ ${UI_MUTED}VPN:${UI_RESET} Disabled"
    fi
    
    echo
    echo -e "${UI_PRIMARY}Services to deploy:${UI_RESET}"
    echo -e "  • Plex (Media Server)"
    echo -e "  • Jellyfin (Media Server)"  
    echo -e "  • Sonarr (TV Shows)"
    echo -e "  • Radarr (Movies)"
    echo -e "  • Bazarr (Subtitles)"
    echo -e "  • Prowlarr (Indexer Management)"
    echo -e "  • SABnzbd (Downloads)"
    echo -e "  • Overseerr (Request Management)"
    echo -e "  • Jellyseerr (Request Management)"
    echo
}

confirm_deployment() {
    echo -e "${UI_BOLD}🚀 Deploy now?${UI_RESET}"
    echo -e "${UI_MUTED}This will create all containers and configure API connections automatically${UI_RESET}"
    echo
    echo -n "Continue? (Y/n): "
    read -r confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        return 1
    else
        return 0
    fi
}

generate_minimal_config() {
    # Quote password so special characters don't break sourcing of settings.env
    local quoted_password
    quoted_password=$(printf '%q' "${MINIMAL_CONFIG["password"]}")

    # Create settings.env with minimal configuration
    cat > "$HOMEBOI_HOME/settings.env" << EOF
# Homeboi Minimal Configuration (Generated by Quick Setup Wizard)
# Edit these settings and run 'Launch Stack' to apply changes

# =============================================================================
# BASIC CONFIGURATION
# =============================================================================

# Server Configuration
HOMEBOI_USERNAME=${MINIMAL_CONFIG["username"]}
HOMEBOI_PASSWORD=$quoted_password
HOMEBOI_EMAIL=${MINIMAL_CONFIG["email"]:-admin@homeboi.local}
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "192.168.1.100")
TIMEZONE=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
HOSTNAME=$(hostname)

# Authentication
ENABLE_ARR_AUTH=true

# Primary Setup
PRIMARY_MEDIA_SERVER=${MINIMAL_CONFIG["primary_media_server"]:-jellyfin}
PRIMARY_REQUEST_APP=${MINIMAL_CONFIG["primary_request_app"]:-jellyseerr}

# Home Automation
enable_home_assistant=${MINIMAL_CONFIG["enable_home_assistant"]}


# =============================================================================
# MEDIA STORAGE PATHS
# =============================================================================

MOVIES_PATH=${MINIMAL_CONFIG["movies_path"]}
TV_SHOWS_PATH=${MINIMAL_CONFIG["tv_path"]}
DOWNLOADS_PATH=${MINIMAL_CONFIG["downloads_path"]}

EOF

    # Add VPN configuration if enabled
    if [[ -n "${MINIMAL_CONFIG["vpn_provider"]}" ]]; then
        cat >> "$HOMEBOI_HOME/settings.env" << EOF
# =============================================================================
# VPN CONFIGURATION
# =============================================================================

VPN_SERVICE_PROVIDER=${MINIMAL_CONFIG["vpn_provider"]}
EOF
        
        if [[ -n "${MINIMAL_CONFIG["openvpn_user"]}" ]]; then
            cat >> "$HOMEBOI_HOME/settings.env" << EOF
OPENVPN_USER=${MINIMAL_CONFIG["openvpn_user"]}
OPENVPN_PASSWORD=${MINIMAL_CONFIG["openvpn_password"]}
EOF
        fi
        
        if [[ -n "${MINIMAL_CONFIG["wireguard_private_key"]}" ]]; then
            cat >> "$HOMEBOI_HOME/settings.env" << EOF
WIREGUARD_PRIVATE_KEY=${MINIMAL_CONFIG["wireguard_private_key"]}
WIREGUARD_ADDRESSES=${MINIMAL_CONFIG["wireguard_addresses"]}
EOF
        fi
    fi

    # Add indexer configuration if enabled
    if [[ "${MINIMAL_CONFIG["private_indexers"]}" == "true" && -n "${MINIMAL_CONFIG["nzbgeek_api"]}" ]]; then
        cat >> "$HOMEBOI_HOME/settings.env" << EOF

# =============================================================================
# INDEXER CONFIGURATION
# =============================================================================

NZBGEEK_API=${MINIMAL_CONFIG["nzbgeek_api"]}
EOF
    fi
    
    # Add completion marker
    cat >> "$HOMEBOI_HOME/settings.env" << EOF

# =============================================================================
# SETUP STATUS  
# =============================================================================
# Wizard completed - DO NOT REMOVE THIS LINE
EOF

    echo -e "${UI_SUCCESS}✓ Configuration saved to settings.env${UI_RESET}"
}
