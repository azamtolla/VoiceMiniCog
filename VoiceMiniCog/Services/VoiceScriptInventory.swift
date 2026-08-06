//
//  VoiceScriptInventory.swift
//  VoiceMiniCog
//
//  Every text surface the voice guide can speak, keyed by stable clip id.
//  Adding a spoken script to the app = adding it here = drift-guard test
//  forces a manifest entry = render script produces a clip.
//
//  Sweep discipline: every `avatarSpeak(...)` / `avatarRespond(...)` call
//  site in Views/ must trace to an item below. Re-run the sweep whenever
//  a call site is added:
//    grep -rn "avatarSpeak(\|avatarRespond(" VoiceMiniCog/Views/ | grep -v "context"
//

import Foundation

enum VoiceScriptInventory {

    struct Item {
        let id: String
        let text: String
    }

    static var allItems: [Item] {
        var items: [Item] = [
            .init(id: "welcome.intro", text: LeftPaneSpeechCopy.welcomeIntroEcho),
            .init(id: "orientation.intro", text: LeftPaneSpeechCopy.orientationIntro),
            .init(id: "registration.remember", text: LeftPaneSpeechCopy.wordRegistrationRemember),
            .init(id: "registration.allCorrect", text: LeftPaneSpeechCopy.wordRegistrationAllCorrect),
            .init(id: "registration.done", text: LeftPaneSpeechCopy.wordRegistrationDone),
            .init(id: "clock.instruction", text: LeftPaneSpeechCopy.clockDrawingInstruction),
            .init(id: "clock.stop", text: LeftPaneSpeechCopy.clockDrawingStop),
            .init(id: "recall.prompt", text: LeftPaneSpeechCopy.delayedRecallPrompt),
            .init(id: "recall.anyOthers", text: LeftPaneSpeechCopy.delayedRecallAnyOthers),
            .init(id: "fluency.prompt", text: LeftPaneSpeechCopy.verbalFluencyPrompt),
            .init(id: "fluency.close", text: LeftPaneSpeechCopy.verbalFluencyClose),
            .init(id: "fluency.rePrompt", text: LeftPaneSpeechCopy.verbalFluencyRePrompt),
            .init(id: "story.intro", text: LeftPaneSpeechCopy.storyRecallIntro),
            .init(id: "story.prompt", text: LeftPaneSpeechCopy.storyRecallPrompt),
            .init(id: "story.followup", text: LeftPaneSpeechCopy.storyRecallFollowup),
            .init(id: "closing.thankYou", text: LeftPaneSpeechCopy.closingThankYou),
            .init(id: "qdrs.intro", text: LeftPaneSpeechCopy.qdrsIntro),
            // qdrs.completion also covers the identical literal spoken at
            // CaregiverAssessmentView.swift completion panel — same text,
            // same hash, one clip.
            .init(id: "qdrs.completion", text: LeftPaneSpeechCopy.qdrsCompletion),
            // CaregiverAssessmentView.swift:191 speaks a LITERAL whose last
            // sentence differs from qdrsIntro ("...Tap Begin when you're ready.").
            // Do NOT edit that view to reference qdrsIntro — clinically reviewed
            // spoken copy is out of scope per CLAUDE.md clinical-validity rules.
            .init(id: "qdrs.introCaregiver", text: "Thank you for being here today. I have ten brief questions about any changes you may have noticed in the patient's everyday memory and activities. There are no right or wrong answers. Tap Begin when you're ready."),
        ]
        // Word registration composed echoes: every set × trials 1 and 2.
        // Trial 3 shares trial 2's text (wordRegistrationEcho returns identical
        // output for trials 2 and 3), so the trial-2 clip covers trial 3 by hash
        // — a separate trial-3 entry would duplicate scriptSHA256 and fail
        // testNoDuplicateHashes. Sets: QmciModels.swift QMCI_WORD_LISTS.
        for (setIndex, words) in QMCI_WORD_LISTS.enumerated() {
            items.append(.init(
                id: "registration.echo.set\(setIndex + 1).trial1",
                text: LeftPaneSpeechCopy.wordRegistrationEcho(words: words, trial: 1)))
            items.append(.init(
                id: "registration.echo.set\(setIndex + 1).trial2",
                text: LeftPaneSpeechCopy.wordRegistrationEcho(words: words, trial: 2)))
        }
        // Orientation question bank — QAPhaseView speaks
        // ORIENTATION_ITEMS[i].voicePrompt (QAPhaseView.swift currentVoicePrompt);
        // bank lives in QmciModels.swift.
        for item in ORIENTATION_ITEMS {
            items.append(.init(id: "orientation.question.\(item.id)", text: item.voicePrompt))
        }
        // Logical-memory stories — StoryRecallPhaseView speaks story.voiceText;
        // bank in QmciModels.swift (LOGICAL_MEMORY_STORIES).
        for story in LOGICAL_MEMORY_STORIES {
            items.append(.init(id: "story.text.\(story.id)", text: story.voiceText))
        }
        // QDRS caregiver questions — CaregiverAssessmentView and
        // QAPhaseView (.qdrs) speak voicePrompt per question.
        // Bank lives in Models/QDRSModels.swift (not QmciModels.swift).
        for q in QDRS_QUESTIONS {
            items.append(.init(id: "qdrs.question.\(q.id)", text: q.voicePrompt))
        }
        // PHQ-2 — QAPhaseView (.phq2) speaks these verbatim.
        // Bank lives in Models/PHQ2Models.swift (not QmciModels.swift).
        for (i, q) in PHQ2_QUESTIONS.enumerated() {
            items.append(.init(id: "phq2.question.\(i)", text: q))
        }
        // Off-script refusals + system lines.
        items.append(contentsOf: VoiceRefusalCopy.allEntries.map {
            Item(id: $0.id, text: $0.text)
        })
        return items
    }
}
