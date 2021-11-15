import WebRTC
import Promises

public class LocalVideoTrack: VideoTrack {

    public internal(set) var capturer: RTCVideoCapturer
    public internal(set) var videoSource: RTCVideoSource
    // used to calculate RTCRtpEncoding
    public let dimensions: Dimensions

    public typealias CreateCapturerResult = (capturer: RTCVideoCapturer,
                                             source: RTCVideoSource,
                                             dimensions: Dimensions)

    init(rtcTrack: RTCVideoTrack,
         capturer: RTCVideoCapturer,
         videoSource: RTCVideoSource,
         name: String,
         source: Track.Source,
         dimensions: Dimensions) {

        self.capturer = capturer
        self.videoSource = videoSource
        self.dimensions = dimensions
        super.init(rtcTrack: rtcTrack, name: name, source: source)
    }

    private static func createCameraCapturer(options: LocalVideoTrackOptions = LocalVideoTrackOptions(),
                                             interceptor: VideoCaptureInterceptor? = nil) throws -> CreateCapturerResult {

        let source: RTCVideoCapturerDelegate
        let output: RTCVideoSource
        if let interceptor = interceptor {
            source = interceptor
            output = interceptor.output
        } else {
            let videoSource = Engine.factory.videoSource()
            source = videoSource
            output = videoSource
        }

        let capturer = RTCCameraVideoCapturer(delegate: source)
        let possibleDevice = RTCCameraVideoCapturer.captureDevices().first {
            // TODO: FaceTime Camera for macOS uses .unspecified
            $0.position == options.position || $0.position == .unspecified
        }

        guard let device = possibleDevice else {
            throw TrackError.mediaError("No \(options.position) video capture devices available.")
        }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let (targetWidth, targetHeight) = (options.captureParameter.dimensions.width,
                                           options.captureParameter.dimensions.height)

        var currentDiff = Int32.max
        var selectedFormat: AVCaptureDevice.Format = formats[0]
        var selectedDimension: Dimensions?
        for format in formats {
            if options.captureFormat == format {
                selectedFormat = format
                break
            }
            let dimension = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let diff = abs(targetWidth - dimension.width) + abs(targetHeight - dimension.height)
            if diff < currentDiff {
                selectedFormat = format
                currentDiff = diff
                selectedDimension = dimension
            }
        }

        guard let selectedDimension = selectedDimension else {
            throw TrackError.mediaError("could not get dimensions")
        }

        let fps = options.captureParameter.encoding.maxFps

        // discover FPS limits
        var minFps = 60
        var maxFps = 0
        for fpsRange in selectedFormat.videoSupportedFrameRateRanges {
            minFps = min(minFps, Int(fpsRange.minFrameRate))
            maxFps = max(maxFps, Int(fpsRange.maxFrameRate))
        }
        if fps < minFps || fps > maxFps {
            throw TrackError.mediaError("requested framerate is unsupported (\(minFps)-\(maxFps))")
        }

        logger.info("starting capture with \(device), format: \(selectedFormat), fps: \(fps)")
        capturer.startCapture(with: device, format: selectedFormat, fps: Int(fps))

        return (capturer, output, selectedDimension)
    }

    public func restartTrack(options: LocalVideoTrackOptions = LocalVideoTrackOptions()) throws {

        let result = try LocalVideoTrack.createCameraCapturer(options: options)

        // Stop previous capturer
        if let capturer = capturer as? RTCCameraVideoCapturer {
            capturer.stopCapture()
        }

        self.capturer = result.capturer
        self.videoSource = result.source

        // create a new RTCVideoTrack
        let rtcTrack = Engine.factory.videoTrack(with: result.source, trackId: UUID().uuidString)
        rtcTrack.isEnabled = true

        // TODO: Stop previous mediaTrack
        mediaTrack.isEnabled = false
        mediaTrack = rtcTrack

        // Set the new track
        sender?.track = rtcTrack
    }

    private static func createBufferCapturer() -> CreateCapturerResult {
        let source = Engine.factory.videoSource()

        #if !os(macOS)
        let dimensions = Dimensions(
            width: Int32(UIScreen.main.bounds.size.width * UIScreen.main.scale),
            height: Int32(UIScreen.main.bounds.size.height * UIScreen.main.scale)
        )
        #else
        let dimensions = Dimensions(width: 0, height: 0)
        #endif

        return (capturer: VideoBufferCapturer(source: source),
                source: source,
                dimensions: dimensions)
    }

    private static func createTrack(name: String,
                                    createCapturerResult: CreateCapturerResult) -> LocalVideoTrack {

        let rtcTrack = Engine.factory.videoTrack(with: createCapturerResult.source, trackId: UUID().uuidString)
        rtcTrack.isEnabled = true

        return LocalVideoTrack(
            rtcTrack: rtcTrack,
            capturer: createCapturerResult.capturer,
            videoSource: createCapturerResult.source,
            name: name,
            source: .camera,
            dimensions: createCapturerResult.dimensions
        )
    }

    @discardableResult
    public override func stop() -> Promise<Void> {
        Promise<Void> { resolve, _ in
            // if the capturer is a RTCCameraVideoCapturer,
            // wait for it to fully stop.
            if let capturer = self.capturer as? RTCCameraVideoCapturer {
                capturer.stopCapture { resolve(()) }
            } else {
                resolve(())
            }
        }.then {
            super.stop()
        }
    }

    // MARK: - High level methods

    public static func createBufferTrack(name: String) -> LocalVideoTrack {
        createTrack(name: name,
                    createCapturerResult: createBufferCapturer())
    }

    public static func createCameraTrack(options: LocalVideoTrackOptions = LocalVideoTrackOptions(),
                                         interceptor: VideoCaptureInterceptor? = nil) throws -> LocalVideoTrack {
        createTrack(name: Track.cameraName,
                    createCapturerResult: try createCameraCapturer(options: options, interceptor: interceptor))
    }
}
