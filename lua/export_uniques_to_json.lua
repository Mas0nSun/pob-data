-- 导出Export/Uniques目录下的Lua文件到JSON格式
-- 基于src/Data/lua_to_json_converter.lua修改

-- 添加缺失的copyTable函数
function copyTable(tbl)
    if type(tbl) ~= "table" then return tbl end
    local res = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            res[k] = copyTable(v)
        else
            res[k] = v
        end
    end
    return res
end

-- 请确保有dkjson库
-- 如果没有，请安装：luarocks install dkjson
local dkjson = require("dkjson")

-- 为 bit 库创建兼容层
bit = bit or {}
if not bit.band then
    bit.band = function(a, b, ...)
        local result = a & b
        for i=1, select("#", ...) do
            result = result & select(i, ...)
        end
        return result
    end
end
if not bit.bor then
    bit.bor = function(a, b, ...)
        local result = a | b
        for i=1, select("#", ...) do
            result = result | select(i, ...)
        end
        return result
    end
end
if not bit.bxor then
    bit.bxor = function(a, b, ...)
        local result = a ~ b
        for i=1, select("#", ...) do
            result = result ~ select(i, ...)
        end
        return result
    end
end
if not bit.bnot then
    bit.bnot = function(a)
        return ~a
    end
end
if not bit.lshift then
    bit.lshift = function(a, b)
        return a << b
    end
end
if not bit.rshift then
    bit.rshift = function(a, b)
        return a >> b
    end
end
if not bit.tobit then
    bit.tobit = function(a)
        return a & 0xFFFFFFFF
    end
end

-- 处理不兼容JSON的数据类型
function sanitizeForJSON(data)
    if type(data) ~= "table" then
        -- 如果是函数、userdata等不支持的类型，返回字符串描述
        if type(data) == "function" then
            return "<function>"
        elseif type(data) == "userdata" then
            return "<userdata>"
        elseif type(data) == "thread" then
            return "<thread>"
        else
            return data
        end
    end
    
    local result = {}
    for k, v in pairs(data) do
        -- 处理表中的值
        if type(v) == "table" then
            result[k] = sanitizeForJSON(v)
        elseif type(v) == "function" then
            result[k] = "<function>"
        elseif type(v) == "userdata" then
            result[k] = "<userdata>"
        elseif type(v) == "thread" then
            result[k] = "<thread>"
        else
            result[k] = v
        end
        
        -- 处理表中的键
        if type(k) == "function" or type(k) == "userdata" or type(k) == "thread" then
            result["<"..type(k)..">"] = result[k]
            result[k] = nil
        end
    end
    
    return result
end

