#!/bin/bash
set -e

# ========= 这里改成你本次赛马的参数 =========
ISSUE_NUM=42
TIME_STAMP="20260902_153000"
# 修改为你项目真实测试命令，例如 npm test / pytest / go test
TEST_CMD="npm test"
# ==========================================

BASE_BRANCH="dev-guo"
AGENTS=("claude" "opencode" "codex")
BEST_WT=""
BEST_SCORE=-1

echo "===== 开始评测 Issue #${ISSUE_NUM} 赛马结果 ${TIME_STAMP} ====="

for agent in "${AGENTS[@]}"; do
  WT_NAME="feat-issue${ISSUE_NUM}-${TIME_STAMP}-${agent}"
  BRANCH_NAME="feat/issue${ISSUE_NUM}-${TIME_STAMP}-${agent}"
  WT_DIR=$(orca worktree path "${WT_NAME}")
  echo
  echo "👉 Worktree: ${WT_NAME} 路径: ${WT_DIR}"

  if [ ! -d "${WT_DIR}" ];then
    echo "⚠️ worktree不存在，跳过"
    continue
  fi

  pushd "${WT_DIR}" >/dev/null
  # 执行测试，捕获返回码
  TEST_EXIT=0
  eval "${TEST_CMD}" || TEST_EXIT=$?
  popd >/dev/null

  if [ ${TEST_EXIT} -eq 0 ];then
    SCORE=100
    RESULT="✅测试全部通过"
  else
    SCORE=0
    RESULT="❌测试失败，退出码 ${TEST_EXIT}"
  fi

  echo "结果：${RESULT} 得分:${SCORE}"

  if (( SCORE > BEST_SCORE ));then
    BEST_SCORE=${SCORE}
    BEST_WT=${WT_NAME}
    BEST_BRANCH=${BRANCH_NAME}
    BEST_AGENT=${agent}
  fi
done

echo
echo "================评测总结================"
echo "测试最优 Worktree: ${BEST_WT} (agent:${BEST_AGENT})，得分${BEST_SCORE}"
echo "对应分支名：${BEST_BRANCH}"
echo "基线分支：${BASE_BRANCH}"
echo "目标PR合并分支：${BASE_BRANCH}"
echo "PR关联 Issue: #${ISSUE_NUM}"

read -p "确认要推送最优分支并创建PR吗？(y/n) " CONFIRM
if [ "${CONFIRM}" = "y" ];then
  WT_DIR=$(orca worktree path "${BEST_WT}")
  pushd "${WT_DIR}" >/dev/null
  # 获取issue标题用于PR标题
  ISSUE_TITLE=$(gh issue view ${ISSUE_NUM} --json title -q .title)
  git push origin "${BEST_BRANCH}"
  gh pr create \
    --base "${BASE_BRANCH}" \
    --head "${BEST_BRANCH}" \
    --title "feat: ${ISSUE_TITLE}" \
    --body "Closes #${ISSUE_NUM}
>由Orca赛马自动筛选测试最优方案，需要人工Review代码逻辑"
  popd >/dev/null
  echo "✅ PR已创建，请前往GitHub完成评审合并"
else
  echo "❌ 取消推送与创建PR，请人工检查代码后手动操作"
fi

