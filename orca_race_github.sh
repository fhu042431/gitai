 #!/bin/bash
BASE_BRANCH="dev-guo"

read -p "请输入 GitHub Issue编号(只填数字，例如 42): " ISSUE_NUM

# 通过 gh 从 github 拉取 issue 标题+内容
ISSUE_TITLE=$(gh issue view $ISSUE_NUM --json title -q .title)
ISSUE_BODY=$(gh issue view $ISSUE_NUM --json body -q .body)
ISSUE_DESC="【$ISSUE_TITLE】
$ISSUE_BODY"

read -p "请输入项目技术栈(例 Vue3+TS,Go,Python FastAPI): " TECH_STACK

PROMPT="#任务说明
请基于本仓库dev‑guo分支实现下面需求。
需求：
${ISSUE_DESC}

项目信息：
技术栈：${TECH_STACK}
编码规范：沿用仓库现有风格，不要私自引入第三方依赖，除非需求明确要求。

硬性约束：
1. 只解决本次需求，禁止大范围重构无关模块，尽量最小改动。
2. 边界条件必须考虑：空值、异常输入、报错处理、兼容旧数据。
3. 添加单元测试，验证新增逻辑正常运行；测试用例覆盖正常场景、异常场景。
4. 如果需要数据库/配置变更，请清晰说明变更点。
5. 修改完成后输出一份简短复盘：
①实现思路
②改动文件清单
③你识别到的风险与注意事项
④测试重点

直接修改对应源码文件，不需要先询问确认，完成全部改动。"

TIME_STAMP=$(date +%Y%m%d_%H%M%S)

echo "👉 拉取GitHub Issue #${ISSUE_NUM}，基线分支：$BASE_BRANCH"
echo "Issue标题：${ISSUE_TITLE}"

orca worktree create \
  --base "${BASE_BRANCH}" \
  --agent claude-code \
  --name "feat-issue${ISSUE_NUM}-${TIME_STAMP}-claude" \
  --branch "feat/issue${ISSUE_NUM}-${TIME_STAMP}-claude" \
  --prompt "${PROMPT}"

orca worktree create \
  --base "${BASE_BRANCH}" \
  --agent opencode \
  --name "feat-issue${ISSUE_NUM}-${TIME_STAMP}-opencode" \
  --branch "feat/issue${ISSUE_NUM}-${TIME_STAMP}-opencode" \
  --prompt "${PROMPT}"

orca worktree create \
  --base "${BASE_BRANCH}" \
  --agent codex \
  --name "feat-issue${ISSUE_NUM}-${TIME_STAMP}-codex" \
  --branch "feat/issue${ISSUE_NUM}-${TIME_STAMP}-codex" \
  --prompt "${PROMPT}"

echo "✅ 3个赛马Worktree任务已提交！"
echo "分支命名规则：feat/issue${ISSUE_NUM}-${TIME_STAMP}-xxx"
echo "👉下一步操作："
echo "1.打开 Orca GUI，等待全部任务执行完成"
echo "2.打分选出最优worktree"
echo "3.推送该分支到GitHub，创建PR，目标分支 dev‑guo，PR描述填写 Closes #${ISSUE_NUM}"
