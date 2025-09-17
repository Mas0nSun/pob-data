# POB 唯一物品数据处理工具使用说明

这个项目包含了两个基于 Generate.lua 架构修改的Lua脚本，用于处理Path of Building的唯一物品数据。

## 脚本说明

### 1. export_uniques_to_json.lua
将现有的POB唯一物品JSON数据转换为结构化格式，分别处理POE1和POE2的数据。

### 2. merge_uniques.lua
合并唯一物品JSON数据，分别处理POE1和POE2数据生成各自的合并文件。

## 环境要求

- 安装了 Lua 或 LuaJIT
- 安装了 `dkjson` 库：`luarocks install dkjson`

## 使用方法

### export_uniques_to_json.lua

将项目中的唯一物品数据转换为结构化JSON格式：

```bash
# 基本用法
lua lua/export_uniques_to_json.lua .

# 或指定项目根目录
lua lua/export_uniques_to_json.lua /path/to/project
```

**功能特性：**
- 处理 `pob-data/poe1/Uniques/` 和 `pob-data/poe2/Uniques/` 目录下的JSON文件
- 解析字符串格式的物品数据为结构化字段
- 提取 variants, modifiers, requirements, flags 等信息
- 生成按物品类型分类的JSON文件
- 创建合并的总文件
- 保留原始字符串格式以保持兼容性

**输出目录结构：**
```
exported-uniques/
├── poe1/
│   ├── amulet.json
│   ├── axe.json
│   ├── ...
│   └── all_uniques.json
└── poe2/
    ├── amulet.json
    ├── belt.json
    ├── ...
    └── all_uniques.json
```

### merge_uniques.lua

合并唯一物品数据，支持多种合并模式：

```bash
# 执行所有合并操作（默认）
lua lua/merge_uniques.lua .

# 或指定具体命令
lua lua/merge_uniques.lua . [命令]
```

**可用命令：**

1. **all**（默认）- 执行所有合并操作
2. **merge** - 基本合并，分别处理POE1和POE2

**功能特性：**
- 支持POE1和POE2数据的独立处理
- 自动检测数据源的存在性
- 结构化解析物品数据
- 保持数据的完整性和一致性

**输出目录结构：**
```
merged-uniques/
├── poe1/
│   └── all_uniques.json
└── poe2/
    └── all_uniques.json
```

## 数据结构说明

转换后的JSON数据包含以下结构化字段：

```json
{
  "物品名称": {
    "name": "物品名称",
    "baseType": "基础类型",
    "itemType": "物品类型（如amulet, sword等）",
    "gameVersion": "游戏版本（poe1或poe2）",
    "sourcePrefix": "数据来源前缀",
    "stats": ["原始属性行数组"],
    "originalString": "原始字符串格式",
    "implicitCount": 0,
    "variants": ["变体信息"],
    "modifiers": ["修饰符列表"],
    "requirements": {
      "level": 等级需求
    },
    "flags": {
      "corrupted": true/false,
      "elderItem": true/false,
      "shaperItem": true/false,
      "hasAltVariant": true/false
    },
    "league": "联盟信息",
    "source": "来源信息",
    "grantSkill": "授予技能",
    "talismanTier": 护符等级,
    "upgrade": "升级信息"
  }
}
```

## 示例用法

### 导出结构化数据
```bash
# 导出POE1和POE2的结构化数据（分别处理，不合并）
lua lua/export_uniques_to_json.lua .
```

### 合并数据
```bash
# 使用merge工具进行合并操作
lua lua/merge_uniques.lua . all
```

## 处理统计

最近一次运行的结果：

**export_uniques_to_json.lua**（分别导出）：
- **POE1**: 1214个唯一物品
- **POE2**: 352个唯一物品

**merge_uniques.lua**（分别合并）：
- POE1和POE2数据将分别处理，生成各自的 all_uniques.json 文件

## 注意事项

1. 脚本会自动跳过 `Special/` 目录下的文件
2. 确保项目根目录包含 `pob-data/poe1/Uniques/` 和/或 `pob-data/poe2/Uniques/` 目录
3. 输出文件使用UTF-8编码和4空格缩进
4. 脚本会自动创建输出目录
5. 如果数据源不存在，脚本会跳过相应的处理步骤
6. POE1和POE2数据将分别处理，生成各自独立的合并文件

## 错误处理

脚本包含完善的错误处理机制：
- 自动检测数据源的存在性
- 处理JSON解析错误
- 处理文件读写错误
- 提供详细的日志信息

## 架构说明

这两个脚本都基于 `Generate.lua` 的架构：
- 使用相同的工具函数（copyTable, sanitiseText等）
- 采用相同的数据清理机制
- 使用相同的JSON输出格式和排序方式
- 保持与原项目的一致性 