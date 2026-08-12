import Foundation

/**
 Runs the same text through both backends and writes the results to the log.

 Comparing them by hand means retyping the same sentence in a real text field
 twice and remembering what happened, which is both tedious and unreliable. This
 puts the two answers next to each other for identical input.

 What it prints is the text as it would actually be applied, after the guardrail
 has had its say, because that is the thing worth comparing. A backend that
 proposes better corrections but has more of them refused is not better.
 */
enum BackendComparison {
    static let samples = [
        "hi tim,i hope your well. i wanted to ask if the meeting is still at 5",
        "can you send me the file when your done please",
        "wir treffen uns morgen im buero, ich bringe die unterlagen mit",
        "ich glaube das wir das morgen schaffen wenn alle da sind",
        "koenntest du das bitte nochmal pruefen bevor wir es abschicken",
    ]

    /**
     Note that this logs sample text, which is safe only because the samples are
     written here rather than taken from anything the user typed.
     */
    static func run(apple: any Corrector, local: any Corrector, localName: String) async {
        Log.app.info("--- backend comparison ---")

        for sample in samples {
            Log.app.info("input:  \(sample, privacy: .public)")

            let appleResult = (try? await apple.correct(sample)) ?? "<failed>"
            Log.app.info("apple:  \(appleResult, privacy: .public)")

            let localResult = (try? await local.correct(sample)) ?? "<failed>"
            Log.app.info("\(localName, privacy: .public): \(localResult, privacy: .public)")
        }

        Log.app.info("--- end comparison ---")
    }
}
