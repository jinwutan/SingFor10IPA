//
//  VolumeGuard.swift
//  SingFor10
//
//  音量守卫：通过 KVO 监听系统输出音量，一旦被调低就自动拉回最大值。
//  使用 MPVolumeView 内建的 slider 以合法方式设置系统音量。
//

import AVFoundation
import MediaPlayer

final class VolumeGuard {

    static let shared = VolumeGuard()

    private var observation: NSKeyValueObservation?
    private var volumeSlider: UISlider?
    private var isEnabled = false

    private init() {}

    /// 启动守卫。volumeView 需由调用方加入视图层级（可隐藏/置于屏幕外）。
    func start(volumeView: MPVolumeView) {
        guard !isEnabled else { return }
        isEnabled = true

        // 从 MPVolumeView 中取出系统音量滑块
        volumeSlider = volumeView.subviews.first { $0 is UISlider } as? UISlider

        // 立即拉满
        forceMax()

        // 监听音量变化
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) {
            [weak self] _, _ in
            guard let self = self, self.isEnabled else { return }
            self.forceMax()
        }
    }

    func stop() {
        isEnabled = false
        observation = nil
        volumeSlider = nil
    }

    // MARK: 内部实现

    private func forceMax() {
        let current = AVAudioSession.sharedInstance().outputVolume
        if current < 0.99 {
            setVolume(1.0)
        }
    }

    private func setVolume(_ value: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let slider = self?.volumeSlider else { return }
            slider.value = value
            slider.sendActions(for: .valueChanged)
        }
    }
}
