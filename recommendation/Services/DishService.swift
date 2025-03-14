class DishService {
    static let shared = DishService()
    
    private var dishes: [Dish] = [
        Dish(name: "西红柿炒鸡蛋", purineContent: 38.5, 
             taste: ["清淡", "酸甜"], 
             mood: ["疲惫", "平静"], 
             category: "炒菜"),
        Dish(name: "青椒土豆丝", purineContent: 25.0, 
             taste: ["清淡", "微辣"], 
             mood: ["平静", "日常"], 
             category: "炒菜"),
        // ... 添加更多菜品数据
    ]
    
    // 根据条件筛选推荐菜品
    func recommendDishes(userPreference: [String: Any]) -> [Dish] {
        // 获取用户偏好
        let preferredTaste = userPreference["taste"] as? [String] ?? []
        let currentMood = userPreference["mood"] as? String ?? ""
        
        // 筛选符合条件的菜品
        let recommendedDishes = dishes.filter { dish in
            // 嘌呤含量必须小于300
            guard dish.purineContent < 300 else { return false }
            
            // 计算口味匹配度
            let tasteMatch = !preferredTaste.isEmpty ? 
                preferredTaste.contains(where: { dish.taste.contains($0) }) : true
            
            // 计算心情匹配度
            let moodMatch = !currentMood.isEmpty ? 
                dish.mood.contains(currentMood) : true
            
            return tasteMatch && moodMatch
        }
        
        // 按嘌呤含量排序
        return recommendedDishes.sorted { $0.purineContent < $1.purineContent }
    }
    
    // 格式化推荐结果
    func formatRecommendations(_ dishes: [Dish]) -> String {
        guard !dishes.isEmpty else {
            return "抱歉，没有找到符合条件的推荐菜品。"
        }
        
        var result = "为您推荐以下菜品：\n\n"
        for (index, dish) in dishes.prefix(5).enumerated() {
            result += "\(index + 1). \(dish.name)\n"
            result += "   口味：\(dish.taste.joined(separator: "、"))\n"
            result += "   嘌呤含量：\(String(format: "%.1f", dish.purineContent))mg/100g\n"
            if index < dishes.prefix(5).count - 1 {
                result += "\n"
            }
        }
        return result
    }
} 