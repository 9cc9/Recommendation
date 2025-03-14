import Foundation

class LocalAIService {
    // Ollama API地址
    private let apiURL = "http://121.48.164.125:11434/api/generate"
    // 使用的模型名称
    private let modelName: String
    
    // 系统提示词，与原AIService保持一致
    private let systemPrompt = """
    你是一个推荐菜助手，根据上下文中匹配到的菜品列表，给出推荐菜。
    """
    
    // 存储对话历史
    private var chatHistory: [(role: String, content: String)] = []
    // 最大历史消息数量
    private let maxHistoryMessages = 10
    
    // 定义回调类型
    typealias CompletionHandler = (String?, Error?) -> Void
    typealias StreamHandler = (String) -> Void
    
    // 初始化方法
    init(modelName: String) {
        self.modelName = modelName
    }
    
    // 清除对话历史
    func clearChatHistory() {
        chatHistory.removeAll()
    }
    
    
    // 发送消息到AI并获取流式回复
    func sendMessageStream(prompt: String, onReceive: @escaping StreamHandler, onComplete: @escaping CompletionHandler) {
        print("开始流式请求，提示词: \(prompt)")
        
        // 添加用户消息到历史记录
        addMessageToHistory(role: "user", content: prompt)
        
        // 创建消息数组，包含系统提示和历史记录
        var messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        
        // 添加历史对话记录
        messages.append(contentsOf: chatHistory.map { ["role": $0.role, "content": $0.content] })
        
        // 创建请求体
        let requestBody: [String: Any] = [
            "model": modelName,
            "prompt": buildPrompt(messages: messages),
            "stream": true,
            "options": [
                "temperature": 0.7,
            ]
        ]
        
        // 创建URL
        guard let url = URL(string: apiURL) else {
            onComplete(nil, NSError(domain: "LocalAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "无效的URL"]))
            return
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            print("请求体已准备: \(String(data: request.httpBody!, encoding: .utf8) ?? "")")
        } catch {
            print("请求体序列化失败: \(error)")
            onComplete(nil, error)
            return
        }
        
        // 创建自定义的流式处理委托
        let streamDelegate = StreamDelegate(onReceive: onReceive, onComplete: { content, error in
            // 如果成功接收到完整回复，添加到历史记录
            if let content = content, error == nil {
                self.addMessageToHistory(role: "assistant", content: content)
            }
            onComplete(content, error)
        })
        
        // 创建会话并设置委托
        let session = URLSession(configuration: .default, delegate: streamDelegate, delegateQueue: .main)
        
        // 创建数据任务
        let task = session.dataTask(with: request)
        
        // 保存任务引用到委托中，以便可以在需要时取消
        streamDelegate.task = task
        
        // 开始任务
        task.resume()
        print("流式请求已发送")
    }
    
    // 添加消息到历史记录
    private func addMessageToHistory(role: String, content: String) {
        chatHistory.append((role: role, content: content))
        
        // 如果历史记录超过最大数量，移除最早的非系统消息
        if chatHistory.count > maxHistoryMessages {
            if let index = chatHistory.firstIndex(where: { $0.role != "system" }) {
                chatHistory.remove(at: index)
            }
        }
    }
    
    // StreamDelegate类实现
    private class StreamDelegate: NSObject, URLSessionDataDelegate {
        private let onReceive: (String) -> Void
        private let onComplete: (String?, Error?) -> Void
        private var fullResponse = ""
        private var buffer = Data()
        
        var task: URLSessionDataTask?
        
        init(onReceive: @escaping (String) -> Void, onComplete: @escaping (String?, Error?) -> Void) {
            self.onReceive = onReceive
            self.onComplete = onComplete
            super.init()
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            processBuffer()
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                DispatchQueue.main.async {
                    self.onComplete(nil, error)
                }
                return
            }
            
            processBuffer(isComplete: true)
            
            DispatchQueue.main.async {
                self.onComplete(self.fullResponse, nil)
            }
        }
        
        private func processBuffer(isComplete: Bool = false) {
            guard let bufferString = String(data: buffer, encoding: .utf8) else {
                return
            }
            
            let lines = bufferString.components(separatedBy: "\n")
            
            for line in lines {
                guard !line.isEmpty else { continue }
                
                do {
                    let options: JSONSerialization.ReadingOptions = [.allowFragments]
                    if let data = line.data(using: .utf8),
                       let json = try JSONSerialization.jsonObject(with: data, options: options) as? [String: Any],
                       let response = json["response"] as? String {
                        
                        self.fullResponse += response
                        
                        DispatchQueue.main.async {
                            self.onReceive(response)
                        }
                    }
                } catch {
                    print("解析流式数据出错: \(error)")
                    if let data = line.data(using: .utf8) {
                        print("原始数据: \(String(data: data, encoding: .utf8) ?? "无法解码")")
                    }
                }
            }
            
            if !isComplete {
                buffer = Data()
            }
        }
    }
    
    // 发送请求的通用方法
    private func sendRequest(requestBody: [String: Any], isStreaming: Bool, completion: @escaping (Data?, Error?) -> Void) {
        guard let url = URL(string: apiURL) else {
            completion(nil, NSError(domain: "LocalAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "无效的URL"]))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            completion(nil, error)
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            completion(data, nil)
        }
        
        task.resume()
    }
    
    // 添加这个辅助方法来构建 prompt
    private func buildPrompt(messages: [[String: String]]) -> String {
        return messages.map { message in
            switch message["role"] {
                case "system":
                    return "System: \(message["content"] ?? "")"
                case "assistant":
                    return "Assistant: \(message["content"] ?? "")"
                case "user":
                    return "Human: \(message["content"] ?? "")"
                default:
                    return message["content"] ?? ""
            }
        }.joined(separator: "\n")
    }
} 
