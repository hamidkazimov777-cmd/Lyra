# Комплексный инженерный аудит приложения Lyra (v1.2.2)

**Дата проведения:** 8 сентября 2026 г.  
**Роль:** Senior Systems & macOS Platform Engineer  
**Объект аудита:** Репозиторий `Lyra` (WhisperDictation), ветка `main` (коммит `8feb1bc`)  
**Платформа:** macOS 12.0+ (Universal Binary: Apple Silicon arm64 + Intel x86_64)  
**Стек:** Swift 5, SwiftUI, AppKit, CoreAudio, Accelerate (vDSP), C++ (`whisper.cpp`, `ggml`), OpenRouter / OpenAI API.

---

## Статус устранения (v1.3.0)

Все пункты аудита проверены по коду и закрыты в релизе 1.3.0. Сводка:

| № | Проблема | Статус | Что сделано |
|---|---|:---:|---|
| 1.1 | Хардкод OpenRouter в LLM-пайплайне | ✅ | Отдельные настройки `llmBaseURL` / `llmAPIKey`; эндпоинт строится динамически; ключ STT уходит на LLM-эндпоинт только при явном согласии **и** совпадении хоста |
| 1.2 | Пресет DeepSeek в STT | ✅ | Удалён из `APIPresetProvider` + миграция сохранённой настройки на рабочий пресет |
| 1.3 | Поглощение Option и ложный Hands-Free | ✅ | `flagsChanged` больше не поглощается; добавлена детекция аккордов с отменой записи и отложенный стартовый звук (120 мс) |
| 2.1 | API-ключи в plaintext UserDefaults | ✅ | `KeychainStore` (`kSecClassGenericPassword`) + одноразовая миграция со стиранием plaintext-копии |
| 2.2 | Расхождение SECURITY.md с реальностью | ✅ | Переписаны `SECURITY.md`, `README.md`, `docs/privacy.html`, `docs/index.html`; добавлен «Приватный режим» (отключение истории) |
| 2.3 | Скрытое скачивание моделей на старте | ✅ | Автозагрузка только при выбранном провайдере Local Whisper |
| 3.1 | Холодный старт AVAudioEngine | ✅ | Standby-движок как явная опция «Быстрый запуск микрофона» (по умолчанию выкл., т.к. может держать индикатор микрофона macOS) |
| 3.2 | Некорректный `vDSP_fft_zrip` и аллокации | ✅ | Упаковка через `vDSP_ctoz`, предвыделенные буферы, исправлена нормализация; покрыто тестами на чистых тонах |
| 3.3 | Утечка CFString в CoreAudio | ✅ | `Unmanaged<CFString>` + `takeRetainedValue()`; предупреждение компилятора устранено |
| 4.1 | Неполная локализация | ✅ | 219 ключей, 100 % покрытие в en/ru/es, дубликатов нет |
| 4.2 | Dynamic Island на нескольких дисплеях | ✅ | Позиционирование по экрану под курсором с фолбэком на ключевое окно |
| 5.1 | Рассинхрон `project.yml` | ⚠️ | **Претензия аудита неверна**: `sources: path: Lyra` — это glob по директории, файлы не могут «отсутствовать». Реальные пробелы (генерация иконок, зависимости тест-таргета, цель `make xcodeproj`) закрыты |
| 5.2 | Нет мок-тестов сетевого слоя | ✅ | Suite на `URLProtocol`: маршрутизация, заголовки, изоляция ключей, 401/404/429/500, битый JSON, обрыв связи, таймаут, Smart Edit |
| §4 | Live Dictation молча отключает облако | ✅ | Явное предупреждение в настройках, когда режим перекрывает включённые облачные функции |

Тесты: **90 passed, 0 failed** (было 47). Сборка: **0 warnings**.

---

## Резюме аудита (Executive Summary)

Проект проделал колоссальный путь от простой утилиты диктовки вокруг локального `whisper.cpp` до многофункционального гибридного ассистента с интеграцией OpenRouter/Gemini 3.5 Flash Lite, умным редактированием выделенного текста (Smart Voice Editing) и плавающим Dynamic Island HUD в стиле Apple Intelligence.

