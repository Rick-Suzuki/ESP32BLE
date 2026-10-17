import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum SettingsArchiveError: Error {
    case unsupportedFormat
}

private struct SettingsTextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct SettingsArchiveFileDocument: FileDocument {
    struct ArchiveEntry {
        let fileName: String
        let data: Data
    }

    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "zip") ?? .data]
    }

    static var writableContentTypes: [UTType] {
        readableContentTypes
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func makeArchiveData(with entries: [ArchiveEntry]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var archiveData = Data()
        var centralDirectoryData = Data()

        for entry in entries {
            let fileNameData = Data(entry.fileName.utf8)
            guard fileNameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  archiveData.count <= Int(UInt32.max) else {
                throw CocoaError(.fileWriteUnknown)
            }

            let crc32 = crc32(of: entry.data)
            let localHeaderOffset = UInt32(archiveData.count)
            let uncompressedSize = UInt32(entry.data.count)
            let compressedSize = UInt32(entry.data.count)
            let fileNameLength = UInt16(fileNameData.count)

            archiveData.appendUInt32LE(0x04034B50)
            archiveData.appendUInt16LE(20)
            archiveData.appendUInt16LE(0)
            archiveData.appendUInt16LE(0)
            archiveData.appendUInt16LE(0)
            archiveData.appendUInt16LE(0)
            archiveData.appendUInt32LE(crc32)
            archiveData.appendUInt32LE(compressedSize)
            archiveData.appendUInt32LE(uncompressedSize)
            archiveData.appendUInt16LE(fileNameLength)
            archiveData.appendUInt16LE(0)
            archiveData.append(fileNameData)
            archiveData.append(entry.data)

            centralDirectoryData.appendUInt32LE(0x02014B50)
            centralDirectoryData.appendUInt16LE(20)
            centralDirectoryData.appendUInt16LE(20)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt32LE(crc32)
            centralDirectoryData.appendUInt32LE(compressedSize)
            centralDirectoryData.appendUInt32LE(uncompressedSize)
            centralDirectoryData.appendUInt16LE(fileNameLength)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt16LE(0)
            centralDirectoryData.appendUInt32LE(0)
            centralDirectoryData.appendUInt32LE(localHeaderOffset)
            centralDirectoryData.append(fileNameData)
        }

        guard centralDirectoryData.count <= Int(UInt32.max),
              archiveData.count <= Int(UInt32.max) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let centralDirectoryOffset = UInt32(archiveData.count)
        let centralDirectorySize = UInt32(centralDirectoryData.count)

        archiveData.append(centralDirectoryData)
        archiveData.appendUInt32LE(0x06054B50)
        archiveData.appendUInt16LE(0)
        archiveData.appendUInt16LE(0)
        archiveData.appendUInt16LE(UInt16(entries.count))
        archiveData.appendUInt16LE(UInt16(entries.count))
        archiveData.appendUInt32LE(centralDirectorySize)
        archiveData.appendUInt32LE(centralDirectoryOffset)
        archiveData.appendUInt16LE(0)

        return archiveData
    }

    static func archiveEntries(from archiveData: Data) throws -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        var offset = 0

        while offset + 4 <= archiveData.count {
            let signature = try archiveData.uint32LE(at: offset)
            if signature == 0x02014B50 || signature == 0x06054B50 {
                break
            }

            guard signature == 0x04034B50 else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let generalPurposeFlags = try archiveData.uint16LE(at: offset + 6)
            let compressionMethod = try archiveData.uint16LE(at: offset + 8)
            let compressedSize = Int(try archiveData.uint32LE(at: offset + 18))
            let uncompressedSize = Int(try archiveData.uint32LE(at: offset + 22))
            let fileNameLength = Int(try archiveData.uint16LE(at: offset + 26))
            let extraFieldLength = Int(try archiveData.uint16LE(at: offset + 28))

            guard generalPurposeFlags & 0x0008 == 0,
                  compressionMethod == 0,
                  compressedSize == uncompressedSize else {
                throw SettingsArchiveError.unsupportedFormat
            }

            let fileNameOffset = offset + 30
            let fileDataOffset = fileNameOffset + fileNameLength + extraFieldLength
            let nextOffset = fileDataOffset + compressedSize

            guard fileNameOffset <= archiveData.count,
                  fileDataOffset <= archiveData.count,
                  nextOffset <= archiveData.count else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let fileNameData = archiveData.subdata(in: fileNameOffset..<(fileNameOffset + fileNameLength))
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let entryData = archiveData.subdata(in: fileDataOffset..<nextOffset)
            entries.append(ArchiveEntry(fileName: fileName, data: entryData))
            offset = nextOffset
        }

        return entries
    }

    private static func crc32(of data: Data) -> UInt32 {
        var crc = UInt32.max

        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crc32Table[index]
        }

        return crc ^ UInt32.max
    }

    private static let crc32Table: [UInt32] = (0..<256).map { value in
        var current = UInt32(value)

        for _ in 0..<8 {
            if current & 1 == 1 {
                current = 0xEDB88320 ^ (current >> 1)
            } else {
                current >>= 1
            }
        }

        return current
    }
}

struct SettingsSingleFileExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish()
        }
    }
}

private extension Data {
    func uint16LE(at offset: Int) throws -> UInt16 {
        guard offset >= 0,
              offset + MemoryLayout<UInt16>.size <= count else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return UInt16(self[offset]) |
            (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0,
              offset + MemoryLayout<UInt32>.size <= count else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        append(Data(bytes: &littleEndianValue, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        append(Data(bytes: &littleEndianValue, count: MemoryLayout<UInt32>.size))
    }
}
