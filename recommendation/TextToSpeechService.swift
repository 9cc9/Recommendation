//
//  TextToSpeechService.swift
//
//  Created by 贝贝 on 2025/2/24.
//

import Foundation
import AVFoundation

class TextToSpeechService: NSObject {
    // 单例模式，方便全局访问
    static let shared = TextToSpeechService()
    
    // 语音合成器
    private let synthesizer = AVSpeechSynthesizer()
    
    // 当前是否正在朗读
    private(set) var isSpeaking = false
    
    // 语音配置
    private var voiceLanguage = "zh-CN"
    private var speechRate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var volume: Float = 1.0
    private var pitchMultiplier: Float = 1.0
    
    // 添加声音标识符变量
    private var voiceIdentifier: String? = nil
    
    // 累积的文本，用于完整朗读
    private var accumulatedText = ""
    
    // 待朗读的文本队列
    private var textQueue: [String] = []
    
    // 是否正在处理队列
    private var isProcessingQueue = false
    
    // 回调闭包类型
    typealias SpeechCompletionHandler = () -> Void
    
    // 完成回调
    private var completionHandler: SpeechCompletionHandler?
    
    // 私有初始化方法，防止外部创建实例
    private override init() {
        super.init()
        synthesizer.delegate = self
        setupPreferredVoice() // 添加设置首选声音的方法调用
    }
    
    // 设置首选声音
    private func setupPreferredVoice() {
        // 获取所有可用的声音
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // 尝试找到最适合的中文女声
        for voice in voices {
            // 优先选择 Siri 的声音，因为它通常质量更好
            if voice.language.starts(with: "zh-") && voice.name.contains("Siri") {
                voiceIdentifier = voice.identifier
                return
            }
        }
        
        // 如果没有找到 Siri 声音，尝试找其他中文女声
        for voice in voices {
            if voice.language.starts(with: "zh-") && 
               (voice.name.contains("Tingting") || voice.name.contains("Female")) {
                voiceIdentifier = voice.identifier
                return
            }
        }
        
        // 如果没有找到合适的声音，使用默认的中文声音
        voiceLanguage = "zh-CN"
    }
    
    // 配置语音参数
    func configure(language: String? = nil, rate: Float? = nil, volume: Float? = nil, pitch: Float? = nil, voiceId: String? = nil) {
        if let language = language {
            voiceLanguage = language
        }

        if let rate = rate {
            speechRate = rate
        }

        if let volume = volume {
            self.volume = volume
        }

        if let pitch = pitch {
            pitchMultiplier = pitch
        }
        
        if let voiceId = voiceId {
            voiceIdentifier = voiceId
        }
    }
    
