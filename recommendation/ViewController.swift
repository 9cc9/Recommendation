//
//  ViewController.swift
//  recommendation
//
//  Created by 贝贝 on 2025/2/24.
//

import UIKit
import AVFoundation
import Speech

class ViewController: UIViewController {
    // 输入相关组件
    let inputTextField = UITextField()
    let voiceButton = UIButton()
    
    // 聊天记录显示区域
    let chatTableView = UITableView()
    var chatMessages: [ChatMessage] = []
    
    // 添加顶部背景视图作为属性
    let topBackgroundView = UIView()
    
    // 语音识别相关
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // 添加停顿检测计时器
    private var pauseDetectionTimer: Timer?
    private let pauseThreshold: TimeInterval = 2.0
    private var lastTranscription: String = ""
    

    private let localAI = LocalAIService(modelName: "deepseek-r1:32b")

    // 添加文字转语音服务
    private let textToSpeechService = TextToSpeechService.shared

    // 添加应用唤起服务
    private let appLaunchService = AppLaunchService.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        requestSpeechAuthorization()
        
        // 配置文字转语音服务
        TextToSpeechService.shared.configure(
            language: "zh-CN",
            rate: AVSpeechUtteranceDefaultSpeechRate * 0.9, // 稍微慢一点的语速
            volume: 1.0,
            pitch: 1.0
        )
        
        // 设置背景色
        view.backgroundColor = .white
        
