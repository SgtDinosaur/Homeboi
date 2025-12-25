#!/bin/bash
# Extract configuration from settings.env and pass to Ansible

CONFIG_FILE="${1:-settings.env}"

# Defaults (prefer failing early over unsafe defaults)
HOMEBOI_USERNAME=""
HOMEBOI_PASSWORD=""
SERVER_IP=""
TIMEZONE="UTC"
VPN_SERVICE_PROVIDER=""
OPENVPN_USER=""
OPENVPN_PASSWORD=""
NZBGEEK_API=""
DRUNKENSLUG_API=""
NZBPLANET_API=""
ENABLE_ARR_AUTH="true"
HOMEBOI_EMAIL=""
HOSTNAME=""
PRIMARY_MEDIA_SERVER="jellyfin"
PRIMARY_REQUEST_APP="jellyseerr"

# Source the config file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    set -a
    source "$CONFIG_FILE"
    set +a
else
    echo "settings file not found: $CONFIG_FILE (run the Homeboi wizard)" >&2
    exit 1
fi

# Basic validation: these are required for idempotent automation
if [[ -z "${HOMEBOI_USERNAME}" || -z "${HOMEBOI_PASSWORD}" || -z "${SERVER_IP}" ]]; then
    echo "settings file is incomplete: $CONFIG_FILE (run the Homeboi wizard)" >&2
    exit 1
fi

# Output as Ansible extra-vars format
echo "homeboi_username=$HOMEBOI_USERNAME"
echo "homeboi_password=$HOMEBOI_PASSWORD"
echo "server_ip=$SERVER_IP"
echo "timezone=$TIMEZONE"
echo "vpn_service_provider=$VPN_SERVICE_PROVIDER"
echo "openvpn_user=$OPENVPN_USER"
echo "openvpn_password=$OPENVPN_PASSWORD"
echo "nzbgeek_api=$NZBGEEK_API"
echo "drunkenslug_api=$DRUNKENSLUG_API"
echo "nzbplanet_api=$NZBPLANET_API"
echo "enable_arr_auth=$ENABLE_ARR_AUTH"
echo "homeboi_email=$HOMEBOI_EMAIL"
echo "homeboi_hostname=$HOSTNAME"
echo "primary_media_server=$PRIMARY_MEDIA_SERVER"
echo "primary_request_app=$PRIMARY_REQUEST_APP"
