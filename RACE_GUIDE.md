# Orca 赛马流水线使用说明

AI 编码赛马流水线：把 GitHub Issue 交给 AI agent 独立开发 → 自动测试打分 → 选出最优方案 → 自动创建 Draft PR 供人工评审。

包含两个脚本：

| 脚本 | 用途 |
|------|------|
| `orca_full_auto_race.sh` | 赛马流水线主体（开发→评测→建PR） |
| `orca_cleanup_race.sh` | 清理赛马产生的 worktree 和分支 |

---

## 一、前置条件

1. **Orca 桌面应用已启动**（worktree 由 Orca 管理）
2. **gh CLI 已登录**（`gh auth status` 可确认），且对目标仓库有读/写权限
3. **opencode CLI 已安装**（AI 执行引擎），模型 `opencode/mimo-v2.5-free` 可用
4. **orca CLI 已注册**（`orca status --json` 返回 `"ok": true`）
5. Windows 环境需在 Git Bash 中运行（脚本依赖 bash/awk/sed）
6. 脚本文件换行符必须为 LF（CRLF 会导致 bash 语法错误）

---

## 二、赛马流水线 orca_full_auto_race.sh

### 用法

```bash
# 方式1：配置文件（推荐，脚本同目录 race.conf，填一次常用参数后直接运行）
bash orca_full_auto_race.sh

# 方式2：位置参数传 GitHub 地址和本地目录，其余交互输入
bash orca_full_auto_race.sh https://github.com/owner/repo D:\code\myrepo

# 方式3：纯交互模式（无配置文件、无参数时逐项询问）
bash orca_full_auto_race.sh
```

**参数优先级**：命令行位置参数 > 配置文件 `race.conf` > 交互输入。

### 配置文件 race.conf

脚本同目录放一个 `race.conf`（`key=value`，支持 `#` 注释），可把常用参数固定下来，避免每次重复输入：

```ini
# GitHub 仓库地址（必填）
GITHUB_URL=https://github.com/fhu042431/orcatest

# 本地仓库目录（必填，绝对路径，反斜杠会原样保留）
REPO_DIR=F:\orca1\orcatest

# 基线分支（默认 dev-guo）
BASE_BRANCH=dev-guo

# 项目技术栈（写入给 AI 的 Prompt）
TECH_STACK=vue

# Issue 编号（可选；支持批量如 "4 5,6 8-10"；不填则每次交互询问）
# ISSUE_INPUT=4

# 测试命令（可选；不填则自动检测，检测不到再询问；填 skip 表示跳过测试）
# TEST_CMD=skip

# GitHub访问代理（可选；所有访问GitHub的 git/gh 流量走代理，本地操作不受影响）
# 支持 127.0.0.1:7897 / http://127.0.0.1:7897 / socks5://127.0.0.1:7897；不填则直连
# 端口以代理软件实际监听为准：Clash Verge=7897 / Clash=7890 / v2rayN=10809
PROXY_URL=http://127.0.0.1:7897
```

说明：

- 某行**留空或删除** = 该项改为交互输入（`ISSUE_INPUT`、`TEST_CMD` 默认注释，因为它们常按需变化）
- `REPO_DIR` 的反斜杠路径直接写 `F:\orca1\orcatest` 即可，脚本会原样读取（用 `read -r` 保护）
- 位置参数始终最高优先级：`bash orca_full_auto_race.sh 新地址 新目录` 会覆盖配置文件中的对应值

GitHub 地址支持三种格式：

- `https://github.com/owner/repo`（可带 `.git`）
- `git@github.com:owner/repo.git`
- `owner/repo`

### 多 Issue 批处理

Issue 编号支持批量输入，格式可混用：

| 格式 | 示例 | 含义 |
|------|------|------|
| 单个 | `4` | 只处理 Issue #4 |
| 空格分隔 | `4 5 6` | 依次处理 4、5、6 |
| 逗号分隔 | `4,5,6` | 同上 |
| 范围 | `4-8` | 处理 4、5、6、7、8 |
| 混合 | `4 6,9 11-13` | 处理 4、6、9、11、12、13（自动去重排序） |