Однако в процессе быстрого добавления облачных возможностей и рефакторинга возник ряд **критических архитектурных несостыковок, проблем с безопасностью и ловушек в обработке ввода**, которые не позволяют назвать текущую сборку готовым коммерческим enterprise-продуктом без исправления этих дефектов.

### Сводная оценка качества

| Направление | Оценка | Статус | Главная проблема |
|---|:---:|:---:|---|
| **Архитектура и Concurrency** | 3.5 / 5 | ⚠️ Требует рефакторинга | Жесткий хардкод OpenRouter в LLM-пайплайне ломает другие провайдеры; изоляция Live VAD от облака. |
| **Безопасность и Приватность** | 2.5 / 5 | 🔴 Критично | Хранение API ключей в plaintext `UserDefaults`; 100% расхождение `SECURITY.md` с реальностью. |
| **Обработка ввода (Hotkeys & AX)** | 3.0 / 5 | ⚠️ Риск для UX | Поглощение клавиши Option (`flagsChanged`) ломает системные шорткаты macOS; отсутствие детекции аккордов. |
| **Инжекция текста (Text Injection)** | 4.0 / 5 | 🟢 Хорошо | Универсальный Cmd+V работает стабильно, но есть риск гонки 450мс таймаута восстановления буфера. |
| **Звуковой движок и FFT** | 4.0 / 5 | 🟢 Хорошо | Некорректная распаковка `vDSP_fft_zrip` в `AudioLevelAnalyzer`, холодный старт `AVAudioEngine` на каждое нажатие. |
| **Интерфейс и Локализация** | 4.0 / 5 | 🟡 Удовлетворительно | Сервис локализации внедрен, но в ряде ключевых HUD и Card-элементов строки захардкожены на английском. |
| **Инфраструктура сборки и CI** | 3.0 / 5 | ⚠️ Рассинхрон | `project.yml` (XcodeGen) заброшен и не собирается; тесты в Makefile не мокают сеть. |

---

## 1. Критические дефекты и архитектурные блокеры

