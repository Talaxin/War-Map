import AVFoundation
import Foundation

@MainActor
final class VoiceGuidanceService {
    private let synthesizer = AVSpeechSynthesizer()
    private weak var settings: AppSettings?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func speak(_ text: String) {
        guard let settings, settings.voiceGuidanceEnabled, !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        if let voiceID = settings.voiceOptions.first(where: { $0.id == settings.selectedVoiceID })?.identifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceID) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
