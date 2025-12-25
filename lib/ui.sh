#!/bin/bash
# lib/ui.sh - Homeboi UI library (inspired by nodeboi)

# Colors (matching nodeboi style)
[[ -z "$UI_PRIMARY" ]] && readonly UI_PRIMARY='\033[0;36m'
[[ -z "$UI_SUCCESS" ]] && readonly UI_SUCCESS='\033[38;5;46m'
[[ -z "$UI_WARNING" ]] && readonly UI_WARNING='\033[38;5;226m'
[[ -z "$UI_ERROR" ]] && readonly UI_ERROR='\033[38;5;196m'
[[ -z "$UI_MUTED" ]] && readonly UI_MUTED='\033[38;5;240m'
[[ -z "$UI_BOLD" ]] && readonly UI_BOLD='\033[1m'
[[ -z "$UI_DIM" ]] && readonly UI_DIM='\033[2m'
[[ -z "$UI_RESET" ]] && readonly UI_RESET='\033[0m'
[[ -z "$PINK" ]] && readonly PINK='\033[38;5;213m'

# Print Homeboi header (similar to nodeboi style)
print_header() {
    local header_color="${PINK:-\033[38;5;213m}"
    local bold="${UI_BOLD:-\033[1m}"
    local reset="${UI_RESET:-\033[0m}"
    local cyan="${UI_PRIMARY:-\033[0;36m}"
    local yellow="${UI_WARNING:-\033[38;5;226m}"
    local version="v0.0.1"
    if [[ -n "${HOMEBOI_HOME:-}" && -f "${HOMEBOI_HOME}/VERSION" ]]; then
        local version_raw
        version_raw="$(tr -d ' \t\r\n' < "${HOMEBOI_HOME}/VERSION" 2>/dev/null || true)"
        [[ -n "${version_raw}" ]] && version="v${version_raw}"
    fi
    
    echo -e "${header_color}${bold}"
    cat << "HEADER"
        ██╗  ██╗ ██████╗ ███╗   ███╗███████╗██████╗  ██████╗ ██╗
        ██║  ██║██╔═══██╗████╗ ████║██╔════╝██╔══██╗██╔═══██╗██║
        ███████║██║   ██║██╔████╔██║█████╗  ██████╔╝██║   ██║██║
        ██╔══██║██║   ██║██║╚██╔╝██║██╔══╝  ██╔══██╗██║   ██║██║
        ██║  ██║╚██████╔╝██║ ╚═╝ ██║███████╗██████╔╝╚██████╔╝██║
        ╚═╝  ╚═╝ ╚═════╝ ╚═╝     ╚═╝╚══════╝╚═════╝  ╚═════╝ ╚═╝
HEADER
    echo -e "${reset}"
    echo -e "                        ${cyan}HOME MEDIA STACK AUTOMATION${reset}"
    echo -e "                                 ${yellow}${version}${reset}"
    echo
}

# Print header with dashboard (for wizard steps)
print_header_with_dashboard() {
    print_header
    
    # Show dashboard if dashboard generation function exists
    if declare -f generate_dashboard >/dev/null; then
        generate_dashboard
        echo
    fi
}

