#!/bin/bash

# ==========================================================================
# MDReader macOS Build & Install Script
# ==========================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${PURPLE}====================================================${NC}"
echo -e "${PURPLE}          Building & Installing MDReader            ${NC}"
echo -e "${PURPLE}====================================================${NC}"

# 1. Build app bundle via shared build script (forwards flags like --universal)
echo -e "${BLUE}[1/3] Building MDReader.app bundle...${NC}"
./scripts/build.sh "$@"
echo -e "  - Bundle build: ${GREEN}Success${NC}"

# 2. Install to /Applications
echo -e "${BLUE}[2/3] Installing to /Applications/MDReader.app...${NC}"
if [ -d "/Applications/MDReader.app" ]; then
    rm -rf "/Applications/MDReader.app"
fi
cp -R "build/MDReader.app" "/Applications/"
codesign --force --deep --sign - /Applications/MDReader.app
echo -e "  - Installed & signed: ${GREEN}/Applications/MDReader.app${NC}"

# 3. Register with macOS Launch Services & Rebuild Services Cache
echo -e "${BLUE}[3/3] Registering Finder Services & Launch Services...${NC}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MDReader.app
/System/Library/CoreServices/pbs -update
echo -e "  - Registration: ${GREEN}Done${NC}"

echo -e "\n${PURPLE}====================================================${NC}"
echo -e "${GREEN}🎉 MDReader is successfully installed!${NC}"
echo -e "${PURPLE}====================================================${NC}"
echo -e "\n${YELLOW}Quick Shortcuts:${NC}"
echo -e "   ${CYAN}Esc / ⌘W${NC}  Dismiss window        ${CYAN}⌘F${NC}   Find in document"
echo -e "   ${CYAN}⌘⇧O${NC}       Toggle Outline        ${CYAN}⌘⇧T${NC}  Toggle Always on Top"
echo -e "   ${CYAN}⌘+ / ⌘- / ⌘0${NC} Zoom               ${CYAN}⌘P / ⌘⇧E${NC} Print / Export PDF"
echo -e "====================================================\n"