批处理行为：

- **逐个串行处理**：每个 Issue 独立走完整流程（拉取→worktree→AI开发→评测→PR），每个 Issue 有独立时间戳，worktree 命名不冲突
- **失败隔离**：单个 Issue 失败（无可用分支/推送失败/建PR失败等）不中断批次，记录后继续下一个
- **启动前预检所有 Issue**：不存在或无权访问的编号提前剔除，不浪费 AI 执行时间
- **批次汇总**：全部完成后输出每个 Issue 的结果清单（成功/失败/PR链接/得分）+ 汇总通知

### 结果汇总报告

每次运行结束自动生成 Markdown 报告：`logs/report-<批次时间戳>.md`，内容包括：

- **批次信息**：仓库、基线分支、测试命令、参赛 agent、成功/失败统计
- **总览表**：每个 Issue 的结果与说明（PR 链接/失败原因）一表看全貌
- **逐 Issue 明细**：
  - 处理耗时
  - 各 agent 评分表（分数/改动文件数/新增测试数/修复轮数/是否通过）——多选手时可直接横向对比
  - 最优方案（agent、得分、分支名）

报告文件与日志同目录，可直接用 VS Code / Typora 打开预览，也方便归档到 PR 描述或团队周报。续跑时跳过的已完成 Issue 也计入报告（标注"已完成,本次跳过"）。

### 断点续跑

脚本将每个 Issue 的处理进度持久化到进度文件：`logs/progress-<owner-repo>-<基线分支>.txt`（按仓库+基线分支各存一份）。

状态流转：

```
STARTED → DEV_DONE → EVAL → DONE（成功，附PR链接）
                  ↘ FAIL（失败，附原因）
```

重跑脚本时的行为：

| 场景 | 行为 |
|------|------|
| 检测到已完成的 Issue | 询问「续跑 / 全部重跑」：续跑则跳过已完成的 Issue；选 n 则忽略进度全部重来 |
| Issue 上次中断（worktree 仍在） | **复用已开发的 worktree，跳过清理和 AI 开发，直接进入评测**——省掉最耗时的步骤 |
| Issue 上次 FAIL 后重跑 | 同上复用（相当于"再试一次"：评测+修复回路重走；如需彻底重来，在续跑询问时选 n，或先用清理脚本删 worktree） |
| 无进度文件（首次运行） | 正常全新执行 |

安全性设计：复用仅在「进度文件中该 Issue 状态非 DONE 且非首次」时触发；选"全部重跑"时会先清掉旧 worktree 再重新开发，不会误复用。

注意：批处理时若上次运行中途中断（如 Ctrl+C），已开始的 Issue 状态停在 `STARTED`/`DEV_DONE`/`EVAL`，重跑续跑即可接着处理，无需从头再来。

### 交互输入项

> 以下每一项若已在 `race.conf` 配置或由位置参数提供，则跳过询问直接使用；只有缺失时才交互输入。

| 输入项 | 说明 | 默认值 |
|--------|------|--------|
| GitHub 仓库地址 | 配置文件 `GITHUB_URL` 或位置参数可提供 | 必填 |
| 本地仓库目录 | 配置文件 `REPO_DIR` 或位置参数可提供 | 必填 |
| 基线分支 | worktree 从该分支拉出，PR 也合入它 | `dev-guo` |
| Issue 编号 | 支持批量（见上表）；配置文件 `ISSUE_INPUT` 可提供 | 必填 |
| 项目技术栈 | 写入给 AI 的 Prompt | 必填 |
| 测试命令 | 评测打分依据（全批次共用）。配置文件 `TEST_CMD` 优先；否则自动检测（依赖 go.mod/package.json/pyproject.toml 等），检测不到循环要求手动输入；输入 `skip` 可跳过测试仅按改动评分 | 自动检测 |

测试命令自动检测规则（回车即用检测值）：

