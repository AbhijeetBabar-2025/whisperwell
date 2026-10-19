import AppKit
import WhisperwellCore
import SwiftUI

/// `Whisperwell --render-indicator <folder>` writes a PNG of each indicator state, for checking the design.
@MainActor
enum IndicatorPreview {
    static func run(folder: String) -> Int32 {
        let directory = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let speech: [CGFloat] = [0.1, 0.3, 0.55, 0.8, 0.6, 0.35, 0.7, 0.95, 0.65, 0.4, 0.25, 0.5, 0.3, 0.15]
        let states: [(String, IndicatorModel.Phase, [CGFloat])] = [
            ("listening", .listening, speech),
            ("live", .listening, speech),
            ("transcribing", .transcribing, speech),
            ("notice", .message("Didn't catch that. Try again.", isError: false), speech),
            ("error", .message("Copied to clipboard. Press ⌘V to paste.", isError: true), speech),
        ]
        for (name, phase, levels) in states {
            let model = IndicatorModel()
            model.phase = phase
            model.levels = levels
            if name == "live" {
                model.partial = LivePreview.tail("so I was thinking we could move the launch to next Thursday because the press kit")
            }
            let view = IndicatorView(model: model)
                .frame(width: 760, height: 80)
                .background(Color(white: 0.85)) // stand-in for a desktop
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
                fputs("error: couldn't render \(name)\n", stderr)
                return 1
            }
            let url = directory.appendingPathComponent("indicator-\(name).png")
            do { try png.write(to: url) } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                return 1
            }
            print("Wrote \(url.path)")
        }
        return 0
    }
}

/// `Whisperwell --render-ui <folder>` writes a PNG of each Settings tab and the setup window.
@MainActor
enum WindowPreview {
    static func run(folder: String) -> Int32 {
        let directory = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var views: [(String, NSView)] = SettingsView.Tab.allCases.map {
            ("settings-\($0.rawValue.lowercased())", SettingsWindowController.makeView(tab: $0))
        }
        views.append(("setup", SetupWindowController.makeView()))
        for (name, view) in views {
            // Render inside a real (offscreen) window so standard controls draw properly.
            let size = view.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                                  backing: .buffered, defer: false)
            // A container that paints the window background, as a real window would.
            let container = NSView(frame: NSRect(origin: .zero, size: size))
            container.wantsLayer = true
            window.contentView = container
            container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            view.frame = container.bounds
            container.addSubview(view)
            container.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else { return 1 }
            container.cacheDisplay(in: container.bounds, to: rep)
            let url = directory.appendingPathComponent("\(name).png")
            guard let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil else {
                fputs("error: couldn't write \(url.path)\n", stderr)
                return 1
            }
            print("Wrote \(url.path)")
        }
        return 0
    }
}
