#!/bin/bash
# Homeboi - Home Media Stack Manager (inspired by nodeboi)
# A beautiful terminal interface for managing your media services

set -eo pipefail
trap 'echo "Error on line $LINENO" >&2' ERR
trap 'printf \"\\033[?25h\" >&2; echo \"Script interrupted by signal\" >&2; exit 130' INT TERM

# Resolve real path when script is symlinked
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    HOMEBOI_HOME="$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}")")" && pwd)"
else
    HOMEBOI_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

HOMEBOI_LIB="${HOMEBOI_HOME}/lib"

SCRIPT_VERSION="v0.0.1"
if [[ -f "${HOMEBOI_HOME}/VERSION" ]]; then
    HOMEBOI_VERSION_RAW="$(tr -d ' \t\r\n' < "${HOMEBOI_HOME}/VERSION" 2>/dev/null || true)"
    if [[ -n "${HOMEBOI_VERSION_RAW}" ]]; then
        SCRIPT_VERSION="v${HOMEBOI_VERSION_RAW}"
    fi
fi

# Create cache directory
mkdir -p "$HOMEBOI_HOME/cache"

# Load all library files
for lib in "${HOMEBOI_LIB}"/*.sh; do
    [[ -f "$lib" ]] && source "$lib"
done

# Check if initial setup/wizard has been completed
wizard_completed() {
    local settings_file="${HOMEBOI_HOME}/settings.env"
    [[ -f "$settings_file" ]] && grep -q "# Wizard completed" "$settings_file" 2>/dev/null
}

config_is_complete() {
    local settings_file="${HOMEBOI_HOME}/settings.env"
    [[ -f "$settings_file" ]] || return 1
    grep -q "# Wizard completed" "$settings_file" 2>/dev/null || return 1
    # shellcheck disable=SC1090
    source "$settings_file" 2>/dev/null || true
    [[ -n "${HOMEBOI_USERNAME:-}" && -n "${HOMEBOI_PASSWORD:-}" && -n "${SERVER_IP:-}" ]]
}

print_safe_config_summary() {
    local settings_file="${HOMEBOI_HOME}/settings.env"
    # shellcheck disable=SC1090
    source "$settings_file" 2>/dev/null || true

    echo -e "${UI_PRIMARY}Using configuration from:${UI_RESET} ${UI_MUTED}${settings_file}${UI_RESET}"
    echo -e "  ${UI_SUCCESS}User:${UI_RESET} ${HOMEBOI_USERNAME:-unknown}"
    echo -e "  ${UI_SUCCESS}Server IP:${UI_RESET} ${SERVER_IP:-unknown}"
    [[ -n "${TIMEZONE:-}" ]] && echo -e "  ${UI_SUCCESS}Timezone:${UI_RESET} ${TIMEZONE}"
    [[ -n "${HOSTNAME:-}" ]] && echo -e "  ${UI_SUCCESS}Hostname:${UI_RESET} ${HOSTNAME}"
    [[ -n "${PRIMARY_MEDIA_SERVER:-}" || -n "${PRIMARY_REQUEST_APP:-}" ]] && echo -e "  ${UI_SUCCESS}Primary:${UI_RESET} ${PRIMARY_MEDIA_SERVER:-jellyfin} + ${PRIMARY_REQUEST_APP:-jellyseerr}"
    [[ -n "${MOVIES_PATH:-}" ]] && echo -e "  ${UI_SUCCESS}Movies:${UI_RESET} ${MOVIES_PATH}"
    [[ -n "${TV_SHOWS_PATH:-}" ]] && echo -e "  ${UI_SUCCESS}TV:${UI_RESET} ${TV_SHOWS_PATH}"
    [[ -n "${DOWNLOADS_PATH:-}" ]] && echo -e "  ${UI_SUCCESS}Downloads:${UI_RESET} ${DOWNLOADS_PATH}"
}

# Main menu
main_menu() {
    while true; do
        local main_options=()
        
        # Always show the core actions so users can recover from partial/aborted setups.
        main_options=("Launch Stack")
        if wizard_completed; then
            main_options+=("Edit Settings")
        fi
        main_options+=("Remove Stack")
        if ansible_services_deployed || services_deployed || has_existing_services; then
            main_options+=("Update Stack")
        fi
        main_options+=("Exit Homeboi")
        
        local selection
        if selection=$(fancy_select_menu "Main Menu" "${main_options[@]}"); then
            local selected_option="${main_options[$selection]}"
            
            case "$selected_option" in
                "Launch Stack")
                    launch_stack
                    ;;
                "Edit Settings")
                    edit_settings_menu
                    ;;
                "Update Stack")
                    update_stack_menu
                    ;;
                "Remove Stack")
                    remove_stack_menu
                    ;;
                "Exit Homeboi")
                    cleanup_and_exit
                    ;;
            esac
        else
            cleanup_and_exit
        fi
    done
}

# Service management submenu
service_management_menu() {
    while true; do
        local service_options=(
            "Individual Service Control"
            "Start All Services"
            "Stop All Services"
            "Restart All Services"
            "Back to Main Menu"
        )
        
        local selection
        if selection=$(fancy_select_menu "Service Management" "${service_options[@]}"); then
            local selected_option="${service_options[$selection]}"
            
            case "$selected_option" in
                "Individual Service Control")
                    individual_service_menu
                    ;;
                "Start All Services")
                    clear
                    print_header
                    start_all_services
                    press_enter
                    ;;
                "Stop All Services")
                    clear
                    print_header
                    stop_all_services
                    press_enter
                    ;;
                "Restart All Services")
                    clear
                    print_header
                    restart_all_services
                    press_enter
                    ;;
                "Back to Main Menu")
                    return
                    ;;
            esac
        else
            return
        fi
    done
}

# Individual service control menu
individual_service_menu() {
    while true; do
        # Build service options with status
        local service_options=()
        
        for service in "${HOMEBOI_SERVICES[@]}"; do
            local status=$(get_service_status "$service")
            local status_icon=""
            
            case "$status" in
                "running") status_icon="${UI_SUCCESS}●${UI_RESET}" ;;
                "stopped") status_icon="${UI_ERROR}●${UI_RESET}" ;;
                "starting") status_icon="${UI_WARNING}●${UI_RESET}" ;;
                *) status_icon="${UI_MUTED}●${UI_RESET}" ;;
            esac
            
            service_options+=("${status_icon} ${service^} (${SERVICE_DESCRIPTIONS[$service]})")
        done
        
        service_options+=("Back to Service Management")
        
        local selection
        if selection=$(fancy_select_menu "Individual Service Control" "${service_options[@]}"); then
            if [[ $selection -eq $((${#service_options[@]} - 1)) ]]; then
                return  # Back option
            else
                local service="${HOMEBOI_SERVICES[$selection]}"
                service_control_menu "$service"
            fi
        else
            return
        fi
    done
}

# Service control menu for individual service
service_control_menu() {
    local service="$1"
    
    while true; do
        local status=$(get_service_status "$service")
        local control_options=()
        
        case "$status" in
            "running")
                control_options+=("Stop Service" "Restart Service")
                ;;
            "stopped"|"not_installed")
                control_options+=("Start Service")
                ;;
            "starting")
                control_options+=("Stop Service")
                ;;
        esac
        
        control_options+=("View Logs" "Open Web Interface" "Back")
        
        local selection
        if selection=$(fancy_select_menu "${service^} Control" "${control_options[@]}"); then
            local selected_action="${control_options[$selection]}"
            
            case "$selected_action" in
                "Start Service")
                    clear
                    print_header
                    start_service "$service"
                    press_enter
                    ;;
                "Stop Service")
                    clear
                    print_header
                    stop_service "$service"
                    press_enter
                    ;;
                "Restart Service")
                    clear
                    print_header
                    restart_service "$service"
                    press_enter
                    ;;
                "View Logs")
                    clear
                    print_header
                    view_service_logs "$service"
                    press_enter
                    ;;
                "Open Web Interface")
                    clear
                    print_header
                    open_service_url "$service"
                    press_enter
                    ;;
                "Back")
                    return
                    ;;
            esac
        else
            return
        fi
    done
}

# Configuration menu
configuration_menu() {
    while true; do
        local config_options=(
            "Initial Setup"
            "View Configuration"
            "Edit Configuration"
            "Reset Configuration"
            "Back to Main Menu"
        )
        
        local selection
        if selection=$(fancy_select_menu "Configuration & Setup" "${config_options[@]}"); then
            local selected_option="${config_options[$selection]}"
            
            case "$selected_option" in
                "Initial Setup")
                    clear
                    print_header
                    run_initial_setup
                    press_enter
                    ;;
                "View Configuration")
                    clear
                    print_header
                    view_configuration
                    press_enter
                    ;;
                "Edit Configuration")
                    clear
                    print_header
                    edit_configuration
                    press_enter
                    ;;
                "Reset Configuration")
                    clear
                    print_header
                    reset_configuration
                    press_enter
                    ;;
                "Back to Main Menu")
                    return
                    ;;
            esac
        else
            return
        fi
    done
}


# Logs menu
logs_menu() {
    while true; do
        local log_options=()
        
        # Add each service as an option
        for service in "${HOMEBOI_SERVICES[@]}"; do
            local status=$(get_service_status "$service")
            if [[ "$status" == "running" || "$status" == "starting" ]]; then
                log_options+=("${service^} logs")
            fi
        done
        
        if [[ ${#log_options[@]} -eq 0 ]]; then
            log_options+=("No running services")
        fi
        
        log_options+=("Back to Main Menu")
        
        local selection
        if selection=$(fancy_select_menu "Service Logs" "${log_options[@]}"); then
            if [[ "${log_options[$selection]}" == "Back to Main Menu" ]]; then
                return
            elif [[ "${log_options[$selection]}" == "No running services" ]]; then
                continue
            else
                # Extract service name from option
                local service_name="${log_options[$selection]%% logs}"
                local service="${service_name,,}"  # Convert to lowercase
                
                clear
                print_header
                view_service_logs "$service"
                press_enter
            fi
        else
            return
        fi
    done
}

# Update stack menu
update_stack_menu() {
    clear
    print_header
    
    echo -e "${UI_BOLD}Update Stack${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    
    if ! services_deployed; then
        echo -e "${UI_WARNING}⚠ No Homeboi stack deployed yet${UI_RESET}"
        echo -e "  Please use 'Launch Stack' first"
        press_enter
        return
    fi
    
    local update_options=(
        "Update Stack"
        "Back to Main Menu"
    )
    
    local selection
    if selection=$(fancy_select_menu "" "${update_options[@]}"); then
        local selected_option="${update_options[$selection]}"
        
        case "$selected_option" in
            "Update Stack")
                clear
                print_header
                # Temporarily disable exit on error for update process
                set +e
                update_all_services
                local update_result=$?
                set -e
                press_enter
                ;;
            "Back to Main Menu")
                return
                ;;
        esac
    fi
}

# Remove stack function
remove_stack_menu() {
    clear
    print_header
    
    echo -e "${UI_BOLD}🗑️ Remove Homeboi Stack${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}This will remove all Homeboi services using Ansible:${UI_RESET}"
    echo -e "  ${UI_SUCCESS}✓${UI_RESET} Stop and remove all containers"
    echo -e "  ${UI_SUCCESS}✓${UI_RESET} Remove Docker network"
    echo -e "  ${UI_PRIMARY}❓${UI_RESET} Ask about removing configuration files"
    echo -e "  ${UI_SUCCESS}✓${UI_RESET} Always keep media files safe"
    echo
    echo -e "${UI_CYAN}💡 Interactive removal with config choice${UI_RESET}"
    echo
    
    # Check if Ansible is available
    if ! check_ansible_prerequisites; then
        echo -e "${UI_ERROR}❌ Cannot proceed without Ansible${UI_RESET}"
        press_enter
        return 1
    fi
    
    # Run Ansible removal
    run_ansible_removal
    
    press_enter
}

# Launch stack function - Now powered by Ansible
launch_stack() {
    clear
    print_header
    
    echo -e "${UI_BOLD}🚀 Launch Automated Stack${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    echo -e "${UI_PRIMARY}Homeboi will automatically deploy your entire media stack with:${UI_RESET}"
    echo -e "  ${UI_SUCCESS}✓${UI_RESET} Ansible-powered reliable deployment"
    echo -e "  ${UI_SUCCESS}✓${UI_RESET} Interactive configuration wizard"
    echo -e "  ${UI_SUCCESS}✓${UI_RESET} Automatic API connections between services"
    echo -e "  ${UI_SUCCESS}✓${UI_RESET} VPN-secured downloads (if configured)"
    echo -e "  ${UI_SUCCESS}✓${UI_RESET} Idempotent deployment (safe to re-run)"
    echo
    echo -e "${UI_CYAN}💡 Powered by Ansible for maximum reliability!${UI_RESET}"
    echo
    
    # Check if Ansible is installed
    if ! check_ansible_prerequisites; then
        echo -e "${UI_ERROR}❌ Missing prerequisites${UI_RESET}"
        return 1
    fi
    
    local force_wizard="false"
    if config_is_complete; then
        echo -e "${UI_SUCCESS}✓ Existing settings detected${UI_RESET}"
        echo
        print_safe_config_summary
        echo

        local choice
        if choice=$(fancy_select_menu "Launch Stack" "Use existing settings" "Re-run wizard (overwrite settings)" "Cancel"); then
            case "$choice" in
                0) force_wizard="false" ;;
                1) force_wizard="true" ;;
                *) return 0 ;;
            esac
        else
            return 0
        fi
    fi

    # Run Ansible deployment (runs wizard if needed, or forced).
    run_ansible_deployment "$force_wizard"
}


# Edit settings function
edit_settings_menu() {
    clear
    print_header
    
    echo -e "${UI_BOLD}Edit Settings${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    
    local settings_file="$HOMEBOI_HOME/settings.env"
    if [[ ! -f "$settings_file" ]]; then
        echo -e "${UI_WARNING}⚠ settings.env not found. Run 'Launch Stack' to create it via the wizard.${UI_RESET}"
        press_enter
        return
    fi
    
    echo -e "${UI_PRIMARY}Opening settings file for editing...${UI_RESET}"
    echo -e "${UI_MUTED}File: $settings_file${UI_RESET}"
    echo
    
    # Determine editor
    local editor="${EDITOR:-nano}"
    if ! command -v "$editor" >/dev/null 2>&1; then
        if command -v nano >/dev/null 2>&1; then
            editor="nano"
        elif command -v vi >/dev/null 2>&1; then
            editor="vi"
        else
            echo -e "${UI_ERROR}✗ No text editor found${UI_RESET}"
            press_enter
            return
        fi
    fi
    
    # Open editor
    "$editor" "$settings_file"
    
    # Ask if user wants to apply settings
    clear
    print_header
    
    echo -e "${UI_BOLD}Apply Settings${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    
    if services_deployed || has_existing_services; then
        echo -e "${UI_PRIMARY}Apply new settings now?${UI_RESET}"
        echo -e "${UI_MUTED}This re-runs the Ansible playbook to apply changes.${UI_RESET}"
        echo
        
        if confirm_prompt "Update stack with new settings?"; then
            clear
            print_header
            update_all_services
        fi
    else
        echo -e "${UI_SUCCESS}✓ Settings saved${UI_RESET}"
        echo -e "${UI_MUTED}Use 'Launch Stack' to start services with these settings${UI_RESET}"
        press_enter
    fi
}


# ============================================================================
# SERVICE DETECTION FOR ANSIBLE DEPLOYMENTS
# ============================================================================

# Check if Ansible-deployed services are running
ansible_services_deployed() {
    # Check if key Homeboi services are running (deployed by Ansible)
    local key_services=("plex" "sonarr" "radarr" "prowlarr")
    local found_services=0
    
    for service in "${key_services[@]}"; do
        if docker ps --filter "name=$service" --filter "status=running" --format "{{.Names}}" | grep -q "^${service}$" 2>/dev/null; then
            ((found_services++))
        fi
    done
    
    # If at least 2 key services are running, consider stack deployed
    [[ $found_services -ge 2 ]]
}

# ============================================================================
# ENHANCED UI FUNCTIONS WITH ANSIBLE BACKEND
# ============================================================================

# Re-run setup wizard using Ansible

# Show service status using Ansible dashboard
show_service_status() {
    clear
    print_header
    
    echo -e "${UI_BOLD}📊 Service Status${UI_RESET}"
    echo -e "${UI_MUTED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${UI_RESET}"
    echo
    
    show_ansible_status
    
    echo
    press_enter
}

# ============================================================================
# ANSIBLE INTEGRATION FUNCTIONS
# ============================================================================

# Install/refresh the `homeboi` command (symlink) after first-time setup.
install_global_command() {
    if [[ -x "${HOMEBOI_HOME}/install.sh" ]]; then
        "${HOMEBOI_HOME}/install.sh" || true
    fi
}

# Check if Ansible prerequisites are installed
check_ansible_prerequisites() {
    echo -e "${UI_PRIMARY}🔍 Checking Ansible prerequisites...${UI_RESET}"
    
    # Check if Ansible is installed
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        echo -e "${UI_WARNING}⚠ Ansible is not installed${UI_RESET}"
        echo -e "${UI_MUTED}Installing Ansible...${UI_RESET}"
        
        # Install Ansible
        if command -v apt >/dev/null 2>&1; then
            sudo apt update >/dev/null 2>&1
            sudo apt install -y ansible >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y ansible >/dev/null 2>&1
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y ansible >/dev/null 2>&1
        else
            echo -e "${UI_ERROR}❌ Could not install Ansible automatically${UI_RESET}"
            echo -e "${UI_MUTED}Please install Ansible manually: https://docs.ansible.com/ansible/latest/installation_guide/${UI_RESET}"
            return 1
        fi
        
        if command -v ansible-playbook >/dev/null 2>&1; then
            echo -e "${UI_SUCCESS}✅ Ansible installed successfully${UI_RESET}"
        else
            echo -e "${UI_ERROR}❌ Ansible installation failed${UI_RESET}"
            return 1
        fi
    else
        echo -e "${UI_SUCCESS}✅ Ansible is already installed${UI_RESET}"
    fi
    
    # Install Ansible requirements
    if [[ -f "ansible/requirements.yml" ]]; then
        echo -e "${UI_PRIMARY}📦 Installing Ansible collections...${UI_RESET}"
        ansible-galaxy collection install -r ansible/requirements.yml >/dev/null 2>&1
        echo -e "${UI_SUCCESS}✅ Ansible collections installed${UI_RESET}"
    fi
    
    return 0
}

# Run Ansible deployment with shell wizard
run_ansible_deployment() {
    # Check for existing configuration and validate it
    local needs_wizard=false
    local settings_file="${HOMEBOI_HOME}/settings.env"
    local force_wizard="${1:-false}"

    if [[ "$force_wizard" == "true" ]]; then
        needs_wizard=true
        echo -e "${UI_PRIMARY}🧙 Re-running configuration wizard...${UI_RESET}"
    fi
    
    if [[ ! -f "$settings_file" ]]; then
        needs_wizard=true
        echo -e "${UI_WARNING}⚠ No configuration file found${UI_RESET}"
    else
        # Check if configuration is complete
        # shellcheck disable=SC1090
        source "$settings_file" 2>/dev/null || true
        if [[ -z "${HOMEBOI_USERNAME:-}" || -z "${HOMEBOI_PASSWORD:-}" || -z "${SERVER_IP:-}" ]]; then
            needs_wizard=true
            echo -e "${UI_WARNING}⚠ Configuration file is incomplete${UI_RESET}"
        else
            # Ensure HOMEBOI_EMAIL exists (needed to automate Overseerr/Jellyseerr bootstrap)
            if [[ -z "${HOMEBOI_EMAIL:-}" ]]; then
                local default_email="admin@homeboi.local"
                echo -e "${UI_WARNING}⚠ HOMEBOI_EMAIL not set - defaulting to ${default_email}${UI_RESET}"
                if grep -q "^HOMEBOI_EMAIL=" "$settings_file"; then
                    sed -i "s/^HOMEBOI_EMAIL=.*/HOMEBOI_EMAIL=${default_email}/" "$settings_file"
                else
                    echo "HOMEBOI_EMAIL=${default_email}" >> "$settings_file"
                fi
                export HOMEBOI_EMAIL="${default_email}"
            fi

            # Ensure primary setup preference exists (used for dashboard checklist ordering)
            if [[ -z "${PRIMARY_MEDIA_SERVER:-}" ]]; then
                local default_primary_media="jellyfin"
                if grep -q "^PRIMARY_MEDIA_SERVER=" "$settings_file"; then
                    sed -i "s/^PRIMARY_MEDIA_SERVER=.*/PRIMARY_MEDIA_SERVER=${default_primary_media}/" "$settings_file"
                else
                    echo "PRIMARY_MEDIA_SERVER=${default_primary_media}" >> "$settings_file"
                fi
                export PRIMARY_MEDIA_SERVER="${default_primary_media}"
            fi
            if [[ -z "${PRIMARY_REQUEST_APP:-}" ]]; then
                local default_primary_request="jellyseerr"
                if grep -q "^PRIMARY_REQUEST_APP=" "$settings_file"; then
                    sed -i "s/^PRIMARY_REQUEST_APP=.*/PRIMARY_REQUEST_APP=${default_primary_request}/" "$settings_file"
                else
                    echo "PRIMARY_REQUEST_APP=${default_primary_request}" >> "$settings_file"
                fi
                export PRIMARY_REQUEST_APP="${default_primary_request}"
            fi
            echo -e "${UI_SUCCESS}✓ Using existing configuration${UI_RESET}"
        fi
    fi
    
    if [[ "$needs_wizard" == "true" ]]; then
        echo -e "${UI_PRIMARY}🧙 Running configuration wizard...${UI_RESET}"
        echo
        
        # Run the minimal installation wizard
        source "$HOMEBOI_LIB/minimal_wizard.sh"
        set +e
        run_minimal_wizard
        local wizard_rc=$?
        set -e
        if [[ $wizard_rc -eq 2 ]]; then
            # User cancelled (not an error)
            echo -e "${UI_MUTED}Setup cancelled${UI_RESET}"
            return 0
        elif [[ $wizard_rc -ne 0 ]]; then
            echo -e "${UI_ERROR}❌ Configuration wizard failed${UI_RESET}"
            return 1
        fi
        
        # Install global homeboi command after first-time setup
        install_global_command
    fi
    
    echo
    echo -e "${UI_PRIMARY}🚀 Starting Ansible deployment...${UI_RESET}"
    echo
    
    # Change to Homeboi directory
    cd "$HOMEBOI_HOME"
    
    # Extract configuration and pass as extra-vars
    echo -e "${UI_MUTED}Loading configuration from settings.env...${UI_RESET}"
    local extra_vars=""
    if [[ -f "extract-config.sh" ]]; then
        extra_vars=$(./extract-config.sh | tr '\n' ' ' | sed 's/ $//')
        echo -e "${UI_SUCCESS}✓ Configuration loaded${UI_RESET}"
    fi
    
    # Run the main Ansible playbook with extracted config
    if ansible-playbook ansible/site.yml -e "$extra_vars"; then
        echo
        echo -e "${UI_SUCCESS}🎉 Deployment completed successfully!${UI_RESET}"
        echo
        # Nudge users into the web UI for any remaining manual steps (Plex/requests).
        # shellcheck disable=SC1090
        source "$settings_file" 2>/dev/null || true
        local dash_ip="${SERVER_IP:-localhost}"
        echo -e "${UI_PRIMARY}➡ Next: open the Homeboi Dashboard to finish any remaining setup steps:${UI_RESET}"
        echo -e "${UI_CYAN}   http://${dash_ip}:6969${UI_RESET}"
        echo -e "${UI_MUTED}   Check the “Setup Checklist” there (Plex/Overseerr/Jellyseerr may need one-time interactive sign-in).${UI_RESET}"
        echo
        echo -e "${UI_PRIMARY}📋 Service URLs have been saved to service_urls.env${UI_RESET}"
        echo -e "${UI_MUTED}Run ./homeboi-status.sh to see all URLs${UI_RESET}"
        echo
    else
        echo
        echo -e "${UI_ERROR}❌ Deployment failed${UI_RESET}"
        echo -e "${UI_MUTED}Check the Ansible output above for details${UI_RESET}"
        return 1
    fi
}

