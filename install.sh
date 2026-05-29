#!/bin/bash

# ==========================================================================
# MDReader macOS Build & Install Script
# ==========================================================================

# Exit immediately if a command exits with a non-zero status
set -e

# Styling colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${PURPLE}====================================================${NC}"
echo -e "${PURPLE}          Building & Installing MDReader            ${NC}"
echo -e "${PURPLE}====================================================${NC}"

# 1. Environment Checks
echo -e "${BLUE}[1/7] Verifying system environment...${NC}"

if ! command -v swiftc &> /dev/null; then
    echo -e "${RED}Error: Swift compiler (swiftc) not found! Please install Xcode Command Line Tools.${NC}"
    exit 1
fi
echo -e "  - Swift compiler: ${GREEN}Available${NC}"

if ! command -v sips &> /dev/null; then
    echo -e "${RED}Error: sips (macOS Image Utility) not found!${NC}"
    exit 1
fi
echo -e "  - sips image utility: ${GREEN}Available${NC}"

if ! command -v iconutil &> /dev/null; then
    echo -e "${RED}Error: iconutil not found!${NC}"
    exit 1
fi
echo -e "  - iconutil app icon builder: ${GREEN}Available${NC}"

# 2. Cleanup old builds
echo -e "${BLUE}[2/7] Cleaning up previous builds...${NC}"
rm -rf build/
rm -rf AppIcon.iconset/
rm -f AppIcon.icns
echo -e "  - Clean: ${GREEN}Done${NC}"

# 3. Create app bundle structure
echo -e "${BLUE}[3/7] Creating macOS app bundle directory structure...${NC}"
BUILD_DIR="build/MDReader.app"
mkdir -p "${BUILD_DIR}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/Contents/Resources"
echo -e "  - Directory structure: ${GREEN}Created${NC}"

# 4. Generate native .icns App Icon
echo -e "${BLUE}[4/7] Generating native multi-resolution Apple AppIcon.icns...${NC}"
if [ -f "src/resources/AppIcon.png" ]; then
    mkdir -p AppIcon.iconset
    
    # Generate standard and retina resolutions using sips (forcing PNG format)
    sips -s format png -z 16 16     src/resources/AppIcon.png --out AppIcon.iconset/icon_16x16.png
    sips -s format png -z 32 32     src/resources/AppIcon.png --out AppIcon.iconset/icon_16x16@2x.png
    sips -s format png -z 32 32     src/resources/AppIcon.png --out AppIcon.iconset/icon_32x32.png
    sips -s format png -z 64 64     src/resources/AppIcon.png --out AppIcon.iconset/icon_32x32@2x.png
    sips -s format png -z 128 128   src/resources/AppIcon.png --out AppIcon.iconset/icon_128x128.png
    sips -s format png -z 256 256   src/resources/AppIcon.png --out AppIcon.iconset/icon_128x128@2x.png
    sips -s format png -z 256 256   src/resources/AppIcon.png --out AppIcon.iconset/icon_256x256.png
    sips -s format png -z 512 512   src/resources/AppIcon.png --out AppIcon.iconset/icon_256x256@2x.png
    sips -s format png -z 512 512   src/resources/AppIcon.png --out AppIcon.iconset/icon_512x512.png
    sips -s format png -z 1024 1024 src/resources/AppIcon.png --out AppIcon.iconset/icon_512x512@2x.png
    
    # Compile iconset folder into binary .icns
    iconutil -c icns AppIcon.iconset
    mv AppIcon.icns "${BUILD_DIR}/Contents/Resources/"
    rm -rf AppIcon.iconset
    echo -e "  - Native Icon Bundle: ${GREEN}Compiled successfully${NC}"
else
    echo -e "  - ${YELLOW}Warning: src/resources/AppIcon.png not found. App bundle will have default icon.${NC}"
fi

# 5. Compile Swift application
echo -e "${BLUE}[5/7] Compiling native Swift/SwiftUI application...${NC}"
swiftc -O src/main.swift -o "${BUILD_DIR}/Contents/MacOS/MDReader"
echo -e "  - Compilation: ${GREEN}Success${NC}"

