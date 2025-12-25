#!/bin/bash
# lib/services.sh - Service management functions for Homeboi (Ansible deployment)

# Services shown in the UI (container names mostly match; see service_container_name)
declare -a HOMEBOI_SERVICES=(
  "overseerr" "jellyseerr" "plex" "jellyfin"
  "radarr" "sonarr" "sabnzbd" "prowlarr" "bazarr"
  "recyclarr" "home-assistant" "gluetun" "web-dashboard"
)

declare -A SERVICE_DESCRIPTIONS=(
  ["plex"]="Media streaming server"
  ["jellyfin"]="Open source media server"
  ["overseerr"]="Request management UI"
  ["jellyseerr"]="Jellyfin-focused request management UI"
  ["sabnzbd"]="Usenet downloader"
  ["gluetun"]="VPN client for secure downloads"
  ["prowlarr"]="Indexer manager"
  ["sonarr"]="TV show management"
  ["radarr"]="Movie management"
  ["bazarr"]="Subtitle management"
  ["recyclarr"]="Quality profile and custom format sync"
  ["home-assistant"]="Home automation platform"
  ["web-dashboard"]="Homeboi web dashboard interface"
)

declare -A SERVICE_PORTS=(
  ["plex"]="32400"
  ["jellyfin"]="8096"
  ["overseerr"]="5055"
  ["jellyseerr"]="5056"
  ["sabnzbd"]="8080"
  ["prowlarr"]="9696"
  ["sonarr"]="8989"
  ["radarr"]="7878"
  ["bazarr"]="6767"
  ["home-assistant"]="8123"
  ["web-dashboard"]="6969"
  ["gluetun"]=""
  ["recyclarr"]=""
)

# Map Homeboi service name to Docker container name where they differ.
service_container_name() {
  local service="$1"
  case "$service" in
    web-dashboard) echo "homeboi-web" ;;
    *) echo "$service" ;;
  esac
}

get_service_status() {
  local service="$1"

  if ! command -v docker >/dev/null 2>&1; then
    echo "unavailable"
    return 1
  fi

  local container_name
  container_name="$(service_container_name "$service")"

  local container_info
  container_info="$(docker ps -a --format "{{.Names}}\t{{.Status}}" | grep -E "^${container_name}\t" 2>/dev/null || true)"

  if [[ -z "$container_info" ]]; then
    echo "not_installed"
    return 1
  fi

  local status
  status="${container_info#*\t}"

  if [[ "$status" == *"Restarting"* ]]; then
    echo "restarting"
    return 0
  fi

  if [[ "$status" == Up* ]]; then
    local health
    health="$(docker inspect "$container_name" --format "{{.State.Health.Status}}" 2>/dev/null || true)"
    if [[ "$health" == "unhealthy" ]]; then
      echo "unhealthy"
      return 0
    fi
    if [[ "$health" == "starting" ]]; then
      echo "starting"
      return 0
    fi
    echo "running"
    return 0
  fi

  if [[ "$status" == Exited* ]]; then
    local exit_code
    exit_code="$(docker inspect "$container_name" --format "{{.State.ExitCode}}" 2>/dev/null || echo 0)"
    if [[ "$exit_code" != "0" ]]; then
      echo "crashed"
    else
      echo "stopped"
    fi
    return 0
  fi

  echo "stopped"
  return 0
}

start_service() {
  local service="$1"
  local container_name
  container_name="$(service_container_name "$service")"

  echo -e "${UI_PRIMARY}Starting ${service}...${UI_RESET}"

  if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$" 2>/dev/null; then
    echo -e "${UI_ERROR}✗ ${service} is not installed (use 'Launch Stack')${UI_RESET}"
    return 1
  fi

  if docker start "$container_name" >/dev/null 2>&1; then
    echo -e "${UI_SUCCESS}✓ ${service} started successfully${UI_RESET}"
    return 0
  fi

  echo -e "${UI_ERROR}✗ Failed to start ${service}${UI_RESET}"
  return 1
}

stop_service() {
  local service="$1"
  local container_name
  container_name="$(service_container_name "$service")"

  echo -e "${UI_PRIMARY}Stopping ${service}...${UI_RESET}"

  if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$" 2>/dev/null; then
    echo -e "${UI_WARNING}! ${service} is not installed${UI_RESET}"
    return 1
  fi

  if docker stop "$container_name" >/dev/null 2>&1; then
    echo -e "${UI_SUCCESS}✓ ${service} stopped successfully${UI_RESET}"
    return 0
  fi

  echo -e "${UI_ERROR}✗ Failed to stop ${service}${UI_RESET}"
  return 1
}

restart_service() {
  local service="$1"
  local container_name
  container_name="$(service_container_name "$service")"

  echo -e "${UI_PRIMARY}Restarting ${service}...${UI_RESET}"

  if ! docker ps -a --format "{{.Names}}" | grep -q "^${container_name}$" 2>/dev/null; then
    echo -e "${UI_WARNING}! ${service} is not installed${UI_RESET}"
    return 1
  fi

  if docker restart "$container_name" >/dev/null 2>&1; then
    echo -e "${UI_SUCCESS}✓ ${service} restarted successfully${UI_RESET}"
    return 0
  fi

  echo -e "${UI_ERROR}✗ Failed to restart ${service}${UI_RESET}"
  return 1
}

start_all_services() {
  echo -e "${UI_PRIMARY}Starting all Homeboi services...${UI_RESET}"
  local failures=0
  for service in "${HOMEBOI_SERVICES[@]}"; do
    start_service "$service" || failures=$((failures + 1))
  done
  return "$failures"
}

stop_all_services() {
  echo -e "${UI_PRIMARY}Stopping all Homeboi services...${UI_RESET}"
  local failures=0
  for service in "${HOMEBOI_SERVICES[@]}"; do
    stop_service "$service" || failures=$((failures + 1))
  done
  return "$failures"
}

restart_all_services() {
  echo -e "${UI_PRIMARY}Restarting all Homeboi services...${UI_RESET}"
  local failures=0
  for service in "${HOMEBOI_SERVICES[@]}"; do
    restart_service "$service" || failures=$((failures + 1))
  done
  return "$failures"
}

services_deployed() {
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi

  local core_containers=("homeboi-web" "sonarr" "radarr" "prowlarr" "sabnzbd" "jellyfin" "plex")
  for c in "${core_containers[@]}"; do
    if docker ps -a --format "{{.Names}}" | grep -q "^${c}$" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

update_all_services() {
  echo -e "${UI_PRIMARY}Updating stack (re-running Ansible playbook)...${UI_RESET}"
  echo
  if ! check_ansible_prerequisites; then
    return 1
  fi
  run_ansible_deployment "false"
}
