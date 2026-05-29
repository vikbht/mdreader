import Cocoa
import SwiftUI
import WebKit
import Combine
import System

// ==========================================================================
// 1. File Watcher (GCD Dispatch Source)
// ==========================================================================

class FileWatcher {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private let filePath: String
    private let callback: () -> Void
    
    init(filePath: String, callback: @escaping () -> Void) {
        self.filePath = filePath
        self.callback = callback
        startWatching()
    }
    
    private func startWatching() {
        // Open file descriptor in read-only event mode
        fileDescriptor = open(filePath, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        
        // Monitor write/attributes-change events
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: DispatchQueue.main
        )
        
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            // Check if file still exists
            if !FileManager.default.fileExists(atPath: self.filePath) {
                // If it was renamed or replaced, re-init watch after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.stopWatching()
                    self.startWatching()
                }
            }
            self.callback()
        }
        
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        
        self.source = source
        source.resume()
    }
    
    func stopWatching() {
        source?.cancel()
        source = nil
    }
    
    deinit {
        stopWatching()
    }
}

// ==========================================================================
// 2. Resource Manager
// ==========================================================================

struct ResourceManager {
    static func getResource(name: String, ext: String) -> String? {
        // Path 1: Inside Bundle Resources folder (Standard App Bundle)
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        
        // Path 2: Relative to executable path (Developer CLI execution)
        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let exeDir = exeURL.deletingLastPathComponent()
        let relativeURL = exeDir.appendingPathComponent("resources/\(name).\(ext)")
        if let content = try? String(contentsOf: relativeURL, encoding: .utf8) {
            return content
        }
        
        // Path 3: Standard macOS App Path Fallback
        let appURL = URL(fileURLWithPath: "/Applications/MDReader.app/Contents/Resources/\(name).\(ext)")
        if let content = try? String(contentsOf: appURL, encoding: .utf8) {
            return content
        }
        
        return nil
    }
    
    static func assembleHTML() -> String {
        let template = getResource(name: "template", ext: "html") ?? defaultTemplate()
        let style = getResource(name: "style", ext: "css") ?? defaultStyle()
        let marked = getResource(name: "marked.min", ext: "js") ?? ""
        let prism = getResource(name: "prism.min", ext: "js") ?? ""
        
        var html = template
        html = html.replacingOccurrences(of: "/* CSS placeholder to be dynamically replaced or loaded */", with: style)
        html = html.replacingOccurrences(of: "<script id=\"marked-js\"></script>", with: "<script>\n\(marked)\n</script>")
        html = html.replacingOccurrences(of: "<script id=\"prism-js\"></script>", with: "<script>\n\(prism)\n</script>")
        
        return html
    }
    
