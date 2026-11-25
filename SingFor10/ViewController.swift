//
//  ViewController.swift
//  SingFor10
//
//  主界面：10 分钟倒计时 + 进度条 + 防误触“退出”按钮。
//

import UIKit
import MediaPlayer

class ViewController: UIViewController {

    // 10 分钟 = 600 秒
    private let totalDuration: TimeInterval = 600
    private var startTime: Date?
    private var timer: Timer?
    private var finished = false

    // MARK: UI 元素

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "🎵 唱歌进行中"
        l.font = .systemFont(ofSize: 28, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        return l
    }()

    private let countdownLabel: UILabel = {
        let l = UILabel()
        l.text = "10:00"
        l.font = .monospacedDigitSystemFont(ofSize: 76, weight: .semibold)
        l.textColor = UIColor(red: 1.0, green: 0.84, blue: 0.30, alpha: 1.0)
        l.textAlignment = .center
        return l
    }()

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.text = "唱满 10 分钟后自动停止\n调小声音也没用哦 😈"
        l.font = .systemFont(ofSize: 16, weight: .medium)
        l.textColor = UIColor.white.withAlphaComponent(0.7)
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    private let progressView: UIProgressView = {
        let p = UIProgressView(progressViewStyle: .bar)
        p.progressTintColor = UIColor(red: 1.0, green: 0.55, blue: 0.35, alpha: 1.0)
        p.trackTintColor = UIColor.white.withAlphaComponent(0.15)
        p.transform = CGAffineTransform(scaleX: 1.0, y: 2.5)
        return p
    }()

    private let decoyButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("退出", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        b.tintColor = UIColor.white.withAlphaComponent(0.35)
        return b
    }()

    private let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))

    // MARK: 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startPrank()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 从后台回到前台时，确保音频仍在播放
        if !finished { AudioEngine.shared.restartIfNeeded() }
    }

    private func setupUI() {
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1.0)

        // 隐藏的音量视图，供 VolumeGuard 取 slider（必须在视图层级中）
        volumeView.alpha = 0.01
        volumeView.isHidden = false
        view.addSubview(volumeView)

        let stack = UIStackView(arrangedSubviews: [titleLabel, countdownLabel, progressView, hintLabel])
        stack.axis = .vertical
        stack.spacing = 28
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40)
        ])

        decoyButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(decoyButton)
        NSLayoutConstraint.activate([
            decoyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            decoyButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            decoyButton.widthAnchor.constraint(equalToConstant: 120),
            decoyButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        decoyButton.addTarget(self, action: #selector(decoyTapped), for: .touchUpInside)

        progressView.progress = 0
    }

    // MARK: 逻辑

    private func startPrank() {
        finished = false
        startTime = Date()
        UIApplication.shared.isIdleTimerDisabled = true

        AudioEngine.shared.start()
        VolumeGuard.shared.start(volumeView: volumeView)

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func tick() {
        guard let start = startTime, !finished else { return }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = max(0, totalDuration - elapsed)

        countdownLabel.text = formattedTime(remaining)
        progressView.progress = Float(min(1.0, elapsed / totalDuration))

        if remaining <= 0 {
            finish()
        }
    }

    private func finish() {
        finished = true
        timer?.invalidate()
        timer = nil

        AudioEngine.shared.stop()
        VolumeGuard.shared.stop()
        UIApplication.shared.isIdleTimerDisabled = false

        countdownLabel.text = "00:00"
        countdownLabel.textColor = .systemGreen
        titleLabel.text = "✅ 唱完了！"
        hintLabel.text = "坚持了整整 10 分钟 🎉"
        decoyButton.isHidden = true
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let total = Int(ceil(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    @objc private func decoyTapped() {
        let alert = UIAlertController(
            title: "再等等～",
            message: "还有一点没唱完呢 😈",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }
}
