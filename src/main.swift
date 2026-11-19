import Cocoa
import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers

// ==========================================================================
// 1. File Watcher (Atomic-Save Safe & Debounced GCD Dispatch Source)
// ==========================================================================

class FileWatcher {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private let filePath: String
    private let callback: () -> Void

    init(filePath: String, callback: @escaping () -> Void) {
        self.filePath = filePath
        self.callback = callback
        startWatching()
    }

    private func startWatching() {
        stopWatchingSourceOnly()

        let fd = open(filePath, O_EVTONLY)
        guard fd >= 0 else { return }
        self.fileDescriptor = fd

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: DispatchQueue.main
        )

        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self = self, let activeSource = newSource else { return }
            let events = activeSource.data

            // Atomic saves (VS Code, Vim, Xcode, etc.) rename/replace the file inode.
            // Even when fileExists(atPath:) is already true, our fd points to the old inode.
            if events.contains(.rename) || events.contains(.delete) {
                self.reattachWithRetry(attemptsLeft: 6)
            } else {
                self.scheduleDebouncedCallback()
            }
        }

        // Capture fd by value so re-attaching never races to close the new descriptor
        newSource.setCancelHandler {
            close(fd)
        }

        self.source = newSource
        newSource.resume()
    }

    private func reattachWithRetry(attemptsLeft: Int) {
        stopWatchingSourceOnly()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self = self else { return }
            if FileManager.default.fileExists(atPath: self.filePath) {
                self.startWatching()
                self.scheduleDebouncedCallback()
            } else if attemptsLeft > 0 {
                self.reattachWithRetry(attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    private func scheduleDebouncedCallback() {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.callback()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: workItem)
    }

    private func stopWatchingSourceOnly() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        stopWatchingSourceOnly()
    }

    deinit {
        stopWatching()
    }
}

// ==========================================================================
// 2. Resource Manager
// ==========================================================================

struct ResourceManager {
    static func resourcesDirectoryURL() -> URL? {
        if let bundleRes = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: bundleRes.appendingPathComponent("template.html").path) {
            return bundleRes.standardizedFileURL
        }

        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let relativeDir = exeURL.deletingLastPathComponent().appendingPathComponent("resources")
        if FileManager.default.fileExists(atPath: relativeDir.appendingPathComponent("template.html").path) {
            return relativeDir.standardizedFileURL
        }

        let appDir = URL(fileURLWithPath: "/Applications/MDReader.app/Contents/Resources")
        if FileManager.default.fileExists(atPath: appDir.appendingPathComponent("template.html").path) {
            return appDir.standardizedFileURL
        }