    // 获取所有可用的声音
    func getAvailableVoices() -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
    }

    // 重置累积文本
    func resetAccumulatedText() {
        accumulatedText = ""
        textQueue.removeAll()
        isProcessingQueue = false

        // 如果正在朗读，停止当前朗读
        if isSpeaking {
            stopSpeaking()
        }
    }

    // 配置语音合成请求
    private func configureUtterance(_ utterance: AVSpeechUtterance) {
        // 设置声音
        if let voiceIdentifier = voiceIdentifier {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        }
        
        utterance.rate = speechRate
        utterance.volume = volume
        utterance.pitchMultiplier = pitchMultiplier
        
        // 设置不朗读标点符号
        if #available(iOS 14.0, *) {
            utterance.prefersAssistiveTechnologySettings = false
            utterance.postUtteranceDelay = 0.0
            utterance.preUtteranceDelay = 0.0
        }
    }

    // 替换标点符号为适当的停顿标记
    private func replacePunctuationWithPauses(_ text: String) -> String {
        var result = text
        
        // 1. 替换句子结束标点为句号（保留停顿但不读出标点名称）
        let sentenceEndingPunctuation = ["！", "!", "？", "?", "；", ";", "…", "......"]
        for punct in sentenceEndingPunctuation {
            result = result.replacingOccurrences(of: punct, with: "。")
        }
        
        // 2. 替换引号和括号（这些通常会被读出）
        let quotesAndBrackets = ["「", "」", "『", "』", "（", "）", "(", ")", "《", "》", "〈", "〉", "\\\"", "'"]
        for bracket in quotesAndBrackets {
            result = result.replacingOccurrences(of: bracket, with: "")
        }
        
        // 3. 替换逗号和顿号为短停顿
        result = result.replacingOccurrences(of: "，", with: ", ")
        result = result.replacingOccurrences(of: "、", with: ", ")
        
        // 4. 替换冒号和破折号
        result = result.replacingOccurrences(of: "：", with: ": ")
        result = result.replacingOccurrences(of: "—", with: ", ")
        result = result.replacingOccurrences(of: "——", with: ", ")
        
        // 5. 处理英文标点（确保它们前后有空格）
        result = result.replacingOccurrences(of: ",", with: ", ")
        result = result.replacingOccurrences(of: ":", with: ": ")
        
        // 6. 移除多余的空格
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        return result
    }

    // 朗读文本（完整文本，会停止当前朗读）
    func speak(_ text: String, completion: SpeechCompletionHandler? = nil) {
        // 如果正在朗读，先停止
        if isSpeaking {
            stopSpeaking()
        }
        
        // 重置累积文本并设置新文本
        resetAccumulatedText()
        accumulatedText = text
        
        // 设置完成回调
        completionHandler = completion
        
        // 确保音频会话设置为播放模式
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("设置音频会话为播放模式失败: \(error)")
        }
        
        // 处理文本，替换标点符号为适当的停顿标记
        let processedText = replacePunctuationWithPauses(text)
        
        // 创建语音合成请求
        let utterance = AVSpeechUtterance(string: processedText)
        configureUtterance(utterance)
        
        // 开始朗读
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // 朗读新增的文本片段（用于流式输出）
    func speakAddition(_ newText: String) {
        // 添加新文本到累积文本
        accumulatedText += newText

        // 将新文本添加到队列
        if !newText.isEmpty {
            // 检查是否是完整的句子或短语
            // 这里我们简单地按标点符号分割，可以根据需要调整
            let sentences = splitIntoSentences(newText)
            textQueue.append(contentsOf: sentences)
        }

        // 如果当前没有处理队列，开始处理
        if !isProcessingQueue {
            processTextQueue()
        }
    }

    // 将文本分割成句子或短语
    private func splitIntoSentences(_ text: String) -> [String] {
        // 如果文本很短，直接返回
        if text.count <= 5 {
            return [text]
        }

        // 按标点符号分割
        let delimiters = ["。", "！", "？", ".", "!", "?", "\n"]
        var result: [String] = []
        var currentSentence = ""

        for char in text {
            currentSentence.append(char)

            // 如果遇到分隔符，添加到结果并重置当前句子
            if delimiters.contains(String(char)) {
                result.append(currentSentence)
                currentSentence = ""
            }
        }

        // 添加最后一个句子（如果有）
        if !currentSentence.isEmpty {
            result.append(currentSentence)
        }

        return result
    }

    // 处理文本队列
    private func processTextQueue() {
        // 如果队列为空或者正在朗读，返回
        if textQueue.isEmpty || isSpeaking {
            isProcessingQueue = false
            return
        }
        
        isProcessingQueue = true
        
        // 确保音频会话设置为播放模式
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("设置音频会话为播放模式失败: \(error)")
        }
        
        // 获取队列中的下一个文本
        let nextText = textQueue.removeFirst()
        
        // 处理文本，替换标点符号为适当的停顿标记
        let processedText = replacePunctuationWithPauses(nextText)
        
        // 创建语音合成请求
        let utterance = AVSpeechUtterance(string: processedText)
        configureUtterance(utterance)
        
        // 开始朗读
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // 停止朗读
    func stopSpeaking() {
        if isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
        }
    }

    // 暂停朗读
    func pauseSpeaking() {
        if isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        }
    }

    // 继续朗读
    func continueSpeaking() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TextToSpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        
        // 处理队列中的下一个文本
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 如果队列不为空，处理下一个文本
            if !self.textQueue.isEmpty {
                self.processTextQueue()
            } else {
                // 队列为空，调用完成回调
                if let completionHandler = self.completionHandler {
                    completionHandler()
                    self.completionHandler = nil
                }
                self.isProcessingQueue = false
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        isProcessingQueue = false
        completionHandler = nil
    }
} 