| 检测到文件 | 测试命令 |
|-----------|---------|
| `go.mod` | `go test ./...` |
| `package.json` | `npm test` |
| `pyproject.toml` / `pytest.ini` / `requirements.txt` | `python -m pytest -v` |
| 均无 | 需手动输入 |

### 执行流程

```
输入参数 + 四重校验（地址格式/本地git仓库/remote匹配/gh可访问）
    ↓
步骤1  拉取 Issue 标题和正文，拼装带硬性约束的 Prompt
    ↓
步骤2  orca worktree create 创建隔离工作区（分支与worktree同名）
    ↓
步骤3  cd 进 worktree，opencode run 阻塞执行 AI 开发
       （要求：最小变更 + 编写单元测试 + 自测通过 + 输出复盘）
    ↓
步骤4  评测：进入每个 worktree 跑测试命令
       通过 = 100 分 / 失败 = 0 分，记录最高分者
    ↓
步骤5  自动提交 agent 未 commit 的改动
       校验分支相对基线有新提交（否则终止）
    ↓
步骤6  git push 推送最优分支
    ↓
步骤7  gh pr create --draft 创建草稿PR（描述含提醒人工Review）
```

### 关键配置（脚本内修改）

- **参赛 agent**：`AGENTS=( "opencode" )`，可添加多个如 `( "opencode" "claude" "codex" )`
- **各 agent 模型**：`declare -A AGENT_MODELS=( ["opencode"]="opencode/mimo-v2.5-free" ... )`
- **自动修复轮数**：`MAX_FIX_ROUNDS=2`（测试失败回喂 agent 修复的最大轮数）
- **测试超时**：`TEST_TIMEOUT=600`（单次测试秒数上限，防死循环）
- **AI任务超时**：`AI_TIMEOUT=3600`（单次 AI 开发/修复秒数上限，防 agent 挂死导致 `wait` 永久阻塞；超时退出码 124）
- **完成通知 webhook**：设置环境变量 `RACE_WEBHOOK_URL`（飞书格式），不设则只用 Windows 气泡通知

### GitHub 访问代理

`race.conf` 中配置 `PROXY_URL` 后，脚本内**所有访问 GitHub 的网络流量**自动走代理：

- 覆盖范围：git 预检（`ls-remote`）、基线分支校验、Issue 拉取/预检、历史分支清理、`fetch`/`push`、`gh pr list/create` 等全部 GitHub 操作
- 实现方式：仅对这些命令注入 `http_proxy`/`https_proxy` 环境变量（git 和 gh 均原生支持）；**本地操作（worktree、status、diff）、npm/go 测试、AI 任务流量不受影响**
- 地址格式：无协议头自动补 `http://`，支持 `127.0.0.1:7897`、`http://127.0.0.1:7897`、`socks5://127.0.0.1:7897`
- **端口预检**：启动时先用 TCP 探测代理端口（3 秒超时），端口不通立即报错退出（附常见端口提示），不会傻等 40 秒超时后才给出含糊错误
- **报错可溯源**：git 预检失败时会把实际报错原文写进日志（`git报错详情: ...`），不再出现无从排查的"未知错误"
- 临时覆盖：`RACE_PROXY_URL=socks5://127.0.0.1:7891 bash orca_full_auto_race.sh`（优先级高于 race.conf，适合临时切换代理）
- 启动时日志会打印 `🌐 GitHub访问已启用代理: <地址>` 便于确认生效

### 核心特性

**多 agent 并行赛马**：所有 agent 的 AI 任务并行后台执行（`&` + `wait`），总耗时 ≈ 最慢者，而非累加。每个 agent 的 AI 开发/修复输出写入独立日志 `logs/dev-<worktree>.log`，多 agent 并行时日志不混杂；AI 任务带超时保护（`AI_TIMEOUT`，默认 3600 秒），单个 agent 挂死不会卡死整条流水线，超时会自动转为评测该 agent 已产生的改动。

