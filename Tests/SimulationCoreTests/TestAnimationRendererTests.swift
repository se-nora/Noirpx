import XCTest
import Foundation

/// Integration tests for the TestAnimationRenderer CLI tool.
/// These tests run the built executable as a subprocess and verify output.
final class TestAnimationRendererTests: XCTestCase {

    /// Find the TestAnimationRenderer executable in the build products
    private func findExecutable() throws -> URL {
        // Look in .build/debug for the executable
        let buildDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug")
        let url = buildDir.appendingPathComponent("TestAnimationRenderer")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("TestAnimationRenderer executable not found at \(url.path). Run 'swift build' first.")
        }
        return url
    }

    /// Run the tool with arguments and capture output
    private func runTool(args: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let executable = try findExecutable()
        let process = Process()
        process.executableURL = executable
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    func testListScenarios() throws {
        let result = try runTool(args: ["--list-scenarios"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("sand-water-displacement"))
        XCTAssertTrue(result.stdout.contains("lava-water-reaction"))
        XCTAssertTrue(result.stdout.contains("beacon-run-full"))
        XCTAssertTrue(result.stdout.contains("cave-world"))
    }

    func testCaptureSandWaterDisplacement() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-anim-sand-water-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runTool(args: [
            "--scenario", "sand-water-displacement",
            "--output-dir", outputDir.path,
            "--ticks", "10",
            "--width", "320",
            "--height", "240"
        ])

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Captured 10 frames"))

        // Verify PNG files exist
        let pngFiles = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(pngFiles.count, 10)

        // Verify first frame is a valid PNG
        let firstFrame = outputDir.appendingPathComponent("frame_00000.png")
        let data = try Data(contentsOf: firstFrame)
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47])) // PNG magic bytes
    }

    func testCaptureLavaWaterReaction() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-anim-lava-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runTool(args: [
            "--scenario", "lava-water-reaction",
            "--output-dir", outputDir.path,
            "--ticks", "15",
            "--width", "320",
            "--height", "240"
        ])

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Captured 15 frames"))

        let pngFiles = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(pngFiles.count, 15)
    }

    func testCaptureBeaconRun() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-anim-beacon-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runTool(args: [
            "--scenario", "beacon-run-full",
            "--output-dir", outputDir.path,
            "--ticks", "30",
            "--width", "640",
            "--height", "360"
        ])

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Captured 30 frames"))

        let pngFiles = try FileManager.default.contentsOfDirectory(atPath: outputDir.path)
            .filter { $0.hasSuffix(".png") }
        XCTAssertEqual(pngFiles.count, 30)
    }

    func testInvalidScenarioFails() throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-anim-invalid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runTool(args: [
            "--scenario", "nonexistent-scenario",
            "--output-dir", outputDir.path,
            "--ticks", "5"
        ])

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Unknown scenario"))
    }

    func testGIFOutputIfFFmpegAvailable() throws {
        // Skip if ffmpeg not available
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["ffmpeg"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        guard which.terminationStatus == 0 else {
            throw XCTSkip("ffmpeg not available")
        }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-anim-gif-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputDir) }

        let result = try runTool(args: [
            "--scenario", "fire-water-reaction",
            "--output-dir", outputDir.path,
            "--ticks", "10",
            "--width", "320",
            "--height", "240",
            "--format", "gif"
        ])

        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Encoding GIF"))

        let gifFile = outputDir.appendingPathComponent("animation.gif")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gifFile.path))
        let data = try Data(contentsOf: gifFile)
        XCTAssertTrue(data.starts(with: [0x47, 0x49, 0x46])) // GIF magic bytes "GIF"
    }

    func testMissingOutputDirFails() throws {
        let result = try runTool(args: [
            "--scenario", "sand-water-displacement",
            "--ticks", "5"
        ])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("output-dir"))
    }
}