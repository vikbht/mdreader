# MDReader Premium Test Document

Welcome to your **MDReader** preview! This file exercises headings, lists, tables, multi-language syntax highlighting, relative images, links, and XSS sanitization.

- [x] Lightweight Swift/SwiftUI core (~30MB memory)
- [x] Glassmorphic translucent backdrop blurs & toggleable Always-on-Top pin
- [x] Atomic-save-safe hot-reload file watcher with scroll preservation
- [x] DOMPurify XSS sanitization & offline Highlight.js multi-language highlighting

---

## 🔗 Smart Links & Relative Images

- **External link** (opens in your default browser): [MDReader on GitHub](https://github.com/vikbht/mdreader)
- **Relative Markdown link** (opens in a new MDReader window): [Open README.md](./README.md)
- **In-page anchor link**: [Jump to Code Blocks](#-code-blocks--copy-button)

### Local Image Rendering
Below is a relative local image loaded safely via the custom `mdreader-doc://` scheme handler:

![MDReader App Icon](./src/resources/AppIcon.png)

---

## 🎨 Styling & Tabular Data

> "Simplicity is the ultimate sophistication."
> — *Leonardo da Vinci*

| Feature Name | Built-in Support | Native macOS | Notes |
| :--- | :---: | :---: | :--- |
| GFM + DOMPurify | Yes | Yes | Strips `<script>` & unsafe event handlers |
| Multi-Lang Highlighting | Yes | Yes | Highlight.js common bundle |
| Relative Images & Links | Yes | Yes | Custom `WKURLSchemeHandler` |
| Atomic-Save Watcher | Yes | Yes | Re-attaches across rename/delete |
| Find / Zoom / PDF Export | Yes | Yes | `⌘F`, `⌘+`/`⌘-`/`⌘0`, `⌘⇧E` |

<!-- Security test: DOMPurify strips this inline script safely -->
<script>window.__xssTriggered = true; document.body.innerHTML = 'XSS FAILED';</script>

---

## 💻 Code Blocks & Copy Button

### Swift
```swift
import Cocoa
import WebKit

final class PreviewPanel: NSPanel {
    func togglePin() {
        level = (level == .floating) ? .normal : .floating
    }
}
```

### Python
```python
def reading_time_minutes(text: str, wpm: int = 200) -> int:
    words = [w for w in text.split() if w]
    return max(1, round(len(words) / wpm))
```

### JSON
```json
{
  "app": "MDReader",
  "version": "1.1.0",
  "universal": ["arm64", "x86_64"]
}
```

---

## 🧭 Outline & Find Verification

1. Press **`⌘⇧O`** (or click the Outline icon) to open the Table of Contents sidebar.
2. Press **`⌘F`** and type `MDReader` to test in-document search and `↩` / `⇧↩` navigation.
3. Press **`⌘⇧T`** (or click the Pin icon) to toggle Always-on-Top mode.
4. Press **`⌘⇧E`** to export a print-styled PDF, or **`Esc`** to dismiss!
