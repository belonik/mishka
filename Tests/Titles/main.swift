import Foundation

// Title and snippet extraction: the first *content* line becomes the note title, and a
// leading YAML block is metadata rather than content.

let checks = Checks("Titles and snippets")

checks.equal("heading becomes the title",
             "# Обычная заметка\n\nТекст".noteTitle,
             "Обычная заметка")

checks.equal("front matter is skipped",
             "---\ntype: quarter\nowner: Продукт\n---\n# Квартальный отчёт\n\nТело".noteTitle,
             "Квартальный отчёт")

checks.equal("front matter does not leak into the snippet",
             "---\ntype: quarter\n---\n# Отчёт\n\nТело заметки.".plainSnippet(limit: 60),
             "Тело заметки.")

checks.equal("a leading thematic break is not a title",
             "---\n\n# Заголовок после линии\n\nТекст".noteTitle,
             "Заголовок после линии")

checks.equal("markers are stripped from the title",
             "## **Жирный** заголовок ##".noteTitle,
             "Жирный заголовок")

checks.equal("an empty note is Untitled", "\n".noteTitle, "Untitled")

checks.equal("front matter alone is Untitled",
             "---\ndraft: true\n---\n".noteTitle,
             "Untitled")

checks.equal("a note without front matter keeps its first line",
             "# Только заголовок".plainSnippet(limit: 40),
             "")

checks.equal("list markers are removed from the snippet",
             "# Список\n\n- [ ] Первый пункт\n- Второй".plainSnippet(limit: 60),
             "Первый пункт Второй")

checks.equal("table rows read as plain text in the snippet",
             "# Отчёт\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nКонец.".plainSnippet(limit: 60),
             "A B 1 2 Конец.")

checks.equal("fenced code is not quoted in the snippet",
             "# Код\n\n```swift\nlet x = 1\n```\n\nПосле кода.".plainSnippet(limit: 60),
             "После кода.")

checks.equal("word count", "один два три".wordCount, 3)

checks.equal("reading time is at least one minute", "слово".readingMinutes, 1)

checks.equal("reading time of an empty note is zero", "".readingMinutes, 0)

// Tag scanning drives the sidebar and the tag chips.
checks.equal("inline tags are found",
             Note.scanTags(in: "Текст #работа/проекты и #идеи"),
             ["идеи", "работа/проекты"])

checks.that("headings are not tags",
            Note.scanTags(in: "# Заголовок\n## Ещё один").isEmpty)

checks.that("tags inside fenced code are ignored",
            Note.scanTags(in: "```\n#нет\n```\n#да").count == 1)

checks.that("a URL fragment is not a tag",
            Note.scanTags(in: "https://example.com/page#section").isEmpty)

checks.that("an open task is detected", Note.scanOpenTask(in: "- [ ] сделать"))
checks.that("a done task is not open", !Note.scanOpenTask(in: "- [x] сделано"))

// Tag tree used by the sidebar.
let tree = TagNode.build(from: [["работа/проекты", "идеи"], ["работа/встречи"]])
checks.equal("tag tree has two roots", tree.count, 2)
checks.equal("nested tag inherits its children's count",
             tree.first { $0.id == "работа" }?.count,
             2)
checks.equal("leaf count", tree.first { $0.id == "работа" }?.children.count, 2)

checks.finish()
