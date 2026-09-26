# Руководство разработчика

Как собрать, проверить и расширить проект.

---

## 1. Требования к окружению

| | |
| --- | --- |
| macOS | 15 Sequoia или новее |
| Xcode | 26 (Swift 6.2) |
| Зависимости | нет, только системные фреймворки |
| Сеть | не нужна ни для сборки, ни для работы |

Проверить окружение:

```bash
swift --version      # Apple Swift version 6.2
sw_vers              # ProductVersion: 15.x
```

---

## 2. Сборка

```bash
./build.sh                 # release → dist/Mishka.app
./build.sh debug           # debug-сборка (быстрее компилируется)
./build.sh release run     # собрать и запустить
```

Скрипт делает четыре вещи:

1. `swift build -c <config>`;
2. собирает `.app`-бандл: бинарник, сгенерированный `Info.plist`, иконку;
3. рисует иконку через `Tools/make-icon.swift`, если её ещё нет;
4. подписывает бандл ad-hoc подписью.

Запуск с отдельным хранилищем — удобно для экспериментов, не задевая рабочие заметки:

```bash
open dist/Mishka.app --args --vault /tmp/mishka-demo
```

### Про кэш модулей

SwiftPM и `swiftc` пишут кэш модулей Clang в `~/Library` или `/var/folders`. В ограниченном
окружении это может быть недоступно, и сборка падает с `error opening '.../ModuleCache/...'`.
`build.sh` и `Tests/run-tests.sh` выставляют `CLANG_MODULE_CACHE_PATH` в каталог проекта —
если запускаете `swiftc` вручную, добавляйте флаг:

```bash
swiftc -module-cache-path .dsh-modulecache -typecheck <файлы>
```

---

## 3. Структура проекта

```
Package.swift              единственный таргет, Swift 5 language mode
build.sh                   сборка .app
README.md                  обзор
docs/                      ТЗ, архитектура, руководства
Sources/Mishka/
├── App/                   точка входа, меню, состояние, настройки
├── Models/                Note, TagNode
├── Storage/               NoteStore
├── Theme/                 Theme, ThemeCatalog
├── Markdown/              MarkdownRenderer (Markdown → HTML)
├── Editor/                MarkdownHighlighter, MarkdownTextView, MarkdownEditor
├── Views/                 SwiftUI-представления
└── Support/               Utilities, Exporter
Tests/                     проверки (см. ниже)
Tools/
├── make-icon.swift        рисует иконку приложения
└── render-samples/        оффскрин-рендер редактора и превью в PNG
```

Правила размещения:

- новый **тип данных** — в `Models/`;
- работа с **файлами и индексом** — в `Storage/NoteStore.swift`;
- **разбор Markdown** — либо в `MarkdownHighlighter` (для редактора), либо в
  `MarkdownRenderer` (для превью и экспорта); это два независимых движка под разные задачи;
- **состояние интерфейса** — в `AppState`; настройки — в `AppSettings`;
- всё, что **переиспользуется** в представлениях, — в `Views/Components.swift`.

---

## 4. Тесты

```bash
./Tests/run-tests.sh
```

Проверки — это отдельные исполняемые программы, а не XCTest-бандл: приложение объявлено
исполняемым таргетом, и тестовый бандл не может его импортировать. Каждая программа
компилируется вместе с исходниками, которые проверяет, — то есть тестируется реальный код,
а не его копия.

| Набор | Что проверяет | Проверок |
| --- | --- | ---: |
| `Titles` | Заголовок и сниппет: front matter, тематические разделители, разметка, теги, дерево тегов | 23 |
| `Store` | Файлы на месте: правка оригинала, отсутствие копий, история, корзина, пропавшие файлы | 22 |
| `Subscriptions` | Любая операция хранилища доходит до интерфейса (перерисовка SwiftUI) | 13 |

### Как добавить проверку

1. Создайте `Tests/<Имя>/main.swift`.
2. Используйте общий помощник:

```swift
import Foundation

let checks = Checks("Мой набор")

checks.equal("два плюс два", 2 + 2, 4)
checks.that("условие", someValue > 0, "пояснение при провале")

checks.finish()   // печатает итог и завершает процесс с нужным кодом
```

3. Добавьте вызов в `Tests/run-tests.sh`:

```bash
run_suite МойНабор \
    "$APP/Support/Utilities.swift" \
    "$APP/Models/Note.swift"
```

