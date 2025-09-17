-- 合并唯一物品JSON文件工具
-- 基于 Generate.lua 架构修改，适配 pob-data-forked 项目

local params = { ... }
local projectRoot = params[1] or "."

print("POB数据唯一物品合并工具")
print("项目根目录:", projectRoot)

-- 全局变量
latestTreeVersion = '0_0'
launch = {}

-- 工具函数 (参考 Generate.lua)
function copyTable(tbl, noRecurse)
    if not tbl or type(tbl) ~= "table" then 
        return tbl 
    end
    local out = {}
    for k, v in pairs(tbl) do
        if not noRecurse and type(v) == "table" then
            out[k] = copyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

function isValueInTable(tbl, val)
    for k, v in pairs(tbl) do
        if val == v then
            return k
        end
    end
end

function isValueInArray(tbl, val)
    for i, v in ipairs(tbl) do
        if val == v then
            return i
        end
    end
end

function sanitiseText(text)
    if not text then return nil end
    -- 参考 Generate.lua 的实现
    return text:find("[\128-\255<]") and text
        :gsub("%b<>", "")
        :gsub("\226\128\144", "-") -- U+2010 HYPHEN
        :gsub("\226\128\145", "-") -- U+2011 NON-BREAKING HYPHEN
        :gsub("\226\128\146", "-") -- U+2012 FIGURE DASH
        :gsub("\226\128\147", "-") -- U+2013 EN DASH
        :gsub("\226\128\148", "-") -- U+2014 EM DASH
        :gsub("\226\128\149", "-") -- U+2015 HORIZONTAL BAR
        :gsub("\226\136\146", "-") -- U+2212 MINUS SIGN
        :gsub("\195\164", "a")     -- U+00E4 LATIN SMALL LETTER A WITH DIAERESIS
        :gsub("\195\182", "o")     -- U+00F6 LATIN SMALL LETTER O WITH DIAERESIS
        -- single-byte: Windows-1252 and similar
        :gsub("\150", "-")         -- U+2013 EN DASH
        :gsub("\151", "-")         -- U+2014 EM DASH
        :gsub("\228", "a")         -- U+00E4 LATIN SMALL LETTER A WITH DIAERESIS
        :gsub("\246", "o")         -- U+00F6 LATIN SMALL LETTER O WITH DIAERESIS
        -- unsupported
        :gsub("[\128-\255]", "?")
        or text
end

