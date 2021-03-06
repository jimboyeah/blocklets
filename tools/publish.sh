set -e

VERSION=$(cat version | awk '{$1=$1;print}')
git config --local user.name "bot"
git config --local user.email "bot@arcblock.io"

echo "check version ${VERSION}"
NPM_VERSION=$(npm view @arcblock/blocklet-registry version)
if [ "$VERSION" = "$NPM_VERSION" ]; then
  echo "current version $VERSION is the latest published version, will bump to new version"
  git remote remove origin
  git remote add origin "https://$GIT_HUB_TOKEN@github.com/$GITHUB_REPOSITORY.git"
  git remote -v
  git pull origin master
  git checkout master
  git branch -a
  echo 'bump version'
  SKIP_INPUT=1 .makefiles/bump_version.sh
  .makefiles/bump_node_version.sh
  echo 'commit'
  git status
  git commit -m 'bump version'
  echo 'push commit to master'
  git status
  cat package.json
  cat version
  cat CHANGELOG.md
  git push origin master
  VERSION=$(cat version)
  echo "version $VERSION pushed"
  echo "make a trigger to github actions"
  curl \
    -X POST \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Authorization: token $GIT_HUB_TOKEN" \
    https://api.github.com/repos/$GITHUB_REPOSITORY/actions/workflows/main.yml/dispatches \
    -d '{"ref":"master"}'
  echo "next build will be trigger"
  echo "done"
  exit
fi

echo "publish version ${VERSION}"

make release
npm config set '//registry.npmjs.org/:_authToken' "${NPM_TOKEN}"
sudo npm install -g @abtnode/cli

echo "publishing blocklets blocklet..."
yarn build
rm -f www/*.map
NODE_ENV=production blocklet bundle --create-release && npm publish .blocklet/bundle

echo "publishing to blocklet registry"
blocklet config registry ${BLOCKLET_REGISTRY}
blocklet publish --developer-sk ${ABTNODE_DEV_SK}

node tools/post-publish.js

# deploy to remote ABT Node
set +e
NAME=$(cat package.json | grep name |  awk '{print $2}' | sed 's/"//g' | sed 's/,//g')
VERSION=$(cat package.json | grep version |  awk '{print $2}' | sed 's/"//g' | sed 's/,//g')
if [ "${ALIYUN_NODE_ENDPOINT}" != "" ]; then
  blocklet deploy .blocklet/bundle --endpoint ${ALIYUN_NODE_ENDPOINT} --access-key ${ALIYUN_NODE_ACCESS_KEY} --access-secret ${ALIYUN_NODE_ACCESS_SECRET} --skip-hooks
  if [ $? == 0 ]; then
    echo "deploy to ${ALIYUN_NODE_ENDPOINT} success"
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"${NAME} v${VERSION} was successfully deployed to ${ALIYUN_NODE_ENDPOINT}\"}" ${SLACK_WEBHOOK}
  else
    echo "deploy to ${ALIYUN_NODE_ENDPOINT} failed"
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\":x: Faild to deploy ${NAME} v${VERSION} to ${ALIYUN_NODE_ENDPOINT}\"}" ${SLACK_WEBHOOK}
  fi
fi
if [ "${AWS_NODE_ENDPOINT}" != "" ]; then
  blocklet deploy .blocklet/bundle --endpoint ${AWS_NODE_ENDPOINT} --access-key ${AWS_NODE_ACCESS_KEY} --access-secret ${AWS_NODE_ACCESS_SECRET} --skip-hooks
  if [ $? == 0 ]; then
    echo "deploy to ${AWS_NODE_ENDPOINT} success"
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"${NAME} v${VERSION} was successfully deployed to ${AWS_NODE_ENDPOINT}\"}" ${SLACK_WEBHOOK}
  else
    echo "deploy to ${AWS_NODE_ENDPOINT} failed"
    curl -X POST -H 'Content-type: application/json' --data "{\"text\":\":x: Faild to deploy ${NAME} v${VERSION} to ${AWS_NODE_ENDPOINT}\"}" ${SLACK_WEBHOOK}
  fi
fi

curl -X POST -H 'Content-type: application/json' --data "{\"text\":\"${NAME} v${VERSION} was successfully published\"}" ${SLACK_WEBHOOK}
