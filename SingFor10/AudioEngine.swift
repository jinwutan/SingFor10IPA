//
//  AudioEngine.swift
//  SingFor10
//
//  自包含音频引擎：使用 AVAudioSourceNode 实时合成“唱歌”音色，
//  不依赖任何外部音频文件；支持后台播放、中断恢复。
//

import AVFoundation

// MARK: - 旋律合成器（仅在音频实时线程内访问，避免数据竞争）
private final class MelodyGenerator {
    let sampleRate: Double
    let melody: [Double]
    let noteDuration: Double

    private var phase: Double = 0        // 载波相位
    private var notePhase: Double = 0    // 以秒为单位的音符时间轴

    init(sampleRate: Double, melody: [Double], noteDuration: Double) {
        self.sampleRate = sampleRate
        self.melody = melody
        self.noteDuration = noteDuration
    }

    func nextSample() -> Float {
        let noteFloat = notePhase / noteDuration
        let idx = Int(noteFloat) % melody.count
        let freq = melody[idx]

        // 计算音符内的归一化位置（0..1）
        let local = noteFloat - floor(noteFloat)
        notePhase += 1.0 / sampleRate

        guard freq > 0 else { return 0 } // 休止符

        // ADSR 简化包络：起音 30ms，释音 80ms
        let attack = min(1.0, local * noteDuration / 0.03)
        let release = min(1.0, (1.0 - local) * noteDuration / 0.08)
        let envelope = max(0.0, min(attack, release)) * 0.9

        // 颤音（vibrato）5Hz
        let vibrato = 1.0 + 0.006 * sin(2.0 * .pi * 5.0 * notePhase)
        phase += 2.0 * .pi * freq * vibrato / sampleRate
        if phase > 2.0 * .pi * 4096 { phase -= 2.0 * .pi * 4096 }

        // 加性合成：基频 + 谐波，模拟元音“啊”的共振峰
        let s = sin(phase)
            + 0.70 * sin(2.0 * phase)
            + 0.35 * sin(3.0 * phase)
            + 0.15 * sin(4.0 * phase)
            + 0.08 * sin(5.0 * phase)

        // 归一化（谐波幅度之和约 2.28）
        return Float(s / 2.28 * envelope)
    }
}

// MARK: - 音频引擎
final class AudioEngine {

    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var isPlaying = false
    private let sampleRate: Double = 44100

    // “小星星”旋律（C5 八度），0 表示休止符
    private let melody: [Double] = [
        523.25, 523.25, 783.99, 783.99, 880.00, 880.00, 783.99, 0,
        698.46, 698.46, 659.25, 659.25, 587.33, 587.33, 523.25, 0,
        783.99, 783.99, 698.46, 698.46, 659.25, 659.25, 587.33, 0,
        783.99, 783.99, 698.46, 698.46, 659.25, 659.25, 587.33, 0,
        523.25, 523.25, 783.99, 783.99, 880.00, 880.00, 783.99, 0,
        698.46, 698.46, 659.25, 659.25, 587.33, 587.33, 523.25, 0
    ]
    private let noteDuration: Double = 0.45

    private init() {
        setupNotifications()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: 播放控制

    func start() {
        guard !isPlaying else { return }
        activateSession()
        buildEngineIfNeeded()
        do {
            try engine.start()
            isPlaying = true
        } catch {
            print("[SingFor10] 音频引擎启动失败: \(error)")
        }
    }

    func stop() {
        guard isPlaying else { return }
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
            sourceNode = nil
        }
        isPlaying = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[SingFor10] 停用音频会话失败: \(error)")
        }
    }

    /// 中断（来电、Siri 等）结束后强制恢复播放
    func restartIfNeeded() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                buildEngineIfNeeded()
                try engine.start()
            }
            isPlaying = true
        } catch {
            print("[SingFor10] 恢复播放失败: \(error)")
        }
    }

    // MARK: 内部实现

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback 类别确保静音拨键开启时仍然发声
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("[SingFor10] 配置音频会话失败: \(error)")
        }
    }

    private func buildEngineIfNeeded() {
        guard sourceNode == nil else { return }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let generator = MelodyGenerator(sampleRate: sampleRate,
                                        melody: melody,
                                        noteDuration: noteDuration)
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = generator.nextSample()
                for buffer in abl {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < buf.count { buf[frame] = sample }
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        sourceNode = node
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            break // 系统会自动挂起引擎
        case .ended:
            // 来电结束 / Siri 退出后立即恢复
            restartIfNeeded()
        @unknown default:
            restartIfNeeded()
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        // 插入/拔出耳机等路由变化后确保继续播放
        if isPlaying { restartIfNeeded() }
    }
}
