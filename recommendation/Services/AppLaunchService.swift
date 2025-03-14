//
//  AppLaunchService.swift
//  recommendation
//

import UIKit

/// 应用启动结果
struct AppLaunchResult {
    let appLaunched: Bool
    let responseMessage: String
}

/// 应用启动服务
class AppLaunchService {
    // MARK: - Singleton
    static let shared = AppLaunchService()
    private init() {}
    
    // MARK: - Properties
    /// 支持的应用及其URL Scheme
    private let supportedApps: [String: (urlScheme: String, appName: String)] = [
        "QQ音乐": ("qqmusic://", "QQ音乐"),
        "网易云音乐": ("orpheuswidget://", "网易云音乐"),
        "喜马拉雅": ("iting://open", "喜马拉雅"),
    ]
    
    // MARK: - Public Methods
    /// 检查并启动应用
    /// - Parameter command: 用户输入的命令
    /// - Returns: 应用启动结果
    func checkAndLaunchApp(for command: String) -> AppLaunchResult? {
        print("检查命令是否需要唤起应用: \(command)")
        
        // 检查命令中是否包含支持的应用名称
        for (appKeyword, appInfo) in supportedApps {
            print("检查应用关键词: \(appKeyword)")
            
            if command.contains(appKeyword) {
                return handleAppLaunch(for: appInfo)
            }
        }
        
        print("没有匹配到任何应用")
        return nil
    }
    
    // MARK: - Private Methods
    private func handleAppLaunch(for appInfo: (urlScheme: String, appName: String)) -> AppLaunchResult {
        print("命令中包含应用关键词: \(appInfo.appName)")
        print("尝试启动应用: \(appInfo.appName), URL Scheme: \(appInfo.urlScheme)")
        
        guard let url = URL(string: appInfo.urlScheme) else {
            print("URL创建失败: \(appInfo.urlScheme)")
            return AppLaunchResult(
                appLaunched: false,
                responseMessage: "无法创建应用URL，请检查URL Scheme格式。"
            )
        }
        
        print("URL创建成功: \(url)")
        let canOpen = UIApplication.shared.canOpenURL(url)
        print("系统是否可以打开URL: \(canOpen)")
        
        if canOpen {
            UIApplication.shared.open(url, options: [:]) { success in
                print("应用 \(appInfo.appName) 启动\(success ? "成功" : "失败")")
            }
            return AppLaunchResult(
                appLaunched: true,
                responseMessage: "正在为您打开\(appInfo.appName)..."
            )
        } else {
            print("系统无法打开URL: \(url)")
            return AppLaunchResult(
                appLaunched: false,
                responseMessage: "您似乎没有安装\(appInfo.appName)，请先安装该应用。"
            )
        }
    }
} 