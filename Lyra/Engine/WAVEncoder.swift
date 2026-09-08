import Foundation

/// Fast, dependency-free encoder that converts 16 kHz Float32 PCM audio samples
/// into standard 16-bit linear PCM WAV container data for HTTP multipart uploads.
enum WAVEncoder {
    /// Encodes mono Float32 audio samples (sampled at 16000 Hz) into 16-bit PCM WAV Data.
    /// Clamps input values to [-1.0, 1.0] before conversion to Int16.
    static func encodeToWAV(samples: [Float], sampleRate: Int = 16000) -> Data {
        let numChannels: Int = 1
        let bitsPerSample: Int = 16
        let byteRate: Int = sampleRate * numChannels * (bitsPerSample / 8)
        let blockAlign: Int = numChannels * (bitsPerSample / 8)
        let dataSize: Int = samples.count * (bitsPerSample / 8)
        let totalSize: Int = 36 + dataSize

        var data = Data(capacity: totalSize + 8)

        // 1. "RIFF" Chunk
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSizeLE = UInt32(totalSize).littleEndian
        withUnsafeBytes(of: &chunkSizeLE) { data.append(contentsOf: $0) }
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // 2. "fmt " Subchunk
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1SizeLE = UInt32(16).littleEndian
        withUnsafeBytes(of: &subchunk1SizeLE) { data.append(contentsOf: $0) }

        var audioFormatLE = UInt16(1).littleEndian // 1 = Linear PCM
        withUnsafeBytes(of: &audioFormatLE) { data.append(contentsOf: $0) }

        var numChannelsLE = UInt16(numChannels).littleEndian
        withUnsafeBytes(of: &numChannelsLE) { data.append(contentsOf: $0) }

        var sampleRateLE = UInt32(sampleRate).littleEndian
        withUnsafeBytes(of: &sampleRateLE) { data.append(contentsOf: $0) }

        var byteRateLE = UInt32(byteRate).littleEndian
        withUnsafeBytes(of: &byteRateLE) { data.append(contentsOf: $0) }

        var blockAlignLE = UInt16(blockAlign).littleEndian
        withUnsafeBytes(of: &blockAlignLE) { data.append(contentsOf: $0) }

        var bitsPerSampleLE = UInt16(bitsPerSample).littleEndian
        withUnsafeBytes(of: &bitsPerSampleLE) { data.append(contentsOf: $0) }

        // 3. "data" Subchunk
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var subchunk2SizeLE = UInt32(dataSize).littleEndian
        withUnsafeBytes(of: &subchunk2SizeLE) { data.append(contentsOf: $0) }

        // 4. PCM Samples Conversion: Float32 [-1.0, 1.0] -> Int16 [-32768, 32767]
        var pcmBuffer = [Int16]()
        pcmBuffer.reserveCapacity(samples.count)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let intSample = Int16(clamped * 32767.0)
            pcmBuffer.append(intSample.littleEndian)
        }

        pcmBuffer.withUnsafeBufferPointer { bufferPtr in
            let rawBuffer = UnsafeRawBufferPointer(bufferPtr)
            data.append(contentsOf: rawBuffer)
        }

        return data
    }
}
