-- 导出唯一物品数据到结构化JSON格式
-- 基于 Generate.lua 架构修改，适配 pob-data-forked 项目

local params = { ... }
local projectRoot = params[1] or "."

print("POB数据唯一物品导出工具")
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

-- 处理单个JSON文件
function processUniqueFile(filePath, itemType, gameVersion)
    print("处理文件:", filePath)
    
    local file = io.open(filePath, "r")
    if not file then
        print("错误: 无法打开文件:", filePath)
        return {}
    end
    
    local content = file:read("*all")
    file:close()
    
    local rawData = json.decode(content)
    if not rawData then
        print("错误: 无法解析JSON文件:", filePath)
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
                itemData.originalString = itemString
                
                processedItems[itemData.name] = itemData
            end
        end
    end
    
    return processedItems
end

-- 批量处理目录
function processUniquesDirectory(sourceDir, outputDir, gameVersion)
    print("开始处理 " .. gameVersion .. " 唯一物品目录:", sourceDir)
    
    -- 确保输出目录存在
    os.execute("mkdir -p " .. outputDir)
    
    -- 获取所有JSON文件
    local files = {}
    local p = io.popen('find "' .. sourceDir .. '" -name "*.json" -not -path "*/Special/*" | sort')
    for file in p:lines() do
        table.insert(files, file)
    end
    p:close()
    
    print("找到", #files, "个唯一物品文件")
    
    local allItems = {}
    local totalItems = 0
    local processedFiles = 0
    
    for _, filePath in ipairs(files) do
        local itemType = filePath:match("/([^/]+)%.json$")
        if itemType then
            local items = processUniqueFile(filePath, itemType, gameVersion)
            
            -- 添加到总表
            for itemName, itemData in pairs(items) do
                allItems[itemName] = itemData
                totalItems = totalItems + 1
            end
            
            -- 单独保存每种类型的文件
            if next(items) then
                local keys = {}
                clean(items, {}, keys, "#")
                local keyorder = {}
                for k, _ in pairs(keys) do table.insert(keyorder, k) end
                table.sort(keyorder, function(l, r)
                    if type(l) == type(r) then
                        return l < r
                    else
                        return type(l) > type(r)
                    end
                end)
                
                local typeOutputFile = outputDir .. "/" .. itemType .. ".json"
                local outFile = io.open(typeOutputFile, "w")
                if outFile then
                    outFile:write(json.encode(items, { indent = true, keyorder = keyorder }))
                    outFile:close()
                    print("已导出", itemType, ":", #table.keys(items), "个物品")
                end
            end
            
            processedFiles = processedFiles + 1
        end
    end
    
    -- 保存合并的文件
    if next(allItems) then
        local keys = {}
        clean(allItems, {}, keys, "#")
        local keyorder = {}
        for k, _ in pairs(keys) do table.insert(keyorder, k) end
        table.sort(keyorder, function(l, r)
            if type(l) == type(r) then
                return l < r
            else
                return type(l) > type(r)
            end
        end)
        
        local allOutputFile = outputDir .. "/all_uniques.json"
        local outFile = io.open(allOutputFile, "w")
        if outFile then
            outFile:write(json.encode(allItems, { indent = true, keyorder = keyorder }))
            outFile:close()
        end
    end
    
    print("处理完成:")
    print("- 处理了", processedFiles, "个文件")
    print("- 总共", totalItems, "个唯一物品")
    print("- 输出目录:", outputDir)
    
    return allItems, totalItems
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
local function main()
    local startTime = os.time()
    
    print("\n=== POB 唯一物品数据导出工具 ===")
    
    -- 配置路径
    local poe1SourceDir = projectRoot .. "/pob-data/poe1/Uniques"
    local poe2SourceDir = projectRoot .. "/pob-data/poe2/Uniques"
    local outputBaseDir = projectRoot .. "/exported-uniques"
    
    local poe1OutputDir = outputBaseDir .. "/poe1"
    local poe2OutputDir = outputBaseDir .. "/poe2"
    
    -- 创建输出目录
    os.execute("mkdir -p " .. poe1OutputDir)
    os.execute("mkdir -p " .. poe2OutputDir)
    
    local poe1Items, poe1Count = {}, 0
    local poe2Items, poe2Count = {}, 0
    
    -- 处理 POE1 数据
    local poe1SourceExists = io.open(poe1SourceDir .. "/amulet.json", "r")
    if poe1SourceExists then
        poe1SourceExists:close()
        print("\n--- 处理 Path of Exile 1 数据 ---")
        poe1Items, poe1Count = processUniquesDirectory(poe1SourceDir, poe1OutputDir, "poe1")
    else
        print("\n--- Path of Exile 1 数据不存在，跳过 ---")
    end
    
    -- 处理 POE2 数据
    local poe2SourceExists = io.open(poe2SourceDir .. "/amulet.json", "r")
    if poe2SourceExists then
        poe2SourceExists:close()
        print("\n--- 处理 Path of Exile 2 数据 ---")
        poe2Items, poe2Count = processUniquesDirectory(poe2SourceDir, poe2OutputDir, "poe2")
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
main() 