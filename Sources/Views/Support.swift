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
    /// 폴더 복사는 이미지가 포함돼 수백 KB~수 MB — 메인 스레드에서 동기로 하면 UI가 멈춘다.
    /// 호출부는 await로 결과 메시지를 받는다.
    static func copyFolder(from source: URL, to directory: URL, name: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            copyFolderSync(from: source, to: directory, name: name)
        }.value
    }

    /// 문서 폴더를 사용자가 고른 디렉토리 아래 <name>/으로 복사. 성공 시 nil, 실패 시 메시지.
    static func copyFolderSync(from source: URL, to directory: URL, name: String) -> String? {
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
        do {
            let destination = directory.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return nil
        } catch {
            return "저장 실패: \(error.localizedDescription)"
        }
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
