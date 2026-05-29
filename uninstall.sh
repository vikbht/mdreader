#!/bin/bash

# ==========================================================================
# MDReader macOS Uninstall Script
# ==========================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}====================================================${NC}"
echo -e "${PURPLE}              Uninstalling MDReader                 ${NC}"
echo -e "${PURPLE}====================================================${NC}"

if [ -d "/Applications/MDReader.app" ]; then
    echo -e "${BLUE}Unregistering from macOS Launch Services...${NC}"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u /Applications/MDReader.app
    
    echo -e "${BLUE}Removing application from /Applications...${NC}"
    rm -rf "/Applications/MDReader.app"
    
    echo -e "${BLUE}Updating macOS Services cache...${NC}"
    /System/Library/CoreServices/pbs -update
    
    echo -e "${GREEN}✓ MDReader has been completely and cleanly uninstalled!${NC}"
else
    echo -e "${RED}MDReader.app was not found in /Applications. Nothing to do!${NC}"
fi

echo -e "${PURPLE}====================================================${NC}\n"