**测试失败自动修复回路**：首次测试失败时，截取失败输出最后 60 行回喂 agent 修复，循环重试最多 `MAX_FIX_ROUNDS` 轮，每轮输出追加到独立日志 `logs/test-<worktree>.log`。

**多维评分（满分100，测试通过为必要条件）**：

| 维度 | 分值 | 说明 |
|------|------|------|
| 测试通过 | 必要条件 | 最终测试失败直接 0 分淘汰 |
| 有实际代码改动 | +40 | 防止零改动方案蒙混过关 |
| 最小变更 | 最多+30 | 改动≤5文件+30 / ≤10文件+20 / ≤20文件+10 / 更多+5 |
| 新增测试文件 | +30 | 检测新增文件名含 test/spec |

**自动清理旧 worktree**：启动时自动清理同 Issue 的历史赛马 worktree 和分支；远程分支只在**没有开放中的 PR** 时才删除，防止误删评审中的代码。

**进度回写 Orca 卡片**：关键节点（AI开发中/修复中/评测完成/已建PR）通过 `orca worktree set --comment` 更新，在 Orca 界面实时可见。

**PR 描述增强**：自动附上改动统计（`diff --stat`）、改动文件清单、测试命令、修复轮数和评分明细。

**完成通知**：流水线结束（无论成功失败）弹 Windows 气泡通知；配置了 `RACE_WEBHOOK_URL` 时同步推送到飞书/钉钉。

### 安全机制

- PR 一律为 **Draft 草稿**，绝不自动合并
- PR 描述中明确要求人工 Review 后才能合并
- 相对基线无新提交时终止流程，不创建空 PR

### 日志

每次运行生成独立日志：`logs/race-<时间戳>.log`（控制台与文件双写），每个 agent 的 AI 开发输出另存 `logs/dev-<worktree>.log`、测试输出另存 `logs/test-<worktree>.log`，批次结束生成汇总报告 `logs/report-<时间戳>.md`。

- 所有命令输出（含 pytest、opencode、gh）均被记录
- 每步操作带时间戳和 `[agent]` 标记
- 脚本异常退出时记录出错行号和退出码
- 排查问题：打开对应时间戳的日志文件即可还原全程

---

## 三、清理脚本 orca_cleanup_race.sh

删除赛马流水线产生的 worktree（`feat-issue*`）及其本地/远程分支。只清理赛马产物，不会误删 `main`、`dev-guo` 等正常分支。

### 用法

```bash
# 交互模式：列出所有赛马worktree，输入序号选择（支持 1 3 多选 / all 全部）
bash orca_cleanup_race.sh

# 按 Issue 编号清理
bash orca_cleanup_race.sh 4

# 按名称模糊匹配清理
bash orca_cleanup_race.sh feat-issue4-20260903
```

### 清理动作（每个 worktree 三层）

1. `orca worktree rm --force`（失败回退 `git worktree remove --force`）
2. `git branch -D` 删本地分支
3. `git push origin --delete` 删远程分支（存在才执行）

执行前有 `y/N` 二次确认，逐项报告成功/失败。

---

## 四、常见问题排查

