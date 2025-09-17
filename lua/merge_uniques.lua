-- 合并所有唯一物品JSON文件到一个单一文件
-- 可以独立运行，不需要重新执行转换过程
-- 基于 src/Data/merge_uniques_json.lua 修改，增加了额外功能

-- 请确保有dkjson库
-- 如果没有，请安装：luarocks install dkjson
local dkjson = require("dkjson")

-- 为Lua 5.1添加table.contains函数
if not table.contains then
    function table.contains(table, element)
        for _, value in pairs(table) do
            if value == element then
                return true
            end
        end
        return false
    end
end

-- 函数：获取所有JSON文件路径
local function getAllJsonFiles(dir, excludePatterns)
    local files = {}
    local p = io.popen('find "' .. dir .. '" -type f -name "*.json" | sort')
    for file in p:lines() do
        local shouldInclude = true
        
        -- 检查是否应该排除此文件
        if excludePatterns then
            for _, pattern in ipairs(excludePatterns) do
                if file:match(pattern) then
                    shouldInclude = false
                    break
                end
            end
        end
        
        if shouldInclude then
            table.insert(files, file)
        end
    end
    p:close()
    return files
end

-- 函数：读取JSON文件内容
local function readJsonFile(filePath)
    local file = io.open(filePath, "r")
    if not file then
        print("错误: 无法打开文件: " .. filePath)
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    local data = dkjson.decode(content)
    if not data then
        print("错误: 无法解析JSON文件: " .. filePath)
        return nil
    end
    
    return data
end

