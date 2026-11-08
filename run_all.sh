#!/usr/bin/env bash
# 一键流水线：拉取远端 → Generate → export/merge uniques → copy output
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "${ROOT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

# Generate.lua / PoB Data 依赖 luajit 内置 bit；dkjson 可能装在 Lua 5.4 路径下
# 把常见 luarocks 路径注入 LUA_PATH，让 luajit 也能加载纯 Lua 的 dkjson
export LUA_PATH="${LUA_PATH:-}./?.lua;/opt/homebrew/share/lua/5.4/?.lua;/opt/homebrew/share/lua/5.4/?/init.lua;/usr/local/share/lua/5.4/?.lua;/opt/homebrew/share/lua/5.1/?.lua;/usr/local/share/lua/5.1/?.lua;;"

LUA_BIN="${LUA_BIN:-}"
if [[ -z "${LUA_BIN}" ]]; then
  # 优先 luajit（bit），其次 lua
  for candidate in luajit lua; do
    if command -v "${candidate}" >/dev/null 2>&1 \
      && "${candidate}" -e 'require("dkjson")' >/dev/null 2>&1; then
      LUA_BIN="${candidate}"
      break
    fi
  done
fi
if [[ -z "${LUA_BIN}" ]]; then
  echo "错误: 未找到可用的 lua/luajit（需要能 require('dkjson')）"
  echo "可先执行: luarocks install dkjson"
  exit 1
fi
echo "使用 Lua 解释器: ${LUA_BIN} ($(command -v "${LUA_BIN}"))"

log() {
  printf '\n==> %s\n' "$*"
}

resolve_pob_dir() {
  local name="$1"
  shift
  local candidate
  for candidate in "$@"; do
    if [[ -d "${candidate}/src/Data" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

git_fetch_pull() {
  local repo_dir="$1"
  local label="$2"

  if [[ ! -d "${repo_dir}/.git" ]]; then
    echo "跳过 ${label}: 不是 git 仓库 (${repo_dir})"
    return 0
  fi

  log "git fetch & pull: ${label} (${repo_dir})"
  git -C "${repo_dir}" fetch --all --prune
  # 优先 pull 当前跟踪分支；失败时仍继续后续步骤
  if ! git -C "${repo_dir}" pull --ff-only; then
    echo "警告: ${label} pull --ff-only 失败，继续使用本地代码"
  fi
}

run_generate() {
  local pob_dir="$1"
  local out_dir="$2"
  local label="$3"

  if [[ -z "${pob_dir}" || ! -d "${pob_dir}/src/Data" ]]; then
    echo "跳过 Generate (${label}): 源目录不存在"
    return 0
  fi

  # Generate.lua 用 require(path .. ".src....")，必须传相对路径，且 cwd 要能找到该相对根目录
  local work_root
  work_root="$(cd "${pob_dir}/.." && pwd)"
  local pob_rel out_rel gen_rel
  pob_rel="$(python3 -c "import os.path; print(os.path.relpath('${pob_dir}', '${work_root}'))")"
  out_rel="$(python3 -c "import os.path; print(os.path.relpath('${out_dir}', '${work_root}'))")"
  gen_rel="$(python3 -c "import os.path; print(os.path.relpath('${ROOT_DIR}/lua/Generate.lua', '${work_root}'))")"

  log "Generate.lua → ${label} (${pob_rel} → ${out_rel}, cwd=${work_root})"
  mkdir -p "${out_dir}"
  find "${pob_dir}/src/Data" -type d \
    | sed "s|${pob_dir}/src/Data|${out_dir}|g" \
    | while read -r dir; do
        mkdir -p "${dir}"
      done

  local ok=0
  local fail=0
  local lua_file rel_lua
  while IFS= read -r -d '' lua_file; do
    rel_lua="$(python3 -c "import os.path; print(os.path.relpath('${lua_file}', '${work_root}'))")"
    if (
      cd "${work_root}"
      "${LUA_BIN}" "${gen_rel}" "${rel_lua}" "${out_rel}/"
    ); then
      ok=$((ok + 1))
    else
      echo "警告: Generate 失败: ${rel_lua}"
      fail=$((fail + 1))
    fi
  done < <(find "${pob_dir}/src/Data" -name '*.lua' -print0)

  echo "Generate (${label}) 完成: 成功 ${ok}, 失败 ${fail}"
}

# ---------- 1. fetch & pull ----------
log "拉取远端代码"
git_fetch_pull "${ROOT_DIR}" "pob-data"

POE1_DIR="$(resolve_pob_dir poe1 \
  "${PARENT_DIR}/PathOfBuilding" \
  "${ROOT_DIR}/PathOfBuilding" \
  || true)"
POE2_DIR="$(resolve_pob_dir poe2 \
  "${PARENT_DIR}/PathOfBuilding-PoE2" \
  "${PARENT_DIR}/PathOfBuilding2" \
  "${ROOT_DIR}/PathOfBuilding2" \
  "${ROOT_DIR}/PathOfBuilding-PoE2" \
  || true)"

if [[ -n "${POE1_DIR}" ]]; then
  git_fetch_pull "${POE1_DIR}" "PathOfBuilding"
else
  echo "未找到 PathOfBuilding，跳过 POE1"
fi

if [[ -n "${POE2_DIR}" ]]; then
  git_fetch_pull "${POE2_DIR}" "PathOfBuilding-PoE2"
else
  echo "未找到 PathOfBuilding-PoE2 / PathOfBuilding2，跳过 POE2"
fi

# ---------- 2. Generate.lua ----------
run_generate "${POE1_DIR:-}" "${ROOT_DIR}/pob-data/poe1" "poe1"
run_generate "${POE2_DIR:-}" "${ROOT_DIR}/pob-data/poe2" "poe2"

# ---------- 3. export / merge uniques ----------
log "export_uniques_to_json.lua"
"${LUA_BIN}" "${ROOT_DIR}/lua/export_uniques_to_json.lua" "${ROOT_DIR}"

log "merge_uniques.lua"
"${LUA_BIN}" "${ROOT_DIR}/lua/merge_uniques.lua" merge

# ---------- 4. copy & rename 到 output ----------
log "copy_to_output.lua"
"${LUA_BIN}" "${ROOT_DIR}/lua/copy_to_output.lua" "${ROOT_DIR}"

log "全部完成"
ls -lh "${ROOT_DIR}/output"
