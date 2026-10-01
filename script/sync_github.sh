#!/bin/zsh
# Explicit one-shot sync, not a background file watcher or automatic release.
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
if (( $# != 1 )) || [[ -z "$1" ]]; then
  print -u2 '用法：./script/sync_github.sh "本次版本修改说明"'
  exit 2
fi
EXPECTED_REMOTE='https://github.com/zhaozachary1-cpu/MirrorLink.git'
[[ "$(git remote get-url origin)" == "$EXPECTED_REMOTE" ]] || { print -u2 'origin 与本项目 GitHub 仓库不符，停止上传'; exit 2; }
BRANCH="$(git symbolic-ref --short HEAD)"
[[ "$BRANCH" == main ]] || { print -u2 '请先人工检查分支；此脚本仅同步 main，不自动合并/改写历史'; exit 2; }
./script/run_core_checks.sh
./script/run_session_checks.sh
./script/run_update_checks.sh
git fetch origin
if git rev-parse --verify origin/main >/dev/null 2>&1; then
  git merge-base --is-ancestor origin/main HEAD || { print -u2 '远端有未整合的提交，停止；请先检查差异'; exit 2; }
fi
git add -A -- .
# Fail closed on credential-like names, even if somebody force-added them.
if git ls-files | LC_ALL=C grep -Ei '(^|/)(\.env($|\.)|credentials[^/]*|secrets?[^/]*|id_(rsa|ed25519)$)|\.(p12|p8|key|pem|mobileprovision|provisionprofile)$'; then
  print -u2 '检测到疑似凭据文件，未提交/推送；暂存区保留以便人工检查。'
  exit 2
fi
# Print matching filenames only, never credential contents.
if git grep --cached -IlE '(ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-[A-Za-z0-9_-]{30,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)' -- .; then
  print -u2 '检测到疑似密钥内容，未提交/推送。'
  exit 2
fi
if ! git diff --cached --quiet; then
  git commit -m "$1"
fi
git push -u origin main
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin refs/heads/main | cut -f1)"
[[ "$LOCAL_SHA" == "$REMOTE_SHA" ]] || { print -u2 '远端校验不一致，请检查推送结果'; exit 1; }
echo "GitHub 已同步并核验：$LOCAL_SHA"
git status --short