function tableConcat(t1, t2)
    local t3 = {}
    for i = 1, #t1 do
        t3[#t3 + 1] = t1[i]
    end
    for i = 1, #t2 do
        t3[#t3 + 1] = t2[i]
    end
    return t3
end

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

-- 获取表的键数量
function table.keys(t)
    local keys = {}
    for k, _ in pairs(t) do
        table.insert(keys, k)
    end
    return keys
end

-- 清理函数 (参考 Generate.lua)
local function clean(map, visited, keys, jpath)
    if type(map) == 'table' then
        for k, v in pairs(map) do
            keys[k] = k
            if type(k) == "table" or type(k) == "function" then
                map[k] = nil
            elseif type(v) == 'function' then
                map[k] = nil
            elseif type(v) == 'table' then
                local seen = visited[v]
                visited[v] = jpath and jpath .. "/" .. k or true
                if seen == true then
                    map[k] = nil
                elseif seen and jpath:find(seen) then
                    -- recursive reference
                    map[k] = { ["$ref"] = seen }
                else
                    clean(v, visited, keys, jpath and jpath .. "/" .. k)
                end
            end
        end
    end
    return map
end

-- 加载 dkjson
local json = require("dkjson")

-- 函数：获取所有JSON文件路径
local function getAllJsonFiles(dir, excludePatterns)
    local files = {}
    local p = io.popen('find "' .. dir .. '" -type f -name "*.json" | sort')
    if not p then
        print("警告: 无法执行find命令，目录可能不存在:", dir)
        return files
    end
    
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
        print("错误: 无法打开文件:", filePath)
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    local data = json.decode(content)
    if not data then
        print("错误: 无法解析JSON文件:", filePath)
        return nil
    end
    
    return data
end

-- 解析单个物品字符串为结构化数据
function parseItemString(itemString)
    local lines = {}
    for line in itemString:gmatch("([^\n]+)") do
        if line:match("%S") then -- 忽略空行
            table.insert(lines, sanitiseText(line:match("^%s*(.-)%s*$"))) -- 移除前后空格并清理文本
        end
    end
    
    if #lines == 0 then return nil end
    
    local itemName = lines[1]
    local baseType = lines[2]
    
    local itemData = {
        name = itemName,
        baseType = baseType,
        stats = copyTable(lines),
        -- 结构化数据
        implicitCount = 0,
        variants = {},
        modifiers = {},
        requirements = {},
        flags = {}
    }
    
    -- 解析各种属性
    for i = 3, #lines do
        local line = lines[i]
        
        if line:match("^Implicits: (%d+)$") then
            itemData.implicitCount = tonumber(line:match("^Implicits: (%d+)$"))
        elseif line:match("^Variant: ") then
            table.insert(itemData.variants, line:sub(10))
        elseif line:match("^Source: ") then
            itemData.source = line:sub(9)
        elseif line:match("^League: ") then
            itemData.league = line:sub(8)
        elseif line:match("^Grants Skill: ") then
            itemData.grantSkill = line:sub(15)
        elseif line:match("^Requires Level ") then
            local levelReq = tonumber(line:match("^Requires Level (%d+)"))
            if levelReq then
                itemData.requirements.level = levelReq
            end
        elseif line:match("^LevelReq: ") then
            local levelReq = tonumber(line:match("^LevelReq: (%d+)"))
            if levelReq then
                itemData.requirements.level = levelReq
            end
        elseif line:match("^Upgrade: ") then
            itemData.upgrade = line:sub(10)
        elseif line:match("^Corrupted$") then
            itemData.flags.corrupted = true
        elseif line:match("^Elder Item$") then
            itemData.flags.elderItem = true
        elseif line:match("^Shaper Item$") then
            itemData.flags.shaperItem = true
        elseif line:match("^Talisman Tier: ") then
            itemData.talismanTier = tonumber(line:match("^Talisman Tier: (%d+)"))
        elseif line:match("^Has Alt Variant: ") then
            itemData.flags.hasAltVariant = line:sub(18) == "true"
        elseif line:match("^{variant:%d+}") or line:match("^{tags:") or line:match("^[%+%-]") or line:match("%%") then
            -- 这是一个修饰符
            table.insert(itemData.modifiers, line)
        end
    end
    
    return itemData
end

-- 处理单个JSON文件并转换为结构化数据
local function processUniqueFile(filePath, itemType, gameVersion, sourcePrefix)
    local rawData = readJsonFile(filePath)
    if not rawData then
        return {}
    end
    
    local processedItems = {}
    
    -- 处理数组中的每个物品字符串
    for _, itemString in ipairs(rawData) do
        if type(itemString) == "string" then
            local itemData = parseItemString(itemString)
            if itemData then
                -- 添加元数据
                itemData.itemType = itemType
                itemData.gameVersion = gameVersion
                itemData.sourcePrefix = sourcePrefix
                itemData.originalString = itemString
                
                processedItems[itemData.name] = itemData
            end
        end
    end
    
    return processedItems
end

-- 函数：合并所有唯一物品JSON数据
local function mergeUniquesJson(sourceDir, targetFile, options)
    print("开始合并唯一物品JSON数据...")
    local startTime = os.time()
    
    options = options or {}
    local prettyPrint = options.prettyPrint ~= false -- 默认为true
    local includeItemTypes = options.includeItemTypes or {}
    local excludeItemTypes = options.excludeItemTypes or {}
    local excludePatterns = options.excludePatterns or {"/Special/"}
    local gameVersion = options.gameVersion or "unknown"
    local sourcePrefix = options.sourcePrefix or ""
    
    -- 获取所有JSON文件
    local jsonFiles = getAllJsonFiles(sourceDir, excludePatterns)
    print("找到", #jsonFiles, "个JSON文件")
    
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
                print("处理", itemType, "类型的唯一物品...")
                
                -- 将物品类型添加到列表中
                if not table.contains(itemTypes, itemType) then
                    table.insert(itemTypes, itemType)
                end
                
                -- 处理文件并获取结构化数据
                local items = processUniqueFile(filePath, itemType, gameVersion, sourcePrefix)
                
                -- 添加所有物品到主表
                for itemName, itemData in pairs(items) do
                    mergedData[itemName] = itemData
                    itemCount = itemCount + 1
                end
            else
                print("跳过", itemType, "类型的唯一物品（过滤设置）")
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
    
    -- 清理数据
    local keys = {}
    clean(mergedData, {}, keys, "#")
    local keyorder = {}
    for k, _ in pairs(keys) do table.insert(keyorder, k) end
    table.sort(keyorder, function(l, r)
        if type(l) == type(r) then
            return l < r
        else
            return type(l) > type(r)
        end
    end)
    
    if prettyPrint then
        jsonOptions.keyorder = keyorder
    end
    
    local jsonStr = json.encode(mergedData, jsonOptions)
    
    -- 确保输出目录存在
    local targetDir = targetFile:match("(.+)/[^/]+$")
    if targetDir then
        os.execute("mkdir -p " .. targetDir)
    end
    
    local file = io.open(targetFile, "w")
    if not file then
        print("错误: 无法创建目标文件:", targetFile)
        return false
    end
    
    file:write(jsonStr)
    file:close()
    
    local elapsedTime = os.difftime(os.time(), startTime)
    print("\n合并完成!")
    print("合并了", itemCount, "个唯一物品数据")
    print("跳过了", skippedCount, "个物品类型")
    print("生成的文件:", targetFile)
    print("用时:", elapsedTime, "秒")
    
    return mergedData, itemCount
end

-- 主函数
local function main(...)
    local startTime = os.time()
    
    -- 配置信息
    local config = {
        -- 源目录
        poe1SourceDir = projectRoot .. "/pob-data/poe1/Uniques",
        poe2SourceDir = projectRoot .. "/pob-data/poe2/Uniques",
        
        -- 输出目录
        outputBaseDir = projectRoot .. "/merged-uniques",
        
        -- 排除模式
        excludePatterns = {"/Special/"}
    }
    
    -- 解析命令行参数
    local args = {...}
    local command = args[2] or "all" -- 默认执行all
    
    print("\n=== POB 唯一物品合并工具 ===")
    print("执行命令:", command)
    
    -- 创建输出目录
    os.execute("mkdir -p " .. config.outputBaseDir)
    os.execute("mkdir -p " .. config.outputBaseDir .. "/poe1")
    os.execute("mkdir -p " .. config.outputBaseDir .. "/poe2")
    
    if command == "merge" then
        -- 基本合并 - 单独处理每个版本
        print("\n--- 合并 POE1 数据 ---")
        mergeUniquesJson(config.poe1SourceDir, config.outputBaseDir .. "/poe1/all_uniques.json", 
            {excludePatterns = config.excludePatterns, gameVersion = "poe1", sourcePrefix = "poe1"})
        
        print("\n--- 合并 POE2 数据 ---")
        mergeUniquesJson(config.poe2SourceDir, config.outputBaseDir .. "/poe2/all_uniques.json", 
            {excludePatterns = config.excludePatterns, gameVersion = "poe2", sourcePrefix = "poe2"})
            
    elseif command == "all" then
        -- 执行基本合并
        print("\n--- 执行所有合并操作 ---")
        
        -- POE1数据处理
        local poe1Exists = io.open(config.poe1SourceDir .. "/amulet.json", "r")
        if poe1Exists then
            poe1Exists:close()
            print("\n1. 合并 POE1 数据")
            mergeUniquesJson(config.poe1SourceDir, config.outputBaseDir .. "/poe1/all_uniques.json", 
                {excludePatterns = config.excludePatterns, gameVersion = "poe1", sourcePrefix = "poe1"})
        else
            print("\n跳过 POE1 数据（不存在）")
        end
        
        -- POE2数据处理
        local poe2Exists = io.open(config.poe2SourceDir .. "/amulet.json", "r")
        if poe2Exists then
            poe2Exists:close()
            print("\n2. 合并 POE2 数据")
            mergeUniquesJson(config.poe2SourceDir, config.outputBaseDir .. "/poe2/all_uniques.json", 
                {excludePatterns = config.excludePatterns, gameVersion = "poe2", sourcePrefix = "poe2"})
        else
            print("\n跳过 POE2 数据（不存在）")
        end
        
    else
        print("未知命令:", command)
        print("可用命令: merge, all")
        return
    end
    
    local elapsedTime = os.difftime(os.time(), startTime)
    print("\n=== 合并完成 ===")
    print("总计用时:", elapsedTime, "秒")
    print("输出目录:", config.outputBaseDir)
end

-- 如果直接运行此脚本（而不是作为模块导入）
if not debug.getinfo(3) then
    main(...)
end

-- 导出函数供其他模块使用
return {
    mergeUniquesJson = mergeUniquesJson
} 