Список исходников перечисляется явно — так набор зависит только от того, что проверяет.

### Чего тесты не делают

Проверок с мышью и клавиатурой нет: синтез событий в системе запрещён
(`CGPreflightPostEventAccess()` возвращает `false`). Пункты приёмки, требующие кликов,
перечислены в [ТЗ](TZ.md) как проверяемые вручную.

---

## 5. Инструменты

### Иконка

```bash
swift Tools/make-icon.swift /tmp/icon.png
```

Рисует иконку 1024×1024 процедурно: суперэллипс, диагональный градиент, медведь.
`build.sh` вызывает скрипт автоматически и собирает `.icns` через `sips` и `iconutil`.

### Оффскрин-рендер вёрстки

Позволяет смотреть на редактор и превью, не запуская приложение и не отвлекаясь на окна:

```bash
swiftc -module-cache-path .dsh-modulecache \
  Sources/Mishka/Support/Utilities.swift \
  Sources/Mishka/Models/Note.swift Sources/Mishka/Models/Tag.swift \
  Sources/Mishka/Theme/Theme.swift Sources/Mishka/Theme/ThemeCatalog.swift \
  Sources/Mishka/Markdown/MarkdownRenderer.swift \
  Sources/Mishka/Editor/MarkdownHighlighter.swift \
  Sources/Mishka/Editor/MarkdownTextView.swift \
  Sources/Mishka/Views/PreviewPane.swift \
  Tools/render-samples/main.swift -o /tmp/render-samples

/tmp/render-samples /tmp
# → /tmp/mishka-preview.png, /tmp/mishka-editor.png, /tmp/mishka-editor-dark.png
```

Образец Markdown лежит в начале `Tools/render-samples/main.swift` — добавьте туда
конструкцию, вид которой хотите проверить, и сравните результат. Это быстрее и надёжнее
скриншотов рабочего стола.

### Проверка CSS без интерфейса

```bash
# выгрузить сгенерированный стиль в файл
swiftc -module-cache-path .dsh-modulecache \
  Sources/Mishka/Theme/Theme.swift Sources/Mishka/Theme/ThemeCatalog.swift \
  Sources/Mishka/Markdown/MarkdownRenderer.swift /tmp/dump/main.swift -o /tmp/dump/run
```

Удобно, когда нужно убедиться, что правило действительно попало в таблицу стилей.

---

## 6. Отладка

### Диагностика интерфейса

`NSLog` и `log show` в этом окружении не показали сообщений приложения. Рабочий приём —
писать в файл:

```swift
enum MishkaDiag {
    static func log(_ message: String) {
        let line = message + "\n"
        let url = URL(fileURLWithPath: "/tmp/mishka-diag.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
```

Так были найдены две ошибки: гонка загрузки превью и пересоздание окон. Помощник был удалён
после отладки — при необходимости добавьте его во временный файл и не забывайте убирать
перед коммитом.

### Полезные приёмы

```bash
# сколько окон открыто у приложения
# (CGWindowListCopyWindowInfo не требует разрешений)
/tmp/winlist

# принудительно завершить все экземпляры
pkill -9 -f "Mishka.app/Contents/MacOS/Mishka"

# проверить, что именно попало в индекс
python3 -m json.tool ~/Library/"Application Support"/Mishka/library.json
```

### Подводные камни

| Симптом | Причина | Что делать |
| --- | --- | --- |
| `error opening '.../ModuleCache/...'` | Драйвер не может писать в системный кэш | Флаг `-module-cache-path` или `CLANG_MODULE_CACHE_PATH` |
| Превью отстаёт на одну заметку | Обновление применилось, пока шла загрузка документа | Смотрите `pendingMarkdown` в `PreviewPane.swift` |
| Интерфейс не реагирует на действия | Потеряна ретрансляция `objectWillChange` | `Tests/Subscriptions` |
| Углы карточки таблицы прямые | WebKit не срезает `border-radius` у скролл-контейнера | Карточка строится из двух блоков |
| Каждое открытие файла создаёт окно | Сцена `WindowGroup` вместо `Window` | `MishkaApp.swift` |
| `WKWebView` создаётся по нескольку раз | Нестабильная идентичность представления | Модификатор `.id(...)` |

---

## 7. Как расширять

### Добавить тему

В `Sources/Mishka/Theme/ThemeCatalog.swift`:

