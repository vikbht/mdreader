# MDReader Premium Test Document

Welcome to your **MDReader** preview! This file displays all the rich elements and custom styling supported by your new lightweight macOS Markdown viewer.

- [x] Lightweight Swift/SwiftUI core (~30MB memory)
- [x] Glassmorphic translucent backdrop blurs
- [x] Auto-reload file watcher
- [x] Zero-dependency offline rendering

---

## 🎨 Premium Styling Features

MDReader styles standard HTML and Markdown tags with carefully curated, responsive, eye-friendly typography. 

### 1. Blockquotes & Emphasis
Here's a quote that shows how blocks are highlighted with our custom Indigo accent:

> "Simplicity is the ultimate sophistication."
> — *Leonardo da Vinci*

### 2. Tabular Data Layout
Our custom styling ensures tabular data is beautifully structured, legible, and responsive:

| Feature Name | Built-in Support | Native macOS | Speed |
| :--- | :---: | :---: | :---: |
| GFM Rendering | Yes | Yes | Instantly |
| Syntax Highlight | Yes | Yes | Fast |
| Outline TOC | Yes | Yes | Dynamic |
| Hot Reloading | Yes | Yes | Real-time |

---

## 💻 Code Block & Copy Button

Below is a block of Swift code. MDReader formats code inside a dark terminal layout, applies pastel color syntax highlights, and adds a handy **Copy** button on hover in the top-right corner.

```swift
import Cocoa
import SwiftUI

// Watch any markdown file natively using GCD Dispatch Sources
class FileWatcher {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    
    init(filePath: String, onUpdate: @escaping () -> Void) {
        fileDescriptor = open(filePath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: .write,
            queue: DispatchQueue.main
        )
        
        source?.setEventHandler {
            onUpdate() // Instant Hot-Reload!
        }
        source?.resume()
    }
}
```

---

## 🧭 Outline Sidebar Navigation

If you click the **List Icon** in the top-right floating header:
1. A glassmorphic **Outline panel** slides in from the right.
2. It lists all `h1`, `h2`, and `h3` headings in this document.
3. Clicking any heading will scroll the page smoothly to that section!
4. Clicking the dark blurred overlay will slide the sidebar closed.

---

## 🔄 How to Verify Hot-Reloading

Let's test the native file watcher!
1. Keep this MDReader window open on one side of your screen.
2. Open this file (`test.md`) in any text editor (like VS Code, TextEdit, or vim).
3. Change this line or write a new paragraph.
4. Save the file.
5. Watch the MDReader preview **instantly update** with a smooth fade-in animation!
