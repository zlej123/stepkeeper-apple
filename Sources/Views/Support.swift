import SwiftUI

enum Pasteboard {
    @MainActor static var string: String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
        #endif
    }
}

/// 로컬 파일 이미지 (문서 폴더의 vg-N.jpg)
struct LocalImage: View {
    let url: URL
    var body: some View {
        #if os(macOS)
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #else
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        #endif
    }
}

/// 메모리 JPEG 썸네일 (후보 선택 UI)
struct JPEGImage: View {
    let data: Data
    var body: some View {
        #if os(macOS)
        if let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
        }
        #else
        if let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFit()
        }
        #endif
    }
}

enum ExportHelper {
    enum Result: Equatable, Sendable {
        case success(name: String)
        case failure(message: String)
    }

    /// 폴더 복사는 이미지가 포함돼 수백 KB~수 MB — 메인 스레드에서 동기로 하면 UI가 멈춘다.
    /// 호출부는 await로 실제 저장된 폴더 이름 또는 실패 메시지를 받는다.
    static func copyFolder(from source: URL, to directory: URL, name: String) async -> Result {
        await Task.detached(priority: .userInitiated) {
            copyFolderSync(from: source, to: directory, name: name)
        }.value
    }

    /// 문서 폴더를 사용자가 고른 디렉토리 아래 <name>/으로 복사한다.
    /// 같은 이름이 있으면 FileManager의 배타적 생성에 맡겨 충돌을 감지하고 <name>-2부터 재시도한다.
    /// 존재 여부를 미리 확인하지 않으므로 동시 내보내기 사이의 TOCTOU 덮어쓰기 경합도 만들지 않는다.
    static func copyFolderSync(from source: URL, to directory: URL, name: String) -> Result {
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager()
        var suffix = 1
        while true {
            let candidateName = suffix == 1 ? name : "\(name)-\(suffix)"
            let destination = directory.appendingPathComponent(candidateName, isDirectory: true)
            do {
                // copyItem은 대상이 이미 있으면 교체하지 않고 file-exists 오류를 낸다.
                // 각 시도가 목적 폴더를 직접 생성하므로 다른 내보내기와 경쟁해도 한 쪽만 성공한다.
                try fileManager.copyItem(at: source, to: destination)
                return .success(name: candidateName)
            } catch {
                if isFileExistsError(error) {
                    suffix += 1
                    continue
                }
                return .failure(
                    message: String(localized: "Couldn't save to the folder")
                        + ": \(error.localizedDescription)")
            }
        }
    }

    private static func isFileExistsError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
           error.code == CocoaError.fileWriteFileExists.rawValue {
            return true
        }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EEXIST) {
            return true
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            return isFileExistsError(underlying)
        }
        return false
    }
}

/// 키 미설정 배너의 시선 유도 배경 — 부드러운 주황 펄스. "동작 줄이기" 설정 시 정적 강조 (온보딩 폴리시).
struct KeyNudgeBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Color.orange.opacity(reduceMotion ? 0.18 : (pulsing ? 0.28 : 0.10))
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                       value: pulsing)
            .onAppear { pulsing = true }
    }
}
