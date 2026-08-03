//
//  DailyVideoView.swift
//  VoiceMiniCog
//
//  UIViewRepresentable wrapping Daily's native VideoView.
//  Renders the Tavus replica's video track directly — no WKWebView.
//

import SwiftUI
import Daily

struct DailyVideoView: UIViewRepresentable {
    let track: VideoTrack?

    func makeUIView(context: Context) -> VideoView {
        let view = VideoView()
        view.videoScaleMode = .fill
        // Clear background so the full-screen phase tint shows through any
        // letterbox / transparent region around the video.
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: VideoView, context: Context) {
        view.track = track
    }
}