    private static func defaultTemplate() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8">
          <style>/* CSS placeholder to be dynamically replaced or loaded */</style>
          <script id="marked-js"></script>
          <script id="prism-js"></script>
        </head>
        <body>
          <header class="app-header">
            <h1 id="file-title">MDReader</h1>
          </header>
          <main id="content" class="content-container">
            <div id="content-body" class="markdown-body"></div>
          </main>
          <script>
            function decodeBase64UTF8(s) {
              return new TextDecoder("utf-8").decode(Uint8Array.from(atob(s), c => c.charCodeAt(0)));
            }
            function updateContent(base64Markdown, fileName) {
              const text = decodeBase64UTF8(base64Markdown);
              document.getElementById('file-title').textContent = fileName;
              document.getElementById('content-body').innerHTML = typeof marked !== 'undefined' ? marked.parse(text) : '<pre>' + text + '</pre>';
              if (typeof Prism !== 'undefined') Prism.highlightAll();
            }
          </script>
        </body>
        </html>
        """
    }
    
    private static func defaultStyle() -> String {
        return "body { font-family: -apple-system; padding: 20px; color: #333; background: #fff; }"
    }
}

// ==========================================================================
// 3. SwiftUI Native Blur Wrapper
// ==========================================================================

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// ==========================================================================
// 4. WKWebView Host in SwiftUI
// ==========================================================================

struct WebView: NSViewRepresentable {
    let htmlContent: String
    let markdownBase64: String
    let fileName: String
    @Binding var reloadTrigger: Int
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        var hasLoaded = false
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoaded = true
            updateHTMLContent(in: webView)
        }
        
        func updateHTMLContent(in webView: WKWebView) {
            let escapedFileName = parent.fileName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            
            let js = "updateContent('\(parent.markdownBase64)', '\(escapedFileName)')"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background to show visual effect blur
        
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.hasLoaded {
            context.coordinator.updateHTMLContent(in: nsView)
        }
    }
}

// ==========================================================================
// 5. Main Preview SwiftUI View
// ==========================================================================

struct PreviewView: View {
    let htmlContent: String
    @ObservedObject var state: PreviewController.PreviewState
    let filePath: String
    
    var body: some View {
        ZStack {
            // macOS Visual Effect Frosted Glass Background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Top margin to prevent header collision with macOS Close buttons
                Spacer()
                    .frame(height: 28)
                
                WebView(
                    htmlContent: htmlContent,
                    markdownBase64: state.markdownBase64,
                    fileName: state.fileName,
                    reloadTrigger: $state.reloadTrigger
                )
            }
        }
        .frame(minWidth: 550, idealWidth: 620, minHeight: 600, idealHeight: 750) // Force minimum and ideal boundaries
        .edgesIgnoringSafeArea(.all)
    }
}

// ==========================================================================
// 6. Fallback File Drop SwiftUI View
// ==========================================================================

struct FileDropView: View {
    @State private var isTargeted = false
    let onFileSelected: (String) -> Void
    
    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                Spacer().frame(height: 28)
                
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
                    .scaleEffect(isTargeted ? 1.1 : 1.0)
                    .animation(.spring(), value: isTargeted)
                
                Text("MDReader Previewer")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Drag & drop a Markdown file here\nor click to browse.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Choose File...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.utf8PlainText, .plainText]
                    panel.allowedFileTypes = ["md", "markdown", "txt"]
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        onFileSelected(url.path)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(20)
            )
        }
        .frame(width: 450, height: 350) // Prevent collapsed selectors
        .onDrop(of: ["public.file-url"], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url = url {
                    DispatchQueue.main.async {
                        self.onFileSelected(url.path)
                    }
                }
            }
            return true
        }
    }
}

// ==========================================================================
// 7. Borderless Floating NSPanel Subclass
// ==========================================================================

class PreviewPanel: NSPanel {
    init(contentRect: NSRect, contentViewController: NSViewController) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .hudWindow, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.contentViewController = contentViewController
        self.isReleasedWhenClosed = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true // Drag from anywhere!
        self.level = .floating // Keep floating on top
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // Float over full screen spaces
        self.hasShadow = true
        
        // Smooth fade-in
        self.alphaValue = 0.0
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true) // Force application to become active so window appears on top!
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }
    
    // Close window immediately on Escape key
    override func cancelOperation(_ sender: Any?) {
        closeAndFadeOut()
    }
    
    func closeAndFadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.close()
        })
    }
}

// ==========================================================================
// 8. Controller class managing window states & hot-reloading
// ==========================================================================

class PreviewController: NSObject {
    static let shared = PreviewController()
    
    // Key: File Path, Value: (Panel, Watcher, StateHolder)
    private var activePreviews: [String: (panel: PreviewPanel, watcher: FileWatcher, state: PreviewState)] = [:]
    
    // Retain the fallback selector window so ARC doesn't garbage collect it instantly
    private var fallbackPanel: PreviewPanel?
    
    class PreviewState: ObservableObject {
        @Published var markdownBase64: String = ""
        @Published var reloadTrigger: Int = 0
        var fileName: String = ""
    }
    
    func openPreview(forFilePath filePath: String) {
        let absolutePath = URL(fileURLWithPath: filePath).path
        
        // If already open, bring to front and highlight
        if let existing = activePreviews[absolutePath] {
            existing.panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true) // Bring to front!
            return
        }
        
        guard FileManager.default.fileExists(atPath: absolutePath) else {
            showErrorAlert(message: "File not found at: \(absolutePath)")
            return
        }
        
        let state = PreviewState()
        state.fileName = URL(fileURLWithPath: absolutePath).lastPathComponent
        
        // Initial load
        updateStateContent(state: state, filePath: absolutePath)
        
        // Setup file watcher for auto-reload
        let watcher = FileWatcher(filePath: absolutePath) { [weak self, weak state] in
            guard let self = self, let state = state else { return }
            self.updateStateContent(state: state, filePath: absolutePath)
        }
        
        // Setup SwiftUI View
        let htmlContent = ResourceManager.assembleHTML()
        let contentView = PreviewView(
            htmlContent: htmlContent,
            state: state,
            filePath: absolutePath
        )
        
        // Host View Controller
        let hostController = NSHostingController(rootView: contentView)
        let rect = NSRect(x: 100, y: 100, width: 620, height: 750)
        hostController.preferredContentSize = rect.size // Force NSHostingController layout bounds!
        
        // Create NSPanel
        let panel = PreviewPanel(contentRect: rect, contentViewController: hostController)
        panel.center()
        
        // Close the fallback selector if it's open to keep things clean
        if let fallback = fallbackPanel {
            fallback.close()
            fallbackPanel = nil
        }
        
        // Track the window close event to clean up resources
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: panel
        )
        
        activePreviews[absolutePath] = (panel, watcher, state)
    }
    
    func openFallbackSelector() {
        // If already open, bring to front
        if let fallback = fallbackPanel {
            fallback.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = FileDropView { [weak self] filePath in
            self?.openPreview(forFilePath: filePath)
        }
        
        let hostController = NSHostingController(rootView: contentView)
        let rect = NSRect(x: 0, y: 0, width: 450, height: 350)
        hostController.preferredContentSize = rect.size // Force size retention
        let panel = PreviewPanel(contentRect: rect, contentViewController: hostController)
        panel.center()
        
        self.fallbackPanel = panel
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: panel
        )
    }
    
    private func updateStateContent(state: PreviewState, filePath: String) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let base64 = data.base64EncodedString()
            
            DispatchQueue.main.async {
                state.markdownBase64 = base64
                state.reloadTrigger += 1
            }
        } catch {
            print("Failed to read file content: \(error.localizedDescription)")
        }
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? PreviewPanel else { return }
        
        // Find which path this panel was previewing and clean it up
        for (path, val) in activePreviews {
            if val.panel == panel {
                val.watcher.stopWatching()
                activePreviews.removeValue(forKey: path)
                break
            }
        }
        
        // Release fallback panel reference if it closed
        if panel == fallbackPanel {
            fallbackPanel = nil
        }
        
        // If all preview windows are closed and the app has LSUIElement (runs in background), exit!
        if activePreviews.isEmpty && fallbackPanel == nil {
            NSApp.terminate(nil)
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "MDReader Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// ==========================================================================
// 9. Application Delegate and Entry Point
// ==========================================================================

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // Strong static reference to prevent Swift ARC from garbage collecting the delegate
    static var shared: AppDelegate?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Register application as NSServices provider for Finder context menu
        NSApp.servicesProvider = self
        
        // 2. Parse launching arguments (for terminal command or CLI call)
        let args = CommandLine.arguments
        if args.count > 1 {
            let filePath = args[1]
            // Skip system-passed arguments (like -psn)
            if !filePath.hasPrefix("-") {
                PreviewController.shared.openPreview(forFilePath: filePath)
                return
            }
        }
        
        // 3. Fallback: If started as a standard GUI, open drop selector or check if a file was passed
        // Delay slightly to allow application(_:openFiles:) to run if macOS sends file open event
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // If no previews have been opened, show file browser fallback
            let windowCount = NSApp.windows.filter { $0.isVisible }.count
            if windowCount == 0 {
                PreviewController.shared.openFallbackSelector()
            }
        }
    }
    
    // NSServices Handler callback
    @objc func handleServiceRequest(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        // Extract file URLs from the pasteboard
        guard let types = pboard.types, types.contains(.fileURL) else { return }
        
        if let files = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for fileURL in files {
                PreviewController.shared.openPreview(forFilePath: fileURL.path)
            }
        }
    }
    
    // Apple Event Handler: Triggers on double-click "Open With" or Drag-to-Dock
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            PreviewController.shared.openPreview(forFilePath: filename)
        }
    }
    
    // Exit app cleanly on close
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// ==========================================================================
// 10. Bootstrap Executable Main
// ==========================================================================

let app = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.shared = delegate // Keep a strong reference to prevent ARC deallocation!
app.delegate = delegate

// Load the standard menu bar items so keyboard shortcuts like Copy/Paste/Cmd+Q work natively!
func setupMenuBar() {
    let mainMenu = NSMenu()
    
    // App Menu
    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)
    let appSubMenu = NSMenu()
    appMenuItem.submenu = appSubMenu
    
    let appName = "MDReader"
    appSubMenu.addItem(withTitle: "About \(appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appSubMenu.addItem(NSMenuItem.separator())
    appSubMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appSubMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
    appSubMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
    appSubMenu.addItem(NSMenuItem.separator())
    appSubMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    
    // File Menu (to support closing windows)
    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileSubMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileSubMenu
    fileSubMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    
    // Edit Menu (so Cmd+C works in our WebView!)
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editSubMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editSubMenu
    editSubMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editSubMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    
    app.mainMenu = mainMenu
}

setupMenuBar()
app.run()