        return nil
    }

    static func getResource(name: String, ext: String) -> String? {
        if let dir = resourcesDirectoryURL() {
            let url = dir.appendingPathComponent("\(name).\(ext)")
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        return nil
    }

    static func customUserCSS() -> String {
        let customCSSURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mdreader/custom.css")
        return (try? String(contentsOf: customCSSURL, encoding: .utf8)) ?? ""
    }

    static func assembleHTML() -> String {
        let template = getResource(name: "template", ext: "html") ?? defaultTemplate()
        let style = getResource(name: "style", ext: "css") ?? defaultStyle()
        let customCSS = customUserCSS()
        let marked = getResource(name: "marked.min", ext: "js") ?? ""
        let purify = getResource(name: "purify.min", ext: "js") ?? ""
        let highlight = getResource(name: "highlight.min", ext: "js") ?? ""

        var html = template
        html = html.replacingOccurrences(of: "/* CSS placeholder to be dynamically replaced or loaded */", with: style)
        html = html.replacingOccurrences(of: "/* CUSTOM USER CSS */", with: customCSS)
        html = html.replacingOccurrences(of: "<script id=\"marked-js\"></script>", with: "<script>\n\(marked)\n</script>")
        html = html.replacingOccurrences(of: "<script id=\"purify-js\"></script>", with: "<script>\n\(purify)\n</script>")
        html = html.replacingOccurrences(of: "<script id=\"highlight-js\"></script>", with: "<script>\n\(highlight)\n</script>")

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
          <script id="purify-js"></script>
          <script id="highlight-js"></script>
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
              const html = typeof marked !== 'undefined' ? marked.parse(text) : '<pre>' + text + '</pre>';
              const safe = typeof DOMPurify !== 'undefined' ? DOMPurify.sanitize(html) : html;
              document.getElementById('content-body').innerHTML = safe;
              if (typeof hljs !== 'undefined') {
                document.querySelectorAll('pre code').forEach(b => hljs.highlightElement(b));
              }
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
// 3. Local & Bundle Asset Scheme Handler (Relative Images + Offline KaTeX/Mermaid)
// ==========================================================================

class LocalAssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdreader-doc"

    private static let allowedImageMimeTypes: [String: String] = [
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "webp": "image/webp",
        "svg": "image/svg+xml",
        "ico": "image/x-icon",
        "bmp": "image/bmp",
        "avif": "image/avif",
        "tif": "image/tiff",
        "tiff": "image/tiff"
    ]

    private static let allowedBundleMimeTypes: [String: String] = [
        "js": "application/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "woff2": "font/woff2",
        "woff": "font/woff",
        "ttf": "font/ttf",
        "svg": "image/svg+xml",
        "png": "image/png"
    ]

    static func baseURL(forFilePath filePath: String) -> URL? {
        let dirURL = URL(fileURLWithPath: filePath).deletingLastPathComponent().standardizedFileURL
        var components = URLComponents()
        components.scheme = scheme
        components.host = "local"
        let path = dirURL.path.hasSuffix("/") ? dirURL.path : dirURL.path + "/"
        components.path = path
        return components.url
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == Self.scheme else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL))
            return
        }

        if url.host == "bundle" {
            serveBundleAsset(url: url, task: urlSchemeTask)
        } else if url.host == "local" {
            serveLocalImage(url: url, task: urlSchemeTask)
        } else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL))
        }
    }

    private func serveBundleAsset(url: URL, task: WKURLSchemeTask) {
        guard let resourcesDir = ResourceManager.resourcesDirectoryURL() else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }

        let relativePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resolvedURL = resourcesDir.appendingPathComponent(relativePath).standardizedFileURL
        let allowedPrefix = resourcesDir.path.hasSuffix("/") ? resourcesDir.path : resourcesDir.path + "/"
        let ext = resolvedURL.pathExtension.lowercased()

        // Guard against path traversal and restrict to expected static resource types
        guard resolvedURL.path.hasPrefix(allowedPrefix),
              let mimeType = Self.allowedBundleMimeTypes[ext],
              FileManager.default.fileExists(atPath: resolvedURL.path),
              let data = try? Data(contentsOf: resolvedURL) else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }

        respond(url: url, mimeType: mimeType, data: data, task: task)
    }

    private func serveLocalImage(url: URL, task: WKURLSchemeTask) {
        let fileURL = URL(fileURLWithPath: url.path).standardizedFileURL
        let ext = fileURL.pathExtension.lowercased()

        // Strictly allow only image MIME types so untrusted markdown cannot probe arbitrary files
        guard let mimeType = Self.allowedImageMimeTypes[ext],
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }

        respond(url: url, mimeType: mimeType, data: data, task: task)
    }

    private func respond(url: URL, mimeType: String, data: Data, task: WKURLSchemeTask) {
        let headers: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=3600"
        ]
        if let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) {
            task.didReceive(httpResponse)
        } else {
            let fallback = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            task.didReceive(fallback)
        }
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Synchronous local reads complete immediately; nothing to cancel.
    }
}

// ==========================================================================
// 4. Weak Script Message Proxy (Avoids WKUserContentController Retain Cycles)
// ==========================================================================

class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// ==========================================================================
// 5. SwiftUI Native Blur Wrapper
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
// 6. WKWebView Host in SwiftUI
// ==========================================================================

