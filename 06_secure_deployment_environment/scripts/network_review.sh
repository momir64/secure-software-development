#!/bin/bash
echo "--- NETWORK REVIEW ---"

#  Network interfaces and routes
echo "[*] Network interfaces and routes:"
ip addr show
echo ""
ip route show

# Check for promiscuous mode
echo -e "\n[*] Checking for interfaces in promiscuous mode:"
PROMISC_FOUND=0
while IFS= read -r iface; do
    FLAGS=$(ip link show "$iface" 2>/dev/null | grep -o 'PROMISC')
    if [ -n "$FLAGS" ]; then
        echo -e "  \033[0;31m[WARNING]\033[0m Interface '$iface' is in PROMISCUOUS mode (possible packet sniffing)."
        PROMISC_FOUND=$((PROMISC_FOUND + 1))
    fi
done < <(ip -o link show | awk -F': ' '{print $2}')
if [ "$PROMISC_FOUND" -eq 0 ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No interfaces in promiscuous mode."
fi

# Check for IP forwarding
echo -e "\n[*] Checking IP forwarding status:"
IPV4_FWD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
IPV6_FWD=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)
if [ "$IPV4_FWD" = "1" ]; then
    echo -e "  \033[0;31m[WARNING]\033[0m IPv4 forwarding is ENABLED (net.ipv4.ip_forward=1). System may act as a router."
else
    echo -e "  \033[0;32m[OK]\033[0m IPv4 forwarding is disabled."
fi
if [ "$IPV6_FWD" = "1" ]; then
    echo -e "  \033[0;31m[WARNING]\033[0m IPv6 forwarding is ENABLED (net.ipv6.conf.all.forwarding=1)."
else
    echo -e "  \033[0;32m[OK]\033[0m IPv6 forwarding is disabled."
fi

# DNS configuration
echo -e "\n[*] DNS configuration (/etc/resolv.conf):"
cat /etc/resolv.conf
if ! grep -q "nameserver" /etc/resolv.conf; then
    echo -e "Status: \033[0;31m[WARNING]\033[0m No nameservers found in resolv.conf!"
fi

# Check DNS config for suspicious entries
echo -e "\n[*] Auditing /etc/hosts for suspicious entries:"
# Filtriraj standardne unose (localhost, ip6-localhost i sl.)
SUSPICIOUS=$(grep -v "^#" /etc/hosts | grep -v "^\s*$" \
    | grep -v "127\.0\.0\.1\s*localhost" \
    | grep -v "::1\s*localhost" \
    | grep -v "127\.0\.1\.1" \
    | grep -v "ip6-")