        // 顶部背景视图
        topBackgroundView.backgroundColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        topBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBackgroundView)
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // 添加顶部背景视图 - 不需要重新创建，使用类属性
        topBackgroundView.backgroundColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        topBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBackgroundView)
        
        // 添加标题标签
        let titleLabel = UILabel()
        titleLabel.text = "痛风患者专属AI"
        titleLabel.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.textColor = .white // 白色文字
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        topBackgroundView.addSubview(titleLabel)
        
        // 添加小图标
        let logoImageView = UIImageView(image: UIImage(systemName: "brain.head.profile"))
        logoImageView.tintColor = .white
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        topBackgroundView.addSubview(logoImageView)
        
        // 聊天记录表格
        chatTableView.register(ChatBubbleCell.self, forCellReuseIdentifier: "ChatCell")
        chatTableView.delegate = self
        chatTableView.dataSource = self
        chatTableView.separatorStyle = .none
        chatTableView.backgroundColor = .systemBackground
        chatTableView.translatesAutoresizingMaskIntoConstraints = false
        // 添加表格背景图案
        let patternImage = UIImage(systemName: "bubble.left.and.bubble.right.fill")?.withTintColor(.systemGray6, renderingMode: .alwaysOriginal)
        chatTableView.backgroundView = UIImageView(image: patternImage)
        chatTableView.backgroundView?.contentMode = .scaleAspectFit
        chatTableView.backgroundView?.alpha = 0.1
        view.addSubview(chatTableView)
        
        // 底部输入区域容器
        let inputContainerView = UIView()
        inputContainerView.backgroundColor = .white // 修改为白色背景
        // 添加阴影效果
        inputContainerView.layer.shadowColor = UIColor.black.cgColor
        inputContainerView.layer.shadowOffset = CGSize(width: 0, height: -2)
        inputContainerView.layer.shadowOpacity = 0.1
        inputContainerView.layer.shadowRadius = 3
        inputContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainerView)
        
        // 语音按钮 - 调大并放在上方居中
        let micConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        voiceButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: micConfig), for: .normal)
        voiceButton.tintColor = .white // 白色图标
        voiceButton.backgroundColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        voiceButton.layer.cornerRadius = 35 // 增大圆角
        voiceButton.layer.shadowColor = UIColor.black.cgColor
        voiceButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        voiceButton.layer.shadowOpacity = 0.3
        voiceButton.layer.shadowRadius = 4
        voiceButton.addTarget(self, action: #selector(voiceButtonTapped), for: .touchUpInside)
        voiceButton.translatesAutoresizingMaskIntoConstraints = false
        inputContainerView.addSubview(voiceButton)
        
        // 文本输入框 - 放在语音按钮下方
        inputTextField.placeholder = "请输入指令或点击上方麦克风"
        inputTextField.font = UIFont.systemFont(ofSize: 16)
        inputTextField.borderStyle = .roundedRect
        inputTextField.backgroundColor = .white
        inputTextField.layer.cornerRadius = 18
        inputTextField.clipsToBounds = true
        inputTextField.delegate = self
        inputTextField.translatesAutoresizingMaskIntoConstraints = false
        inputContainerView.addSubview(inputTextField)
        
        // 布局约束
        NSLayoutConstraint.activate([
            // 顶部背景视图约束
            topBackgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            topBackgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBackgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBackgroundView.heightAnchor.constraint(equalToConstant: 100),
            
            // 标题标签约束
            titleLabel.centerXAnchor.constraint(equalTo: topBackgroundView.centerXAnchor, constant: 15),
            titleLabel.bottomAnchor.constraint(equalTo: topBackgroundView.bottomAnchor, constant: -15),
            
            // 图标约束
            logoImageView.trailingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: -10),
            logoImageView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            logoImageView.widthAnchor.constraint(equalToConstant: 30),
            logoImageView.heightAnchor.constraint(equalToConstant: 30),
            
            // 底部输入区域约束
            inputContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            inputContainerView.heightAnchor.constraint(equalToConstant: 120), // 增加高度
            
            // 语音按钮约束 - 放在上方居中
            voiceButton.centerXAnchor.constraint(equalTo: inputContainerView.centerXAnchor),
            voiceButton.topAnchor.constraint(equalTo: inputContainerView.topAnchor, constant: 12),
            voiceButton.widthAnchor.constraint(equalToConstant: 60), // 增大按钮尺寸
            voiceButton.heightAnchor.constraint(equalToConstant: 60), // 增大按钮尺寸
            
            // 输入框约束 - 放在下方
            inputTextField.leadingAnchor.constraint(equalTo: inputContainerView.leadingAnchor, constant: 16),
            inputTextField.trailingAnchor.constraint(equalTo: inputContainerView.trailingAnchor, constant: -16),
            inputTextField.topAnchor.constraint(equalTo: voiceButton.bottomAnchor, constant: 12),
            inputTextField.heightAnchor.constraint(equalToConstant: 36),
            
            // 聊天记录表格约束
            chatTableView.topAnchor.constraint(equalTo: topBackgroundView.bottomAnchor),
            chatTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chatTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chatTableView.bottomAnchor.constraint(equalTo: inputContainerView.topAnchor)
        ])
    }
    
    // 语音授权请求
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            OperationQueue.main.addOperation {
                self.voiceButton.isEnabled = authStatus == .authorized
            }
        }
    }
    
    // 语音按钮点击处理
    @objc private func voiceButtonTapped() {
        if audioEngine.isRunning {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    // 开始录音
    private func startRecording() {
        do {
            // 先停止并重置引擎
            if audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                throw NSError(domain: "SpeechError", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法创建识别请求"])
            }
            
            let inputNode = audioEngine.inputNode
            
            // 确保移除旧tap
            inputNode.removeTap(onBus: 0)
            
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0 else {
                throw NSError(domain: "AudioError", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效的音频格式"])
            }
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                DispatchQueue.main.async {
                    self?.recognitionRequest?.append(buffer)
                }
            }
            
            audioEngine.prepare()
            
            // 添加标志变量，防止重复处理
            var hasProcessedFinalResult = false
            
            // 关键部分：创建识别任务
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                // 结果处理
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    DispatchQueue.main.async {
                        self.inputTextField.text = text
                        
                        // 重置停顿计时器
                        self.resetPauseDetectionTimer()
                        
                        // 保存当前转录文本
                        self.lastTranscription = text
                    }
                }
                
                // 错误/完成处理
                if let error = error {
                    DispatchQueue.main.async {
                        self.showAlert(message: "识别错误: \(error.localizedDescription)")
                    }
                    self.stopRecording()
                } else if result?.isFinal == true && !hasProcessedFinalResult {
                    // 标记为已处理，防止重复
                    hasProcessedFinalResult = true
                    
                    // 在语音识别完成后处理指令
                    if let finalText = result?.bestTranscription.formattedString, !finalText.isEmpty {
                        DispatchQueue.main.async {
                            self.processCommand(finalText)
                        }
                    }
                    self.stopRecording()
                }
            }
            
            try audioEngine.start()
            let micConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
            voiceButton.setImage(UIImage(systemName: "mic.slash.fill", withConfiguration: micConfig), for: .normal)
        } catch {
            showAlert(message: "录音启动失败：\(error.localizedDescription)")
        }
    }
    
    // 停止录音
    private func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
            audioEngine.inputNode.removeTap(onBus: 0)
            
            // 重置音频会话为播放模式
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("重置音频会话失败: \(error)")
            }
        }
        
        // 重置UI
        let micConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        voiceButton.setImage(UIImage(systemName: "mic.fill", withConfiguration: micConfig), for: .normal)
        
        // 取消计时器
        pauseDetectionTimer?.invalidate()
        pauseDetectionTimer = nil
    }
    
    // 重置停顿检测计时器
    private func resetPauseDetectionTimer() {
        // 取消现有计时器
        pauseDetectionTimer?.invalidate()
        
        // 创建新计时器
        pauseDetectionTimer = Timer.scheduledTimer(withTimeInterval: pauseThreshold, repeats: false) { [weak self] _ in
            guard let self = self, self.audioEngine.isRunning, !self.lastTranscription.isEmpty else { return }
            
            // 停顿超过阈值，处理当前识别的文本
            DispatchQueue.main.async {
                // 停止录音会触发recognitionTask的完成回调，所以这里不需要再调用processCommand
                self.stopRecording()
            }
        }
    }
    
    // 新增警告框方法
    private func showAlert(message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: "提示",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            self.present(alert, animated: true)
        }
    }

    
    private func processCommand(_ text: String) {
        // 清空输入框
        inputTextField.text = ""
        
        // 添加用户消息到聊天记录
        addMessage(sender: "user", message: text)
        
        // 检查是否需要唤起应用
        if let appLaunchResult = appLaunchService.checkAndLaunchApp(for: text) {
            // 如果成功识别并尝试启动应用
            addOrUpdateAIMessage(appLaunchResult.responseMessage, messageType: .normal)
            
            // 如果成功启动应用，不需要继续发送到AI服务
            if appLaunchResult.appLaunched {
                return
            }
        }
        
        // 确保音频会话设置为播放模式
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("设置音频会话为播放模式失败: \(error)")
        }
        
        // 发送到AI服务并获取回复
        print("🚀 开始发送消息到本地AI服务...")
        localAI.sendMessageStream(
            prompt: text,
            onReceive: { [weak self] chunk in
                guard let self = self else { return }
                
                print("📥 收到AI响应片段: \(chunk)")
                
                // 添加或更新AI消息
                self.addOrUpdateAIMessage(chunk, messageType: .normal)
                
                // 使用文字转语音服务朗读新增内容
                TextToSpeechService.shared.speakAddition(chunk)
            },
            onThinking: { [weak self] chunk in
                guard let self = self else { return }
                
                print("🤔 AI思考过程: \(chunk)")
                
                // 添加或更新思考消息
                self.addOrUpdateAIMessage(chunk, messageType: .thinking)
            },
            onLoading: { [weak self] isLoading in
                // 暂时不需要显示加载状态
                // guard let self = self else { return }
                
                // DispatchQueue.main.async {
                //     // 根据加载状态更新UI
                //     if isLoading {
                //         // AI开始思考时显示的消息
                //         self.addOrUpdateAIMessage("正在加载知识库...")
                //     }
                // }
            },
            onComplete: { [weak self] fullResponse, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ AI服务连接错误: \(error.localizedDescription)")
                    print("❌ 错误详情: \(error)")
                    
                    // 向用户显示更友好的错误信息
                    let errorMessage = "无法连接到AI服务，请检查：\n1. AI服务是否已启动\n2. 端口11434是否正确\n3. 本地网络连接是否正常"
                    self.showAlert(message: errorMessage)
                    
                    // 在聊天界面显示错误信息
                    self.addOrUpdateAIMessage("抱歉，我现在无法回应，请检查AI服务是否正常运行。", messageType: .normal)
                    return
                }
                
                print("✅ AI响应完成")
                if let response = fullResponse {
                    print("📝 完整响应内容: \(response)")
                }
            }
        )
    }
    
    // 添加消息到聊天记录并返回索引
    private func addMessage(sender: String, message: String) -> Int {
        let chatMessage = ChatMessage(
            sender: sender,
            message: message,
            type: .normal,
            isExpanded: true
        )
        chatMessages.append(chatMessage)
        let indexPath = IndexPath(row: chatMessages.count - 1, section: 0)
        chatTableView.insertRows(at: [indexPath], with: .automatic)
        chatTableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
        return chatMessages.count - 1
    }
    
    // 更新AI消息单元格
    private func updateAIMessageCell(at index: Int) {
        let indexPath = IndexPath(row: index, section: 0)
        
        // 先更新数据源中的消息
        let currentMessage = chatMessages[index]
    
        
        // 更新表格视图
        chatTableView.beginUpdates()
        
        if let cell = chatTableView.cellForRow(at: indexPath) as? ChatBubbleCell {
            cell.messageLabel.text = currentMessage.message
            // 强制布局更新
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
        }
        
        chatTableView.endUpdates()
        
        // 确保滚动到最新消息
        chatTableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
    }
    
    // 添加或更新AI消息
    private func addOrUpdateAIMessage(_ chunk: String, messageType: MessageType) {
        DispatchQueue.main.async {
            if let lastMessageIndex = self.chatMessages.indices.last,
               self.chatMessages[lastMessageIndex].sender == "ai" &&
               self.chatMessages[lastMessageIndex].type == messageType {
                // 更新现有消息
                var updatedMessage = self.chatMessages[lastMessageIndex]
                updatedMessage.message += chunk
                self.chatMessages[lastMessageIndex] = updatedMessage
                self.updateAIMessageCell(at: lastMessageIndex)
            } else {
                // 添加新消息
                let message = ChatMessage(
                    sender: "ai",
                    message: chunk,
                    type: messageType,
                    isExpanded: true
                )
                self.chatMessages.append(message)
                let index = self.chatMessages.count - 1
                let indexPath = IndexPath(row: index, section: 0)
                self.chatTableView.insertRows(at: [indexPath], with: .automatic)
                self.chatTableView.scrollToRow(at: indexPath, at: .bottom, animated: true)
            }
        }
    }
}

