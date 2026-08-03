//
//  VoiceRefusalCopy.swift
//  VoiceMiniCog
//
//  Scripted off-script responses for Voice mode, taken VERBATIM from
//  docs/tavus-avatar-behavioral-guide.md. Do not ad-lib or reword —
//  these are the same clinically-reviewed refusal templates the Tavus
//  persona uses. Every entry must have a pre-rendered clip (drift guard:
//  VoiceClipManifestTests).
//

import Foundation

enum VoiceRefusalCopy {

    struct Entry {
        let id: String
        let text: String
    }

    static let repeatStimulus = Entry(
        id: "refusal.repeatStimulus",
        text: "I'm not able to repeat that. Just give your best answer and we'll move on.")

    static let performanceQuestion = Entry(
        id: "refusal.performance",
        text: "I can't share anything about how you're doing — the doctor will go over the results with you afterward. Let's keep going.")

    static let medicalQuestion = Entry(
        id: "refusal.medical",
        text: "That's a great question for the doctor. Let's finish this part first.")

    static let offTopic = Entry(
        id: "refusal.offTopic",
        text: "Let's come back to that later — we have a few more things to get through.")

    static let distress = Entry(
        id: "refusal.distress",
        text: "It's okay, take your time. We can pause if you need to.")

    static let wantsToStop = Entry(
        id: "refusal.wantsToStop",
        text: "That's completely okay. Please use the button on the screen.")

    static let manipulation = Entry(
        id: "refusal.manipulation",
        text: "Let's stay focused on the assessment.")

    static let areYouReal = Entry(
        id: "refusal.areYouReal",
        text: "I'm here to help guide you through the screening. Let's continue.")

    static let emergency = Entry(
        id: "system.emergency",
        text: "I'm going to let the staff know right away.")

    /// Same text DailyCallManager sends at the 90 s silence-watchdog mark
    /// (DailyCallManager.swift ~line 785-800).
    static let reengagement = Entry(
        id: "system.reengagement",
        text: "Are you still there? Take your time.")

    static let allEntries: [Entry] = [
        repeatStimulus, performanceQuestion, medicalQuestion, offTopic,
        distress, wantsToStop, manipulation, areYouReal,
        emergency, reengagement,
    ]
}