```swift
private static let myTheme = Theme(
    id: "my-theme", name: "My Theme", isDark: false,
    background: "#FFFFFF", sidebar: "#F7F7F5", list: "#FAFAF8", elevated: "#FFFFFF",
    text: "#1C1C1E", secondaryText: "#565660", tertiaryText: "#8A8A93",
    heading: "#0F0F11", link: "#C33A22", tag: "#B03520", quote: "#5A5A63",
    codeText: "#A8250F", codeBackground: "#F1F1EC",
    selection: "#F6D9D3", border: "#E6E6DF", marker: "#91919B"
)
```

и добавьте `myTheme` в `all`. Обязательно проверьте контраст: основной текст к фону —
не ниже 4,5:1. `Theme` типизирован как `Codable`, так что тема автоматически попадает и в
редактор, и в CSS превью.

### Добавить команду в меню

1. Реализуйте действие на `MarkdownTextView`:

```swift
@objc func doSomething(_ sender: Any?) { /* … */ }
```

2. Добавьте пункт в `MishkaCommands` (`App/MishkaApp.swift`):

```swift
Button("Do Something") { send(#selector(MarkdownTextView.doSomething(_:))) }
    .keyboardShortcut("j", modifiers: [.command, .shift])
```

Команды формата идут через цепочку респондеров (`NSApp.sendAction(_:to: nil)`), поэтому
меню не знает о редакторе напрямую и работает с любым активным полем ввода.

Команды уровня приложения (создать, открыть, импортировать) вызывают методы `AppState`.

### Добавить поддержку конструкции Markdown

Конструкцию нужно провести через **два независимых движка**.

**Редактор** (`Editor/MarkdownHighlighter.swift`):

1. Блочные конструкции ищите в `scanStructure` (там построчный разбор с состоянием:
   блок кода, таблица, front matter), строчные — в `scanInline`.
2. Примените атрибуты (`addAttributes`) и, если внутри конструкции не должна работать
   другая разметка, добавьте диапазон в `protected`.
3. Для отрисовки на полях или фона используйте пользовательский атрибут и прочитайте его
   в `MarkdownLayoutManager`.

**Превью** (`Markdown/MarkdownRenderer.swift`):

1. Разбор — в `MDRBlockParser` (блоки) или `MDRUtil` (строчные элементы).
2. Стили — в `MDRStylesheet.build`, цвета берутся только из `MDRPalette`, который строится
   из `Theme`. Никаких зашитых в CSS значений: иначе темы разойдутся.
3. Весь пользовательский текст обязан проходить через `escape(...)`.

**Проверка.** Добавьте случай в `Tests/Titles` (если конструкция влияет на разбор текста)
или проверьте вид через `Tools/render-samples`. Загляните в раздел «Приёмка» в
[ТЗ](TZ.md) — возможно, пункт стоит дополнить.

### Изменить оформление

Стили превью — `MDRStylesheet.build` в `MarkdownRenderer.swift`. Помните: `Theme` описывает
палитру, а не раскладку, поэтому отступы, размеры и скругления задаются прямо в CSS.

Оформление редактора — `MarkdownHighlighter` (шрифты, цвета, отступы абзацев) и
`MarkdownLayoutManager` (гуттер, карточки таблиц).

---

## 8. Соглашения

- **Комментарии объясняют «почему», а не «что».** В коде уже есть развёрнутые пояснения к
  неочевидным местам — гонке превью, ретрансляции наблюдаемости, скруглению углов. Такой
  комментарий должен оставаться рядом с кодом, а не переезжать в документацию.
- **Один тип — один файл**, за исключением мелких вспомогательных структур рядом с хозяином.
- **Никаких внешних зависимостей.** Новый пакет требует серьёзного обоснования.
- **Тексты интерфейса на английском**, содержимое заметок — на любом языке; строки UI
  пока не вынесены в таблицы локализации.
- **Производные данные не хранятся.** Если значение можно вычислить из текста — оно
  вычисляется и кэшируется, но не попадает в файл.
- **Никаких изменений пользовательского текста.** Ни подсветка, ни превью, ни экспорт не
  переписывают содержимое заметки.
- **Проверка перед коммитом:**

```bash
./Tests/run-tests.sh && ./build.sh release
```

---

## 9. Полезные ссылки

- [ТЗ](TZ.md) — требования и критерии приёмки.
- [Архитектура](ARCHITECTURE.md) — устройство и ключевые решения.
- [Руководство пользователя](USER-GUIDE.md) — что умеет приложение.
