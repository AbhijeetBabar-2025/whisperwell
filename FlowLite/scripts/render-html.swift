// Renders an HTML file to a PNG of an exact pixel size with WebKit.
// Usage: swift scripts/render-html.swift <input.html> <output.png> <width> <height>
// The page is laid out at half the pixel size (CSS points) and captured at 2x.
import AppKit
import WebKit

final class Renderer: NSObject, WKNavigationDelegate {
    let input: URL
    let output: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let size: NSSize
    let webView: WKWebView
    let window: NSWindow

    init(input: URL, output: URL, pixelWidth: Int, pixelHeight: Int) {
        self.input = input
        self.output = output
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        size = NSSize(width: pixelWidth / 2, height: pixelHeight / 2)
        webView = WKWebView(frame: NSRect(origin: .zero, size: size))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        super.init()
        window.contentView = webView
        webView.navigationDelegate = self
    }

    func start() {
        webView.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give fonts and layout a moment to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.capture() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fputs("error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    private func capture() {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(origin: .zero, size: size)
        webView.takeSnapshot(with: config) { image, error in
            guard let image else {
                fputs("error: snapshot failed: \(error?.localizedDescription ?? "unknown")\n", stderr)
                exit(1)
            }
            self.write(image)
        }
    }

    private func write(_ image: NSImage) {
        // Redraw into a bitmap of exactly the requested pixels, whatever the screen scale.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        NSGraphicsContext.restoreGraphicsState()
        do {
            try rep.representation(using: .png, properties: [:])!.write(to: output)
            print("Wrote \(output.path) (\(pixelWidth)x\(pixelHeight))")
            exit(0)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

let args = CommandLine.arguments
guard args.count == 5, let width = Int(args[3]), let height = Int(args[4]) else {
    fputs("usage: render-html.swift <input.html> <output.png> <width> <height>\n", stderr)
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer(input: URL(fileURLWithPath: args[1]), output: URL(fileURLWithPath: args[2]),
                        pixelWidth: width, pixelHeight: height)
renderer.start()
app.run()
