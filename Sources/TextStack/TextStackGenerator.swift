/*
 *  TextStackGenerator.swift
 *  TextStack
 *
 *  Created by alpha on 2024/8/31.
 *  Copyright © 2024 alphaArgon.
 */

import AVFoundation
import QuartzCore


public class TextStackGenerator {

    private var _textStack: TextStack

    public init(initializeTextStack: (inout TextStack) -> Void) {
        _textStack = TextStack()
        initializeTextStack(&_textStack)
    }

    public func makeVideo(in time: Range<TimeInterval>, fps: TimeInterval = 30, saveTo url: URL,
                          updateTextStack: (inout TextStack, TimeInterval) -> Void) throws {
        let width = Int(_textStack.size.width)
        let height = Int(_textStack.size.height)

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let videoWriter = try AVAssetWriter(url: url, fileType: .mov)
        let videoSettings = [AVVideoCodecKey: AVVideoCodecType.h264.rawValue,
                             AVVideoWidthKey: width,
                            AVVideoHeightKey: height] as [String: Any]

        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let bufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoWriterInput,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB,
                                                    kCVPixelBufferWidthKey: width,
                                                   kCVPixelBufferHeightKey: height] as [String: Any])
        videoWriter.add(videoWriterInput)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: .zero)
        _textStack.reset(time: time.lowerBound)

        for i in 0..<Int(fps * (time.upperBound - time.lowerBound)) {
            let videoTime = TimeInterval(i) / fps
            let layerTime = videoTime + time.lowerBound
            _textStack.setTime(layerTime)
            updateTextStack(&_textStack, layerTime)
            guard _textStack.layoutLines() else {continue}

            var buffer: CVPixelBuffer!
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bufferAdaptor.pixelBufferPool!, &buffer)
            guard status == kCVReturnSuccess, buffer != nil else {return}

            CVPixelBufferLockBaseAddress(buffer, [])
            let data = CVPixelBufferGetBaseAddress(buffer)!
            memset(data, 0, CVPixelBufferGetDataSize(buffer))  //  Clear the buffer quickly.

            let context = CGContext(data: data, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!

            _textStack.draw(in: context)

            CVPixelBufferUnlockBaseAddress(buffer, [])

            let frameTime = CMTime(seconds: videoTime, preferredTimescale: CMTimeScale(fps * 10))

            if !videoWriterInput.isReadyForMoreMediaData {
                repeat {
                    //  This sleep duration is tested out on my Mac, anyway.
                    Thread.sleep(forTimeInterval: 0.0035)
                } while !videoWriterInput.isReadyForMoreMediaData
            }

            bufferAdaptor.append(buffer, withPresentationTime: frameTime)
        }

        var isFinished = false
        videoWriterInput.markAsFinished()
        videoWriter.finishWriting {
            isFinished = true
        }

        while !isFinished {
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}
