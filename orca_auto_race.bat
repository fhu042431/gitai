@echo off
chcp 936 >nul
setlocal enabledelayedexpansion

set "BASE_BRANCH=dev-guo"

echo ======================================
echo    Orca + GitHub 赛马自动化流水线
echo ======================================
set /p ISSUE_NUM=请输入GitHub Issue编号(数字): 
set /p TECH_STACK=请输入项目技术栈(如 Vue3+TS / Go / Python FastAPI): 

:: 获取Issue标题和内容，需要gh已登录
for /f "delims=" %%t in ('gh issue view %ISSUE_NUM% --json title -q .title') do set ISSUE_TITLE=%%t
for /f "delims=" %%b in ('gh issue view %ISSUE_NUM% --json body -q .body') do set ISSUE_BODY=%%b

for /f "delims=" %%a in ('powershell -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"') do set TIME_STAMP=%%a

set AGENTS=claude opencode codex

echo.
echo 【信息】Issue #%ISSUE_NUM% : !ISSUE_TITLE!
echo 时间戳: %TIME_STAMP%
echo.

:: Prompt内容
set "PROMPT=#任务说明
基线分支：%BASE_BRANCH%
需求：
【!ISSUE_TITLE!】
!ISSUE_BODY!

技术栈：%TECH_STACK%

硬性约束：
1.基于dev‑guo实现需求，最小变更，不要大范围重构无关代码，不新增不必要第三方依赖。
2.实现业务代码，同时编写完整单元测试用例覆盖正常场景、边界、异常输入。
3.你需要输出可直接运行的测试代码，写完代码后在当前环境自测，保证测试可以通过。
4.如果现有项目已有测试目录/测试框架，沿用现有测试方案，不要自创测试方式。
5.输出复盘：
①实现思路
②改动文件清单
③新增测试文件与测试点
④自测结果：是否测试通过，存在哪些潜在风险

直接修改对应源码文件，完成功能+测试代码。"

echo 开始批量创建 Worktree...
for %%a in (%AGENTS%) do (
    set WT_NAME=feat-issue%ISSUE_NUM%-%TIME_STAMP%-%%a
    set BRANCH_NAME=feat/issue%ISSUE_NUM%-%TIME_STAMP%-%%a
    echo 创建 %%a : !WT_NAME! ^| !BRANCH_NAME!
    orca worktree create --base %BASE_BRANCH% --agent %%a-code --name !WT_NAME! --branch !BRANCH_NAME! --prompt "%PROMPT%"
)

echo.
echo ========== 轮询等待全部任务执行完成 ==========
:wait_loop
set ALL_DONE=1
for %%a in (%AGENTS%) do (
    set WT_NAME=feat-issue%ISSUE_NUM%-%TIME_STAMP%-%%a
    orca worktree status !WT_NAME! | findstr /i "completed" >nul
    if errorlevel 1 (
        set ALL_DONE=0
    )
)
if !ALL_DONE! equ 0 (
    echo 任务尚未全部完成，等待10秒...
    timeout /t 10 /nobreak >nul
    goto wait_loop
)
echo ✅ 全部Agent任务执行完成，进入评测阶段

:: =================评测阶段=================
:: 修改这里为你的项目测试命令
set "TEST_CMD=npm test"

set BEST_SCORE=-1
set BEST_WT=
set BEST_BRANCH=
set BEST_AGENT=

echo.
echo ========== 开始运行测试筛选最优Worktree ==========
for %%a in (%AGENTS%) do (
    set WT_NAME=feat-issue%ISSUE_NUM%-%TIME_STAMP%-%%a
    set BRANCH_NAME=feat/issue%ISSUE_NUM%-%TIME_STAMP%-%%a
    for /f "delims=" %%p in ('orca worktree path !WT_NAME!') do set WT_DIR=%%p
    if not exist "!WT_DIR!\" (
        echo ⚠️ !WT_NAME! 目录不存在，跳过
        goto next_agent
    )
    echo 👉正在测试 !WT_NAME!
    pushd "!WT_DIR!"
    %TEST_CMD%
    set TEST_RET=!errorlevel!
    popd
    if !TEST_RET! equ 0 (
        set CUR_SCORE=100
        set RESULT=✅测试通过
    ) else (
        set CUR_SCORE=0
        set RESULT=❌测试失败，返回码 !TEST_RET!
    )
    echo [%%a] !RESULT! 得分:!CUR_SCORE!
    if !CUR_SCORE! gtr !BEST_SCORE! (
        set BEST_SCORE=!CUR_SCORE!
        set BEST_WT=!WT_NAME!
        set BEST_BRANCH=!BRANCH_NAME!
        set BEST_AGENT=%%a
    )
:next_agent
)

echo.
echo ==========评测结果==========
echo 最优 worktree: !BEST_WT! , Agent:!BEST_AGENT! , 得分 !BEST_SCORE!
echo 对应分支: !BEST_BRANCH!
if "!BEST_BRANCH!"=="" (
    echo ❌没有可用分支，程序退出
    pause
    exit /b 1
)

::推送分支，创建草稿PR
for /f "delims=" %%p in ('orca worktree path !BEST_WT!') do set WT_BEST_DIR=%%p
echo.
echo 推送分支 !BEST_BRANCH! 到GitHub
pushd "!WT_BEST_DIR!"
git push origin !BEST_BRANCH!
echo 创建草稿PR，目标分支 %BASE_BRANCH%
gh pr create --base %BASE_BRANCH% --head !BEST_BRANCH! --title "feat: !ISSUE_TITLE!" --draft --body "Closes #%ISSUE_NUM%
🤖由 Orca 赛马流水线自动生成
候选模型：%AGENTS%
选中模型：!BEST_AGENT!
说明：AI完成编码并自行编写测试用例，脚本自动运行项目测试，选出测试通过最优方案。
⚠️【重要提醒】请人工仔细Review代码逻辑、边界条件、安全问题后再合并！"
popd

echo.
echo 🎉流水线全部执行完成！
echo PR已创建为草稿(Draft)，请打开GitHub人工审核。
echo 定期同步main到dev‑guo命令：
echo git checkout dev-guo ^&^& git fetch origin ^&^& git merge origin/main ^&^& git push origin dev-guo
pause

