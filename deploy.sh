#!/bin/bash -ex

export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL}"

REMOTE=$(git remote get-url origin)

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

cd pages.git

git add -A
git commit -m "Deployment at $(date -u -Is)"
git remote add origin $REMOTE
git push -f origin pages