if [ -z "$SUSPICIOUS" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m No unexpected entries in /etc/hosts."
else
    echo -e "Status: \033[0;33m[WARNING]\033[0m Non-standard entries found in /etc/hosts (verify each one):"
    echo "$SUSPICIOUS"
fi

# Firewall Rules (IPv4 & IPv6)
audit_fw() {
    local proto=$1
    local cmd=$2
    echo -e "\n[*] $proto Rules (using $cmd):"
    $cmd -L -v -n
    
    # Audit logic
    if $cmd -S | grep -q "\-P.*ACCEPT"; then
        echo -e "Status: \033[0;31m[CRITICAL]\033[0m Default policy is ACCEPT. All traffic is allowed by default."
    else
        echo -e "Status: \033[0;32m[OK]\033[0m Default policy is restrictive."
    fi
}

audit_fw "IPv4" "iptables"
audit_fw "IPv6" "ip6tables"

# Check for empty chains
echo -e "\n[*] Checking for empty firewall chains (no rules defined):"
for chain in INPUT OUTPUT FORWARD; do
    COUNT=$(iptables -L "$chain" --line-numbers 2>/dev/null | grep -c "^[0-9]")
    if [ "$COUNT" -eq 0 ]; then
        echo -e "  \033[0;33m[WARNING]\033[0m iptables chain '$chain' has no rules."
    else
        echo -e "  \033[0;32m[OK]\033[0m iptables chain '$chain' has $COUNT rule(s)."
    fi
done

# Check for outbound filtering
echo -e "\n[*] Checking for outbound (egress) filtering:"
OUTPUT_RULES=$(iptables -L OUTPUT --line-numbers 2>/dev/null | grep -c "^[0-9]")
OUTPUT_POLICY=$(iptables -S OUTPUT 2>/dev/null | grep "^-P OUTPUT" | awk '{print $3}')
if [ "$OUTPUT_POLICY" = "ACCEPT" ] && [ "$OUTPUT_RULES" -eq 0 ]; then
    echo -e "Status: \033[0;31m[WARNING]\033[0m No outbound rules and default OUTPUT policy is ACCEPT."
    echo "  Egress filtering is missing. A compromised host can freely communicate outbound."
else
    echo -e "Status: \033[0;32m[OK]\033[0m OUTPUT chain has rules or a restrictive default policy."
fi

# Checking for SSH port configuration
echo -e "\n[*] Checking SSH port configuration:"
SSH_PORT=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22 (default, Port line not set in sshd_config)"
    echo -e "Status: \033[0;33m[INFO]\033[0m SSH is running on port 22 (default). Consider changing to reduce automated scanning exposure."
elif [ "$SSH_PORT" = "22" ]; then
    echo -e "Status: \033[0;33m[INFO]\033[0m SSH is explicitly set to port 22 (default). Consider changing to reduce automated scanning exposure."
else
    echo -e "Status: \033[0;32m[OK]\033[0m SSH is configured on non-default port: $SSH_PORT"
fi

# Firewall Persistence
echo -e "\n[*] Checking firewall persistence:"
PERSISTENCE_FOUND=false
FILES=("/etc/network/if-pre-up.d/iptables" "/etc/iptables/rules.v4" "/etc/iptables.rules")

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "Found persistence file: $file"
        PERSISTENCE_FOUND=true
    fi
done

if [ "$PERSISTENCE_FOUND" = false ]; then
    echo -e "Status: \033[0;31m[WARNING]\033[0m No standard persistence found. Rules will disappear after reboot."
fi

# Check for unsaved firewall rules
echo -e "\n[*] Checking if saved firewall rules match active rules:"
SAVED_RULES_FILE="/etc/iptables/rules.v4"
if [ -f "$SAVED_RULES_FILE" ]; then
    ACTIVE=$(iptables-save 2>/dev/null | grep -v "^#" | sort)
    SAVED=$(grep -v "^#" "$SAVED_RULES_FILE" | sort)
    if [ "$ACTIVE" = "$SAVED" ]; then
        echo -e "Status: \033[0;32m[OK]\033[0m Active rules match saved rules in $SAVED_RULES_FILE."
    else
        echo -e "Status: \033[0;31m[WARNING]\033[0m Active iptables rules DO NOT match saved rules in $SAVED_RULES_FILE."
        echo "  Manual changes may have been made without saving. A reboot would revert to saved (different) rules."
    fi
else
    echo -e "Status: \033[0;33m[INFO]\033[0m No saved rules file found at $SAVED_RULES_FILE to compare against."
fi

# IPv6 Check
echo -e "\n[*] Auditing IPv6 status:"
IPV6_STATUS=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
if [ "$IPV6_STATUS" = "1" ]; then
    echo -e "Status: \033[0;32m[OK]\033[0m IPv6 is disabled."
else
    echo -e "Status: \033[0;33m[INFO]\033[0m IPv6 is enabled. Ensure you have ip6tables rules configured."
fi

# Check if IPv6 is enabled but no ip6tables rules exist
if [ "$IPV6_STATUS" != "1" ]; then
    echo -e "\n[*] Checking ip6tables rules (IPv6 is active):"
    IP6_RULES=$(ip6tables -L 2>/dev/null | grep -c "^[A-Z]")
    IP6_INPUT_POLICY=$(ip6tables -S INPUT 2>/dev/null | grep "^-P INPUT" | awk '{print $3}')
    if [ "$IP6_INPUT_POLICY" = "ACCEPT" ]; then
        IP6_RULE_COUNT=$(ip6tables -L INPUT --line-numbers 2>/dev/null | grep -c "^[0-9]")
        if [ "$IP6_RULE_COUNT" -eq 0 ]; then
            echo -e "Status: \033[0;31m[CRITICAL]\033[0m IPv6 INPUT chain is ACCEPT with no rules. All IPv6 traffic is unrestricted."
        else
            echo -e "Status: \033[0;33m[WARNING]\033[0m IPv6 INPUT default is ACCEPT but $IP6_RULE_COUNT rule(s) exist. Review carefully."
        fi
    else
        echo -e "Status: \033[0;32m[OK]\033[0m IPv6 INPUT chain has a restrictive default policy."
    fi
fi

echo -e "\n--- END OF NETWORK REVIEW ---"