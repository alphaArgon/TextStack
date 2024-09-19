/*
 *  TextStack.swift
 *  TextStack
 *
 *  Created by alpha on 2024/8/29.
 *  Copyright © 2024 alphaArgon.
 */

import AppKit
import QuartzCore


/// Coordinates are not flipped. That is, the y-axis points up.
public struct TextStack {

    /// A line may have the following states:
    /// - `appearTime ..< (appearTime + appearDuration)`: appearing
    /// - `(appearTime + appearDuration) ..< unemphasisTime`: emphasized, aka larger, font size
    /// - `unemphasisTime ..< (unemphasisTime + unemphasisDuration)`: animate to smaller font size
    /// - `(unemphasisTime + unemphasisDuration) ...`: still at smaller font size
    private typealias _Line = (
        text: _SimpleText,
        appearTime: TimeInterval,
        unemphasisTime: TimeInterval
    )

    private var _lines: [_Line] = []  //  New lines are prepended.
    private var _currentTime: TimeInterval = 0

    public var size: CGSize = .zero
    public var padding: CGSize = .zero
    public var baseline: CGFloat = 0  //  Above which the lines are stacked.

    public var appearDuration: TimeInterval = 0.75
    public var unemphasisDuration: TimeInterval = 0.75

    public var emphasizedFontSize: CGFloat = 24
    public var normalFontSize: CGFloat = 16

    public var font: CTFont = NSFont.systemFont(ofSize: 0)
    public var lineHeight: CGFloat = 1.5

    public mutating func reset(time: TimeInterval) {
        _lines.removeAll()
        _currentTime = time
    }

    public mutating func setTime(_ time: TimeInterval) {
        precondition(time >= _currentTime, "Can't go back in time")
        _currentTime = time
    }

    public mutating func addLine(_ string: String, duration: TimeInterval, color: CGColor = .black, flushRight: Bool = false) {
        var text = _SimpleText(string, font: font, color: color)
        text.flushRight = flushRight
#if USE_TEXT_BITMAP_CACHE
        text.cacheForFontSize(emphasizedFontSize)
        text.cacheForFontSize(normalFontSize)
#endif

        let line = (text, _currentTime, _currentTime + max(duration, appearDuration))
        _lines.insert(line, at: 0)
    }

    /// Returns whether the layout has changed.
    @discardableResult
    public mutating func layoutLines() -> Bool {
        var changed = false
        var y = baseline
        let maxY = size.height
        let contentWidth = size.width - padding.width * 2

        for i in 0..<_lines.count {
            if y >= maxY {
                //  The line is invisible. Remove it and all subsequent lines.
                _lines.removeSubrange(i...)
                break
            }

            let oldFrame = _lines[i].text.frame

            let appearTime = _lines[i].appearTime
            let unemphasisTime = _lines[i].unemphasisTime

            //  `_currentTime >= line.appearTime` is guaranteed.
            let appearing: Bool
            var phase: Double

            let fontSize: CGFloat

            if _currentTime < appearTime + appearDuration {
                appearing = true
                phase = (_currentTime - appearTime) / appearDuration
                phase = 1 + pow(phase - 1, 3)
                fontSize = emphasizedFontSize * phase

            } else if _currentTime < unemphasisTime {
                appearing = true
                phase = 1
                fontSize = emphasizedFontSize

            } else if _currentTime < unemphasisTime + unemphasisDuration {
                appearing = false
                phase = (_currentTime - unemphasisTime) / unemphasisDuration
                phase = 0.5 - 0.5 * cos(phase * .pi)
                phase = 1 - pow(phase - 1, 2)
                fontSize = emphasizedFontSize - (emphasizedFontSize - normalFontSize) * phase

            } else {
                appearing = false
                phase = 1
                fontSize = normalFontSize
            }

            var newFrame = CGRect(x: padding.width, y: y, width: contentWidth, height: fontSize * lineHeight)

            if newFrame != oldFrame {
                changed = true

                if newFrame.maxY < oldFrame.maxY {
                    //  Lines should not go down.
                    newFrame.origin.y = oldFrame.maxY - newFrame.height
                }

                _lines[i].text.frame = newFrame
                _lines[i].text.fontSize = fontSize
            }

            if appearing {
                _lines[i].text.opacity = phase
            } else {
                let baseOpacity = 1 - sqrt((newFrame.origin.y - baseline) / (maxY - baseline))
                _lines[i].text.opacity = 1 - (1 - baseOpacity) * phase
            }

            y = newFrame.maxY
        }

        return changed
    }

