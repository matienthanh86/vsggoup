// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import AVFoundation
import AudioToolbox

public final class AgentNotiAudioPlayer: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    public static let shared = AgentNotiAudioPlayer()

    private var ringtonePlayer: AVAudioPlayer?
    private var endCallPlayer: AVAudioPlayer?
    private var vibrationTimer: Timer?

    private override init() {
        super.init()
    }

    public func startCallRingtone() {
        stopCallRingtone()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        if let ringtoneUrl = Bundle.main.url(forResource: "universfield_incoming_phone_call_152490", withExtension: "mp3") {
            do {
                ringtonePlayer = try AVAudioPlayer(contentsOf: ringtoneUrl)
                ringtonePlayer?.numberOfLoops = -1
                ringtonePlayer?.prepareToPlay()
                ringtonePlayer?.play()
            } catch {}
        }

        AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        DispatchQueue.main.async { [weak self] in
            self?.vibrationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
            }
        }
    }

    public func stopCallRingtone() {
        ringtonePlayer?.stop()
        ringtonePlayer = nil

        vibrationTimer?.invalidate()
        vibrationTimer = nil
    }

    public func playEndCallSound() {
        stopCallRingtone()

        if let endCallUrl = Bundle.main.url(forResource: "end_call_02", withExtension: "mp3") {
            do {
                endCallPlayer = try AVAudioPlayer(contentsOf: endCallUrl)
                endCallPlayer?.numberOfLoops = 0
                endCallPlayer?.prepareToPlay()
                endCallPlayer?.play()
            } catch {}
        }
    }
}
