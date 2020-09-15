import AVFoundation
import Accelerate

final class FFTTransformer: Transformer {
  func transform(buffer: AVAudioPCMBuffer) throws -> Buffer {
    let frameCount = buffer.frameLength
    let log2n = UInt(round(log2(Double(frameCount))))
    let bufferSizePOT = Int(1 << log2n)
    let inputCount = bufferSizePOT / 2
    let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))

    var realp = UnsafeMutableBufferPointer<Float>.allocate(capacity: inputCount)
    var imagp = UnsafeMutableBufferPointer<Float>.allocate(capacity: inputCount)
    defer {
      realp.deallocate()
      imagp.deallocate()
    }
    var output = DSPSplitComplex(realp: realp.baseAddress!, imagp: imagp.baseAddress!)

    let windowSize = bufferSizePOT
    var transferBuffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: windowSize)
    var window = UnsafeMutableBufferPointer<Float>.allocate(capacity: windowSize)
    defer {
      transferBuffer.deallocate()
      window.deallocate()
    }
    vDSP_hann_window(window.baseAddress!, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
    vDSP_vmul((buffer.floatChannelData?.pointee)!, 1, window.baseAddress!,
              1, transferBuffer.baseAddress!, 1, vDSP_Length(windowSize))

    let temp = UnsafePointer<Float>(transferBuffer.baseAddress!)

    temp.withMemoryRebound(to: DSPComplex.self, capacity: transferBuffer.count) { (typeConvertedTransferBuffer) -> Void in
        vDSP_ctoz(typeConvertedTransferBuffer, 2, &output, 1, vDSP_Length(inputCount))
    }

    vDSP_fft_zrip(fftSetup!, &output, 1, log2n, FFTDirection(FFT_FORWARD))

    var magnitudes = [Float](repeating: 0.0, count: inputCount)
    vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(inputCount))

    var normalizedMagnitudes = [Float](repeating: 0.0, count: inputCount)
    vDSP_vsmul(sqrtq(magnitudes), 1, [2.0 / Float(inputCount)],
      &normalizedMagnitudes, 1, vDSP_Length(inputCount))

    let buffer = Buffer(elements: normalizedMagnitudes)

    vDSP_destroy_fftsetup(fftSetup)

    return buffer
  }

  // MARK: - Helpers

  func sqrtq(_ x: [Float]) -> [Float] {
    var results = [Float](repeating: 0.0, count: x.count)
    vvsqrtf(&results, x, [Int32(x.count)])

    return results
  }
}