    public mutating func draw(in context: CGContext) {
        for i in _lines.indices {
            _lines[i].text.draw(in: context)
        }
    }
}


//  This type is named “Simple” because it doesn’t take care about optical sizes.
private struct _SimpleText {

    private let _ctLine: CTLine
    private let _baseSize: CGFloat
    private let _ascent: CGFloat
    private let _width: CGFloat

#if USE_TEXT_BITMAP_CACHE
    private var _cachingFontSizes: Set<CGFloat>
    private var _cachedRenders: [(fontSize: CGFloat, layer: CGLayer, shift: CGPoint)]
#endif

    public var fontSize: CGFloat
    public var frame: CGRect
    public var flushRight: Bool
    public var opacity: CGFloat

    public init(_ string: String, font: CTFont, color: CGColor) {
        let attrString = CFAttributedStringCreate(kCFAllocatorDefault,
                                                  string as CFString,
                                                  [kCTFontAttributeName: font,
                                        kCTForegroundColorAttributeName: color] as CFDictionary)!
        _ctLine = CTLineCreateWithAttributedString(attrString)
        _baseSize = CTFontGetSize(font)
        _ascent = CTFontGetAscent(font)
        _width = CGFloat(CTLineGetTypographicBounds(_ctLine, nil, nil, nil))

#if USE_TEXT_BITMAP_CACHE
        _cachingFontSizes = []
        _cachedRenders = []
#endif

        fontSize = _baseSize
        frame = .zero
        flushRight = false
        opacity = 1
    }

    public mutating func draw(in context: CGContext) {
        if fontSize < 1 || opacity < 0.01 {return}

#if DEBUG
        context.setAlpha(1)
        context.setStrokeColor(gray: 0.5, alpha: 0.2)
        context.setLineWidth(1)
        context.stroke(frame)
#endif

        //  The ascent is aligned to the top of the frame.
        let textScale = fontSize / _baseSize
        let y = frame.origin.y + frame.height - _ascent * textScale
        var x = frame.origin.x
        if flushRight {x += frame.width - _width * textScale}

#if USE_TEXT_BITMAP_CACHE
        var bestFit = _cachedRenders.first {$0.fontSize >= fontSize}
        if bestFit == nil, _cachingFontSizes.contains(fontSize) {
            var bbox = CTLineGetImageBounds(_ctLine, nil)
            bbox.origin.x *= textScale
            bbox.origin.y *= textScale
            bbox.size.width *= textScale
            bbox.size.height *= textScale
            bbox = bbox.integral

            let layer = CGLayer(context, size: bbox.size, auxiliaryInfo: nil)!
            let context = layer.context!
            context.translateBy(x: -bbox.origin.x, y: -bbox.origin.y)
            context.scaleBy(x: textScale, y: textScale)
            context.textPosition = .zero
            CTLineDraw(_ctLine, context)

            bestFit = (fontSize, layer, bbox.origin)
            _cachedRenders.append(bestFit!)
            _cachedRenders.sort {$0.fontSize < $1.fontSize}
        }
#endif

        context.setAlpha(opacity)

        context.translateBy(x: x, y: y)

#if USE_TEXT_BITMAP_CACHE
        if let bestFit = bestFit {
            let scale = fontSize / bestFit.fontSize
            context.scaleBy(x: scale, y: scale)
            context.draw(bestFit.layer, at: bestFit.shift)
            context.scaleBy(x: 1 / scale, y: 1 / scale)

        } else {
            context.scaleBy(x: textScale, y: textScale)
            context.textPosition = .zero
            CTLineDraw(_ctLine, context)
            context.scaleBy(x: 1 / textScale, y: 1 / textScale)
        }
#else
        context.scaleBy(x: textScale, y: textScale)
        context.textPosition = .zero
        CTLineDraw(_ctLine, context)
        context.scaleBy(x: 1 / textScale, y: 1 / textScale)
#endif

        context.translateBy(x: -x, y: -y)
    }

#if USE_TEXT_BITMAP_CACHE
    public mutating func cacheForFontSize(_ fontSize: CGFloat) {
        _cachingFontSizes.insert(fontSize)
    }
#endif
}
