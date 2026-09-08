import Foundation

/// Supported dictation languages and their Whisper model catalogs.
enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"
    case spanish = "es"
    case turkish = "tr"
    case azerbaijani = "az"

    var id: String { rawValue }

    /// Display name in the language itself.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        case .spanish: return "Español"
        case .turkish: return "Türkçe"
        case .azerbaijani: return "Azərbaycanca"
        }
    }

    /// Two-letter ISO code passed to whisper.cpp.
    var whisperCode: String { rawValue }

    /// Whether technical terms and acronyms post-processing should run.
    var usesTechTermsPostProcessing: Bool { true }

    /// Default prompt used to bias Whisper and API models toward relevant vocabulary.
    var defaultPrompt: String {
        switch self {
        case .english:
            return AppSettings.defaultVocabularyPrompt
        case .russian:
            return LanguageCatalog.defaultRussianVocabularyPrompt
        case .spanish:
            return LanguageCatalog.defaultSpanishVocabularyPrompt
        case .turkish:
            return LanguageCatalog.defaultTurkishVocabularyPrompt
        case .azerbaijani:
            return LanguageCatalog.defaultAzerbaijaniVocabularyPrompt
        }
    }

    static func from(code: String) -> Language {
        Language(rawValue: code.lowercased()) ?? .english
    }
}

extension LanguageCatalog {
    /// Comprehensive Russian vocabulary prompt (Priority #1) covering modern IT, engineering, business and daily terms.
    static let defaultRussianVocabularyPrompt = """
        Обсуждение разработки программного обеспечения, архитектуры и системного дизайна. \
        Термины: бэкенд, фронтенд, пулреквест, мерж, коммит, репозиторий, ветка, деплой, релиз, \
        стейджинг, прод, продакшн, пайплайн, сборка, баг, фича, багфикс, хотфикс, рефакторинг, \
        код-ревью, спринт, таска, бэклог, архитектура, микросервисы, монолит, контейнеризация, \
        кубернетес, кластер, неймспейс, докер, образ, база данных, таблица, запрос, транзакция, \
        индекс, миграция, шардинг, репликация, кэш, кэширование, сессия, куки, токен, авторизация, \
        аутентификация, права доступа, хэш, шифрование, эндпоинт, роут, контроллер, сервис, \
        интерфейс, абстракция, полиморфизм, наследование, инкапсуляция, паттерн, синглтон, \
        асинхронный, корутины, потоки, мьютекс, гонка данных, дедлок, очередь, брокер сообщений, \
        событийная модель, вебхук, сокеты, стриминг, протокол, схема, валидация, сериализация, \
        десериализация, логирование, трассировка, метрики, мониторинг, алерт, инцидент, таймаут, \
        ретрай, фреймворк, библиотека, зависимость, пакетный менеджер, линтер, форматер, \
        юнит-тесты, интеграционные тесты, моки, стабы, покрытие, документация, спецификация. \
        Технологии: Swift, SwiftUI, Python, JavaScript, TypeScript, Go, Rust, Java, Kotlin, C++, \
        C#, SQL, PostgreSQL, MySQL, SQLite, MongoDB, Redis, Kafka, RabbitMQ, Docker, Kubernetes, \
        Git, GitHub, GitLab, REST, GraphQL, gRPC, JSON, YAML, HTML, CSS, React, Next.js, Vue, \
        FastAPI, Django, Flask, Spring Boot, Linux, macOS, iOS, Android, AWS, GCP, Azure, \
        OpenAI, Claude, ChatGPT, LLM, API, SDK, CLI, IDE, CI/CD, DevOps, HTTP, HTTPS, TCP, UDP, \
        DNS, SSL, TLS, SSH, OAuth, JWT, CORS, CSRF, WebSocket, CPU, GPU, RAM, SSD, UI, UX. \
        Форматирование: естественная пунктуация, запятые, точки, тире, кавычки и заглавные буквы в начале предложений.
        """

    /// Turkish software and daily vocabulary prompt.
    static let defaultTurkishVocabularyPrompt = """
        Yazılım geliştirme, teknoloji ve mühendislik tartışması. Türkçe doğal noktalama işaretleri, virgüller ve noktalar. \
        Terimler: yazılım, mimari, veritabanı, sunucu, istemci, ön yüz, arka yüz, istek, \
        yanıt, oturum, yetkilendirme, kimlik doğrulama, API, arayüz, işlev, metot, sınıf, nesne, \
        bellek, önbellek, işlem, kütüphane, dağıtım, sürüm, kod incelemesi, hata ayıklama, \
        test, Swift, Python, JavaScript, TypeScript, Go, Docker, Kubernetes, Git, GitHub.
        """

