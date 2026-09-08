import XCTest
@testable import Lyra

final class AudioLevelAnalyzerTests: XCTestCase {
    func testRmsOfSilenceIsZero() {
        let analyzer = AudioLevelAnalyzer(levelCount: 10, windowSize: 512)
        let silence = [Float](repeating: 0, count: 512)
        analyzer.process(silence)

        let expectation = self.expectation(description: "levels update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(analyzer.levels.allSatisfy { $0 == 0 }, "Silence should produce zero levels")
    }

    func testRmsOfNonZeroSamplesIsPositive() {
        let analyzer = AudioLevelAnalyzer(levelCount: 10, windowSize: 512)
        var samples = [Float](repeating: 0, count: 512)
        for i in samples.indices {
            samples[i] = sin(Float(i) * 0.1) * 0.5
        }
        analyzer.process(samples)

        let expectation = self.expectation(description: "levels update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(analyzer.levels.contains { $0 > 0 }, "Non-zero signal should produce positive levels")
        XCTAssertTrue(analyzer.levels.allSatisfy { $0 <= 1 }, "Levels should be normalized to <= 1")
    }

    func testResetClearsLevels() {
        let analyzer = AudioLevelAnalyzer(levelCount: 10, windowSize: 512)
        var samples = [Float](repeating: 0, count: 512)
        for i in samples.indices { samples[i] = 0.5 }
        analyzer.process(samples)

        let processExpectation = self.expectation(description: "levels update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            processExpectation.fulfill()
        }
        wait(for: [processExpectation], timeout: 1.0)

        XCTAssertTrue(analyzer.levels.contains { $0 > 0 })

        analyzer.reset()

        let resetExpectation = self.expectation(description: "reset applies")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            resetExpectation.fulfill()
        }
        wait(for: [resetExpectation], timeout: 1.0)

        XCTAssertTrue(analyzer.levels.allSatisfy { $0 == 0 }, "Reset should zero all levels")
    }

    func testLevelBufferMaintainsFixedSize() {
        let levelCount = 8
        let analyzer = AudioLevelAnalyzer(levelCount: levelCount, windowSize: 64)
        for _ in 0..<20 {
            var samples = [Float](repeating: 0, count: 64)
            for i in samples.indices { samples[i] = Float.random(in: -0.1...0.1) }
            analyzer.process(samples)
        }

        let expectation = self.expectation(description: "levels update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(analyzer.levels.count, levelCount, "Level buffer should stay at configured size")
    }
}
