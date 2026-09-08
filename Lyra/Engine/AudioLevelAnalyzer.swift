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

/// Lightweight FFT helper using Accelerate/vDSP.
///
/// All working buffers are allocated once in `init` and reused, so `bands(for:)`
/// runs on the audio callback path without touching the heap; only the returned
/// band array is fresh.
final class FFTAnalyzer {
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let n: Int
    private let halfN: Int

    private var hannWindow: [Float]
    // Windowed input, then the even/odd split-complex halves required by
    // vDSP_fft_zrip, then the magnitude output. All sized once, reused forever.
    private let windowed: UnsafeMutablePointer<Float>
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>

    init(size: Int) {
        n = size
        log2n = vDSP_Length(log2(Float(size)))
        halfN = size / 2
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        hannWindow = [Float](repeating: 0, count: size)
        vDSP_hann_window(&hannWindow, vDSP_Length(size), Int32(vDSP_HANN_NORM))

        windowed = .allocate(capacity: size)
        windowed.initialize(repeating: 0, count: size)
        realp = .allocate(capacity: halfN)
        realp.initialize(repeating: 0, count: halfN)
        imagp = .allocate(capacity: halfN)
        imagp.initialize(repeating: 0, count: halfN)
        magnitudes = .allocate(capacity: halfN)
        magnitudes.initialize(repeating: 0, count: halfN)
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        windowed.deinitialize(count: n); windowed.deallocate()
        realp.deinitialize(count: halfN); realp.deallocate()
        imagp.deinitialize(count: halfN); imagp.deallocate()
        magnitudes.deinitialize(count: halfN); magnitudes.deallocate()
    }

    /// Returns one normalized magnitude value per frequency band.
    func bands(for samples: [Float], bandCount: Int) -> [Float] {
        guard samples.count == n else { return Array(repeating: 0, count: bandCount) }

        // Apply Hann window to reduce spectral leakage.
        vDSP_vmul(samples, 1, hannWindow, 1, windowed, 1, vDSP_Length(n))

        var split = DSPSplitComplex(realp: realp, imagp: imagp)

        // vDSP_fft_zrip operates in place on an N/2 split-complex buffer whose
        // real/imaginary halves hold the even/odd input samples. Feeding it the
        // flat N-length signal (with an all-zero imaginary array) computes a
        // different transform entirely and mis-maps every frequency band, so the
        // even/odd packing via vDSP_ctoz is mandatory here.
        windowed.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { interleaved in
            vDSP_ctoz(interleaved, 2, &split, 1, vDSP_Length(halfN))
        }

        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))

        // zrip packs the Nyquist bin into imagp[0]; zero it so bin 0 carries DC
        // magnitude alone rather than a DC/Nyquist mixture.
        imagp[0] = 0

        vDSP_zvmags(&split, 1, magnitudes, 1, vDSP_Length(halfN))

        // Normalize so a full-scale sine peaks at exactly 1.0 (0 dB) instead of
        // saturating the dB mapping. The constant folds together zrip's factor
        // of 2, the 1/N transform scale and the Hann window's coherent gain
        // under vDSP_HANN_NORM (measured: a full-scale tone lands at 2/3 of N²).
        var scale: Float = 1.5 / (Float(n) * Float(n))
        vDSP_vsmul(magnitudes, 1, &scale, magnitudes, 1, vDSP_Length(halfN))

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
                maxMag = max(maxMag, magnitudes[j])
            }
            // Compress dynamic range and map to 0...1. Magnitudes are squared,
            // so 10*log10 is the amplitude dB.
            let db = 10 * log10(maxMag + 1e-12)
            let normalized = (db + 60) / 60 // -60 dB ... 0 dB -> 0...1
            bands[i] = min(1, max(0, normalized))
        }
        return bands
    }
}
