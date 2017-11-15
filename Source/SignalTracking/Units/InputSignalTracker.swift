import AVFoundation

public enum InputSignalTrackerError: Error {
  case inputNodeMissing
}

class InputSignalTracker: SignalTracker {

  weak var delegate: SignalTrackerDelegate?
  var levelThreshold: Float?

  fileprivate let bufferSize: AVAudioFrameCount
  fileprivate var audioChannel: AVCaptureAudioChannel?
  fileprivate let captureSession = AVCaptureSession()
  fileprivate var audioEngine: AVAudioEngine?
  fileprivate let session = AVAudioSession.sharedInstance()
  fileprivate let bus = 0

  var peakLevel: Float? {
    get {
      return audioChannel?.peakHoldLevel
    }
  }

  var averageLevel: Float? {
    get {
      return audioChannel?.averagePowerLevel
    }
  }

  var mode: SignalTrackerMode {
    get { return .record }
  }

  // MARK: - Initialization

  required init(bufferSize: AVAudioFrameCount = 2048,
                delegate: SignalTrackerDelegate? = nil) {
    self.bufferSize = bufferSize
    self.delegate = delegate

    setupAudio()
  }

  // MARK: - Tracking

  func start() throws {
    audioEngine = AVAudioEngine()

    guard let inputNode = audioEngine?.inputNode else {
      throw InputSignalTrackerError.inputNodeMissing
    }

    let format = inputNode.outputFormat(forBus: bus)
    if format.sampleRate == 0.0 || format.channelCount == 0 {
      // This should be checked like this, according to apple: https://developer.apple.com/documentation/avfoundation/avaudioengine/1386063-inputnode
      throw InputSignalTrackerError.inputNodeMissing
    }

    inputNode.installTap(onBus: bus, bufferSize: bufferSize, format: format) { buffer, time in
      guard let averageLevel = self.averageLevel else { return }

      let levelThreshold = self.levelThreshold ?? -1000000.0

      if averageLevel > levelThreshold {
        DispatchQueue.main.async {
          self.delegate?.signalTracker(self, didReceiveBuffer: buffer, atTime: time)
        }
      } else {
        DispatchQueue.main.async {
          self.delegate?.signalTrackerWentBelowLevelThreshold(self)
        }
      }
    }

    captureSession.startRunning()
    audioEngine?.prepare()
    try audioEngine?.start()
  }

  func stop() {
    guard audioEngine != nil else {
      return
    }

    audioEngine?.stop()
    audioEngine?.reset()
    audioEngine = nil
    captureSession.stopRunning()
  }

  fileprivate func setupAudio() {
    do {
      let audioDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeAudio)
      let audioCaptureInput = try AVCaptureDeviceInput(device: audioDevice)

      captureSession.addInput(audioCaptureInput)

      // if we don't call this, the startSession will configure session for application
      // and we will lose bluetooth playback (and more)
      captureSession.automaticallyConfiguresApplicationAudioSession = false

      let audioOutput = AVCaptureAudioDataOutput()
      captureSession.addOutput(audioOutput)

      let connection = audioOutput.connections[0] as? AVCaptureConnection
      audioChannel = connection?.audioChannels[0] as? AVCaptureAudioChannel
    } catch {}
  }
}
