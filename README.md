# 📖 MDReader (macOS Previewer)

**MDReader** is a lightweight, native macOS utility designed to preview Markdown (`.md` or `.markdown`) files instantly in a translucent, glassmorphic floating window. Inspired by the speed and feel of macOS *Quick Look*, it renders technical Markdown—including Mermaid diagrams, LaTeX math, and GitHub alerts—100% offline without launching heavy editors or browser tabs.

---

## ✨ Features

- **⚡ Native Floating HUD Panel**: Built in SwiftUI + AppKit with automatic light/dark mode sync, drag-from-anywhere movement, persistent window sizing, smart multi-window cascading, and a toggleable **Always on Top** pin (`⌘⇧T`).
- **🎨 Built-In Themes + Custom CSS**: Switch instantly between **Glass**, **GitHub**, **Sepia**, and **Nord** themes from the header palette or menu bar, or drop personal overrides into `~/.config/mdreader/custom.css`.
- **📊 Technical Markdown (100% Offline, Lazy-Loaded)**:
  - **Mermaid.js Diagrams**: Renders `mermaid` flowcharts, sequence, state, and ER diagrams to theme-adaptive SVG on demand.
  - **KaTeX Mathematics**: Renders inline `$...$` and display `$$...$$` LaTeX formulas with bundled `.woff2` math fonts.
  - **GitHub-Style Alerts**: Styled callouts for `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, and `[!CAUTION]`.
  - **YAML Frontmatter Card**: Renders leading `---` frontmatter blocks into a structured metadata header with tag pills.
- **🛡️ Safe Offline Rendering**: Embedded `marked.js`, **DOMPurify** XSS sanitization, and **Highlight.js** multi-language syntax highlighting (Swift, Python, JS/TS, Bash, JSON, YAML, Go, Rust, SQL, and more).
- **🔄 Atomic-Save Hot-Reloading**: Watches files via debounced GCD dispatch sources and re-attaches seamlessly across atomic saves (VS Code, Vim, Neovim, Xcode, TextEdit) while preserving scroll position.
- **🖱️ Finder Integration & Smart Links**: Registers as a macOS Service (**Quick Actions / Services → Preview in MDReader**), renders relative local images safely, opens external links in your browser, and opens linked `.md` files right in MDReader.
- **🎛️ Built-in Reader Tools**: Dynamic Outline sidebar (`⌘⇧O`), In-Document Find (`⌘F`), Persistent Zoom (`⌘+`/`⌘-`/`⌘0`), Print (`⌘P`), Export to PDF (`⌘⇧E`), Open in Editor (`⌘E`), Reveal in Finder (`⌘⇧R`), and native `NSPasteboard` code copy buttons.

---

## 🛠️ Installation

### Option 1: Download Prebuilt Binary
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

To build a Universal binary (`arm64` + `x86_64`) on compatible SDKs:
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
  /Applications/MDReader.app/Contents/MacOS/MDReader README.md test.md
  ```

### Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Esc` or `⌘W` | Close active panel (dismisses Theme/Find/Outline first if open) |
| `⌘F` | Find in document (`↩` / `⇧↩` for next/prev match) |
| `⌘⇧O` | Toggle Outline sidebar |
| `⌘⇧T` | Toggle Always on Top pin |
| `⌘+` / `⌘-` / `⌘0` | Zoom In / Zoom Out / Reset Zoom |
| `⌘E` | Open current file in your code editor |
| `⌘⇧R` | Reveal current file in Finder |
| `⌘P` | Print document |
| `⌘⇧E` | Export as PDF |
| `⌘O` | Open file(s) |
| `⌘Q` | Quit MDReader |

---

## 🎨 Custom CSS Overrides

Place any personal CSS rules in `~/.config/mdreader/custom.css` and MDReader will automatically load them into every preview window:

```css
/* Example: ~/.config/mdreader/custom.css */
.content-container {
  max-width: 920px;
}
```

---

## 🗑️ Uninstallation

Remove `/Applications/MDReader.app` and refresh Finder service caches cleanly:

```bash
./uninstall.sh
```

---

## 📄 License

Released under the [MIT License](LICENSE).