// 聊天气泡单元格
class ChatBubbleCell: UITableViewCell {
    let bubbleView = UIView()
    let messageLabel = UILabel()
    let avatarImageView = UIImageView()
    
    var isUserMessage: Bool = false {
        didSet {
            setupBubbleStyle()
        }
    }
    
    private let expandButton = UIButton()
    private var isThinkingCell = false
    var onExpandTapped: (() -> Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        // 头像图片视图
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarImageView)
        
        // 气泡视图
        bubbleView.layer.cornerRadius = 18
        bubbleView.clipsToBounds = true
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)
        
        // 消息标签 - 确保在最上层
        messageLabel.numberOfLines = 0
        messageLabel.font = UIFont.systemFont(ofSize: 16)
        messageLabel.backgroundColor = .clear // 确保背景透明
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(messageLabel) // 直接添加到contentView而不是bubbleView
        
        // 添加展开/折叠按钮
        expandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        expandButton.tintColor = .gray
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(expandButton)
        
        expandButton.addTarget(self, action: #selector(expandButtonTapped), for: .touchUpInside)
        
        // 布局约束
        NSLayoutConstraint.activate([
            // 消息标签约束 - 相对于气泡视图定位
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),
            
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.7),
            
            avatarImageView.widthAnchor.constraint(equalToConstant: 36),
            avatarImageView.heightAnchor.constraint(equalToConstant: 36),
            avatarImageView.centerYAnchor.constraint(equalTo: bubbleView.centerYAnchor),
            
            expandButton.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            expandButton.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -8),
            expandButton.widthAnchor.constraint(equalToConstant: 20),
            expandButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    private func setupBubbleStyle() {
        if isUserMessage {
            // 用户消息样式
            bubbleView.backgroundColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
            messageLabel.textColor = .white
            
            // 用户头像设置
            avatarImageView.image = UIImage(named: "UserAvatar")
            avatarImageView.layer.cornerRadius = 18
            avatarImageView.clipsToBounds = true
            avatarImageView.layer.borderWidth = 1.0
            avatarImageView.layer.borderColor = UIColor.white.cgColor
            
            // 用户消息靠右，头像在最右侧
            NSLayoutConstraint.deactivate(bubbleView.constraints.filter { 
                $0.firstAttribute == .leading || $0.firstAttribute == .trailing 
            })
            NSLayoutConstraint.activate([
                // 头像靠右
                avatarImageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                // 气泡在头像左侧
                bubbleView.trailingAnchor.constraint(equalTo: avatarImageView.leadingAnchor, constant: -8),
                bubbleView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 60)
            ])
            
        } else {
            // AI消息样式
            bubbleView.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            messageLabel.textColor = .black
            
            // AI头像设置
            avatarImageView.image = UIImage(systemName: "brain.head.profile")
            avatarImageView.tintColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
            avatarImageView.layer.cornerRadius = 18
            avatarImageView.clipsToBounds = true
            avatarImageView.backgroundColor = UIColor(red: 0.95, green: 0.98, blue: 1.0, alpha: 1.0)
            
            // AI消息靠左，头像在最左侧
            NSLayoutConstraint.deactivate(bubbleView.constraints.filter { 
                $0.firstAttribute == .leading || $0.firstAttribute == .trailing 
            })
            NSLayoutConstraint.activate([
                // 头像靠左
                avatarImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                // 气泡在头像右侧
                bubbleView.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 8),
                bubbleView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -60)
            ])
        }
        
        // 强制更新布局
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    // 添加layoutSubviews方法确保圆角正确应用
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 确保头像是圆形 - 在实际布局后设置圆角
        avatarImageView.layer.cornerRadius = avatarImageView.frame.width / 2
    }
    
    @objc private func expandButtonTapped() {
        onExpandTapped?()
    }
    
    func configure(with message: ChatMessage, isUser: Bool) {
        messageLabel.text = message.message
        isUserMessage = isUser
        isThinkingCell = message.type == .thinking
        
        // 设置展开/折叠按钮状态
        expandButton.isHidden = !isThinkingCell
        let imageName = message.isExpanded ? "chevron.up" : "chevron.down"
        expandButton.setImage(UIImage(systemName: imageName), for: .normal)
        
        // 设置思考消息的特殊样式
        if isThinkingCell {
            bubbleView.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 1.0, alpha: 1.0)
            messageLabel.font = UIFont.italicSystemFont(ofSize: 16)
            
            // 根据展开状态调整约束
            if message.isExpanded {
                messageLabel.isHidden = false
                // 恢复正常约束
                NSLayoutConstraint.activate([
                    messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
                    messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
                    messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
                    messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14)
                ])
            } else {
                messageLabel.isHidden = true
                // 收起时将气泡高度设为最小值
                bubbleView.heightAnchor.constraint(equalToConstant: 40).isActive = true
            }
        } else {
            messageLabel.isHidden = false
            bubbleView.backgroundColor = isUserMessage ? 
                UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) : 
                UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            messageLabel.font = UIFont.systemFont(ofSize: 16)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        messageLabel.text = ""
        
        // 移除所有自定义约束
        bubbleView.constraints.forEach { constraint in
            if constraint.firstAttribute == .height {
                bubbleView.removeConstraint(constraint)
            }
        }
    }
}

// 表格视图代理和数据源
extension ViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return chatMessages.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatCell", for: indexPath) as! ChatBubbleCell
        let message = chatMessages[indexPath.row]
        
        cell.configure(with: message, isUser: message.sender == "user")
        
        cell.onExpandTapped = { [weak self] in
            guard let self = self else { return }
            
            // 切换展开状态
            var updatedMessage = self.chatMessages[indexPath.row]
            updatedMessage.isExpanded.toggle()
            self.chatMessages[indexPath.row] = updatedMessage
            
            // 重新加载单元格
            tableView.reloadRows(at: [indexPath], with: .automatic)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
}

// 文本输入处理
extension ViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let text = textField.text, !text.isEmpty {
            processCommand(text)
            textField.resignFirstResponder()
            return true
        }
        return false
    }
}

// 添加消息类型枚举
enum MessageType {
    case normal
    case thinking
}

// 修改消息结构
struct ChatMessage {
    let sender: String
    var message: String
    let type: MessageType
    var isExpanded: Bool
}
