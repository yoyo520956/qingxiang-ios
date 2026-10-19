import AVFoundation
import AVFAudio
import SwiftUI
import UIKit

final class PlayerLayerHostView: UIView {
    var playerLayer: AVPlayerLayer?

    func attach(_ player: AVPlayer, gravity: AVLayerVideoGravity) {
        let l = AVPlayerLayer()
        l.player = player
        l.videoGravity = gravity
        l.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        layer.addSublayer(l)
        playerLayer = l
        setNeedsLayout()
    }

    func setGravity(_ g: AVLayerVideoGravity) {
        playerLayer?.videoGravity = g
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity

    func makeUIView(context: Context) -> PlayerLayerHostView {
        let v = PlayerLayerHostView()
        v.backgroundColor = .black
        v.attach(player, gravity: gravity)
        return v
    }

    func updateUIView(_ uiView: PlayerLayerHostView, context: Context) {
        uiView.setGravity(gravity)
    }
}

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