# Run Ansible removal
run_ansible_removal() {
    echo -e "${UI_WARNING}🗑️ Starting Ansible removal...${UI_RESET}"
    echo
    
    # Change to Homeboi directory
    cd "$HOMEBOI_HOME"
    
    # Run the removal playbook
    if ansible-playbook ansible/site-remove.yml; then
        echo
        echo -e "${UI_SUCCESS}✅ Services removed successfully${UI_RESET}"
        echo
    else
        echo
        echo -e "${UI_ERROR}❌ Removal failed${UI_RESET}"
        echo -e "${UI_MUTED}Check the Ansible output above for details${UI_RESET}"
        return 1
    fi
}

# Show Ansible-powered status
show_ansible_status() {
    if [[ -f "$HOMEBOI_HOME/homeboi-status.sh" ]]; then
        "$HOMEBOI_HOME/homeboi-status.sh"
    else
        echo -e "${UI_WARNING}⚠ Status script not found${UI_RESET}"
        echo -e "${UI_MUTED}Deploy the stack first to generate status dashboard${UI_RESET}"
    fi
}


# Cleanup and exit
cleanup_and_exit() {
    clear
    exit 0
}

# Check dependencies
check_dependencies() {
    local missing=()
    
    command -v docker >/dev/null 2>&1 || missing+=("docker")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${UI_ERROR}✗ Missing dependencies: ${missing[*]}${UI_RESET}"
        echo -e "Please install them first:"
        echo -e "  ${UI_PRIMARY}sudo apt update && sudo apt install docker.io python3${UI_RESET}"
        echo -e "  ${UI_PRIMARY}sudo systemctl start docker && sudo usermod -aG docker \$USER${UI_RESET}"
        echo
        echo -e "${UI_WARNING}Note: You may need to log out and back in after adding yourself to the docker group${UI_RESET}"
        exit 1
    fi
}

# Main entry point
main() {
    # Check dependencies first
    check_dependencies
    
    # Generate initial dashboard
    update_dashboard_cache
    
    # Start main menu
    main_menu
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
