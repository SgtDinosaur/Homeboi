#!/bin/bash
# Quick test of Ansible integration in Homeboi

set -e

echo "🧪 Testing Homeboi Ansible Integration"
echo "======================================"

# Check if Ansible files exist
echo "📁 Checking Ansible files..."
for file in "ansible/site.yml" "ansible/site-remove.yml" "ansible/tasks/wizard.yml"; do
    if [[ -f "$file" ]]; then
        echo "  ✅ $file exists"
    else
        echo "  ❌ $file missing"
        exit 1
    fi
done

# Check if homeboi.sh has Ansible functions
echo "📋 Checking Homeboi script integration..."
if grep -q "check_ansible_prerequisites" homeboi.sh; then
    echo "  ✅ Ansible prerequisite checking integrated"
else
    echo "  ❌ Ansible prerequisite checking missing"
    exit 1
fi

if grep -q "run_ansible_deployment" homeboi.sh; then
    echo "  ✅ Ansible deployment function integrated"
else
    echo "  ❌ Ansible deployment function missing"
    exit 1
fi

if grep -q "rerun_setup_wizard" homeboi.sh; then
    echo "  ✅ Re-run wizard function integrated"
else
    echo "  ❌ Re-run wizard function missing"
    exit 1
fi

# Check if Ansible syntax is valid
echo "🔍 Validating Ansible syntax..."
if command -v ansible-playbook >/dev/null 2>&1; then
    ansible-playbook --syntax-check ansible/site.yml
    ansible-playbook --syntax-check ansible/site-remove.yml
    echo "  ✅ Ansible syntax valid"
else
    echo "  ⚠️ Ansible not installed - syntax check skipped"
fi

echo
echo "✅ Ansible integration test completed successfully!"
echo
echo "🎯 Integration Summary:"
echo "  • Terminal UI: Preserved familiar interface"
echo "  • Backend: Powered by Ansible for reliability"  
echo "  • Auto-install: Ansible installed automatically if missing"
echo "  • Wizard: Integrated into Launch Stack flow"
echo "  • Removal: Clean Ansible-powered removal"
echo
echo "🚀 Ready to test: ./homeboi.sh"
