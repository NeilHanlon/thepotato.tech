#!/bin/bash -ex

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL}"
export GIT_SSH_COMMAND="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

REMOTE="${PUSH_REMOTE:-git@git.shrug.pw:neil/neilhanlon.me.git}"

rm -fr pages.git
mkdir pages.git

( cd pages.git && git init -b pages )
rsync -av public/* pages.git

cat << EOF > pages.git/.domains
neilhanlon.me
neilhanlon.com
hanlon.ninja
thepotato.tech
EOF

cp .woodpecker.yml pages.git/

cd pages.git

set -x
git config user.name "$GIT_AUTHOR_NAME"
git config user.email "$GIT_AUTHOR_EMAIL"
git add -A
git commit -m "Deployment at $(date -u -Is)"
git remote add origin $REMOTE
git push -f origin pages

curl -X POST --fail \
  -F token=$GITLAB_DEPLOY_TOKEN \
  -F ref=main \
  https://gitlab.com/api/v4/projects/29559707/trigger/pipeline