import UIKit
import UniformTypeIdentifiers

/// 유튜브 공유 → URL을 App Group에 저장하고 안내 후 닫힘 (스펙 4.7).
final class ShareViewController: UIViewController {
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = String(localized: "Checking…")
        label.font = .preferredFont(forTextStyle: .headline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
        handleAttachment()
    }

    private func handleAttachment() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap(\.attachments).flatMap { $0 } ?? []
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) else {
            finish(String(localized: "No URL found"))
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] value, _ in
            let urlString = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }   // 해제됐으면 시스템이 확장을 정리한다 — 빈 suiteName 쓰기 방지 (리뷰 반영)
                guard YouTubeURL.videoID(from: urlString) != nil else {
                    self.finish(String(localized: "That isn't a YouTube video link"))
                    return
                }
                ShareInbox.push(urlString)   // FIFO — 여러 번 공유해도 덮어쓰지 않는다
                self.finish(String(localized: "Saved.\nOpen stepkeeper to start the analysis."))
            }
        }
    }

    private func finish(_ message: String) {
        label.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
