import Foundation

enum Templates {
    struct NotFound: Error { let profile: String }

    /// 코어 render.py::load_template과 동일 규칙 — template.<language>.md가 있으면 우선,
    /// 없으면 template.md(영어 기본). 문서 뼈대(라벨·출처 줄)가 출력 언어를 따라간다.
    static func load(profile: String, language: String = "") throws -> String {
        let directory = "skill-core/\(profile)"
        if !language.isEmpty, let localized = Bundle.main.url(
            forResource: "template.\(language)", withExtension: "md", subdirectory: directory) {
            return try String(contentsOf: localized, encoding: .utf8)
        }
        guard let url = Bundle.main.url(
            forResource: "template", withExtension: "md", subdirectory: directory) else {
            throw NotFound(profile: profile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// render.py::build_context + 서버 /v1/documents 조립 파이프라인 포팅.
/// 앱은 image_refs(클라이언트 캡처 이미지의 상대 파일명)만 쓴다 — 디스크 프레임·picks 분기는 코어 전용이라 생략.
enum MarkdownBuilder {
    /// 코어 hms: 시간 단위 없이 분:초
    static func hms(_ sec: Int) -> String {
        "\(sec / 60):" + String(format: "%02d", sec % 60)
    }

    static func context(videoId: String, analysis: Analysis,
                        imageRefs: [String: String]) -> MustacheValue {
        var byStep: [Int: [VisualGuide]] = [:]
        for guide in analysis.visualGuides {
            byStep[guide.stepId, default: []].append(guide)
        }

        let steps: [MustacheValue] = analysis.steps.map { step in
            let guides: [MustacheValue] = (byStep[step.id] ?? []).map { guide in
                let ts = guide.bestVisualTimestamp
                var ctx: [String: MustacheValue] = [
                    "id": .string(guide.id),
                    "phrase": .string(guide.phrase),
                    "source_phrase": .string(guide.sourcePhrase),
                    "guide_text": .string(guide.guideText),
                    "importance": .double(guide.importance),
                    "has_screenshot": .bool(false),
                    "screenshot": .string(""),
                    "timestamp_hms": .string(ts.map(hms) ?? ""),
                    "timestamp_link": .string(
                        ts.map { "https://youtu.be/\(videoId)?t=\($0)" }
                        ?? "https://youtu.be/\(videoId)"),
                ]
                if let ref = imageRefs[guide.id] {
                    ctx["has_screenshot"] = .bool(true)
                    ctx["screenshot"] = .string(ref)
                }
                return .dict(ctx)
            }
            return .dict([
                "id": .int(step.id),
                "summary": .string(step.summary),
                "detail": .string(step.detail),
                "visual_guides": .list(guides),
            ])
        }

        let materials = MustacheValue.list(analysis.materials.map {
            .dict(["name": .string($0.name), "amount": .string($0.amount)])
        })
        return .dict([
            "high_risk": .bool(!HighRiskDetector.hits(
                in: analysis.title, analysis.category, analysis.summary).isEmpty),
            "title": .string(analysis.title),
            "summary": .string(analysis.summary),
            "video_summary": .string(analysis.summary),
            "category": .string(analysis.category ?? ""),
            "servings": .string(analysis.servings ?? ""),
            "materials": materials,
            "ingredients": materials,
            "steps": .list(steps),
            "video_title": .string(analysis.title),
            "video_url": .string("https://youtu.be/\(videoId)"),
        ])
    }

    static func markdown(videoId: String, analysis: Analysis,
                         imageRefs: [String: String], template: String) throws -> String {
        let body: Substring
        if let range = template.range(of: "\n---\n") {
            body = template[range.upperBound...]
        } else {
            body = template[...]
        }
        let rendered = try MustacheLite.render(
            String(body),
            context(videoId: videoId, analysis: analysis, imageRefs: imageRefs))
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func markdown(videoId: String, analysis: Analysis,
                         imageRefs: [String: String]) throws -> String {
        try markdown(videoId: videoId, analysis: analysis, imageRefs: imageRefs,
                     template: Templates.load(profile: analysis.profile ?? "generic",
                                              language: analysis.outputLanguage ?? ""))
    }
}
