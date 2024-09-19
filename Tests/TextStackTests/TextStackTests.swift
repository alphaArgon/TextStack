/*
 *  TextStackTests.swift
 *  TextStack
 *
 *  Created by alpha on 2024/9/20.
 *  Copyright © 2024 alphaArgon.
 */

@testable
import TextStack
import XCTest
import AppKit


final class TextStackTests: XCTestCase {

    /// Opens a window that animates the text stack after a click.
    func testRun() throws {}  //  Just triggers `setUp`.

    override class func setUp() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}


final class TextStackGeneratorTests: XCTestCase {

    /// Generates a video and opens it.
    func test() throws {
        let source = SourceOfTruth()

        let generator = TextStackGenerator {textStack in
            textStack.size = CGSize(width: 960, height: 540)
            textStack.padding.width = 96
            textStack.baseline = 108
            textStack.font = NSFont.boldSystemFont(ofSize: 28)
            textStack.normalFontSize = 20
            textStack.emphasizedFontSize = 30
            textStack.lineHeight = 1.5
        }

        var url = URL(fileURLWithPath: NSTemporaryDirectory())
        url.append(component: "text-stack-generator-demo.mov")

        try generator.makeVideo(in: 0..<(source.duration + 1), saveTo: url) {textStack, time in
            source.addScripts(to: &textStack, upTo: time)
        }

        NSWorkspace.shared.open(url)
    }
}


//  MARK: - Helper Types


public class AppDelegate: NSObject, NSApplicationDelegate {

    private var _window: NSWindow!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        _window = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 960, height: 540),
                           styleMask: [.closable, .titled, .resizable],
                           backing: .buffered,
                           defer: true)
        _window.title = "TextStack Demo"
        _window.contentView = ScriptView(frame: NSRect(x: 0, y: 0, width: 960, height: 540))
        _window.makeKeyAndOrderFront(nil)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}


public class SourceOfTruth {

    private typealias _Script = (start: TimeInterval, duration: TimeInterval, text: String)

    private let _scripts: [_Script] = [
        "Here’s to the crazy ones,",
        "the misfits,",
        "the rebels,",
        "the troublemakers,",
        "the round pegs in the square holes…",
        "the ones who see things differently",
        "— they’re not fond of rules…",
        "You can quote them,",
        "disagree with them,",
        "glorify or vilify them,",
        "but the only thing you can’t do is ignore them",
        "because they change things…",
        "they push the human race forward,",
        "and while some may see them as the crazy ones,",
        "we see genius,",
        "because the ones who are crazy enough",
        "to think that they can change the world,",
        "are the ones who do."
    ].reduce(into: (now: 0 as TimeInterval, scripts: [] as [_Script])) {partialResult, text in
        let duration = TimeInterval(text.count) * 0.1
        let start = partialResult.now

        if text.hasSuffix("…") {partialResult.now += 1}
        partialResult.now += duration
        partialResult.scripts.append((start, duration, text))
    }.scripts

    private var _scriptIndex: Int = 0

    public var duration: TimeInterval {
        let last = _scripts.last!
        return last.start + last.duration
    }

    public func reset(_ textStack: inout TextStack) {
        _scriptIndex = 0
        textStack.reset(time: 0)
    }

    public func addScripts(to textStack: inout TextStack, upTo time: TimeInterval) {
        while _scriptIndex < _scripts.count && _scripts[_scriptIndex].start < time {
            let script = _scripts[_scriptIndex]
            textStack.addLine(script.text, duration: script.duration, color: .white)
            _scriptIndex += 1
        }
    }
}


public class ScriptView: NSView {

    private var _source: SourceOfTruth
    private var _textStack: TextStack
    private var _timeShift: TimeInterval = .nan

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override init(frame: NSRect) {
        _source = SourceOfTruth()
        _textStack = TextStack()
        _textStack.font = NSFont.boldSystemFont(ofSize: 28)
        _textStack.normalFontSize = 20
        _textStack.emphasizedFontSize = 30
        _textStack.lineHeight = 1.5
        super.init(frame: frame)
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        _timeShift = Date.timeIntervalSinceReferenceDate
        _source.reset(&_textStack)
        needsLayout = true
    }

    public override func layout() {
        super.layout()

        let size = self.bounds.size
        _textStack.size = size
        _textStack.padding.width = size.width * 0.1
        _textStack.baseline = size.height * 0.2

        if _timeShift.isNaN {return}

        let time = Date.timeIntervalSinceReferenceDate - _timeShift
        _textStack.setTime(time)
        _source.addScripts(to: &_textStack, upTo: time)

        if _textStack.layoutLines() {
            needsDisplay = true
        }

        DispatchQueue.main.async {[weak self] in
            self?.needsLayout = true
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
        _textStack.draw(in: NSGraphicsContext.current!.cgContext)
    }
}
