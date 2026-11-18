import Foundation

/// Encodes PNG frames into GIF/MP4 using ffmpeg if available
public enum VideoEncoder {
    public enum OutputFormat: String {
        case png = "png"   // Frames only, no video
        case gif = "gif"
        case mp4 = "mp4"
    }

    /// Check if ffmpeg is available in PATH
    public static func isFFmpegAvailable() -> Bool {
        return findExecutable("ffmpeg") != nil
    }

    /// Find an executable in PATH
    private static func findExecutable(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Encode frames to video
    /// - Parameters:
    ///   - format: Output format (gif or mp4)
    ///   - framesDirectory: Directory containing frame_*.png files
    ///   - outputURL: Output video file URL
    ///   - fps: Frames per second
    ///   - width: Video width (must be even for mp4)
    ///   - height: Video height (must be even for mp4)
    public static func encode(
        format: OutputFormat,
        framesDirectory: URL,
        outputURL: URL,
        fps: Int,
        width: Int,
        height: Int
    ) throws {
        guard format != .png else { return }
        guard let ffmpeg = findExecutable("ffmpeg") else {
            throw NSError(domain: "VideoEncoder", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "ffmpeg not found in PATH. Install ffmpeg to enable video output."])
        }

        let pattern = framesDirectory.appendingPathComponent("frame_%05d.png").path

        var args: [String] = [
            "-y",                           // Overwrite output
            "-framerate", String(fps),      // Input framerate
            "-i", pattern,                  // Input pattern
        ]

        switch format {
        case .mp4:
            // Ensure even dimensions for yuv420p
            let evenWidth = width % 2 == 0 ? width : width + 1
            let evenHeight = height % 2 == 0 ? height : height + 1
            args += [
                "-vf", "scale=\(evenWidth):\(evenHeight)",
                "-c:v", "libx264",
                "-pix_fmt", "yuv420p",
                "-crf", "23",
                outputURL.path
            ]
        case .gif:
            // Two-pass GIF for better quality
            let paletteURL = framesDirectory.appendingPathComponent("palette.png")
            // First pass: generate palette
            let paletteArgs = [
                "-y",
                "-framerate", String(fps),
                "-i", pattern,
                "-vf", "palettegen",
                paletteURL.path
            ]
            try runProcess(ffmpeg, paletteArgs)
            // Second pass: apply palette
            args += [
                "-i", paletteURL.path,
                "-lavfi", "paletteuse",
                outputURL.path
            ]
        case .png:
            break
        }

        try runProcess(ffmpeg, args)
    }

    private static func runProcess(_ executable: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "VideoEncoder", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: "ffmpeg failed: \(output)"])
        }
    }
}