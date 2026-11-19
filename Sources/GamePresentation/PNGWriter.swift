import Foundation

/// Pure-Swift PNG writer using stored-block DEFLATE (no zlib dependency).
/// Deterministic: same input pixels always produces identical PNG bytes.
public enum PNGWriter {
    /// Encodes RGBA pixels to PNG data. Pixels are top-down row-major, width*height*4 bytes.
    public static func pngData(_ pixels: [UInt8], width: Int, height: Int) -> Data {
        var data = Data()
        // PNG signature
        data.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // IHDR chunk
        data.append(chunk(type: "IHDR", data: ihdrData(width: width, height: height)))
        // IDAT chunk(s) - stored blocks
        let idat = idatData(pixels: pixels, width: width, height: height)
        data.append(chunk(type: "IDAT", data: idat))
        // IEND chunk
        data.append(chunk(type: "IEND", data: Data()))
        return data
    }

    /// Writes PNG to file.
    public static func write(_ pixels: [UInt8], width: Int, height: Int, to path: String) throws {
        let data = pngData(pixels, width: width, height: height)
        try data.write(to: URL(fileURLWithPath: path))
    }

    // MARK: - Chunk encoding

    private static func chunk(type: String, data: Data) -> Data {
        var chunk = Data()
        // Length (big-endian)
        var len = UInt32(data.count).bigEndian
        chunk.append(Data(bytes: &len, count: 4))
        // Type
        chunk.append(type.data(using: .ascii)!)
        // Data
        chunk.append(data)
        // CRC32 (type + data)
        var crc = crc32(type.data(using: .ascii)!)
        crc = crc32(data, seed: crc)
        var crcBE = crc.bigEndian
        chunk.append(Data(bytes: &crcBE, count: 4))
        return chunk
    }

    private static func ihdrData(width: Int, height: Int) -> Data {
        var data = Data()
        var w = UInt32(width).bigEndian
        var h = UInt32(height).bigEndian
        data.append(Data(bytes: &w, count: 4))
        data.append(Data(bytes: &h, count: 4))
        // Bit depth: 8, Color type: 6 (RGBA), Compression: 0, Filter: 0, Interlace: 0
        data.append(contentsOf: [8, 6, 0, 0, 0])
        return data
    }

    // MARK: - Stored-block DEFLATE (RFC 1951)

    /// Builds a zlib stream containing the scanlines as stored blocks.
    /// Each scanline = filter byte (0) + width*4 RGBA bytes.
    private static func idatData(pixels: [UInt8], width: Int, height: Int) -> Data {
        let scanlineSize = 1 + width * 4
        let maxBlockSize = 65535
        var zlib = Data()
        // zlib header: CMF=0x78 (deflate, 32K window), FLG=0x01 (no compression, no dict, check bits)
        zlib.append(contentsOf: [0x78, 0x01])

        var scanlines = Data()
        scanlines.reserveCapacity(height * scanlineSize)
        for y in 0..<height {
            scanlines.append(0) // filter type 0 (none)
            let rowStart = y * width * 4
            scanlines.append(contentsOf: pixels[rowStart..<rowStart + width * 4])
        }

        // Split into stored blocks (max 65535 bytes each)
        var offset = 0
        while offset < scanlines.count {
            let remaining = scanlines.count - offset
            let blockSize = min(remaining, maxBlockSize)
            let isLast = (offset + blockSize == scanlines.count)
            // Stored block header: BFINAL+BTYPE (1 bit BFINAL, 2 bits BTYPE=00) -> 0x01 if last, 0x00 if not
            zlib.append(isLast ? 0x01 : 0x00)
            // LEN (little-endian)
            var len = UInt16(blockSize).littleEndian
            zlib.append(Data(bytes: &len, count: 2))
            // NLEN = ~LEN
            var nlen = (~UInt16(blockSize)).littleEndian
            zlib.append(Data(bytes: &nlen, count: 2))
            // Data
            zlib.append(scanlines[offset..<offset + blockSize])
            offset += blockSize
        }

        // Adler32 checksum of uncompressed scanlines
        let adler = adler32(scanlines)
        var adlerBE = adler.bigEndian
        zlib.append(Data(bytes: &adlerBE, count: 4))

        return zlib
    }

    // MARK: - CRC32 (ISO 3309 polynomial 0xEDB88320)

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1
            }
            table[i] = crc
        }
        return table
    }()

    private static func crc32(_ data: Data, seed: UInt32 = 0xFFFFFFFF) -> UInt32 {
        var crc = seed
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    // MARK: - Adler32 (RFC 1950)

    private static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        let base: UInt32 = 65521
        for byte in data {
            a = (a + UInt32(byte)) % base
            b = (b + a) % base
        }
        return (b << 16) | a
    }
}