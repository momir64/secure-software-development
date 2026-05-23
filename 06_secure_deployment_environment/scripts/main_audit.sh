#!/bin/bash

GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}Starting Detailed Security Audit...${NC}"
echo "===================================================="

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root." 
   exit 1
fi

# Execution of modules
chmod +x system_review.sh network_review.sh filesystem_review.sh users_review.sh

./system_review.sh
echo -e "\n"
./network_review.sh
echo -e "\n"
./filesystem_review.sh
echo -e "\n"
./users_review.sh

echo "===================================================="
echo -e "${GREEN}Audit completed.${NC}"