struct WebView: NSViewRepresentable {
    let htmlContent: String
    let markdownBase64: String
    let fileName: String
    let filePath: String
    @Binding var reloadTrigger: Int
    let onWebViewCreated: (WKWebView) -> Void
    let onTogglePin: () -> Void

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        var hasLoaded = false

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            hasLoaded = true
            let savedTheme = UserDefaults.standard.string(forKey: "MDReaderTheme") ?? "glass"
            webView.evaluateJavaScript("setTheme('\(savedTheme)', false)", completionHandler: nil)
            updateHTMLContent(in: webView)
        }

        // Intercept clicks on external links and relative markdown links
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = (url.scheme ?? "").lowercased()

            if scheme == "http" || scheme == "https" || scheme == "mailto" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            if scheme == LocalAssetSchemeHandler.scheme && url.host == "local" {
                let targetPath = URL(fileURLWithPath: url.path).standardizedFileURL.path
                let ext = URL(fileURLWithPath: targetPath).pathExtension.lowercased()
                let markdownExts: Set<String> = ["md", "markdown", "mdown", "mkd", "txt"]

                if FileManager.default.fileExists(atPath: targetPath) {
                    if markdownExts.contains(ext) {
                        DispatchQueue.main.async {
                            PreviewController.shared.openPreview(forFilePath: targetPath)
                        }
                    } else {
                        NSWorkspace.shared.open(URL(fileURLWithPath: targetPath))
                    }
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.cancel)
        }

        // Receive JS -> Swift bridge actions
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mdreader",
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            switch action {
            case "copyText":
                if let text = body["text"] as? String {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }
            case "togglePin":
                DispatchQueue.main.async {
                    self.parent.onTogglePin()
                }
            case "setTheme":
                if let theme = body["theme"] as? String {
                    DispatchQueue.main.async {
                        PreviewController.shared.setTheme(theme)
                    }
                }
            default:
                break
            }
        }

        func updateHTMLContent(in webView: WKWebView) {
            let escapedFileName = parent.fileName
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")

            let js = "updateContent('\(parent.markdownBase64)', '\(escapedFileName)')"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalAssetSchemeHandler(), forURLScheme: LocalAssetSchemeHandler.scheme)
        config.userContentController.add(WeakScriptMessageHandler(delegate: context.coordinator), name: "mdreader")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background to show visual effect blur

        // Restore saved zoom factor
        let savedZoom = UserDefaults.standard.double(forKey: "MDReaderPageZoom")
        if savedZoom >= 0.5 && savedZoom <= 3.0 {
            webView.pageZoom = CGFloat(savedZoom)
        }

        let baseURL = LocalAssetSchemeHandler.baseURL(forFilePath: filePath)
        webView.loadHTMLString(htmlContent, baseURL: baseURL)

        DispatchQueue.main.async {
            onWebViewCreated(webView)
        }

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
// 7. Main Preview SwiftUI View (Supports Drag & Drop of New Files)
// ==========================================================================

struct PreviewView: View {
    let htmlContent: String
    @ObservedObject var state: PreviewController.PreviewState
    let filePath: String
    let onWebViewCreated: (WKWebView) -> Void
    let onTogglePin: () -> Void
    let onFileDropped: (String) -> Void

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
                    filePath: filePath,
                    reloadTrigger: $state.reloadTrigger,
                    onWebViewCreated: onWebViewCreated,
                    onTogglePin: onTogglePin
                )
            }

            if state.isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .background(Color.accentColor.opacity(0.08).cornerRadius(12))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 550, idealWidth: 620, minHeight: 600, idealHeight: 750)
        .edgesIgnoringSafeArea(.all)
        .onDrop(of: ["public.file-url"], isTargeted: $state.isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    DispatchQueue.main.async {
                        onFileDropped(url.path)
                    }
                }
            }
            return true
        }
    }
}

// ==========================================================================
// 8. Fallback File Drop SwiftUI View
// ==========================================================================

class DropZoneState: ObservableObject {
    @Published var isTargeted = false
}