-- 函数: 将Lua文件转换为JSON文件
function convertLuaToJson(luaFilePath, jsonFilePath)
    -- 检查是否是Uniques目录下的文件
    local isUniquesFile = luaFilePath:match("/Uniques/") ~= nil
    
    -- 加载Lua文件并执行它，获取返回的表
    local chunk, err = loadfile(luaFilePath)
    if not chunk then
        print("错误: 无法加载Lua文件: " .. err)
        return false
    end
    
    -- 执行Lua文件，获取返回的表
    local success, luaTable
    success, luaTable = pcall(function()
        return chunk()
    end)

    if not success then
        print("错误: 执行Lua文件时出错: " .. luaFilePath .. " - " .. tostring(luaTable))
        return false
    end

    if not luaTable then
        print("警告: Lua文件没有返回任何数据: " .. luaFilePath)
        return false
    end
    
    local jsonString
    
    -- 特殊处理Uniques目录下的文件
    if isUniquesFile then
        -- 为Uniques创建一个更有结构的表
        local structuredTable = {}
        
        -- 检查luaTable是否是数组
        if type(luaTable) == "table" and #luaTable > 0 then
            -- 它是一个数组，遍历每个元素
            for _, itemData in ipairs(luaTable) do
                if type(itemData) == "string" then
                    -- 第一行是物品名称
                    local lines = {}
                    for line in itemData:gmatch("([^\n]+)") do
                        if line:match("%S") then -- 忽略空行
                            table.insert(lines, line:match("^%s*(.-)%s*$")) -- 移除前后空格
                        end
                    end
                    
                    if #lines > 0 then
                        local itemName = lines[1]
                        local baseType = lines[2]
                        
                        structuredTable[itemName] = {
                            baseType = baseType,
                            stats = {}
                        }
                        
                        -- 进一步解析属性
                        local implicitCount = 0
                        local variants = {}
                        local source = nil
                        local affixes = {}
                        -- 用于保存每个属性的最新变体版本
                        local variantModsMap = {}
                        
                        for i = 3, #lines do
                            local line = lines[i]
                            
                            if line:match("^Implicits: (%d+)$") then
                                implicitCount = tonumber(line:match("^Implicits: (%d+)$"))
                                structuredTable[itemName].implicitCount = implicitCount
                            elseif line:match("^Variant: ") then
                                table.insert(variants, line:sub(10))
                            elseif line:match("^Source: ") then
                                source = line:sub(9)
                                structuredTable[itemName].source = source
                            elseif line:match("^League: ") then
                                -- 提取联盟信息作为单独字段
                                structuredTable[itemName].league = line:sub(8)
                            elseif line:match("^Grants Skill: ") then
                                -- 提取技能信息作为单独字段
                                structuredTable[itemName].grantSkill = line:sub(14)
                            elseif line:match("^Requires Level ") then
                                -- 提取等级需求作为单独字段
                                local levelReq = tonumber(line:match("^Requires Level (%d+)"))
                                if levelReq then
                                    structuredTable[itemName].level = levelReq
                                end
                            elseif line:match("^{variant:%d+}") then
                                local variantNum = tonumber(line:match("{variant:(%d+)}"))
                                local modText = line:gsub("{variant:%d+}", ""):match("^%s*(.-)%s*$") -- 移除variant前缀和前后空格
                                
                                -- 计算mod的唯一标识（去除值部分）
                                local modKey = modText:gsub("%[.-%]", "")
                                
                                -- 更新到最新的变体版本
                                if not variantModsMap[modKey] or variantModsMap[modKey].variant < variantNum then
                                    variantModsMap[modKey] = {
                                        text = modText,
                                        variant = variantNum
                                    }
                                end
                            else
                                -- 添加其他属性到affixes，直接作为文本
                                table.insert(affixes, line)
                            end
                        end
                        
                        -- 将variant中保存的最新版本添加到affixes
                        for _, modInfo in pairs(variantModsMap) do
                            table.insert(affixes, modInfo.text)
                        end
                        
                        if #variants > 0 then
                            structuredTable[itemName].variants = variants
                        end
                        
                        if #affixes > 0 then
                            structuredTable[itemName].affixes = affixes
                        end
                        
                        -- 保留原始stats供兼容性
                        structuredTable[itemName].stats = lines
                    end
                end
            end
        else
            -- 已经是对象格式，按之前的逻辑处理
            for itemName, itemData in pairs(luaTable) do
                -- 如果是字符串，则尝试解析
                if type(itemData) == "string" then
                    local baseType = itemData:match("^([^\n]+)")
                    if baseType then
                        structuredTable[itemName] = {
                            baseType = baseType,
                            stats = {}
                        }
                        
                        -- 提取所有属性行
                        local statsText = itemData:sub(#baseType + 1)
                        local lines = {}
                        for line in statsText:gmatch("([^\n]+)") do
                            if line:match("%S") then -- 忽略空行
                                table.insert(lines, line:match("^%s*(.-)%s*$")) -- 移除前后空格
                            end
                        end
                        
                        -- 进一步解析属性
                        local implicitCount = 0
                        local variants = {}
                        local source = nil
                        local affixes = {}
                        -- 用于保存每个属性的最新变体版本
                        local variantModsMap = {}
                        
                        for _, line in ipairs(lines) do
                            if line:match("^Implicits: (%d+)$") then
                                implicitCount = tonumber(line:match("^Implicits: (%d+)$"))
                                structuredTable[itemName].implicitCount = implicitCount
                            elseif line:match("^Variant: ") then
                                table.insert(variants, line:sub(10))
                            elseif line:match("^Source: ") then
                                source = line:sub(9)
                                structuredTable[itemName].source = source
                            elseif line:match("^League: ") then
                                -- 提取联盟信息作为单独字段
                                structuredTable[itemName].league = line:sub(8)
                            elseif line:match("^Grants Skill: ") then
                                -- 提取技能信息作为单独字段
                                structuredTable[itemName].grantSkill = line:sub(14)
                            elseif line:match("^Requires Level ") then
                                -- 提取等级需求作为单独字段
                                local levelReq = tonumber(line:match("^Requires Level (%d+)"))
                                if levelReq then
                                    structuredTable[itemName].level = levelReq
                                end
                            elseif line:match("^{variant:%d+}") then
                                local variantNum = tonumber(line:match("{variant:(%d+)}"))
                                local modText = line:gsub("{variant:%d+}", ""):match("^%s*(.-)%s*$") -- 移除variant前缀和前后空格
                                
                                -- 计算mod的唯一标识（去除值部分）
                                local modKey = modText:gsub("%[.-%]", "")
                                
                                -- 更新到最新的变体版本
                                if not variantModsMap[modKey] or variantModsMap[modKey].variant < variantNum then
                                    variantModsMap[modKey] = {
                                        text = modText,
                                        variant = variantNum
                                    }
                                end
                            else
                                -- 添加其他属性到affixes，直接作为文本
                                table.insert(affixes, line)
                            end
                        end
                        
                        -- 将variant中保存的最新版本添加到affixes
                        for _, modInfo in pairs(variantModsMap) do
                            table.insert(affixes, modInfo.text)
                        end
                        
                        if #variants > 0 then
                            structuredTable[itemName].variants = variants
                        end
                        
                        if #affixes > 0 then
                            structuredTable[itemName].affixes = affixes
                        end
                        
                        -- 保留原始stats供兼容性
                        structuredTable[itemName].stats = lines
                    end
                else
                    structuredTable[itemName] = itemData
                end
            end
        end
        
        -- 预处理数据，处理函数等不支持的类型
        local sanitizedTable = sanitizeForJSON(structuredTable)
        
        -- 将结构化表转换为JSON
        jsonString = dkjson.encode(sanitizedTable, { 
            indent = "    ",  -- 使用4个空格作为缩进
            keyorder = nil,   -- 保持键的顺序
            level = 0         -- 起始缩进级别
        })
    else
        -- 预处理数据，处理函数等不支持的类型
        local sanitizedTable = sanitizeForJSON(luaTable)
        
        -- 将Lua表转换为JSON，使用缩进设置
        jsonString = dkjson.encode(sanitizedTable, { 
            indent = "    ",  -- 使用4个空格作为缩进
            keyorder = nil,   -- 保持键的顺序
            level = 0         -- 起始缩进级别
        })
    end
    
    if not jsonString then
        print("错误: 无法将Lua表转换为JSON: " .. luaFilePath)
        return false
    end
    
    -- 确保输出目录存在
    local jsonFileDir = jsonFilePath:match("(.+)/[^/]+$")
    if jsonFileDir then
        os.execute("mkdir -p " .. jsonFileDir)
    end
    
    -- 写入JSON文件
    local file = io.open(jsonFilePath, "w")
    if not file then
        print("错误: 无法打开JSON文件进行写入: " .. jsonFilePath)
        return false
    end
    
    file:write(jsonString)
    file:close()
    
    return true
end

-- 函数: 批量转换目录中所有Lua文件
function convertDirectory(luaDir, jsonDir)
    -- 确保输出目录存在
    os.execute("mkdir -p " .. jsonDir)
    
    -- 获取Lua目录中的所有文件
    local files = {}
    local p = io.popen('find "' .. luaDir .. '" -type f -name "*.lua" | sort')
    for file in p:lines() do
        table.insert(files, file)
    end
    p:close()
    
    print("找到 " .. #files .. " 个Lua文件")
    
    -- 转换每个文件
    local convertedCount = 0
    local failedCount = 0
    local startTime = os.time()
    
    for i, luaFile in ipairs(files) do
        local relativePath = luaFile:sub(#luaDir + 2) -- 移除luaDir前缀
        local jsonFile = jsonDir .. "/" .. relativePath:gsub("%.lua$", ".json")
        
        -- 确保输出目录存在
        local jsonFileDir = jsonFile:match("(.+)/[^/]+$")
        if jsonFileDir then
            os.execute("mkdir -p " .. jsonFileDir)
        end
        
        print("转换中 [" .. i .. "/" .. #files .. "]: " .. luaFile .. " → " .. jsonFile)
        if convertLuaToJson(luaFile, jsonFile) then
            convertedCount = convertedCount + 1
        else
            failedCount = failedCount + 1
        end
    end
    
    print("\n转换完成!")
    print("总计: " .. #files .. " 个文件")
    print("成功: " .. convertedCount .. " 个文件")
    print("失败: " .. failedCount .. " 个文件")
    print("用时: " .. (os.time() - startTime) .. " 秒")
    
    return convertedCount, failedCount
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

-- 合并所有唯一物品JSON数据
function mergeUniquesJson(sourceDir, targetFile)
    print("开始合并唯一物品JSON数据...")
    local startTime = os.time()
    
    -- 获取所有JSON文件
    local jsonFiles = {}
    local p = io.popen('find "' .. sourceDir .. '" -type f -name "*.json" | sort')
    for file in p:lines() do
        table.insert(jsonFiles, file)
    end
    p:close()
    
    print("找到 " .. #jsonFiles .. " 个JSON文件")
    
    -- 合并数据 - 打平成一级结构
    local mergedData = {}
    local itemTypes = {}
    local itemCount = 0
    
    for _, filePath in ipairs(jsonFiles) do
        -- 提取物品类型 (如amulet, body等)
        local itemType = filePath:match("/([^/]+)%.json$")
        if itemType then
            print("处理 " .. itemType .. " 类型的唯一物品...")
            
            -- 将物品类型添加到列表中
            if not table.contains(itemTypes, itemType) then
                table.insert(itemTypes, itemType)
            end
            
            -- 读取JSON文件
            local file = io.open(filePath, "r")
            if not file then
                print("错误: 无法打开文件: " .. filePath)
                goto continue
            end
            
            local content = file:read("*all")
            file:close()
            
            local data = dkjson.decode(content)
            if not data then
                print("错误: 无法解析JSON文件: " .. filePath)
                goto continue
            end
            
            -- 添加所有物品到主表，并添加物品类型属性
            for itemName, itemData in pairs(data) do
                -- 添加物品类型作为属性
                itemData.itemType = itemType
                
                -- 添加到合并数据
                mergedData[itemName] = itemData
                itemCount = itemCount + 1
            end
            
            ::continue::
        end
    end
    
    -- 转换为JSON并写入文件
    local jsonStr = dkjson.encode(mergedData, { 
        indent = "    ",  -- 使用4个空格作为缩进
        keyorder = nil,   -- 保持键的顺序
        level = 0         -- 起始缩进级别
    })
    
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
    print("生成的文件: " .. targetFile)
    print("用时: " .. elapsedTime .. " 秒")
    
    return true
end

-- 主函数 - 适配 pob-data-forked 项目结构
local function main(...)
    local params = { ... }
    local projectRoot = params[1] or "."
    
    print("\n=== POB 唯一物品数据导出工具 ===")
    print("项目根目录:", projectRoot)
    
    local startTime = os.time()
    
    -- 配置路径 - 处理从 PathOfBuilding 克隆的 Lua 文件
    local poe1SourceDir = projectRoot .. "/PathOfBuilding/src/Export/Uniques"
    local poe2SourceDir = projectRoot .. "/PathOfBuilding2/src/Export/Uniques"
    local outputBaseDir = projectRoot .. "/exported-uniques"
    
    local poe1OutputDir = outputBaseDir .. "/poe1"
    local poe2OutputDir = outputBaseDir .. "/poe2"
    
    -- 创建输出目录
    os.execute("mkdir -p " .. poe1OutputDir)
    os.execute("mkdir -p " .. poe2OutputDir)
    
    local poe1Items, poe1Count = {}, 0
    local poe2Items, poe2Count = {}, 0
    
    -- 处理 POE1 数据
    local poe1SourceExists = io.open(poe1SourceDir .. "/amulet.lua", "r")
    if poe1SourceExists then
        poe1SourceExists:close()
        print("\n--- 处理 Path of Exile 1 数据 ---")
        poe1Count, _ = convertDirectory(poe1SourceDir, poe1OutputDir)
        -- 合并 POE1 数据
        mergeUniquesJson(poe1OutputDir, poe1OutputDir .. "/all_uniques.json")
    else
        print("\n--- Path of Exile 1 数据不存在，跳过 ---")
    end
    
    -- 处理 POE2 数据
    local poe2SourceExists = io.open(poe2SourceDir .. "/amulet.lua", "r")
    if poe2SourceExists then
        poe2SourceExists:close()
        print("\n--- 处理 Path of Exile 2 数据 ---")
        poe2Count, _ = convertDirectory(poe2SourceDir, poe2OutputDir)
        -- 合并 POE2 数据
        mergeUniquesJson(poe2OutputDir, poe2OutputDir .. "/all_uniques.json")
    else
        print("\n--- Path of Exile 2 数据不存在，跳过 ---")
    end
    
    local elapsedTime = os.difftime(os.time(), startTime)
    print("\n=== 导出完成 ===")
    print("总计用时:", elapsedTime, "秒")
    print("POE1 物品数:", poe1Count)
    print("POE2 物品数:", poe2Count)
    print("输出目录:", outputBaseDir)
end

-- 执行主函数
main(...) 