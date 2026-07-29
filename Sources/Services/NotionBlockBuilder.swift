import Foundation

/// Notion 블록 표현 — JSONSerialization 호환 딕셔너리.
/// nonisolated 동일 태스크 안에서만 흐른다(MainActor 경계 통과 금지 — 스펙 3.1).
typealias NotionBlock = [String: Any]

/// 코어 export.py::build_notion_blocks 1:1 포팅.
/// 골든(expected-notion.json)이 파리티 심판 — 동작을 임의로 개선하지 말 것.
/// 절 제목은 코어와 같이 문서의 출력 언어를 따른다 (DocumentStrings). 단 순서 제목은
/// 코어 Notion 경로가 요리 프로파일에서도 "순서"를 쓰므로 stepsTitle이 아니라 steps를 쓴다.
enum NotionBlockBuilder {
    /// 코어 _rich: 2000자 절단 + 선택적 링크
    static func rich(_ text: String, link: String? = nil) -> [[String: Any]] {
        var textDict: [String: Any] = ["content": String(text.prefix(2000))]
        if let link {
            textDict["link"] = ["url": link]
        }
        return [["type": "text", "text": textDict]]
    }

    static func blocks(analysis: Analysis, videoId: String,
                       imageUploadIds: [String: String]) -> [NotionBlock] {
        let labels = DocumentStrings.forLanguage(analysis.outputLanguage ?? "")
        let isRecipe = analysis.profile == "recipe"
        var blocks: [NotionBlock] = []
        if !HighRiskDetector.hits(in: analysis.title, analysis.category,
                                  analysis.summary).isEmpty {
            // 코어 파리티: 안전 고지는 저장물 자체의 최상단 callout
            blocks.append(["type": "callout", "callout": [
                "icon": ["type": "emoji", "emoji": "⚠️"],
                "rich_text": rich(labels.highRiskNotice)] as [String: Any]])
        }
        if !analysis.summary.isEmpty {
            blocks.append(["type": "paragraph",
                           "paragraph": ["rich_text": rich(analysis.summary)]])
        }
        blocks.append(["type": "paragraph", "paragraph": ["rich_text": rich(
            labels.sourceLink, link: "https://youtu.be/\(videoId)")]])

        if !analysis.materials.isEmpty {
            blocks.append(["type": "heading_2",
                           "heading_2": ["rich_text": rich(
                               isRecipe ? labels.ingredients : labels.materials)]])
            for material in analysis.materials {
                blocks.append(["type": "bulleted_list_item", "bulleted_list_item":
                    ["rich_text": rich("\(material.name) \(material.amount)")]])
            }
        }

        var byStep: [Int: [VisualGuide]] = [:]
        for guide in analysis.visualGuides {
            byStep[guide.stepId, default: []].append(guide)
        }

        blocks.append(["type": "heading_2",
                       "heading_2": ["rich_text": rich(labels.steps)]])
        for step in analysis.steps {
            blocks.append(["type": "numbered_list_item", "numbered_list_item":
                ["rich_text": rich("\(step.summary) — \(step.detail)")]])
            for guide in byStep[step.id] ?? [] {
                blocks.append(["type": "quote", "quote": ["rich_text": rich(
                    "💡 " + labels.guidePrefix(guide.phrase) + " \(guide.guideText)")]])
                if let uploadId = imageUploadIds[guide.id] {
                    blocks.append(["type": "image", "image":
                        ["type": "file_upload", "file_upload": ["id": uploadId]]])
                } else if let ts = guide.bestVisualTimestamp {
                    blocks.append(["type": "paragraph", "paragraph": ["rich_text": rich(
                        labels.seeAt(MarkdownBuilder.hms(ts)),
                        link: "https://youtu.be/\(videoId)?t=\(ts)")]])
                }
            }
        }
        return blocks
    }
}
