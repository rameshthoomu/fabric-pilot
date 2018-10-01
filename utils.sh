#!/bin/bash

# exit on the first error
set -o pipefail

# set targets here
FABRIC_1_0_TARGETS=(docker release-clean release)
FABRIC_TARGETS=(docker release-clean release docker-thirdparty)
FABRIC_CA_TARGETS=(docker)
FABRIC_CA_1_0_TARGETS=(docker-fabric-ca)
FABRIC_IMAGES=(peer orderer ccenv tools)
FABRIC_CA_IMAGES=(ca)
BASE_DIR=${WORKSPACE}/gopath/src/github.com/hyperledger
NEXUS_BASE_URL=nexus3.hyperledger.org:10001
ORG_NAME=hyperledger/fabric
JAVA_IMAGE=javaenv
WD="${WORKSPACE}/gopath/src/github.com/hyperledger/${PROJECT}"

# get arch
function getArch() {
    ARCH=$(go env GOARCH)
    if [ "$ARCH" = "amd64" ]; then
	    ARCH=amd64
    else
        ARCH=$(uname -m)
    fi
}

# Here $1 is the project name $2 is branch name
function cloneRepo(){
        projectName=$1
        branchName=$2
        echo "########## $1"
        # Clone repository
	if [ -d "${WD}" ]; then # if directory exists
		rm -rf "${WD}"
	fi
        git clone --single-branch -b "$2" --depth=1 git://cloud.hyperledger.org/mirror/"$1" "$WD"
        echo "Clone and checkout to the given branch"
	cd "${WD}" || exit
        if ! git checkout "$2" > /dev/null 2>&1
        then
                echo "------> Branch "$2" not found - Checkout to master"
		cd "${WD}" || exit
                git checkout master
        fi
        if [ -d "${WD}" ]; then # if directory exists
        # Be at project root directory
            COMMIT=$(git log -1 --pretty=format:"%h")
            echo "------> Commit SHA is ${COMMIT}"
        else
            echo "------> Directory not found. Clone again"
            exit 1
        fi
} # close cloneRepo

## Here $1 is the project name, $2 is branch name
function buildImages(){
        projectName=$1
        branchName=$2
        echo "########## ${projectName}"
        if [ "${projectName}" = "fabric" ]; then
                echo "------> Build artifacts for ${projectName}"
                if [ "${branchName}" = "release-1.0" ]; then # only on release-1.0 branch
                       for TARGET in ${FABRIC_1_0_TARGETS[*]}; do
                            # Build artifacts
                           if ! make "${TARGET}" > /dev/null 2>&1
                           then
                                echo "ERROR: ------> make ${TARGET} failed"
                                exit 1
                            fi
                       done
                else # otherthan release-1.0 branch
                    for TARGET in "${FABRIC_TARGETS[@]}"; do
                        # Build artifacts
                        if ! make "${TARGET}" > /dev/null 2>&1
                        then
                            echo "ERROR: ------> make ${TARGET} failed"
                            exit 1
                        fi
                    done
                fi
        elif [ "${projectName}" = "fabric-ca" ]; then
                echo "------> Build artifacts for ${projectName}"
                if [ "${branchName}" = "release-1.0" ]; then # only on release-1.0 branch
                       for TARGET in ${FABRIC_CA_1_0_TARGETS[*]}; do
                            # Build artifacts
                           if ! make "${TARGET}" > /dev/null 2>&1
                           then
                                echo "ERROR: ------> make ${TARGET} failed"
                                exit 1
                            fi
                       done
                else # otherthan release-1.0 branch
                    for TARGET in "${FABRIC_CA_TARGETS[@]}"; do
                        # Build artifacts
                        if ! make "${TARGET}" > /dev/null 2>&1
                        then
                            echo "ERROR: ------> make ${TARGET} failed"
                            exit 1
                        fi
                    done 
                fi
        fi
} # Close for buildImages

function buildAllImages() {
        getArch
        cloneRepo fabric branch_name
	export_Go fabric
        buildImages fabric branch_name
        cloneRepo fabric-ca branch_name
	export_Go fabric-ca
        buildImages fabric-ca branch_name

} # Close buildAllImages

function export_Go {
    echo "-------> Export GOPATH"
    cd "${BASE_DIR}"/"${projectName}" || exit
    GO_VER=$(cat ci.properties | grep GO_VER | cut -d "=" -f 2)
    echo "------> GO_VER: ${GO_VER}"
    OS_VER=$(dpkg --print-architecture)
    echo "------> OS_VER: ${OS_VER}"
    export GOROOT=/opt/go/go${GO_VER}.linux.${OS_VER}
    export PATH=${GOROOT}/bin:${PATH}
}

function pullJavaImages() {
        getArch
        echo "------> Pull Docker Images"
        if [ "${ARCH}" = "amd64" ]; then # JAVAENV is not available on other platforms
            if [ "${branchName}" = "master" ]; then
                export STABLE_VERSION=1.4.0-stable
                export JAVA_ENV_TAG=1.4.0
            else
                export STABLE_VERSION=1.3.0-stable
                export JAVA_ENV_TAG=1.3.0
            fi
            docker pull $NEXUS_BASE_URL/$ORG_NAME-$JAVA_IMAGE:"${ARCH}"-$STABLE_VERSION
            docker tag $NEXUS_BASE_URL/$ORG_NAME-$JAVA_IMAGE:"${ARCH}"-$STABLE_VERSION $ORG_NAME-"${JAVA_IMAGE}"
            docker tag $NEXUS_BASE_URL/$ORG_NAME-$JAVA_IMAGE:"${ARCH}"-$STABLE_VERSION $ORG_NAME-"${JAVA_IMAGE}":"${ARCH}"-$JAVA_ENV_TAG
        fi
}

# pull fabric-ca docker images
function pull_Images() {
        getArch
        # export image list
        if [ "${projectName}" = "fabric" ]; then
            export IMAGES_LIST="${FABRIC_IMAGES[*]}"
        else
            export IMAGES_LIST="${FABRIC_CA_IMAGES[*]}"
        fi
        # pull images
        for IMAGES in ${IMAGES_LIST[*]}; do
            docker pull $NEXUS_BASE_URL/$ORG_NAME-"${IMAGES}":"${ARCH}"-$STABLE_VERSION
            docker tag $NEXUS_BASE_URL/$ORG_NAME-"${IMAGES}":"${ARCH}"-$STABLE_VERSION $ORG_NAME-"${IMAGES}":"${ARCH}"-"$RELEASE_VERSION"
            docker tag $NEXUS_BASE_URL/$ORG_NAME-"${IMAGES}":"${ARCH}"-$STABLE_VERSION $ORG_NAME-"${IMAGES}"
            docker rmi -f $NEXUS_BASE_URL/$ORG_NAME-"${IMAGES}":"${ARCH}"-$STABLE_VERSION
        done
}

cloneRepo fabric maser
buildImages fabric