struct FileDropView: View {
    @ObservedObject var dropState: DropZoneState
    let onFileSelected: (String) -> Void

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 20) {
                Spacer().frame(height: 28)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundColor(dropState.isTargeted ? .accentColor : .secondary)
                    .scaleEffect(dropState.isTargeted ? 1.1 : 1.0)
                    .animation(.spring(), value: dropState.isTargeted)

                Text("MDReader Previewer")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("Drag & drop a Markdown file here\nor click to browse.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Choose File...") {
                    PreviewController.shared.presentOpenFilePanel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(dropState.isTargeted ? Color.accentColor : Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(20)
            )
        }
        .frame(width: 450, height: 350)
        .onDrop(of: ["public.file-url"], isTargeted: $dropState.isTargeted) { providers in
            guard let provider = providers.first else { return false }

            _ = provider.loadObject(ofClass: URL.self) { url, _ in
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
// 9. Borderless Floating NSPanel Subclass
// ==========================================================================

class PreviewPanel: NSPanel {
    weak var webView: WKWebView?
    var sourceFileName: String = "Document"
    var sourceFilePath: String?
    private(set) var isPinned: Bool = true

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
        self.level = .floating // Start pinned on top
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = true

        // Smooth fade-in
        self.alphaValue = 0.0
        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }, completionHandler: nil)
    }

    func togglePin() {
        isPinned.toggle()
        self.level = isPinned ? .floating : .normal
        webView?.evaluateJavaScript("setPinState(\(isPinned ? "true" : "false"))", completionHandler: nil)
    }

    func toggleOutline() {
        webView?.evaluateJavaScript("toggleOutline()", completionHandler: nil)
    }

    func openFindBar() {
        webView?.evaluateJavaScript("openFindBar()", completionHandler: nil)
    }

    func applyTheme(_ theme: String) {
        webView?.evaluateJavaScript("setTheme('\(theme)', false)", completionHandler: nil)
    }

    func openInDefaultEditor() {
        guard let path = sourceFilePath else { return }
        let fileURL = URL(fileURLWithPath: path)
        let myBundleURL = Bundle.main.bundleURL.standardizedFileURL

        let candidateApps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
            .filter { $0.standardizedFileURL != myBundleURL }

        let preferredBundleNames = [
            "Cursor.app", "Visual Studio Code.app", "Zed.app",
            "Sublime Text.app", "Nova.app", "BBEdit.app",
            "Xcode.app", "TextEdit.app"
        ]

        let targetApp = preferredBundleNames.compactMap { name in
            candidateApps.first { $0.lastPathComponent == name }
        }.first ?? candidateApps.first

        if let appURL = targetApp {
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    func revealInFinder() {
        guard let path = sourceFilePath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func adjustZoom(delta: CGFloat? = nil) {
        guard let webView = webView else { return }
        let nextZoom: CGFloat
        if let delta = delta {
            nextZoom = min(3.0, max(0.5, webView.pageZoom + delta))
        } else {
            nextZoom = 1.0
        }
        webView.pageZoom = nextZoom
        UserDefaults.standard.set(Double(nextZoom), forKey: "MDReaderPageZoom")
    }

    func printDocument() {
        guard let webView = webView else { return }
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: self, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func exportPDF() {
        guard let webView = webView else { return }
        let baseName = URL(fileURLWithPath: sourceFileName).deletingPathExtension().lastPathComponent
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "\(baseName).pdf"
        savePanel.beginSheetModal(for: self) { response in
            guard response == .OK, let destinationURL = savePanel.url else { return }
            let config = WKPDFConfiguration()
            webView.createPDF(configuration: config) { result in
                if case .success(let data) = result {
                    try? data.write(to: destinationURL, options: .atomic)
                }
            }
        }
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
// 10. Controller Class Managing Window States & Hot-Reloading
// ==========================================================================

class PreviewController: NSObject {
    static let shared = PreviewController()

    private var activePreviews: [String: (panel: PreviewPanel, watcher: FileWatcher, state: PreviewState)] = [:]
    private var fallbackPanel: PreviewPanel?
    private var fallbackDropState: DropZoneState?

    class PreviewState: ObservableObject {
        @Published var markdownBase64: String = ""
        @Published var reloadTrigger: Int = 0
        @Published var isDropTargeted: Bool = false
        var fileName: String = ""
    }

    func openPreview(forFilePath filePath: String) {
        let absolutePath = URL(fileURLWithPath: filePath).standardizedFileURL.path

        // If already open, bring to front
        if let existing = activePreviews[absolutePath] {
            existing.panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
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

        // Setup atomic-save-safe file watcher for auto-reload
        let watcher = FileWatcher(filePath: absolutePath) { [weak self, weak state] in
            guard let self = self, let state = state else { return }
            self.updateStateContent(state: state, filePath: absolutePath)
        }

        var panelRef: PreviewPanel?

        // Setup SwiftUI View
        let htmlContent = ResourceManager.assembleHTML()
        let contentView = PreviewView(
            htmlContent: htmlContent,
            state: state,
            filePath: absolutePath,
            onWebViewCreated: { webView in
                panelRef?.webView = webView
            },
            onTogglePin: {
                panelRef?.togglePin()
            },
            onFileDropped: { [weak self] droppedPath in
                self?.openPreview(forFilePath: droppedPath)
            }
        )

        // Host View Controller using saved preferred window dimensions
        let hostController = NSHostingController(rootView: contentView)
        let savedWidth = UserDefaults.standard.double(forKey: "MDReaderWindowWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "MDReaderWindowHeight")
        let width = (savedWidth >= 550 && savedWidth <= 2400) ? savedWidth : 660
        let height = (savedHeight >= 600 && savedHeight <= 1800) ? savedHeight : 780
        let rect = NSRect(x: 100, y: 100, width: width, height: height)
        hostController.preferredContentSize = rect.size

        // Create NSPanel
        let panel = PreviewPanel(contentRect: rect, contentViewController: hostController)
        panel.sourceFileName = state.fileName
        panel.sourceFilePath = absolutePath
        positionCascadedPanel(panel)
        panelRef = panel

        // Close the fallback selector if open
        if let fallback = fallbackPanel {
            fallback.close()
            fallbackPanel = nil
        }

        // Track window close and resize to clean up resources and persist preferred size
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: panel
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEndLiveResize(_:)),
            name: NSWindow.didEndLiveResizeNotification,
            object: panel
        )

        activePreviews[absolutePath] = (panel, watcher, state)
    }

    private func positionCascadedPanel(_ panel: PreviewPanel) {
        panel.center()
        let openCount = activePreviews.count
        guard openCount > 0 else { return }

        let step: CGFloat = 28
        let offsetIndex = CGFloat(openCount % 8)
        var frame = panel.frame
        frame.origin.x += offsetIndex * step
        frame.origin.y -= offsetIndex * step

        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if frame.maxX > visible.maxX {
                frame.origin.x = visible.minX + 40
            }
            if frame.minY < visible.minY {
                frame.origin.y = visible.maxY - frame.height - 40
            }
        }
        panel.setFrameOrigin(frame.origin)
    }

    func setTheme(_ theme: String) {
        let valid: Set<String> = ["glass", "github", "sepia", "nord"]
        guard valid.contains(theme) else { return }
        UserDefaults.standard.set(theme, forKey: "MDReaderTheme")
        for (_, val) in activePreviews {
            val.panel.applyTheme(theme)
        }
    }

    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        guard let panel = notification.object as? PreviewPanel,
              panel != fallbackPanel else { return }
        UserDefaults.standard.set(Double(panel.frame.width), forKey: "MDReaderWindowWidth")
        UserDefaults.standard.set(Double(panel.frame.height), forKey: "MDReaderWindowHeight")
    }

    func openFallbackSelector() {
        if let fallback = fallbackPanel {
            fallback.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let dropState = DropZoneState()
        self.fallbackDropState = dropState
        let contentView = FileDropView(dropState: dropState) { [weak self] filePath in
            self?.openPreview(forFilePath: filePath)
        }

        let hostController = NSHostingController(rootView: contentView)
        let rect = NSRect(x: 0, y: 0, width: 450, height: 350)
        hostController.preferredContentSize = rect.size
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

    func presentOpenFilePanel() {
        let openPanel = NSOpenPanel()
        var contentTypes: [UTType] = [.plainText, .utf8PlainText]
        if let mdType = UTType(filenameExtension: "md") { contentTypes.insert(mdType, at: 0) }
        if let markdownType = UTType(filenameExtension: "markdown") { contentTypes.insert(markdownType, at: 0) }
        openPanel.allowedContentTypes = contentTypes
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = true

        NSApp.activate(ignoringOtherApps: true)
        if openPanel.runModal() == .OK {
            for url in openPanel.urls {
                openPreview(forFilePath: url.path)
            }
        }
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

        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didEndLiveResizeNotification, object: panel)

        for (path, val) in activePreviews {
            if val.panel == panel {
                val.watcher.stopWatching()
                activePreviews.removeValue(forKey: path)
                break
            }
        }

        if panel == fallbackPanel {
            fallbackPanel = nil
            fallbackDropState = nil
        }

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
// 11. Application Delegate and Menu Actions
// ==========================================================================

class AppDelegate: NSObject, NSApplicationDelegate {
    // Strong static reference to prevent Swift ARC from garbage collecting the delegate
    static var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Register application as NSServices provider for Finder context menu
        NSApp.servicesProvider = self

        // 2. Parse all launching CLI file arguments (skip system flags like -psn)
        let fileArgs = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if !fileArgs.isEmpty {
            for filePath in fileArgs {
                PreviewController.shared.openPreview(forFilePath: filePath)
            }
            return
        }

        // 3. Fallback: If started as a standard GUI, open drop selector if no openFiles event arrived
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let windowCount = NSApp.windows.filter { $0.isVisible }.count
            if windowCount == 0 {
                PreviewController.shared.openFallbackSelector()
            }
        }
    }

    // NSServices Handler callback
    @objc func handleServiceRequest(_ pboard: NSPasteboard, userData: String, error: NSErrorPointer) {
        guard let types = pboard.types, types.contains(.fileURL) else { return }

        if let files = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for fileURL in files {
                PreviewController.shared.openPreview(forFilePath: fileURL.path)
            }
        }
    }

    // Apple Event Handler: Triggers on double-click, "Open With", or Drag-to-App
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            PreviewController.shared.openPreview(forFilePath: filename)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menu Bar Actions

    private var activePreviewPanel: PreviewPanel? {
        return (NSApp.keyWindow as? PreviewPanel) ?? (NSApp.mainWindow as? PreviewPanel)
    }

    @objc func openFileAction(_ sender: Any?) {
        PreviewController.shared.presentOpenFilePanel()
    }

    @objc func findAction(_ sender: Any?) {
        activePreviewPanel?.openFindBar()
    }

    @objc func zoomInAction(_ sender: Any?) {
        activePreviewPanel?.adjustZoom(delta: 0.1)
    }

    @objc func zoomOutAction(_ sender: Any?) {
        activePreviewPanel?.adjustZoom(delta: -0.1)
    }

    @objc func zoomResetAction(_ sender: Any?) {
        activePreviewPanel?.adjustZoom(delta: nil)
    }

    @objc func togglePinAction(_ sender: Any?) {
        activePreviewPanel?.togglePin()
    }

    @objc func toggleOutlineAction(_ sender: Any?) {
        activePreviewPanel?.toggleOutline()
    }

    @objc func printAction(_ sender: Any?) {
        activePreviewPanel?.printDocument()
    }

    @objc func exportPDFAction(_ sender: Any?) {
        activePreviewPanel?.exportPDF()
    }

    @objc func openInEditorAction(_ sender: Any?) {
        activePreviewPanel?.openInDefaultEditor()
    }

    @objc func revealInFinderAction(_ sender: Any?) {
        activePreviewPanel?.revealInFinder()
    }

    @objc func selectThemeAction(_ sender: NSMenuItem) {
        if let theme = sender.representedObject as? String {
            PreviewController.shared.setTheme(theme)
        }
    }
}

// ==========================================================================
// 12. Bootstrap Executable Main
// ==========================================================================

let app = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.shared = delegate // Keep a strong reference to prevent ARC deallocation
app.delegate = delegate

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

    // File Menu
    let fileMenuItem = NSMenuItem()
    mainMenu.addItem(fileMenuItem)
    let fileSubMenu = NSMenu(title: "File")
    fileMenuItem.submenu = fileSubMenu
    fileSubMenu.addItem(withTitle: "Open...", action: #selector(AppDelegate.openFileAction(_:)), keyEquivalent: "o")
    fileSubMenu.addItem(withTitle: "Open in Editor", action: #selector(AppDelegate.openInEditorAction(_:)), keyEquivalent: "e")
    let revealItem = fileSubMenu.addItem(withTitle: "Reveal in Finder", action: #selector(AppDelegate.revealInFinderAction(_:)), keyEquivalent: "r")
    revealItem.keyEquivalentModifierMask = [.command, .shift]
    fileSubMenu.addItem(NSMenuItem.separator())
    let exportPDFItem = fileSubMenu.addItem(withTitle: "Export as PDF...", action: #selector(AppDelegate.exportPDFAction(_:)), keyEquivalent: "e")
    exportPDFItem.keyEquivalentModifierMask = [.command, .shift]
    fileSubMenu.addItem(withTitle: "Print...", action: #selector(AppDelegate.printAction(_:)), keyEquivalent: "p")
    fileSubMenu.addItem(NSMenuItem.separator())
    fileSubMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    // Edit Menu
    let editMenuItem = NSMenuItem()
    mainMenu.addItem(editMenuItem)
    let editSubMenu = NSMenu(title: "Edit")
    editMenuItem.submenu = editSubMenu
    editSubMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editSubMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editSubMenu.addItem(NSMenuItem.separator())
    editSubMenu.addItem(withTitle: "Find...", action: #selector(AppDelegate.findAction(_:)), keyEquivalent: "f")

    // View Menu
    let viewMenuItem = NSMenuItem()
    mainMenu.addItem(viewMenuItem)
    let viewSubMenu = NSMenu(title: "View")
    viewMenuItem.submenu = viewSubMenu
    let outlineItem = viewSubMenu.addItem(withTitle: "Toggle Outline", action: #selector(AppDelegate.toggleOutlineAction(_:)), keyEquivalent: "o")
    outlineItem.keyEquivalentModifierMask = [.command, .shift]
    let pinItem = viewSubMenu.addItem(withTitle: "Toggle Always on Top", action: #selector(AppDelegate.togglePinAction(_:)), keyEquivalent: "t")
    pinItem.keyEquivalentModifierMask = [.command, .shift]
    viewSubMenu.addItem(NSMenuItem.separator())

    // Theme Submenu
    let themeMenuItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
    let themeSubMenu = NSMenu(title: "Theme")
    for (label, value) in [("Glass (Default)", "glass"), ("GitHub", "github"), ("Sepia", "sepia"), ("Nord", "nord")] {
        let item = themeSubMenu.addItem(withTitle: label, action: #selector(AppDelegate.selectThemeAction(_:)), keyEquivalent: "")
        item.representedObject = value
    }
    themeMenuItem.submenu = themeSubMenu
    viewSubMenu.addItem(themeMenuItem)

    viewSubMenu.addItem(NSMenuItem.separator())
    viewSubMenu.addItem(withTitle: "Zoom In", action: #selector(AppDelegate.zoomInAction(_:)), keyEquivalent: "=")
    viewSubMenu.addItem(withTitle: "Zoom Out", action: #selector(AppDelegate.zoomOutAction(_:)), keyEquivalent: "-")
    viewSubMenu.addItem(withTitle: "Actual Size", action: #selector(AppDelegate.zoomResetAction(_:)), keyEquivalent: "0")

    app.mainMenu = mainMenu
}

setupMenuBar()
app.run()
