import Foundation
import WebRTC
import ReplayKit
import Promises

#if os(macOS)

/// Options for ``MacOSScreenCapturer``
struct MacOSScreenCapturerOptions {
    //
}

extension MacOSScreenCapturer.Source {
    public static let mainDisplay: MacOSScreenCapturer.Source = .display(CGMainDisplayID())
}

extension MacOSScreenCapturer {

    public static func sources() -> [MacOSScreenCapturer.Source] {
        let displayIDs = displayIDs().map { MacOSScreenCapturer.Source.display($0) }
        let windowIDs = windowIDs().map { MacOSScreenCapturer.Source.window($0) }
        return [displayIDs, windowIDs].flatMap { $0 }
    }

    // gets a list of window IDs
    public static func windowIDs() -> [CGWindowID] {

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly,
                                               .excludeDesktopElements ], kCGNullWindowID)! as Array

        return list
            .filter { ($0.object(forKey: kCGWindowLayer) as! NSNumber).intValue == 0 }
            .map { $0.object(forKey: kCGWindowNumber) as! NSNumber }.compactMap { $0.uint32Value }
    }

    // gets a list of display IDs
    public static func displayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        var activeCount: UInt32 = 0

        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else {
            return []
        }

        var displayIDList = [CGDirectDisplayID](repeating: kCGNullDirectDisplay, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &(displayIDList), &activeCount) == .success else {
            return []
        }

        return displayIDList
    }
}

public class MacOSScreenCapturer: VideoCapturer {

    public enum Source {
        case display(CGDirectDisplayID)
        case window(CGWindowID)
    }

    private let capturer = RTCVideoCapturer()

    // TODO: Make it possible to change dynamically
    public let source: Source

    // used for display capture
    private lazy var session: AVCaptureSession = {
        let session = AVCaptureSession()
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: .main)
        return session
    }()

    private let timeInterval: TimeInterval = 1 / 30

    // used for window capture
    private lazy var timer: DispatchSourceTimer = {
        let result = DispatchSource.makeTimerSource()
        result.schedule(deadline: .now() + timeInterval, repeating: timeInterval)
        result.setEventHandler(handler: { [weak self] in
            self?.onWindowCaptureTimer()
        })
        return result
    }()

    init(delegate: RTCVideoCapturerDelegate, source: Source) {
        self.source = source
        super.init(delegate: delegate)
    }

    private func onWindowCaptureTimer() {

        guard case .window(let windowId) = source else { return }

        guard let image = CGWindowListCreateImage(CGRect.null,
                                                  .optionIncludingWindow,
                                                  windowId, [.shouldBeOpaque, .nominalResolution ]),
              let pixelBuffer = image.toPixelBuffer() else { return }

        let systemTime = ProcessInfo.processInfo.systemUptime
        let timestampNs = UInt64(systemTime * Double(NSEC_PER_SEC))

        print("did capture ts: \(timestampNs)")
        delegate?.capturer(capturer, didCapture: pixelBuffer, timeStampNs: timestampNs)
        self.dimensions = Dimensions(width: Int32(image.width),
                                     height: Int32(image.height))
    }

    public override func startCapture() -> Promise<Void> {
        super.startCapture().then { () -> Void in

            if case .display(let displayID) = self.source {

                // clear all previous inputs
                for input in self.session.inputs {
                    self.session.removeInput(input)
                }

                // try to create a display input
                guard let input = AVCaptureScreenInput(displayID: displayID) else {
                    // reject promise if displayID is invalid
                    throw TrackError.invalidTrackState("Failed to create screen input with displayID: \(displayID)")
                }

                input.capturesCursor = true
                input.capturesMouseClicks = true
                self.session.addInput(input)

                self.session.startRunning()

                self.dimensions = Dimensions(width: Int32(CGDisplayPixelsWide(displayID)),
                                             height: Int32(CGDisplayPixelsHigh(displayID)))
            } else if case .window = self.source {
                self.timer.resume()
            }
        }
    }

    public override func stopCapture() -> Promise<Void> {
        super.stopCapture().then {

            if case .display = self.source {
                self.session.stopRunning()
            } else if case .window = self.source {
                self.timer.suspend()
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension MacOSScreenCapturer: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(_ output: AVCaptureOutput, didOutput
                                sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        logger.debug("\(self) Captured sample buffer")
        delegate?.capturer(capturer, didCapture: sampleBuffer)
    }
}

extension LocalVideoTrack {
    /// Creates a track that captures the whole desktop screen
    public static func createMacOSScreenShareTrack(source: MacOSScreenCapturer.Source = .mainDisplay) -> LocalVideoTrack {
        let videoSource = Engine.factory.videoSource()
        let capturer = MacOSScreenCapturer(delegate: videoSource, source: source)
        return LocalVideoTrack(
            capturer: capturer,
            videoSource: videoSource,
            name: Track.screenShareName,
            source: .screenShareVideo
        )
    }
}

#endif
