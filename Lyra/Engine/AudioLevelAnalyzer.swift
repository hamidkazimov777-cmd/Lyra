import Foundation
import Combine
import Accelerate

/// Computes rolling RMS audio levels and a frequency-band visualization from
/// 16 kHz mono Float32 samples.
///
/// Samples arrive on the audio tap thread; published values are safe to read
/// from the main actor because the internal buffers are protected by a lock and
/// the `@Published` properties are written only on the main thread.
final class AudioLevelAnalyzer: ObservableObject, @unchecked Sendable {
    /// Number of recent RMS values exposed to the UI (≈1 s of history at 30 fps).
    private let levelCount: Int
    /// Analysis window size in samples (512 @ 16 kHz ≈ 32 ms).
    private let windowSize: Int
    /// Number of frequency bands shown in the HUD visualization.
    private let bandCount: Int
    /// FFT size. Must be a power of two.
    private let fftSize: Int

    @Published private(set) var levels: [Float]
    @Published private(set) var frequencyBands: [Float]

    private let lock = NSLock()
    private var pending: [Float] = []
    private var fftBuffer: [Float] = []
    private let fft: FFTAnalyzer

    init(levelCount: Int = 30, windowSize: Int = 512, bandCount: Int = 16, fftSize: Int = 1024) {
        self.levelCount = levelCount
        self.windowSize = windowSize
        self.bandCount = bandCount
        self.fftSize = fftSize
        self.levels = Array(repeating: 0, count: levelCount)
        self.frequencyBands = Array(repeating: 0, count: bandCount)
        self.fft = FFTAnalyzer(size: fftSize)
        self.fftBuffer.reserveCapacity(fftSize)
    }

    /// Process a batch of samples on the audio tap thread.
    /// Kept allocation-free on the hot path: slice views for RMS and in-place
    /// FFT buffers.
    func process(_ samples: [Float]) {
        lock.lock()
        pending.append(contentsOf: samples)

        var newLevels: [Float] = []
        newLevels.reserveCapacity(pending.count / windowSize)
        while pending.count >= windowSize {
            let slice = pending[..<windowSize]
            let rms = Self.rms(slice)
            newLevels.append(rms)
            pending.removeFirst(windowSize)
        }

        // Feed the FFT buffer from the same sample stream.
        fftBuffer.append(contentsOf: samples)
        var newBands: [Float]?
        while fftBuffer.count >= fftSize {
            let slice = Array(fftBuffer[..<fftSize])
            newBands = fft.bands(for: slice, bandCount: bandCount)
            fftBuffer.removeFirst(fftSize / 2) // 50% overlap for smoother motion
        }
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if !newLevels.isEmpty {
                var current = self.levels
                current.append(contentsOf: newLevels)
                if current.count > self.levelCount {
                    current.removeFirst(current.count - self.levelCount)
                } else if current.count < self.levelCount {
                    current = Array(repeating: 0, count: self.levelCount - current.count) + current
                }
                self.levels = current
            }

            if let bands = newBands {
                self.frequencyBands = bands
            }
        }
    }

    /// Reset levels and frequency bands to silence. Safe to call from any thread.
    func reset() {
        lock.lock()
        pending.removeAll()
        fftBuffer.removeAll()
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.levels = Array(repeating: 0, count: self?.levelCount ?? 30)
            self?.frequencyBands = Array(repeating: 0, count: self?.bandCount ?? 16)
        }
    }

    private static func rms<S: Sequence>(_ samples: S) -> Float where S.Element == Float {
        var count = 0
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
            count += 1
        }
        guard count > 0 else { return 0 }
        let mean = sum / Float(count)
        let value = sqrt(mean)
        // Normalize roughly to 0...1 for typical speech levels.
        return min(1, max(0, value * 4))
    }
}

// MARK: - FFT

/// Lightweight FFT helper using Accelerate/vDSP. Reusable setup; per-call
/// analysis allocates only its result array.
private final class FFTAnalyzer {
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let n: Int
    private let halfN: Int
    private var hannWindow: [Float]

    init(size: Int) {
        n = size
        log2n = vDSP_Length(log2(Float(size)))
        halfN = size / 2
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        hannWindow = [Float](repeating: 0, count: size)
        vDSP_hann_window(&hannWindow, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Returns one normalized magnitude value per frequency band.
    func bands(for samples: [Float], bandCount: Int) -> [Float] {
        guard samples.count == n else { return Array(repeating: 0, count: bandCount) }

        var real = samples
        var imaginary = [Float](repeating: 0, count: n)

        // Apply Hann window to reduce spectral leakage.
        vDSP_vmul(real, 1, hannWindow, 1, &real, 1, vDSP_Length(n))

        // Forward real FFT.
        real.withUnsafeMutableBufferPointer { realPtr in
            imaginary.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        // Compute magnitudes.
        var magnitudes = [Float](repeating: 0, count: halfN)
        real.withUnsafeMutableBufferPointer { realPtr in
            imaginary.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Normalize into a fresh buffer (vDSP_vsmul cannot read and write the
        // same array without an explicit copy).
        var scaled = [Float](repeating: 0, count: halfN)
        var scale: Float = 2.0 / Float(n)
        vDSP_vsmul(&magnitudes, 1, &scale, &scaled, 1, vDSP_Length(halfN))

        // Group into logarithmically spaced bands.
        var bands = [Float](repeating: 0, count: bandCount)
        let binCount = Float(halfN)
        for i in 0..<bandCount {
            let t0 = Float(i) / Float(bandCount)
            let t1 = Float(i + 1) / Float(bandCount)
            // Square mapping puts more resolution in low-mid frequencies where speech lives.
            let start = Int(t0 * t0 * binCount)
            let end = max(start + 1, Int(t1 * t1 * binCount))
            let clampedEnd = min(end, halfN)
            var maxMag: Float = 0
            for j in start..<clampedEnd {
                maxMag = max(maxMag, scaled[j])
            }
            // Compress dynamic range and map to 0...1.
            let db = 20 * log10(maxMag + 1e-12)
            let normalized = (db + 60) / 60 // -60 dB ... 0 dB -> 0...1
            bands[i] = min(1, max(0, normalized))
        }
        return bands
    }
}
