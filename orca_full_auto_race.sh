#!/bin/bash
set -eo pipefail

BASE_BRANCH="dev-guo"

# 1.输入参数
read -p "输入GitHub Issue编号(数字): " ISSUE_NUM
read -p "项目技术栈(如 Vue3+TS / Go / Python FastAPI): " TECH_STACK

# 拉取issue信息
ISSUE_TITLE=$(gh issue view "${ISSUE_NUM}" --json title -q .title)
ISSUE_BODY=$(gh issue view "${ISSUE_NUM}" --json body -q .body)
ISSUE_FULL="【${ISSUE_TITLE}】
${ISSUE_BODY}"

TIME_STAMP=$(date +%Y%m%d_%H%M%S)
AGENTS=( "opencode" )

# ===================== Prompt：要求AI开发功能 + 自行编写测试代码并自测 =====================
PROMPT="#任务说明
基线分支：${BASE_BRANCH}
需求：
${ISSUE_FULL}

技术栈：${TECH_STACK}

硬性约束：
1.基于dev‑guo实现需求，最小变更，不要大范围重构无关代码，不新增不必要第三方依赖。
2.实现业务代码，**同时编写完整单元测试用例**覆盖正常场景、边界、异常输入。
3.你需要输出可直接运行的测试代码，写完代码后**在当前环境自测，保证测试可以通过**。
4.如果现有项目已有测试目录/测试框架，沿用现有测试方案，不要自创测试方式。
5.输出复盘：
①实现思路
②改动文件清单
③新增测试文件与测试点
④自测结果：是否测试通过，存在哪些潜在风险

直接修改对应源码文件，完成功能+测试代码。"

echo "================ 启动赛马任务 TIME_STAMP=${TIME_STAMP} ================"
# 批量创建 worktree
for agent in "${AGENTS[@]}"; do
  WT_NAME="feat-issue${ISSUE_NUM}-${TIME_STAMP}-${agent}"
  BRANCH_NAME="feat/issue${ISSUE_NUM}-${TIME_STAMP}-${agent}"
  echo "启动 agent ${agent} worktree=${WT_NAME} branch=${BRANCH_NAME}"

  orca worktree create \
    --base "${BASE_BRANCH}" \
    --agent "${agent}-code" \
    --model opencode/mimo-v2.5-free \
    --name "${WT_NAME}" \
    --branch "${BRANCH_NAME}" \
    --prompt "${PROMPT}"
done

echo "✅全部worktree任务已下发，请等待AI全部执行完毕！"
echo "等待30秒，可根据模型速度自行调大，也可以先在Orca确认全部Completed再继续"
sleep 30

# ============ 评测阶段：进入每个worktree执行项目测试命令，选出测试最优方案 ============
# ⚠️请把 TEST_CMD 修改为你项目实际测试命令
TEST_CMD="npm test"

BEST_SCORE=-1
BEST_WT=""
BEST_BRANCH=""
BEST_AGENT=""

echo -e "\n==================== 开始评测所有worktree ===================="
for agent in "${AGENTS[@]}"; do
  WT_NAME="feat-issue${ISSUE_NUM}-${TIME_STAMP}-${agent}"
  BRANCH_NAME="feat/issue${ISSUE_NUM}-${TIME_STAMP}-${agent}"
  WT_DIR=$(orca worktree path "${WT_NAME}" 2>/dev/null || true)

  if [[ -z "${WT_DIR}" || ! -d "${WT_DIR}" ]]; then
    echo "⚠️ ${WT_NAME} worktree不存在或未生成，跳过"
    continue
  fi

  pushd "${WT_DIR}" >/dev/null
  TEST_RET=0
  echo "👉执行测试 ${WT_NAME}"
  eval "${TEST_CMD}" || TEST_RET=$?
  popd >/dev/null

  if [[ ${TEST_RET} -eq 0 ]]; then
    CUR_SCORE=100
    RESULT="✅测试执行通过"
  else
    CUR_SCORE=0
    RESULT="❌测试执行失败 exit=${TEST_RET}"
  fi
  echo "[${agent}] ${RESULT} score=${CUR_SCORE}"

  if (( CUR_SCORE > BEST_SCORE )); then
    BEST_SCORE=${CUR_SCORE}
    BEST_WT=${WT_NAME}
    BEST_BRANCH=${BRANCH_NAME}
    BEST_AGENT=${agent}
  fi
done

echo -e "\n================评测结果================"
echo "最优 worktree: ${BEST_WT} agent=${BEST_AGENT} score=${BEST_SCORE}"
echo "对应分支：${BEST_BRANCH}"

if [[ -z "${BEST_BRANCH}" ]]; then
  echo "❌没有可用分支，终止流程"
  exit 1
fi

# ============ 自动推送最优分支，创建 Draft PR（草稿PR，不会直接合并） ============
WT_BEST_DIR=$(orca worktree path "${BEST_WT}")
pushd "${WT_BEST_DIR}" >/dev/null

echo "推送分支 ${BEST_BRANCH} 到 GitHub"
git push origin "${BEST_BRANCH}"

echo "创建 Draft PR，目标分支 ${BASE_BRANCH}"
gh pr create \
  --base "${BASE_BRANCH}" \
  --head "${BEST_BRANCH}" \
  --title "feat: ${ISSUE_TITLE}" \
  --draft \
  --body "Closes #${ISSUE_NUM}
> 🤖由 Orca 赛马流水线自动生成
> 候选模型：${AGENTS[*]}
> 选中模型：${BEST_AGENT}
> 说明：AI完成编码并自行编写测试用例，脚本自动运行项目测试，选出测试通过最优方案。
> ⚠️【重要提醒】请人工仔细Review代码逻辑、边界条件、安全问题后再合并！"

popd >/dev/null

echo -e "\n🎉流水线全部执行完成！"
echo "PR已经创建为草稿(Draft)，请打开GitHub查看PR进行人工评审。"
echo "后续定期执行：同步main到dev‑guo："
echo 'git checkout dev-guo && git fetch origin && git merge origin/main && git push origin dev-guo'