# 6. Copy Info.plist and Resources into the bundle
echo -e "${BLUE}[6/7] Packaging assets, HTML/CSS templates, and metadata...${NC}"
cp Info.plist "${BUILD_DIR}/Contents/"
cp src/resources/template.html "${BUILD_DIR}/Contents/Resources/"
cp src/resources/style.css "${BUILD_DIR}/Contents/Resources/"
cp src/resources/marked.min.js "${BUILD_DIR}/Contents/Resources/"
cp src/resources/prism.min.js "${BUILD_DIR}/Contents/Resources/"
echo -e "  - App Bundle packaging: ${GREEN}Done${NC}"

# 7. Install to /Applications
echo -e "${BLUE}[7/7] Installing to system Applications folder...${NC}"
# Delete old app if exists
if [ -d "/Applications/MDReader.app" ]; then
    echo "  - Removing old installation..."
    rm -rf "/Applications/MDReader.app"
fi

cp -R "build/MDReader.app" "/Applications/"
echo -e "  - Installation location: ${GREEN}/Applications/MDReader.app${NC}"

# Apply deep ad-hoc code signature (Crucial for Apple Silicon & Finder launches)
echo -e "${BLUE}Applying native code signature to app bundle...${NC}"
codesign --force --deep --sign - /Applications/MDReader.app

# Register with macOS Launch Services & Rebuild Services Cache
echo -e "${BLUE}Registering service with macOS and rebuilding Finder menus...${NC}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MDReader.app
/System/Library/CoreServices/pbs -update

echo -e "${GREEN}  - Service registered successfully!${NC}"

echo -e "\n${PURPLE}====================================================${NC}"
echo -e "${GREEN}🎉 MDReader is successfully installed!${NC}"
echo -e "${PURPLE}====================================================${NC}"
echo -e "\n${YELLOW}How to use MDReader:${NC}"
echo -e "1. ${CYAN}Finder Context Menu${NC}:"
echo -e "   - Right-click any Markdown (.md or .markdown) file in Finder."
echo -e "   - Select ${GREEN}'Quick Actions' > 'Preview in MDReader'${NC} (or ${GREEN}'Services' > 'Preview in MDReader'${NC})."
echo -e "   - It will render instantly in a beautiful, translucent floating window!"
echo -e "2. ${CYAN}Open With Menu${NC}:"
echo -e "   - Right-click file, select ${GREEN}'Open With' > 'MDReader'${NC}."
echo -e "3. ${CYAN}Terminal CLI Command${NC}:"
echo -e "   - Launch from your terminal directly:"
echo -e "     ${GREEN}/Applications/MDReader.app/Contents/MacOS/MDReader \"/path/to/file.md\"${NC}"
echo -e "4. ${CYAN}Standalone GUI Mode${NC}:"
echo -e "   - Double click ${GREEN}MDReader${NC} in your Applications folder."
echo -e "   - A gorgeous glassmorphic screen will appear, allowing you to drag & drop any file to preview."
echo -e "\n${YELLOW}Premium Features Included:${NC}"
echo -e "   ✅ ${CYAN}Hot Reloading${NC}: Saves made in any external editor will instantly refresh in the preview!"
echo -e "   ✅ ${CYAN}Keyboard Dismissal${NC}: Press ${GREEN}Escape${NC} or ${GREEN}Cmd+W${NC} to dismiss the preview instantly."
echo -e "   ✅ ${CYAN}Translucent Dragging${NC}: Drag the window from ANY background point, not just the title bar."
echo -e "   ✅ ${CYAN}Outline Navigation${NC}: Toggle Outline side panel to browse headings and scroll smoothly."
echo -e "   ✅ ${CYAN}Metadata Stats${NC}: Automatic live word counts and read-time estimates."
echo -e "   ✅ ${CYAN}One-Click Copy${NC}: Code snippets feature a hover 'Copy' button."
echo -e "====================================================\n"
