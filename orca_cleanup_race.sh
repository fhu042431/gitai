#!/bin/bash
# 清理赛马流水线产生的 worktree 和分支
# 用法：
#   bash orca_cleanup_race.sh                    # 交互模式：列出所有赛马 worktree，输入序号选择删除
#   bash orca_cleanup_race.sh 4                  # 删除 issue4 相关的所有赛马 worktree 和分支
#   bash orca_cleanup_race.sh feat-issue4-xxx    # 按名称前缀精确清理
set -eo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_DIR}"

# ============ 收集待清理的 worktree ============
# 赛马 worktree 命名规律：feat-issue<编号>-<时间戳>-<agent>
mapfile -t ALL_WT < <(git worktree list --porcelain | awk '$1=="worktree" && $2 ~ /feat-issue[0-9]+-/ {print $2}')

if [[ ${#ALL_WT[@]} -eq 0 ]]; then
  echo "没有找到任何赛马 worktree（feat-issue*），无需清理"
  exit 0
fi

# 根据参数过滤
FILTER="${1:-}"
TARGETS=()
if [[ -z "${FILTER}" ]]; then
  echo "========== 赛马 worktree 列表 =========="
  for i in "${!ALL_WT[@]}"; do
    echo "  [$((i+1))] ${ALL_WT[$i]}"
  done
  echo "========================================"
  read -r -p "输入要删除的序号(多个用空格分隔, all=全部): " SELECTION
  for s in ${SELECTION}; do
    if [[ "${s}" == "all" ]]; then
      TARGETS=("${ALL_WT[@]}")
      break
    fi
    if [[ "${s}" =~ ^[0-9]+$ ]] && (( s >= 1 && s <= ${#ALL_WT[@]} )); then
      TARGETS+=("${ALL_WT[$((s-1))]}")
    else
      echo "⚠️ 无效序号: ${s}，跳过"
    fi
  done
else
  for wt in "${ALL_WT[@]}"; do
    if [[ "${wt}" == *"${FILTER}"* ]]; then
      TARGETS+=("${wt}")
    fi
  done
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "没有匹配的 worktree，退出"
  exit 0
fi

echo -e "\n将删除以下 worktree 及其分支（本地+远程）:"
printf '  %s\n' "${TARGETS[@]}"
read -r -p "确认删除? (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "已取消"
  exit 0
fi

# ============ 执行删除 ============
FAILED=0
for wt_path in "${TARGETS[@]}"; do
  wt_name=$(basename "${wt_path}")
  echo -e "\n---------- 清理 ${wt_name} ----------"

  # orca 需要 Windows 风格路径（git worktree list 输出正斜杠如 C:/Users/...，orca 需 C:\Users\...）
  if command -v cygpath >/dev/null 2>&1; then
    wt_win_path=$(cygpath -w "${wt_path}" 2>/dev/null || echo "${wt_path}")
  else
    wt_win_path="${wt_path}"
  fi

  # 1.删除 worktree（优先用 orca 清理其元数据，失败则用 git）
  if orca worktree rm --worktree "path:${wt_win_path}" --force 2>/dev/null; then
    echo "✅ orca worktree rm 完成"
  else
    if git worktree remove --force "${wt_path}" 2>/dev/null; then
      echo "✅ git worktree remove 完成"
    else
      echo "⚠️ worktree 删除失败（可能已不存在），继续清理分支"
    fi
  fi

  # 2.删除本地分支
  if git show-ref --verify --quiet "refs/heads/${wt_name}"; then
    git branch -D "${wt_name}" && echo "✅ 本地分支已删除: ${wt_name}"
  else
    echo "ℹ️ 本地分支不存在: ${wt_name}"
  fi

  # 3.删除远程分支
  if git ls-remote --exit-code --heads origin "${wt_name}" >/dev/null 2>&1; then
    if git push origin --delete "${wt_name}" 2>/dev/null; then
      echo "✅ 远程分支已删除: ${wt_name}"
    else
      echo "⚠️ 远程分支删除失败: ${wt_name}"
      FAILED=1
    fi
  else
    echo "ℹ️ 远程分支不存在: ${wt_name}"
  fi
done

echo -e "\n========== 清理完成 =========="
(( FAILED == 0 )) && echo "✅ 全部成功" || echo "⚠️ 部分远程分支删除失败，请手动检查"