    /// Spanish software and daily vocabulary prompt.
    static let defaultSpanishVocabularyPrompt = """
        Desarrollo de software, tecnología, ingeniería y diseño de sistemas. Puntuación natural en español, comas, puntos y acentos. \
        Términos: backend, frontend, pull request, merge, commit, repositorio, rama, despliegue, release, \
        staging, producción, pipeline, build, bug, función, refactorización, revisión de código, sprint, \
        arquitectura, microservicios, contenedor, docker, kubernetes, base de datos, consulta, transacción, \
        índice, migración, caché, sesión, token, autenticación, autorización, endpoint, controlador, servicio, \
        asíncrono, hilos, cola, webhook, sockets, streaming, protocolo, validación, métricas, monitoreo, alerta, \
        Swift, Python, JavaScript, TypeScript, Go, Rust, Java, Kotlin, SQL, PostgreSQL, Git, GitHub, API, REST, Linux, macOS.
        """

    /// Azerbaijani software and daily vocabulary prompt.
    static let defaultAzerbaijaniVocabularyPrompt = """
        Proqram təminatı hazırlanması, texnologiya və mühəndislik müzakirəsi. Azərbaycan dili orfoqrafiyası və durğu işarələri. \
        Terminlər: proqramlaşdırma, arxitektura, verilənlər bazası, server, müştəri, sorğu, \
        cavab, autentifikasiya, avtorizasiya, interfeys, metod, funksiya, sinif, obyekt, \
        yaddaş, keş, sazlama, testləşdirmə, buraxılış, Swift, Python, JavaScript, Docker, Git.
        """
}

/// Groups Whisper models by the language they support.
enum LanguageCatalog {
    /// Models recommended for English dictation (English-only models).
    static let englishModels: [ModelManager.ModelInfo] = [
        ModelManager.ModelInfo.baseEnQ5,
        ModelManager.ModelInfo.smallEnQ5,
        ModelManager.ModelInfo.mediumEnQ5,
        ModelManager.ModelInfo.baseEn,
        ModelManager.ModelInfo.smallEn,
        ModelManager.ModelInfo.mediumEn
    ]

    /// Multilingual models usable for Russian, Spanish, Turkish, Azerbaijani, and English.
    static let multilingualModels: [ModelManager.ModelInfo] = [
        ModelManager.ModelInfo.baseMultiQ5,
        ModelManager.ModelInfo.smallMultiQ5,
        ModelManager.ModelInfo.mediumMultiQ5,
        ModelManager.ModelInfo.baseMulti,
        ModelManager.ModelInfo.smallMulti,
        ModelManager.ModelInfo.mediumMulti,
        ModelManager.ModelInfo.largeV3TurboQ5
    ]

    static func models(for language: Language) -> [ModelManager.ModelInfo] {
        switch language {
        case .english:
            return englishModels
        case .russian, .spanish, .turkish, .azerbaijani:
            return multilingualModels
        }
    }

    static func recommendedModels(for language: Language) -> [ModelManager.ModelInfo] {
        switch language {
        case .english:
            return [ModelManager.ModelInfo.baseEnQ5, ModelManager.ModelInfo.smallEnQ5, ModelManager.ModelInfo.mediumEnQ5]
        case .russian, .spanish, .turkish, .azerbaijani:
            return [ModelManager.ModelInfo.baseMultiQ5, ModelManager.ModelInfo.smallMultiQ5, ModelManager.ModelInfo.mediumMultiQ5]
        }
    }

    /// Suggested default model for a new user of the given language.
    /// For multilingual languages on Intel Macs we default to the fastest
    /// quantized model (base) so dictation feels responsive; the user can
    /// upgrade to small/medium in Settings for better accuracy.
    static func defaultModel(for language: Language) -> ModelManager.ModelInfo {
        switch language {
        case .english:
            return ModelManager.ModelInfo.baseEnQ5
        case .russian, .spanish, .turkish, .azerbaijani:
            return ModelManager.ModelInfo.baseMultiQ5
        }
    }
}
