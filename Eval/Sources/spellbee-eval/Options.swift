import Foundation

/**
 What to run.

 Every filter defaults to everything, so a bare `swift run` sweeps every model,
 language, variant and both guardrail settings. Nothing here names a language or
 a model: the values are matched against `CorrectionLanguage`, `LocalModel` and
 `PromptVariant`, so the flags grow when those do.
 */
struct Options: Sendable {
    var languages: [CorrectionLanguage] = CorrectionLanguage.allCases
    var models: [String] = Backends.all().map(\.id)
    var variants: [PromptVariant] = PromptVariant.all
    var guardrails: [Bool] = [true, false]

    /**
     Whether protected spans are hidden from the model.

     A sweep of its own rather than a fixed choice, because the question it
     answers is a paired one: the same cases, the same replies scored both
     ways, is a link in the sentence costing corrections elsewhere in it.
     */
    var masking: [Bool] = [true]
    var limit: Int?
    var output: URL?
    var datasets: URL?

    /**
     Candidate wordings to sweep alongside the built-in ones.

     The shipping wording is always added back in `EvalMain`, since a sweep
     with no control in it cannot say whether anything improved.
     */
    var variantsFile: URL?
    var showsFailures = false

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var languages: [CorrectionLanguage] = []
        var models: [String] = []
        var variants: [PromptVariant] = []

        var index = 0
        func next(_ flag: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw EvalError.unknownArgument("\(flag) needs a value") }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--language", "-l":
                let value = try next(argument)
                guard let language = CorrectionLanguage.matching(value) else {
                    throw EvalError.unknownArgument("--language \(value)")
                }
                languages.append(language)

            case "--model", "-m":
                let value = try next(argument)
                guard Backends.named(value) != nil else {
                    throw EvalError.unknownArgument("--model \(value)")
                }
                models.append(value)

            case "--variant", "-v":
                let value = try next(argument)
                guard let variant = PromptVariant.named(value) else {
                    throw EvalError.unknownArgument("--variant \(value)")
                }
                variants.append(variant)

            case "--guardrail", "-g":
                let value = try next(argument)
                switch value {
                case "on": options.guardrails = [true]
                case "off": options.guardrails = [false]
                case "both": options.guardrails = [true, false]
                default: throw EvalError.unknownArgument("--guardrail \(value)")
                }

            case "--masking":
                let value = try next(argument)
                switch value {
                case "on": options.masking = [true]
                case "off": options.masking = [false]
                case "both": options.masking = [true, false]
                default: throw EvalError.unknownArgument("--masking \(value)")
                }

            case "--limit", "-n":
                options.limit = Int(try next(argument))

            case "--out", "-o":
                options.output = URL(fileURLWithPath: try next(argument))

            case "--variants-file":
                options.variantsFile = URL(fileURLWithPath: try next(argument))

            case "--datasets":
                options.datasets = URL(fileURLWithPath: try next(argument))

            case "--failures", "-f":
                options.showsFailures = true

            case "--help", "-h":
                print(help)
                exit(0)

            default:
                throw EvalError.unknownArgument(argument)
            }

            index += 1
        }

        if !languages.isEmpty { options.languages = languages }
        if !models.isEmpty { options.models = models }
        if !variants.isEmpty { options.variants = variants }

        return options
    }

    static var help: String {
        """
        spellbee-eval: measures the correction prompt against the datasets.

        The downloaded models need MLX's Metal kernels, which SwiftPM does not
        build. Run ./build-metallib.sh once after the first swift build.

        Everything is swept by default. Each flag may be repeated to widen a filter.

          --language, -l   \(CorrectionLanguage.allCases.map(\.code).joined(separator: " | "))
          --model, -m      \(Backends.all().map(\.id).joined(separator: " | "))
          --variant, -v    \(PromptVariant.all.map(\.id).joined(separator: " | "))
          --guardrail, -g  on | off | both        (default both)
          --limit, -n      first N cases per language
          --out, -o        where to write the per-case JSON
          --datasets       directory holding the dataset files
          --failures, -f   print every case that did not match exactly
        """
    }
}

extension CorrectionLanguage {
    /** Two-letter code, which is also the dataset file's name. */
    var code: String { nlLanguage.rawValue }

    static func matching(_ value: String) -> CorrectionLanguage? {
        allCases.first { $0.code == value || $0.rawValue == value }
    }
}
