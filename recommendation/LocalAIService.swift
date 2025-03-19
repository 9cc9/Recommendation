import Foundation

class LocalAIService {
    // 修改API地址
    private let apiURL = "http://121.48.164.125/v1/chat-messages"
    // 添加认证token
    private let authToken = "Bearer app-PYdCdf9SgMb5twkshkDSvvkg"
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
    typealias LoadingHandler = (Bool) -> Void
    
    // 初始化方法
    init(modelName: String) {
        self.modelName = modelName
    }
    
    // 清除对话历史
    func clearChatHistory() {
        chatHistory.removeAll()
    }
    
    
    // 发送消息到AI并获取流式回复
    func sendMessageStream(prompt: String, 
                         onReceive: @escaping StreamHandler, 
                         onLoading: @escaping LoadingHandler,
                         onComplete: @escaping CompletionHandler) {
        print("开始流式请求，提示词: \(prompt)")
        
        // 添加用户消息到历史记录
        addMessageToHistory(role: "user", content: prompt)
        
        // 创建新的请求体格式
        let requestBody: [String: Any] = [
            "inputs": [:],
            "query": prompt,
            "response_mode": "streaming",
            "conversation_id": "",
            "user": "abc-123"
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
        request.addValue(authToken, forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            print("请求体已准备: \(String(data: request.httpBody!, encoding: .utf8) ?? "")")
        } catch {
            print("请求体序列化失败: \(error)")
            onComplete(nil, error)
            return
        }
        
        // 创建自定义的流式处理委托
        let streamDelegate = StreamDelegate(
            onReceive: onReceive,
            onLoading: onLoading,
            onComplete: { content, error in
                // 如果成功接收到完整回复，添加到历史记录
                if let content = content, error == nil {
                    self.addMessageToHistory(role: "assistant", content: content)
                }
                onComplete(content, error)
            }
        )
        
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
        private let onLoading: (Bool) -> Void
        private var fullResponse = ""
        private var buffer = Data()
        private var messageId: String?
        private var conversationId: String?
        private var lastPingTime: Date?
        
        var task: URLSessionDataTask?
        
        init(onReceive: @escaping (String) -> Void, 
             onLoading: @escaping (Bool) -> Void,
             onComplete: @escaping (String?, Error?) -> Void) {
            self.onReceive = onReceive
            self.onLoading = onLoading
            self.onComplete = onComplete
            super.init()
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            buffer.append(data)
            processBuffer()
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            DispatchQueue.main.async {
                self.onLoading(false)
                
                if let error = error {
                    self.onComplete(nil, error)
                    return
                }
                
                self.processBuffer(isComplete: true)
                self.onComplete(self.fullResponse, nil)
            }
        }
        
        private func processBuffer(isComplete: Bool = false) {
            guard let bufferString = String(data: buffer, encoding: .utf8) else {
                return
            }
            
            // 按照SSE格式分割数据流
            let chunks = bufferString.components(separatedBy: "\n\n")
            
            for chunk in chunks {
                guard !chunk.isEmpty else { continue }
                
                // 处理 ping 事件
                if chunk.trimmingCharacters(in: .whitespaces) == "event: ping" {
                    handlePingEvent()
                    continue
                }
                
                // 移除"data: "前缀
                guard chunk.hasPrefix("data: ") else { continue }
                let jsonString = String(chunk.dropFirst(6))
                
                do {
                    guard let data = jsonString.data(using: .utf8),
                          let json = try JSONSerialization.jsonObject(with: data, options: [.allowFragments]) as? [String: Any],
                          let event = json["event"] as? String else {
                        continue
                    }
                    
                    // 处理不同类型的事件
                    switch event {
                    case "agent_message":
                        if let answer = json["answer"] as? String {
                            self.fullResponse += answer
                            DispatchQueue.main.async {
                                self.onReceive(answer)
                            }
                        }
                    case "agent_thought":
                        if let thought = json["thought"] as? String,
                           !thought.isEmpty,
                           let observation = json["observation"] as? String,
                           let tool = json["tool"] as? String,
                           let toolInput = json["tool_input"] as? String,
                           let position = json["position"] as? Int {
                            
                            let thoughtProcess = """
                            🤔 思考过程 #\(position)
                            ----------------
                            💭 思考: \(thought)
                            🔧 使用工具: \(tool)
                            📝 工具输入: \(toolInput)
                            📋 观察结果: \(observation)
                            """
                            
                            DispatchQueue.main.async {
                                // 使用 > 来创建可折叠的引用块
                                self.onReceive("\n\n<展开思考过程 #\(position)>\n\n>\(thoughtProcess.split(separator: "\n").joined(separator: "\n>"))\n\n")
                            }
                        }
                    case "message_end":
                        self.messageId = json["message_id"] as? String
                        self.conversationId = json["conversation_id"] as? String
                        
                    case "error":
                        if let errorMessage = json["message"] as? String {
                            DispatchQueue.main.async {
                                let error = NSError(domain: "LocalAIService",
                                                  code: json["status"] as? Int ?? 500,
                                                  userInfo: [NSLocalizedDescriptionKey: errorMessage])
                                self.onComplete(nil, error)
                            }
                        }
                        
                    case "message_replace":
                        if let answer = json["answer"] as? String {
                            self.fullResponse = answer
                            DispatchQueue.main.async {
                                self.onReceive(answer)
                            }
                        }
                        
                    default:
                        break
                    }
                    
                } catch {
                    print("解析流式数据出错: \(error)")
                    print("原始数据: \(chunk)")
                }
            }
            
            if !isComplete {
                buffer = Data()
            }
        }
        
        private func handlePingEvent() {
            let currentTime = Date()
            lastPingTime = currentTime
            
            DispatchQueue.main.async {
                self.onLoading(true)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self else { return }
                    if let lastPing = self.lastPingTime,
                       currentTime == lastPing {
                        self.onLoading(false)
                    }
                }
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
