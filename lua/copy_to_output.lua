-- 将 pob-data/poe2 中的指定文件 copy 到 output/，并按约定重命名
-- 用法: lua lua/copy_to_output.lua [projectRoot]
--
-- 注意: macOS 默认大小写不敏感，Essence.json 与 essence.json 是同一路径，
-- 因此通过临时文件中转，避免“清理旧名”误删新文件。

local function fileExists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function copyFile(src, dst)
    local input = io.open(src, "rb")
    if not input then
        return false, "无法读取源文件: " .. src
    end

    local content = input:read("*all")
    input:close()

    local targetDir = dst:match("(.+)/[^/]+$")
    if targetDir then
        os.execute('mkdir -p "' .. targetDir .. '"')
    end

    local output = io.open(dst, "wb")
    if not output then
        return false, "无法写入目标文件: " .. dst
    end

    output:write(content)
    output:close()
    return true
end

local function main(...)
    local params = { ... }
    local projectRoot = params[1] or "."

    local sourceDir = projectRoot .. "/pob-data/poe2"
    local outputDir = projectRoot .. "/output"

    -- 源文件名 -> output 下目标文件名
    local files = {
        { src = "Essence.json", dst = "essence.json" },
        { src = "ModCorrupted.json", dst = "mod_corrupted.json" },
        { src = "ModJewel.json", dst = "mod_jewel.json" },
        { src = "ModMap.json", dst = "mod_map.json" },
    }

    print("\n=== 复制文件到 output ===")
    print("源目录:", sourceDir)
    print("目标目录:", outputDir)

    os.execute('mkdir -p "' .. outputDir .. '"')

    local okCount = 0
    local failCount = 0

    for _, item in ipairs(files) do
        local srcPath = sourceDir .. "/" .. item.src
        local dstPath = outputDir .. "/" .. item.dst
        local tmpPath = outputDir .. "/." .. item.dst .. ".tmp"

        if not fileExists(srcPath) then
            print("跳过（源文件不存在）:", srcPath)
            failCount = failCount + 1
        else
            local ok, err = copyFile(srcPath, tmpPath)
            if not ok then
                print("失败:", err)
                failCount = failCount + 1
            else
                -- 删除可能存在的旧大小写变体，再原子改名为目标名
                os.remove(dstPath)
                if item.src:lower() ~= item.dst:lower() or item.src ~= item.dst then
                    os.remove(outputDir .. "/" .. item.src)
                end

                local renamed, renameErr = os.rename(tmpPath, dstPath)
                if not renamed then
                    -- 部分 FS 上同 inode 大小写 rename 会失败，回退为再写一次
                    local ok2, err2 = copyFile(tmpPath, dstPath)
                    os.remove(tmpPath)
                    if not ok2 then
                        print("失败: 无法落地", item.dst, renameErr or err2)
                        failCount = failCount + 1
                    else
                        print("复制:", item.src, "->", item.dst)
                        okCount = okCount + 1
                    end
                else
                    print("复制:", item.src, "->", item.dst)
                    okCount = okCount + 1
                end
            end
        end
    end

    print("\n完成: 成功", okCount, "失败", failCount)
    return failCount == 0
end

main(...)
