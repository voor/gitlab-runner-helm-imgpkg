#!/usr/bin/env bash
set -eux -o pipefail

USAGE="Usage: $0 PACKAGE ACTION REPO # ACTION should be test or deploy"

if [ "$#" == "0" ]; then
  echo "$USAGE"
  exit 1
fi

PACKAGE=${1}
SERVICE_FOLDER=${PACKAGE}
ACTION=${2}

if [ -z "$PACKAGE" ]
then
  echo "build package failed. must set PACKAGE"
  echo "$USAGE"
  exit 2
fi

if [ -z "$ACTION" ]
then
  echo "build package failed. must set ACTION"
  echo "$USAGE"
  exit 2
elif [ "$ACTION" == 'deploy' ]; then
  HARBOR_REPO=${3}
  if [ -z "$HARBOR_REPO" ]
  then
    echo "build package failed. must set REPO for deploy"
    echo "$USAGE"
    exit 2
  fi
fi

vendir sync

WORKING_FOLDER=${PWD}/bundle

BUILD_SCRIPT=$(basename $0)

# Create folders we'll need for imgpkg and additional manifests, follow
mkdir -p ${WORKING_FOLDER}/.imgpkg ${WORKING_FOLDER}/config sample versions

# Either we have a helm chart involved, or it's just config.
if [ -d "${PWD}/bundle/chart" ]; then
  # Apply our values overlay to the defaults in the chart.

  mv ${WORKING_FOLDER}/chart/values.yaml ${WORKING_FOLDER}/chart/values.yaml.original
  echo -e "#@data/values\n---\n\n" > ${WORKING_FOLDER}/chart/values.yaml
  ytt -f ${WORKING_FOLDER}/chart/values.yaml.original --file-mark "values.yaml.original:type=yaml-plain" -f helm/values-overlay.yaml >> ${WORKING_FOLDER}/chart/values.yaml

  CHART_VERSION=$(yq eval .version ${WORKING_FOLDER}/chart/Chart.yaml)
  APP_VERSION=$(yq eval .appVersion ${WORKING_FOLDER}/chart/Chart.yaml)

  # Add chart version to the end of the values file.
  yq eval '{"chartInfo": { "appVersion": .appVersion } } ' ${WORKING_FOLDER}/chart/Chart.yaml >> ${WORKING_FOLDER}/chart/values.yaml

  echo -e "#! I am a sample that was automatically generated with ${BUILD_SCRIPT}\n\n---" > sample/${SERVICE_FOLDER}-${CHART_VERSION}.yaml
  helm template ${PACKAGE} ${WORKING_FOLDER}/chart --namespace sample-namespace --include-crds \
    | ytt --ignore-unknown-comments -f ${WORKING_FOLDER}/chart/values.yaml -f - -f ${WORKING_FOLDER}/config \
    | kbld -f - --imgpkg-lock-output ${WORKING_FOLDER}/.imgpkg/images.yml >>sample/${SERVICE_FOLDER}-${CHART_VERSION}.yaml

  if [ "$ACTION" == 'deploy' ]; then
    IMGPKG_BUNDLE=${HARBOR_REPO}/imgpkg/charts/${SERVICE_FOLDER}
    imgpkg push -b ${IMGPKG_BUNDLE}:${CHART_VERSION} -f ${WORKING_FOLDER}
    imgpkg copy -b ${IMGPKG_BUNDLE}:${CHART_VERSION} --to-repo ${IMGPKG_BUNDLE} --lock-output current-version.yml
    cp current-version.yml versions/${SERVICE_FOLDER}-${CHART_VERSION}.yml
  fi
else

  APP_VERSION=$(yq eval '.. | select(has("tag")).tag' vendir.lock.yml)

  echo -e "#! I am a sample that was automatically generated with ${BUILD_SCRIPT}\n\n---" > sample/${SERVICE_FOLDER}-${APP_VERSION}.yaml
  ytt --ignore-unknown-comments -f ${WORKING_FOLDER}/config \
      | kbld -f - --imgpkg-lock-output ${WORKING_FOLDER}/.imgpkg/images.yml >>sample/${SERVICE_FOLDER}-${APP_VERSION}.yaml

  if [ "$ACTION" == 'deploy' ]; then
    IMGPKG_BUNDLE=${HARBOR_REPO}/imgpkg/charts/${SERVICE_FOLDER}
    imgpkg push -b ${IMGPKG_BUNDLE}:${APP_VERSION} -f ${WORKING_FOLDER}
    imgpkg copy -b ${IMGPKG_BUNDLE}:${APP_VERSION} --to-repo ${IMGPKG_BUNDLE} --lock-output current-version.yml
    cp current-version.yml versions/${SERVICE_FOLDER}-${APP_VERSION}.yml
  fi
fi
