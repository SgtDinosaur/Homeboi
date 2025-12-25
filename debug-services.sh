#!/bin/bash
echo "Testing service connectivity..."

SERVER_IP="${SERVER_IP:-127.0.0.1}"

echo -n "Prowlarr: "
if timeout 3 curl -s "http://${SERVER_IP}:9696" >/dev/null 2>&1; then echo "OK"; else echo "FAIL"; fi

echo -n "Sonarr: "  
if timeout 3 curl -s "http://${SERVER_IP}:8989" >/dev/null 2>&1; then echo "OK"; else echo "FAIL"; fi

echo -n "Radarr: "
if timeout 3 curl -s "http://${SERVER_IP}:7878" >/dev/null 2>&1; then echo "OK"; else echo "FAIL"; fi

echo
echo "Testing API endpoints..."

echo -n "Prowlarr API: "
timeout 3 curl -s "http://${SERVER_IP}:9696/api/v1/system/status" >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo -n "Sonarr API: " 
timeout 3 curl -s "http://${SERVER_IP}:8989/api/v1/system/status" >/dev/null 2>&1 && echo "OK" || echo "FAIL"

echo -n "Radarr API: "
timeout 3 curl -s "http://${SERVER_IP}:7878/api/v1/system/status" >/dev/null 2>&1 && echo "OK" || echo "FAIL"
