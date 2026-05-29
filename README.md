# 📖 MDReader (macOS Previewer)

**MDReader** is a lightning-fast, premium native macOS utility designed to preview Markdown (`.md` or `.markdown`) files instantly in a gorgeous, glassmorphic floating window. Inspired by the speed and integration of the macOS native *Quick Look* preview tool, it gives you a stunning view of your markdown documents without needing to launch heavy editors, IDEs, or browser tabs.

---

## ✨ Features

- **⚡ Native Floating HUD Panel**: Opens instantly in a custom transparent `NSPanel` that stays floating on top of your work. It is fully responsive, dark/light mode sensitive, and completely dismissible with the `Escape` key.
- **🖱️ Finder Right-Click Integration**: Integrates directly as a macOS system service. Right-click any file and select **"Quick Actions" > "Preview in MDReader"** or **"Services" > "Preview in MDReader"** to open.
- **🔄 Live Hot-Reloading**: Automatically watches the previewed file in the background. Saving edits in *any* text editor instantly refreshes the rendering inside the viewer—without losing your current scroll position!
- **🌐 Completely Offline & Self-Contained**: Features pre-packaged rendering assets (`marked.js` and `prism.js`). Works flawlessly with zero network connection.
- **🎛️ Premium UX Details**:
  - **Dynamic Table of Contents (TOC)**: Sidebar panel that parses headings (`h1`, `h2`, `h3`) for outline navigation and smooth scroll mapping.
  - **Live stats badge**: Displays active word counts and estimated reading time at a glance.
  - **One-click Copy Buttons**: Code blocks have a fade-in clipboard copy button.
  - **Drag-from-anywhere background**: Move the floating panel by clicking and dragging *anywhere* on the visual background, not just the top bar.
  - **Fallback Drag & Drop Screen**: Launching the app standalone opens an elegant drop-zone to drag files or browse recursively.

---

## 🛠️ Build & Installation

### Prerequisites
- A macOS machine (macOS 12 Monterey or newer).
- Xcode Command Line Tools (checks for `swiftc`, `sips`, and `iconutil` which are installed automatically with standard tools).

### Install Steps
1. Open terminal and navigate to the project directory:
   ```bash
   cd /Users/vikasbhatia/code/mdreader
   ```
2. Make the installer executable:
   ```bash
   chmod +x install.sh uninstall.sh
   ```
3. Run the installer:
   ```bash
   ./install.sh
   ```

*The installer will automatically download compiler assets, compile the native Swift executable, build a scaled Retina app icon bundle, install it into `/Applications/MDReader.app`, and refresh your macOS Finder menu bindings.*

---

## 🚀 How to Use

### 1. The Context Menu (Right-Click)
- Right-click any Markdown (`.md` or `.markdown`) file in Finder.
- Hover over **Quick Actions** (or **Services**) and select **Preview in MDReader**.
- *To customize its order, go to System Settings > Keyboard > Keyboard Shortcuts > Services and configure the checkbox for "Preview in MDReader".*

### 2. The "Open With" Menu
- Right-click a Markdown file.
- Hover over **Open With** and select **MDReader.app**.

### 3. Make MDReader the Default Viewer (Recommended)
You can make MDReader open automatically when you double-click *any* Markdown file:
1. In Finder, right-click any `.md` file and select **Get Info** (or press `Cmd+I`).
2. Expand the **Open with:** section.
3. Select **MDReader** from the dropdown menu.
4. Click the **Change All...** button right below it, and confirm the system dialog.

### 4. Terminal Command Line
You can pass relative or absolute paths directly:
```bash
/Applications/MDReader.app/Contents/MacOS/MDReader ~/Desktop/notes.md
```

### 5. Keyboard Controls
- `Escape` or `Cmd+W`: Closes and fades out the preview window instantly.
- `Cmd+Q`: Quits the application.

---

## 🗑️ Clean Uninstallation

To remove all application binaries, unregister launch bindings, and completely refresh your Finder menus, run:
```bash
./uninstall.sh
```