-- 函数：合并所有唯一物品JSON数据
local function mergeUniquesJson(sourceDir, targetFile, options)
    print("开始合并唯一物品JSON数据...")
    local startTime = os.time()
    
    options = options or {}
    local prettyPrint = options.prettyPrint or true
    local includeItemTypes = options.includeItemTypes or {}
    local excludeItemTypes = options.excludeItemTypes or {}
    local excludePatterns = options.excludePatterns or {"/Special/"}
    
    -- 获取所有JSON文件
    local jsonFiles = getAllJsonFiles(sourceDir, excludePatterns)
    print("找到 " .. #jsonFiles .. " 个JSON文件")
    
    -- 合并数据 - 打平成一级结构
    local mergedData = {}
    local itemTypes = {}
    local itemCount = 0
    local skippedCount = 0
    
    for _, filePath in ipairs(jsonFiles) do
        -- 提取物品类型 (如amulet, body等)
        local itemType = filePath:match("/([^/]+)%.json$")
        if itemType then
            -- 检查是否应该包含这个物品类型
            local shouldInclude = true
            
            if #includeItemTypes > 0 then
                shouldInclude = table.contains(includeItemTypes, itemType)
            end
            
            if #excludeItemTypes > 0 and table.contains(excludeItemTypes, itemType) then
                shouldInclude = false
            end
            
            if shouldInclude then
                print("处理 " .. itemType .. " 类型的唯一物品...")
                
                -- 将物品类型添加到列表中
                if not table.contains(itemTypes, itemType) then
                    table.insert(itemTypes, itemType)
                end
                
                -- 读取JSON文件
                local data = readJsonFile(filePath)
                if data then
                    -- 添加所有物品到主表，并添加物品类型属性
                    for itemName, itemData in pairs(data) do
                        -- 添加物品类型作为属性
                        itemData.itemType = itemType
                        
                        -- 检查并提取联盟信息和授予技能信息 (参考原始实现)
                        if itemData.stats then
                            for _, stat in ipairs(itemData.stats) do
                                -- 提取联盟信息
                                local leagueName = stat:match("^League: (.+)$")
                                if leagueName then
                                    itemData.league = leagueName
                                end
                                
                                -- 提取授予技能信息
                                local grantSkill = stat:match("^Grants Skill: (.+)$")
                                if grantSkill then
                                    itemData.grantSkill = grantSkill
                                end
                                
                                -- 提取等级需求信息
                                local levelReq = stat:match("^Requires Level (%d+)$")
                                if levelReq then
                                    itemData.level = tonumber(levelReq)
                                end
                            end
                        end
                        
                        -- 处理affixes，如果它们是对象格式的，将它们转换为直接文本格式
                        if itemData.affixes and type(itemData.affixes) == "table" then
                            local newAffixes = {}
                            
                            for _, affix in ipairs(itemData.affixes) do
                                if type(affix) == "table" and affix.text then
                                    local affixText = affix.text
                                    
                                    -- 检查是否有特殊处理
                                    local isLeague = affixText:match("^League: (.+)$")
                                    local isGrantSkill = affixText:match("^Grants Skill: (.+)$")
                                    local isLevelReq = affixText:match("^Requires Level (%d+)$")
                                    
                                    if isLeague then
                                        itemData.league = isLeague
                                    elseif isGrantSkill then
                                        itemData.grantSkill = isGrantSkill
                                    elseif isLevelReq then
                                        itemData.level = tonumber(isLevelReq)
                                    else
                                        -- 将对象格式转换为直接文本
                                        table.insert(newAffixes, affixText)
                                    end
                                else
                                    -- 已经是直接文本格式的
                                    table.insert(newAffixes, affix)
                                end
                            end
                            
                            -- 替换原始affixes
                            itemData.affixes = newAffixes
                        end
                        
                        -- 添加到合并数据
                        mergedData[itemName] = itemData
                        itemCount = itemCount + 1
                    end
                end
            else
                print("跳过 " .. itemType .. " 类型的唯一物品（过滤设置）")
                skippedCount = skippedCount + 1
            end
        end
    end
    
    -- 转换为JSON并写入文件
    local jsonOptions = {}
    if prettyPrint then
        jsonOptions = { 
            indent = "    ",  -- 使用4个空格作为缩进
            keyorder = nil,   -- 保持键的顺序
            level = 0         -- 起始缩进级别
        }
    end
    
    local jsonStr = dkjson.encode(mergedData, jsonOptions)
    
    -- 确保输出目录存在
    local targetDir = targetFile:match("(.+)/[^/]+$")
    if targetDir then
        os.execute("mkdir -p " .. targetDir)
    end
    
    local file = io.open(targetFile, "w")
    if not file then
        print("错误: 无法创建目标文件: " .. targetFile)
        return false
    end
    
    file:write(jsonStr)
    file:close()
    
    local elapsedTime = os.difftime(os.time(), startTime)
    print("\n合并完成!")
    print("合并了 " .. itemCount .. " 个唯一物品数据")
    print("跳过了 " .. skippedCount .. " 个物品类型")
    print("生成的文件: " .. targetFile)
    print("用时: " .. elapsedTime .. " 秒")
    
    return true
end

-- 函数：合并多个来源的唯一物品数据
local function mergeMultipleSources(sources, targetFile)
    print("开始从多个来源合并唯一物品数据...")
    local startTime = os.time()
    
    local mergedData = {}
    local totalItems = 0
    
    for _, source in ipairs(sources) do
        local sourceDir = source.dir
        local prefix = source.prefix or ""
        local excludePatterns = source.excludePatterns or {"/Special/"}
        
        print("处理来源: " .. sourceDir)
        
        local jsonFiles = getAllJsonFiles(sourceDir, excludePatterns)
        print("在 " .. sourceDir .. " 中找到 " .. #jsonFiles .. " 个JSON文件")
        
        for _, filePath in ipairs(jsonFiles) do
            local itemType = filePath:match("/([^/]+)%.json$")
            if itemType then
                print("处理 " .. itemType .. " 类型的唯一物品...")
                
                local data = readJsonFile(filePath)
                if data then
                    for itemName, itemData in pairs(data) do
                        -- 添加物品类型和来源标记
                        itemData.itemType = itemType
                        itemData.source = prefix
                        
                        -- 处理affixes，如果它们是对象格式的，将它们转换为直接文本格式
                        if itemData.affixes and type(itemData.affixes) == "table" then
                            local newAffixes = {}
                            
                            for _, affix in ipairs(itemData.affixes) do
                                if type(affix) == "table" and affix.text then
                                    -- 将对象格式转换为直接文本
                                    table.insert(newAffixes, affix.text)
                                else
                                    -- 已经是直接文本格式的
                                    table.insert(newAffixes, affix)
                                end
                            end
                            
                            -- 替换原始affixes
                            itemData.affixes = newAffixes
                        end
                        
                        -- 使用带前缀的键名，避免不同来源的同名物品冲突
                        local mergedKey = prefix ~= "" and (prefix .. ":" .. itemName) or itemName
                        mergedData[mergedKey] = itemData
                        totalItems = totalItems + 1
                    end
                end
            end
        end
    end
    
    -- 转换为JSON并写入文件
    local jsonStr = dkjson.encode(mergedData, { 
        indent = "    ",  -- 使用4个空格作为缩进
        keyorder = nil,   -- 保持键的顺序
        level = 0         -- 起始缩进级别
    })
    
    -- 确保输出目录存在
    local targetDir = targetFile:match("(.+)/[^/]+$")
    if targetDir then
        os.execute("mkdir -p " .. targetDir)
    end
    
    local file = io.open(targetFile, "w")
    if not file then
        print("错误: 无法创建目标文件: " .. targetFile)
        return false
    end
    
    file:write(jsonStr)
    file:close()
    
    local elapsedTime = os.difftime(os.time(), startTime)
    print("\n多源合并完成!")
    print("合并了 " .. totalItems .. " 个唯一物品数据")
    print("生成的文件: " .. targetFile)
    print("用时: " .. elapsedTime .. " 秒")
    
    return true
end

-- 函数：按类别分组合并唯一物品
local function mergeByCategory(sourceDir, targetDir, excludePatterns)
    print("开始按类别合并唯一物品数据...")
    local startTime = os.time()
    
    -- 定义物品类别
    local categories = {
        ["weapons"] = {"axe", "bow", "claw", "crossbow", "dagger", "flail", "mace", "sceptre", "spear", "staff", "sword", "wand"},
        ["armour"] = {"body", "boots", "gloves", "helmet", "shield"},
        ["accessories"] = {"amulet", "belt", "ring", "quiver"},
        ["other"] = {"fishing", "flask", "focus", "jewel", "soulcore", "traptool"}
    }
    
    -- 创建反向查找表
    local typeToCategory = {}
    for category, types in pairs(categories) do
        for _, itemType in ipairs(types) do
            typeToCategory[itemType] = category
        end
    end
    
    -- 按类别合并数据
    local categoryData = {}
    local totalItems = 0
    local processedFiles = 0
    
    -- 初始化类别数据
    for category, _ in pairs(categories) do
        categoryData[category] = {}
    end
    
    -- 获取所有JSON文件
    local jsonFiles = getAllJsonFiles(sourceDir, excludePatterns)
    print("找到 " .. #jsonFiles .. " 个JSON文件")
    
    for _, filePath in ipairs(jsonFiles) do
        local itemType = filePath:match("/([^/]+)%.json$")
        if itemType then
            local category = typeToCategory[itemType] or "other"
            
            print("处理 " .. itemType .. " 类型的唯一物品 (类别: " .. category .. ")")
            
            local data = readJsonFile(filePath)
            if data then
                processedFiles = processedFiles + 1
                
                for itemName, itemData in pairs(data) do
                    -- 添加物品类型
                    itemData.itemType = itemType
                    
                    -- 处理affixes，如果它们是对象格式的，将它们转换为直接文本格式
                    if itemData.affixes and type(itemData.affixes) == "table" then
                        local newAffixes = {}
                        
                        for _, affix in ipairs(itemData.affixes) do
                            if type(affix) == "table" and affix.text then
                                -- 将对象格式转换为直接文本
                                table.insert(newAffixes, affix.text)
                            else
                                -- 已经是直接文本格式的
                                table.insert(newAffixes, affix)
                            end
                        end
                        
                        -- 替换原始affixes
                        itemData.affixes = newAffixes
                    end
                    
                    -- 添加到对应类别
                    categoryData[category][itemName] = itemData
                    totalItems = totalItems + 1
                end
            end
        end
    end
    
    -- 确保输出目录存在
    os.execute("mkdir -p " .. targetDir)
    
    -- 输出每个类别的JSON文件
    for category, data in pairs(categoryData) do
        local itemCount = 0
        for _, _ in pairs(data) do
            itemCount = itemCount + 1
        end
        
        if itemCount > 0 then
            local targetFile = targetDir .. "/" .. category .. ".json"
            
            local jsonStr = dkjson.encode(data, { 
                indent = "    ",  -- 使用4个空格作为缩进
                keyorder = nil,   -- 保持键的顺序
                level = 0         -- 起始缩进级别
            })
            
            local file = io.open(targetFile, "w")
            if file then
                file:write(jsonStr)
                file:close()
                print("类别 " .. category .. " 写入了 " .. itemCount .. " 个物品到 " .. targetFile)
            else
                print("错误: 无法创建类别文件: " .. targetFile)
            end
        else
            print("类别 " .. category .. " 没有物品，跳过")
        end
    end
    
    local elapsedTime = os.difftime(os.time(), startTime)
    print("\n按类别合并完成!")
    print("共处理了 " .. processedFiles .. " 个文件")
    print("合并了 " .. totalItems .. " 个唯一物品数据")
    print("按 " .. #table.keys(categoryData) .. " 个类别分组")
    print("输出目录: " .. targetDir)
    print("用时: " .. elapsedTime .. " 秒")
    
    return true
end

-- 获取表的键数量
function table.keys(t)
    local keys = {}
    for k, _ in pairs(t) do
        table.insert(keys, k)
    end
    return keys
end

-- 主函数
local function main(...)
    -- 配置信息
    local config = {
        -- 源目录（默认）
        sourceDir = "exported-uniques/poe2",
        
        -- 输出文件（默认）
        targetFile = "merged-uniques/poe2/all_uniques.json",
        
        -- 按类别分组的输出目录
        categoryDir = "merged-uniques/poe2/categories",
        
        -- 排除模式
        excludePatterns = {"/Special/"},
        
        -- 多源合并配置
        sources = {
            { dir = "data/ExportData/Uniques", prefix = "export", excludePatterns = {"/Special/"} },
            -- 可以添加其他来源，比如：
            -- { dir = "data/Data/Uniques", prefix = "data", excludePatterns = {"/Special/"} },
        }
    }
    
    -- 解析命令行参数
    local args = {...}
    local command = args[1] or "merge"
    
    if command == "merge" then
        -- 基本合并
        mergeUniquesJson(config.sourceDir, config.targetFile, {excludePatterns = config.excludePatterns})
    elseif command == "categories" then
        -- 按类别合并
        mergeByCategory(config.sourceDir, config.categoryDir, config.excludePatterns)
    elseif command == "multi" then
        -- 多源合并
        mergeMultipleSources(config.sources, config.targetFile:gsub(".json", "_multi.json"))
    elseif command == "all" then
        -- 执行所有合并
        mergeUniquesJson(config.sourceDir, config.targetFile, {excludePatterns = config.excludePatterns})
        mergeByCategory(config.sourceDir, config.categoryDir, config.excludePatterns)
        
        -- 只有在配置了多个源时才执行多源合并
        if #config.sources > 1 then
            mergeMultipleSources(config.sources, config.targetFile:gsub(".json", "_multi.json"))
        end
    else
        print("未知命令: " .. command)
        print("可用命令: merge, categories, multi, all")
    end
end

-- 如果直接运行此脚本（而不是作为模块导入）
if not debug.getinfo(3) then
    main(...)
end

-- 导出函数供其他模块使用
return {
    mergeUniquesJson = mergeUniquesJson,
    mergeByCategory = mergeByCategory,
    mergeMultipleSources = mergeMultipleSources
} 