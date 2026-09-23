import Foundation

/**
 Runs the datasets through every model, language, prompt variant and guardrail
 setting asked for, and prints what came back.

 Cases run one at a time and models are loaded one at a time. Both are on
 purpose: a several-gigabyte model held alongside another distorts the latency
 it is being measured on, and two of them at once does not fit.
 */
@main
struct EvalMain {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        let datasetDirectory = try locateDatasets(options)

        var datasets: [CorrectionLanguage: Dataset] = [:]
        for language in options.languages {
            datasets[language] = try DatasetLoader.load(language, from: datasetDirectory)
        }

        print("datasets: \(datasetDirectory.path)")
        for language in options.languages {
            guard let dataset = datasets[language] else { continue }
            let negatives = dataset.cases.count(where: \.isNegative)
            print("  \(language.code): \(dataset.cases.count) cases, \(negatives) already correct")
        }
        print("")

        var summaries: [Summary] = []
        var perConfiguration: [String: [Scoring.CaseResult]] = [:]
        var unavailable: [String] = []

        for id in options.models {
            guard let backend = Backends.named(id) else { continue }

            print("loading \(backend.displayName)")
            let loadStarted = ContinuousClock.now

            do {
                try await backend.prepare()
            } catch {
                print("  unavailable: \(error)\n")
                unavailable.append("\(backend.displayName): \(error)")
                continue
            }

            print(String(format: "  ready in %.1fs\n", seconds(since: loadStarted)))

            /** Always with the shipping wording first, as the control. */
            var variants = options.variants
            if let file = options.variantsFile {
                variants = try [PromptVariant.shipping] + PromptVariant.loaded(from: file)
            }

            for variant in variants {
              for masks in options.masking {
                for tells in options.tellsModel {
                for language in options.languages {
                    guard let dataset = datasets[language] else { continue }

                    let cases = options.limit.map { Array(dataset.cases.prefix($0)) } ?? dataset.cases
                    let pipeline = EvalPipeline(
                        backend: backend,
                        variant: variant,
                        masks: masks,
                        appliesDeadline: options.appliesDeadline,
                        disabledRules: options.disabledRules,
                        tellsModel: tells
                    )

                    let maskLabel = masks ? "masked" : "unmasked"
                    /** Only when something is switched off, so an ordinary run reads as it always did. */
                    let armLabel = options.disabledRules.isEmpty ? "" : (tells ? "/told" : "/silent")
                    print("running \(backend.id) \(language.code) \(variant.id)\(armLabel) \(maskLabel) (\(cases.count) cases)")

                    /** One pass over the model, scored twice, once for each guardrail setting. */
                    var scored: [Bool: [Scoring.CaseResult]] = [:]
                    for testCase in cases {
                        let started = ContinuousClock.now
                        let pass = await pipeline.correct(testCase.input)
                        let elapsed = seconds(since: started)

                        for guardrail in options.guardrails {
                            scored[guardrail, default: []].append(
                                Scoring.score(testCase, output: pass[guardrail], seconds: elapsed)
                            )
                        }
                    }

                    for guardrail in options.guardrails {
                        guard let results = scored[guardrail] else { continue }

                        let summary = Summary(
                            model: backend.id,
                            language: language.code,
                            variant: (masks ? variant.id : variant.id + "/raw") + armLabel,
                            guardrail: guardrail,
                            results: results
                        )
                        summaries.append(summary)
                        perConfiguration["\(backend.id) \(language.code) \(variant.id)\(armLabel) \(maskLabel) guardrail=\(guardrail ? "on" : "off")"] = results

                        print("  guardrail \(guardrail ? "on " : "off"): "
                            + "exact \(Report.percent(summary.exactMatchRate)), "
                            + "recall \(Report.percent(summary.fixRecall)), "
                            + "\(summary.falsePositiveTotal) unrequested changes, "
                            + "\(summary.negativesUntouched)/\(summary.negatives) correct texts left alone")

                        if options.showsFailures, guardrail == options.guardrails[0] {
                            print(Report.failures(results))
                        }
                    }
                }
                }
              }
            }

            await backend.release()
        }

        print("\n\(Report.table(summaries))\n")

        if !unavailable.isEmpty {
            print("not measured:")
            for note in unavailable { print("  \(note)") }
            print("")
        }

        let output = options.output ?? datasetDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Results/run-\(stamp()).json")

        try Report.write(
            Report.Run(startedAt: Date(), summaries: summaries, results: perConfiguration),
            to: output
        )
        print("wrote \(output.path)")
    }

    private static func locateDatasets(_ options: Options) throws -> URL {
        if let directory = options.datasets { return directory }

        let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let found = DatasetLoader.locateDirectory(startingAt: here) { return found }

        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        if let found = DatasetLoader.locateDirectory(startingAt: executable) { return found }

        throw EvalError.missingDatasets
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