# Fancy select menu with keyboard navigation (like nodeboi)
fancy_select_menu() {
    local title="$1"
    shift
    local options=("$@")
    local selected=0
    local total=${#options[@]}
    
    # Cache file for dashboard
    local dashboard_cache_file="$HOMEBOI_HOME/cache/dashboard.cache"
    local lock_file="$HOMEBOI_HOME/cache/dashboard.lock"
    
    # Hide cursor
    printf '\033[?25l' >&2
    
    # Function to show cursor on exit
    show_cursor() {
        printf '\033[?25h' >&2
    }
    
    # Trap to restore cursor
    trap show_cursor EXIT INT TERM
    
    local last_selected=-1
    local needs_full_redraw=true
    local last_dashboard=""
    local dashboard_read_time=0
    
    while true; do
        # Read dashboard content
        local current_dashboard=""
        local current_dashboard_time=0
        
        # Check cache file modification time
        if [[ -f "$dashboard_cache_file" ]]; then
            current_dashboard_time=$(stat -c %Y "$dashboard_cache_file" 2>/dev/null || echo 0)
        fi
        
        dashboard_read_time="$current_dashboard_time"
        
        # Clean up stale lock files
        if [[ -f "$lock_file" ]]; then
            local lock_pid=$(cat "$lock_file" 2>/dev/null)
            if [[ -z "$lock_pid" ]] || ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -f "$lock_file" 2>/dev/null || true
            fi
        fi
        
        # Use cached dashboard but generate fresh if cache is empty or very old
        current_dashboard=""
        local cache_age=0
        
        if [[ -f "$dashboard_cache_file" ]]; then
            cache_age=$(($(date +%s) - current_dashboard_time))
            
            # Read cache if it's recent (less than 10 seconds old)
            if [[ $cache_age -lt 10 && -s "$dashboard_cache_file" ]]; then
                {
                    local line
                    while IFS= read -r line || [[ -n "$line" ]]; do
                        current_dashboard+="$line"$'\n'
                    done
                } < "$dashboard_cache_file" 2>/dev/null
                current_dashboard="${current_dashboard%$'\n'}"
            fi
        fi
        
        # Generate fresh dashboard if cache is empty, old, or doesn't have status circles
        if [[ -z "$current_dashboard" || $cache_age -gt 10 || ! "$current_dashboard" =~ 🟢|🟡|🔴|⚫ ]]; then
            if declare -f generate_dashboard >/dev/null; then
                current_dashboard=$(generate_dashboard 2>/dev/null || echo "Services Status\n---------------\nDashboard unavailable")
                # Update cache with fresh content
                echo -e "$current_dashboard" > "$dashboard_cache_file" 2>/dev/null || true
            fi
        fi
        
        # Only redraw when selection changes, dashboard changes, or first render
        if [[ "$needs_full_redraw" == true ]] || [[ "$selected" != "$last_selected" ]] || [[ "$current_dashboard" != "$last_dashboard" ]]; then
            clear >&2
            
            # Show header
            print_header >&2
            
            if [[ -n "$current_dashboard" ]]; then
                echo -e "$current_dashboard" >&2
            fi
            
            echo >&2
            echo -e "${UI_BOLD}$title${UI_RESET}" >&2
            echo -e "${UI_PRIMARY}$(printf '=%.0s' $(seq 1 ${#title}))${UI_RESET}" >&2
            echo >&2
            
            # Show options
            for i in "${!options[@]}"; do
                local prefix="  "
                local suffix=""
                
                if [[ $i -eq $selected ]]; then
                    prefix="${UI_PRIMARY}> ${UI_RESET}"
                    suffix="${UI_PRIMARY}${UI_RESET}"
                else
                    prefix="  "
                fi
                
                echo -e "${prefix}${options[$i]}${suffix}" >&2
            done
            
            echo >&2
            echo -e "${UI_MUTED}Use ↑/↓ to navigate, Enter to select, q to quit${UI_RESET}" >&2
            
            last_selected="$selected"
            last_dashboard="$current_dashboard"
            needs_full_redraw=false
        fi
        
        # Read single key
        read -rsn1 key >&2
        
        case "$key" in
            $'\x1b')  # ESC sequence
                read -rsn2 -t 0.1 seq >&2
                case "$seq" in
                    '[A') # Up arrow
                        ((selected > 0)) && ((selected--))
                        ;;
                    '[B') # Down arrow
                        ((selected < total - 1)) && ((selected++))
                        ;;
                esac
                ;;
            '') # Enter
                show_cursor
                trap - EXIT INT TERM
                echo "$selected"
                return 0
                ;;
            'q'|'Q') # Quit
                show_cursor
                trap - EXIT INT TERM
                return 1
                ;;
            'j') # Vim down
                ((selected < total - 1)) && ((selected++))
                ;;
            'k') # Vim up
                ((selected > 0)) && ((selected--))
                ;;
        esac
    done
}

# Pause for user input
press_enter() {
    echo
    echo -e "${UI_MUTED}Press Enter to continue...${UI_RESET} " && read -r
}

# Simple yes/no prompt
confirm_prompt() {
    local message="$1"
    local options=("Yes" "No")
    
    if selection=$(fancy_select_menu "$message" "${options[@]}"); then
        case $selection in
            0) return 0 ;;  # Yes
            1) return 1 ;;  # No
        esac
    else
        return 255  # User pressed 'q'
    fi
}

# Storage-aware select menu that shows storage info above menu
show_storage_menu() {
    local storage_info="$1"
    local title="$2"
    shift 2
    local options=("$@")
    local selected=0
    local total=${#options[@]}
    
    # Hide cursor
    tput civis
    
    while true; do
        clear >&2
        
        # Show header and dashboard
        print_header_with_dashboard >&2
        
        # Show storage information
        echo -e "$storage_info" >&2
        
        # Show menu title
        echo -e "${UI_BOLD}$title${UI_RESET}" >&2
        echo -e "${UI_PRIMARY}$(printf '=%.0s' $(seq 1 ${#title}))${UI_RESET}" >&2
        echo >&2
        
        # Show options with selection highlight
        for ((i=0; i<total; i++)); do
            if [[ $i -eq $selected ]]; then
                echo -e "${UI_PRIMARY}> ${options[i]}${UI_RESET}" >&2
            else
                echo -e "  ${options[i]}" >&2
            fi
        done
        
        echo >&2
        echo -e "${UI_MUTED}Use ↑/↓ to navigate, Enter to select, q to quit${UI_RESET}" >&2
        
        # Read input
        read -rsn1 key
        case "$key" in
            $'\033')
                read -rsn2 key
                case "$key" in
                    '[A'|'[k') # Up arrow or k
                        ((selected > 0)) && ((selected--))
                        ;;
                    '[B'|'[j') # Down arrow or j  
                        ((selected < total-1)) && ((selected++))
                        ;;
                esac
                ;;
            'k'|'K')
                ((selected > 0)) && ((selected--))
                ;;
            'j'|'J')
                ((selected < total-1)) && ((selected++))
                ;;
            $'\n'|'') # Enter
                tput cnorm >&2
                echo "$selected"
                return 0
                ;;
            'q'|'Q')
                tput cnorm >&2
                return 1
                ;;
        esac
    done
}
