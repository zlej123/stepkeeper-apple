import Testing
@testable import stepkipper

struct MustacheLiteTests {
    private func d(_ pairs: [String: MustacheValue]) -> MustacheValue { .dict(pairs) }

    @Test func substitutesVariables() throws {
        #expect(try MustacheLite.render("Hello {{name}}!", d(["name": .string("stepkipper")]))
                == "Hello stepkipper!")
    }
    @Test func missingKeyRendersEmpty() throws {
        #expect(try MustacheLite.render("[{{nope}}]", d([:])) == "[]")
    }
    @Test func intVariableRendersLikePythonStr() throws {
        #expect(try MustacheLite.render("{{id}}.", d(["id": .int(3)])) == "3.")
    }
    @Test func sectionIteratesListWithParentLookup() throws {
        let tpl = "{{#items}}{{name}}@{{host}};{{/items}}"
        let data = d(["host": .string("h"),
                      "items": .list([d(["name": .string("a")]), d(["name": .string("b")])])])
        #expect(try MustacheLite.render(tpl, data) == "a@h;b@h;")
    }
    @Test func invertedSectionOnFalsy() throws {
        let tpl = "{{^has}}없음{{/has}}{{#has}}있음{{/has}}"
        #expect(try MustacheLite.render(tpl, d(["has": .bool(false)])) == "없음")
        #expect(try MustacheLite.render(tpl, d(["has": .bool(true)])) == "있음")
        #expect(try MustacheLite.render(tpl, d(["has": .string("")])) == "없음")
        #expect(try MustacheLite.render(tpl, d([:])) == "없음")   // 미존재 키도 falsy
    }
    @Test func emptyListSectionSkipsBody() throws {
        #expect(try MustacheLite.render("[{{#xs}}x{{/xs}}]", d(["xs": .list([])])) == "[]")
    }
    @Test func standaloneSectionLinesLeaveNoBlankLines() throws {
        // 파이썬 전처리: 섹션 태그만 있는 줄은 들여쓰기+개행 제거
        let tpl = "A\n{{#x}}\nB\n{{/x}}\nC\n"
        #expect(try MustacheLite.render(tpl, d(["x": .bool(true)])) == "A\nB\nC\n")
        #expect(try MustacheLite.render(tpl, d(["x": .bool(false)])) == "A\nC\n")
    }
    @Test func standaloneSectionLinesHandleCRLF() throws {
        let tpl = "A\r\n{{#x}}\r\nB\r\n{{/x}}\r\nC\r\n"
        #expect(try MustacheLite.render(tpl, d(["x": .bool(true)])) == "A\r\nB\r\nC\r\n")
        #expect(try MustacheLite.render(tpl, d(["x": .bool(false)])) == "A\r\nC\r\n")
    }
    @Test func nestedSectionsOfSameShapeResolve() throws {
        let tpl = "{{#steps}}{{id}}:{{#visual_guides}}<{{id}}>{{/visual_guides}} {{/steps}}"
        let data = d(["steps": .list([
            d(["id": .int(1), "visual_guides": .list([d(["id": .string("vg-1")])])]),
            d(["id": .int(2), "visual_guides": .list([])]),
        ])])
        #expect(try MustacheLite.render(tpl, data) == "1:<vg-1> 2: ")
    }
    @Test func unclosedSectionThrows() {
        #expect(throws: MustacheLite.UnclosedSection.self) {
            try MustacheLite.render("{{#a}}x", d(["a": .bool(true)]))
        }
    }
}
