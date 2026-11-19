# 📖 MDReader (macOS Previewer)

**MDReader** is a lightweight, native macOS utility designed to preview Markdown (`.md` or `.markdown`) files instantly in a translucent, glassmorphic floating window. Inspired by the speed and feel of macOS *Quick Look*, it renders your Markdown cleanly without launching heavy editors, IDEs, or browser tabs.

---

## ✨ Features

- **⚡ Native Floating HUD Panel**: Opens instantly in a custom translucent `NSPanel` (SwiftUI + AppKit) with automatic light/dark mode sync, drag-from-anywhere movement, and a toggleable **Always on Top** pin button.
- **🖱️ Finder Right-Click Integration**: Registers as a native macOS Service. Right-click any Markdown file in Finder and choose **Quick Actions → Preview in MDReader** (or **Services → Preview in MDReader**), or use **Open With**.
- **🔄 Atomic-Save Hot-Reloading**: Watches the open file via debounced GCD dispatch sources and automatically re-attaches across atomic saves (VS Code, Vim, Neovim, Xcode, TextEdit) while preserving your scroll position.
- **🛡️ Safe Offline Rendering**: Self-contained with embedded `marked.js`, **DOMPurify** HTML sanitization (blocking XSS scripts), and **Highlight.js** multi-language syntax highlighting (Swift, Python, JS/TS, Bash, JSON, YAML, Go, Rust, SQL, and more).
- **🖼️ Local Images & Smart Links**: Renders relative local images cleanly, opens external `http`/`https` links in your default browser, and opens linked local `.md` files right inside MDReader.
- **🎛️ Built-in Reader Tools**:
  - **Dynamic Outline Sidebar**: Slide-out Table of Contents built from document headings.
  - **In-Document Find (`⌘F`)**: Instant text search with match counter and jump controls.
  - **Print & PDF Export (`⌘P` / `⌘⇧E`)**: Crisp print-optimized layout and one-click PDF export.
  - **Persistent Zoom (`⌘+` / `⌘-` / `⌘0`)**: Remembers your preferred reading scale.
  - **Native Copy Buttons**: One-click code block copy backed directly by `NSPasteboard`.

---

## 🛠️ Installation

### Option 1: Download Prebuilt Universal Binary (Apple Silicon & Intel)
1. Download the latest `MDReader.zip` from the [GitHub Releases](https://github.com/vikbht/mdreader/releases) page.
2. Unzip and drag `MDReader.app` into `/Applications/`.
3. Register the Finder Service once in Terminal:
   ```bash
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MDReader.app
   /System/Library/CoreServices/pbs -update
   ```

### Option 2: Build & Install from Source

**Prerequisites**: macOS 12 Monterey or newer + Xcode Command Line Tools (`swiftc`, `sips`, `iconutil`, `codesign`).

```bash
git clone https://github.com/vikbht/mdreader.git
cd mdreader
chmod +x install.sh uninstall.sh scripts/build.sh
./install.sh
```

To build a Universal binary (`arm64` + `x86_64`) locally, run:
```bash
./install.sh --universal
```

---

## 🚀 Usage & Shortcuts

### Ways to Open Files
- **Finder Right-Click**: Right-click any `.md` file → **Quick Actions** (or **Services**) → **Preview in MDReader**.
- **Open With / Default Viewer**: Right-click a `.md` file → **Get Info (`⌘I`)** → set **Open with** to **MDReader** → click **Change All...**.
- **Drag & Drop**: Launch MDReader standalone to open the drop zone, or drag a `.md` file directly onto any open preview window.
- **Terminal CLI** (supports multiple files):
  ```bash
  /Applications/MDReader.app/Contents/MacOS/MDReader README.md CHANGELOG.md
  ```

### Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Esc` or `⌘W` | Close active panel (dismisses Find/Outline first if open) |
| `⌘F` | Find in document (`↩` / `⇧↩` for next/prev match) |
| `⌘⇧O` | Toggle Outline sidebar |
| `⌘⇧T` | Toggle Always on Top pin |
| `⌘+` / `⌘-` / `⌘0` | Zoom In / Zoom Out / Reset Zoom |
| `⌘P` | Print document |
| `⌘⇧E` | Export as PDF |
| `⌘O` | Open file(s) |
| `⌘Q` | Quit MDReader |

---

## 🗑️ Uninstallation

Remove `/Applications/MDReader.app` and refresh Finder service caches cleanly:

```bash
./uninstall.sh
```

---

## 📄 License

Released under the [MIT License](LICENSE).