### 1.1. Жесткий хардкод OpenRouter в сервисе постобработки и Smart Edit
- **Файл:** [OpenAISpeechService.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/Engine/OpenAISpeechService.swift#L371-L395) (строки 371, 537)
- **Суть проблемы:**
  В методах `postProcessDetailed` и `transformSelectedText` конечный URL захардкожен намертво:
  ```swift
  let endpointURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
  ...
  request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
  ```
  При этом в приложении есть полноценный выбор провайдера: **OpenAI**, **Groq**, **Local Gateway (Ollama/vLLM)**.
  Если пользователь выбирает пресет OpenAI и вводит свой ключ `sk-proj-...` (или Groq `gsk_...`, или локальный Ollama без ключа):
  1. Аудио транскрибируется через указанный провайдер.
  2. Но затем текст отправляется на `openrouter.ai` с ключом от OpenAI/Groq!
  3. Запрос завершается ошибкой `HTTP 401: Invalid API Key`, и постобработка тихо отваливается.
  4. Приватный ключ пользователя стороннего сервиса нелегитимно отправляется на сервер OpenRouter.
- **Решение:** Формировать URL комплишенов динамически на основе `settings.apiBaseURL` (или сделать независимый выбор провайдера для LLM-постобработки).

### 1.2. Ошибочный пресет DeepSeek в секции распознавания речи
- **Файл:** [SpeechProviderProtocol.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/Engine/SpeechProviderProtocol.swift#L38-L45), [ProviderSection.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/UI/ProviderSection.swift#L62-L78)
- **Суть проблемы:**
  Пресет `DeepSeek` добавлен в список `APIPresetProvider` (эндпоинты распознавания речи `/audio/transcriptions`).
  У DeepSeek **нет аудиомоделей и нет эндпоинта STT**. Если пользователь выберет пресет DeepSeek в Настройках диктовки, распознавание гарантированно сломается с `HTTP 404`.
- **Решение:** Перенести DeepSeek исключительно в пресеты моделей текстовой постобработки (`popularPostProcessingPresets`).

### 1.3. Поглощение системного модификатора Option и ложные срабатывания
- **Файл:** [HotkeyMonitor.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/Utilities/HotkeyMonitor.swift#L184-L207)
- **Суть проблемы:**
  В обработчике `handleEvent` при нажатии модификатора возвращается `nil`:
  ```swift
  if type == .flagsChanged && isTargetModifierKey(keyCode: keyCode) {
      handleKeyStateChange(isPressed: isPressed)
      return nil // Событие поглощается!
  }
  ```
  В macOS клавиша `Option` критически важна для навигации (`Option + Left/Right` — перемещение по словам, `Option + Delete` — удаление слова, `Option + Shift + V` — вставка без форматирования, ввод диакритических знаков).
  При текущей реализации:
  1. Нажатие Option блокируется для системы.
  2. `DictationEngine.handleKeyDown()` **мгновенно начинает запись микрофона** и подает звуковой сигнал.
  3. Если пользователь нажал `Option + Left Arrow` (время нажатия ~0.1 с), `DictationEngine.handleKeyUp()` видит `duration < 0.35s` и переходит в режим **Hands-Free**! В итоге запись звука продолжается в фоне, микрофон остается открытым, а пользователь об этом даже не подозревал.
- **Решение:**
  - Не поглощать `flagsChanged` (`return Unmanaged.passRetained(event)`), либо поглощать только если не было сопутствующих нажатий других клавиш.
  - Реализовать детекцию аккордов (chording): если пока нажат Option, нажимается любая другая клавиша, сбрасывать флаг диктовки и немедленно отменять запись.
  - Не запускать Hands-Free при сверхкоротких нажатиях, если были нажаты другие клавиши.

---

## 2. Безопасность, комплаенс и конфиденциальность

### 2.1. Хранение API-ключей в открытом виде (Plaintext UserDefaults)
- **Файл:** [Settings.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/Utilities/Settings.swift#L128-L133)
- **Суть проблемы:**
  Секретный API-ключ сохраняется в стандартный `UserDefaults`:
  `defaults.set(newValue, forKey: Key.apiKey.rawValue)`
  Файл `com.lyra.Lyra.plist` хранится в открытом виде на диске (`~/Library/Preferences/`). Любой непривилегированный скрипт, вредоносное ПО или расширение может прочитать чужой баланс и ключ через команду `defaults read com.lyra.Lyra apiKey`.
- **Решение:** Использовать системный Apple **Keychain Services API** (`kSecClassGenericPassword`). В `UserDefaults` хранить только факт наличия ключа.

### 2.2. Критическое расхождение документации `SECURITY.md` с кодовой базой
- **Файл:** [SECURITY.md](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/SECURITY.md)
- **Суть проблемы:**
  Политика безопасности проекта утверждает:
  - ❌ *"No audio or transcription data leaves the device. Ever."* — **Неправда**: звук и текст отправляются на внешние облачные API (OpenRouter, OpenAI, Google).
  - ❌ *"No logging of transcribed text. Dictated content is never written to disk..."* — **Неправда**: `HistoryStore` сохраняет до 1000 диктовок в незашифрованный JSON-файл `~/Library/Application Support/Lyra/history.json`.
  - ❌ *"No clipboard access."* — **Неправда**: `TextInjector` читает, перезаписывает и восстанавливает `NSPasteboard.general`.
  - ❌ *"No network requests except for user-initiated model downloads..."* — **Неправда**: на старте приложение автоматически опрашивает сетевые каталоги моделей.
- **Решение:** Полностью обновить `SECURITY.md` и политику конфиденциальности, честно отразив гибридную архитектуру. Добавить в настройки режим **Incognito / Private Mode** (отключение сохранения истории).

### 2.3. Скрытое автоматическое скачивание тяжелых моделей на старте
- **Файл:** [ModelManager.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/Engine/ModelManager.swift#L208-L213), [LyraApp.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/App/LyraApp.swift#L100)
- **Суть проблемы:**
  Вызов `ModelManager.shared.ensureDownloadedRecommendedModel(for: AppSettings.shared.selectedLanguage)` при запуске приложения проверяет наличие локальной модели. Если пользователь использует только Cloud API и не качал локальную модель, приложение **молча в фоне начинает скачивать с HuggingFace файл размером от 190 МБ до 1.5 ГБ**. Это расходует трафик (включая платный мобильный хотспот) и место на диске без подтверждения пользователя.
- **Решение:** Скачивать локальные модели только по явному клику пользователя или предлагать выбор в онбординге.

---

## 3. Производительность и звуковая подсистема

### 3.1. Холодный старт `AVAudioEngine` на каждое нажатие
- **Файл:** [AudioCapture.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/Engine/AudioCapture.swift#L63-L82)
- **Суть проблемы:**
  В методе `startRecording()` каждый раз создается новый `AVAudioEngine()`, переинициализируется граф и запускается Hardware Audio Layer:
  ```swift
  let engine = AVAudioEngine()
  AudioDeviceManager.shared.applySelectedDevice(to: engine)
  engine.prepare()
  try engine.start()
  ```
  Это приводит к задержке активации микрофона в **100–250 мс**. Если пользователь начинает говорить одновременно с нажатием клавиши, первое слово или слог «съедаются».
- **Решение:** Держать `AVAudioEngine` постоянно подготовленным (standby/warm state) или глушить вход через mute-ноду/активацию тапа без полного пересоздания движка.

### 3.2. Нарушение математики `vDSP_fft_zrip` и паразитные аллокации
- **Файл:** [AudioLevelAnalyzer.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/Engine/AudioLevelAnalyzer.swift#L148-L169)
- **Суть проблемы:**
  Функция `vDSP_fft_zrip` требует, чтобы входные вещественные сэмплы были предварительно упакованы в четно-нечетную комплексную структуру (`vDSP_ctoz`) размером `N/2`. В текущем коде:
  ```swift
  var real = samples // N = 1024
  var imaginary = [Float](repeating: 0, count: n) // N = 1024
  ```
  Это искажает спектральный анализ FFT. Кроме того, создание 4 динамических массивов `Float` на каждый фрейм в функции `bands()` создает непрерывную нагрузку на аллокатор памяти (хотя в комментариях заявлено "allocation-free").
- **Решение:** Использовать выделенный статический сплит-буфер и функцию `vDSP_ctoz`.

### 3.3. Утечка памяти в CoreAudio Device Manager
- **Файл:** [AudioDeviceManager.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/Utilities/AudioDeviceManager.swift#L115-L121)
- **Суть проблемы:**
  Компилятор выдает предупреждение:
  `forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'`
  CoreAudio API возвращает созданный объект `CFString` с refcount +1. Использование нетипизированного указателя не регистрирует его в Swift ARC, приводя к утечке `CFString` при каждом опросе микрофонов.
- **Решение:** Использовать `Unmanaged<CFString>?` и метод `.takeRetainedValue()`.

---

## 4. Пользовательский опыт (UI/UX) и локализация

### 4.1. Неполная локализация интерфейса
- **Файл:** [DynamicIslandHUDView.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/UI/DynamicIslandHUDView.swift), [ProviderSection.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/UI/ProviderSection.swift)
- **Суть проблемы:**
  Несмотря на наличие качественных файлов `Localizable.strings` (русский, испанский, английский):
  - В Dynamic Island HUD строки `"Say instruction..."`, `"Recording"`, `"Stop"`, `"Smart Edit"`, `"Inserting text..."`, `"Transcribing..."`, `"Local Fallback..."`, `"Enable Accessibility"` не вызывают `L10n.tr()` и всегда отображаются на английском.
  - В `ProviderSection` и `SpeechSection` метки полей `"Base URL"`, `"API Key"`, `"Model Identifier"` также захардкожены.
- **Решение:** Обернуть все пользовательские строки в `L10n.tr(...)` и проверить полноту словаря `ru.lproj`.

### 4.2. Непредсказуемое поведение Dynamic Island на нескольких дисплеях
- **Файл:** [RecordingHUDWindow.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Lyra/UI/RecordingHUDWindow.swift#L52-L61)
- **Суть проблемы:**
  Привязка панели идет только к `NSScreen.main`. Если пользователь работает на внешнем 4K-мониторе, а главным экраном в macOS назначен экран закрытого или бокового MacBook, Dynamic Island появляется на другом экране вдали от фокуса внимания.
- **Решение:** Отображать HUD на экране, где в данный момент находится курсор мыши (`NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }`) или окно с активным текстовым полем.

---

## 5. Инженерная культура и качество кода (Code Quality & Build)

### 5.1. Рассинхронизация `project.yml` (XcodeGen) и `Makefile`
- **Файлы:** [project.yml](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/project.yml), [Makefile](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/Makefile)
- **Суть проблемы:**
  Проект собирается через рукописный `Makefile` прямым вызовом `xcrun swiftc`. При этом конфигурационный файл `project.yml` не обновлялся: в нем отсутствуют 8 новых Swift-файлов архитектуры. Попытка сгенерировать проект через `xcodegen` приводит к неработающему проекту в Xcode.
- **Решение:** Синхронизировать `project.yml` со списком файлов в `Makefile`.

### 5.2. Отсутствие мок-тестирования сетевого слоя
- **Файл:** [run-unit-tests.swift](file:///Users/hamidkazimov/Downloads/WhisperDictation-main/scripts/run-unit-tests.swift)
- **Суть проблемы:**
  Все 47 тестов проверяют только локальные алгоритмы (WAV энкодер, регулярные выражения, UserDefaults). В сюите тестов нет ни одного теста с `URLProtocol` для проверки:
  - Корректности парсинга ответов OpenRouter / OpenAI.
  - Реакции на HTTP 401, 404, 429 (Rate Limit), 500.
  - Срабатывания таймаута и корректного отката на сырой черновик Whisper.
- **Решение:** Внедрить мок-сессию на базе кастомного `URLProtocol` в unit-тесты.

---

## 6. Приоритетный план исправления (Actionable Roadmap)

### Фаза 1: Устранение критических дефектов и стабильность (P0 — Срочно)
1. **Динамический роутинг LLM в `OpenAISpeechService`**: Убрать захардкоженный `openrouter.ai` для комплишенов; использовать endpoint провайдера либо разделить настройки STT-провайдера и LLM-провайдера.
2. **Исправление перехвата Option в `HotkeyMonitor`**: Не поглощать `flagsChanged` вслепую; внедрить распознавание аккордов (отменять диктовку, если нажата вторая клавиша).
3. **Безопасное хранение ключей в Keychain**: Заменить открытый `UserDefaults` на Keychain Services для API-ключа.
4. **Устранение CoreAudio warning/leak**: Исправить `AudioDeviceManager.swift` с `Unmanaged<CFString>`.

### Фаза 2: Качество UX и доработка функций (P1 — Важно)
1. **Интеллектуальное автоскачивание моделей**: Отключить скрытую загрузку тяжелых моделей при старте приложения; запрашивать согласие пользователя.
2. **Полная локализация HUD и меню**: Перевести оставшиеся строки Dynamic Island HUD на русский и испанский языки.
3. **Мультимониторное позиционирование**: Привязать позицию Dynamic Island к экрану с активным окном / курсором.
4. **Актуализация `SECURITY.md`**: Привести политику безопасности в полное соответствие с реальностью.

### Фаза 3: Архитектурный лоск (P2 — Улучшение)
1. **Синхронизация `project.yml`**: Обеспечить чистую сборку и запуск тестов в Xcode через XcodeGen.
2. **Оптимизация `AudioLevelAnalyzer`**: Исправить упаковку FFT через `vDSP_ctoz` и убрать аллокации из горячего пути.
3. **Standby-режим `AVAudioEngine`**: Устранить задержку старта записи микрофона.