| 现象 | 原因与解决 |
|------|-----------|
| `git无法免密访问origin`（启动时终止） | git 凭证缺失。脚本已自动尝试 `gh auth setup-git`；仍失败则按日志提示三选一：gh auth login / credential.helper manager / 改 SSH remote |
| `Missing repo selector` | 未传 `--repo`。脚本已自动带 `--repo path:<目录>`，若仍报错检查本地目录是否正确 |
| `repo_not_found` | Orca 未注册该路径的仓库（Git Bash 的 `/f/...` 风格路径 Orca 无法识别）。脚本已自动转换 Windows 路径，仍报错时会自动 `orca repo add` 注册后重试；手动修复：`orca repo add --path "F:\\your\\repo"` |
| AI任务"成功"但agent没干活 | opencode 权限被自动拒绝（日志出现 `permission requested ... auto-rejecting`）但进程仍 exit 0。脚本已用 `--auto` 参数自动批准权限并在任务结束后核实 worktree 是否真有改动；若日志仍提示 `agent未产生任何改动` 查看对应 dev 日志 |
| `runtime_unavailable` / `Could not read Orca runtime metadata` | Orca 应用未启动，先打开 Orca |
| `No commits between dev-guo and ...` | 分支无新提交。脚本已含自动 commit 防护；若 agent 确实没改代码会提前终止并提示 |
| `Missing script: "test"` | 测试命令与项目不匹配。运行时在"测试命令"一栏手动输入正确命令 |
| `语法 error near unexpected token 'do\r'` | 脚本被改成 CRLF 换行。转换回 LF（VS Code 右下角或 `dos2unix`） |
| `git push` 失败 src refspec | 分支名不匹配。脚本通过 git 实际查询分支名，检查 worktree 是否真的由 Orca 创建 |
| worktree 找不到/跳过评测 | Orca 创建失败或被手动删除，查看日志中步骤2的输出 |
| commit 失败 `Please tell me who you are` | 未配置 git 身份。脚本已内置 race-bot 兜底身份，正常不会遇到；如遇检查是否手动提交 |
| 测试超时退出码 124 | 测试超过 `TEST_TIMEOUT`（默认600秒）被强杀。检查是否有死循环，或在配置区调大超时 |
| `远程分支 origin/xxx 不存在` | 基线分支拼写错误或未推送，检查输入的基线分支名 |

### 启动前预检清单

脚本在参数校验阶段依次执行以下检查，任一失败立即终止并给出解决指引：

1. Issue 编号列表格式合法（数字/范围，自动去重排序）
2. GitHub 地址可解析为 owner/repo
3. 本地目录存在且为 git 仓库
4. `gh` 已登录且能访问该仓库
5. **git 访问预检**（免密访问 origin）：失败时自动重试 3 次（网络波动），凭证错误自动尝试 `gh auth setup-git` 修复，并区分网络/凭证错误给出对应解决方案
6. 基线分支在远程存在（网络错误与分支不存在分开报错）
7. 测试命令已提供（自动检测或手动输入，检测不到会循环重问；输入 `skip` 可跳过测试）
8. **每个 Issue 均可达**：不存在或无权访问的编号提前剔除并记录，全部不可达才终止

**git 凭证说明**：若本地 remote 为 HTTPS 且凭证未缓存，直接推送会卡在"输入用户名密码"交互（且日志重定向后提示不可见）。脚本通过预检 + 自动配置规避此问题；也可预先执行 `gh auth setup-git` 一劳永逸。

**网络 vs 凭证诊断**：git 报 `Connection was reset / Failed to connect` 是网络问题（访问 GitHub 常见波动，脚本会自动重试）；报 `Authentication failed / could not read Username` 才是凭证问题。判断技巧：`gh api repos/<owner>/<repo>` 能通而 `git ls-remote origin` 不通 = git 直连被墙，配置 git 代理即可。

### 其他健壮性设计

- **git 身份兜底**：自动提交时若未配置 `user.name/email`，用 `-c` 参数临时指定 race-bot 身份（不修改全局配置）
- **测试超时保护**：单次测试超过 `TEST_TIMEOUT`（默认600秒）强制终止，防止死循环测试卡死流水线（无 timeout 命令的环境自动跳过）
- **PR 已存在检测**：重跑脚本时若该分支已有 PR，跳过创建直接复用，避免 `gh pr create` 报错
- **评分隔离**：每个 agent 评测前重置分数，失败 agent 严格为 0 分

---

## 五、已知局限

1. 目前只配置 1 个 agent（`opencode`），并行赛马和多维评分需配置多选手才能体现价值
2. 评测阶段为串行执行（每个 agent 依次跑测试+修复回路），agent 多时评测耗时线性增长
3. 多 agent 修复回路中的 `opencode run` 无法保证完全幂等，个别修复轮可能产生无效果改动（有评分机制兜底淘汰）
4. Windows 气泡通知依赖 PowerShell，在精简版系统上可能静默失败（不影响主流程）
