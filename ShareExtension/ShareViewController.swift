import UIKit
import UniformTypeIdentifiers

/// 유튜브 공유 → URL을 App Group에 저장하고 안내 후 닫힘 (스펙 4.7).
final class ShareViewController: UIViewController {
    private let groupID = "group.com.stepkeeper.shared"
    private let urlKey = "pendingURL"
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        label.text = "확인 중…"
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
            finish("URL을 찾지 못했습니다")
            return
        }
        let groupID = self.groupID
        let urlKey = self.urlKey
        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] value, _ in
            let urlString = (value as? URL)?.absoluteString ?? (value as? String) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }   // 해제됐으면 시스템이 확장을 정리한다 — 빈 suiteName 쓰기 방지 (리뷰 반영)
                guard YouTubeURL.videoID(from: urlString) != nil else {
                    self.finish("유튜브 영상 링크가 아닙니다")
                    return
                }
                UserDefaults(suiteName: groupID)?.set(urlString, forKey: urlKey)
                self.finish("저장됐습니다.\nstepkeeper를 열면 분석이 시작됩니다.")
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
