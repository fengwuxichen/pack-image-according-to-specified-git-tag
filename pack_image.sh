#!/bin/bash

if [ $# -ne 4 ];then
    echo "Usage: `basename $0` <project_name> <history_tag> <region> <docker_registry>"
    exit 2
fi

PROJECT_NAME=$1
HISTORY_TAG=$2
REGION=$3
DR=$4
BASEPATH=$(cd `dirname $0`; pwd)

GIT_CLONE_ADDR=`awk -F"|" '{if($1=="'${PROJECT_NAME}'") print$2}' project_info`
SCRIPT_FILE=`awk -F"|" '{if($1=="'${PROJECT_NAME}'") print$3}' project_info`
PROJECT_DIR=`awk -F"|" '{if($1=="'${PROJECT_NAME}'") print "'${PROJECT_NAME}'""/"$4}' project_info`
if [ X${GIT_CLONE_ADDR} == X"" -o X${SCRIPT_FILE} == X"" -o X${PROJECT_DIR} == X"" ];then
    echo "[ERROR] `date '+%Y-%m-%d %H:%M:%S'` - Failed to retrieve project ${PROJECT_NAME} in configuration file: project_info." >> ${BASEPATH}/build_result.log
    exit 1
fi

mkdir -p $PROJECT_NAME
rm -rf ${BASEPATH}/${PROJECT_DIR}
cd $PROJECT_NAME
git clone ${GIT_CLONE_ADDR} 


if [ X"$?" == X"0" ];then
    echo "[INFO] Git clone ${PROJECT_NAME} successfully"
    if [ `cd ${BASEPATH}/${PROJECT_DIR} && git tag -v ${HISTORY_TAG} 2>/dev/null | grep object | wc -l` -eq 0 ];then   
	    echo "[ERROR] `date '+%Y-%m-%d %H:%M:%S'` - Not found tag ${HISTORY_TAG} in project ${PROJECT_NAME}." >> ${BASEPATH}/build_result.log
	    exit 1
    fi
else
    echo "[ERROR] `date '+%Y-%m-%d %H:%M:%S'` - Clone project ${PROJECT_NAME} failed." >> ${BASEPATH}/build_result.log
    exit 1
fi

REGION_TAG=`echo ${HISTORY_TAG} | awk -F"_" '{print "'${REGION}'_"$NF}'`
IMAGE=${DR}/${PROJECT_NAME}:${REGION_TAG}

#创建目标tag分支
cd ${BASEPATH}/${PROJECT_DIR}
git checkout -B branch_${HISTORY_TAG} ${HISTORY_TAG}

#临时修改打包脚本文件
sed -i 's#${CI_BUILD_TAG}_${CI_BUILD_REF}#'$REGION_TAG'#1'  ${SCRIPT_FILE}
sed -i 's/docker push $image//' ${SCRIPT_FILE}

#获取创建镜像的脚本执行方法并执行
EXEC_BUILD_SCRIPT=`awk -F"bash" '{if($NF~/.\/'${SCRIPT_FILE}' bp original_registry:5000/) print $NF}' .gitlab-ci.yml | sed 's/original_registry:5000/'${DR}'/'`


#例外
<<HERECOMMENT
if [ *** ];then
    EXEC_BUILD_SCRIPT="***"
elif [ *** ];then
    EXEC_BUILD_SCRIPT="***"
fi
HERECOMMENT

echo "[INFO]-Begin to build image ${IMAGE}"
bash $EXEC_BUILD_SCRIPT

if [ X"$?" == X"0" -a X"`docker images -q $IMAGE | wc -l`" == X"1" ]; then
    echo "[INFO] `date '+%Y-%m-%d %H:%M:%S'` - Build image ${IMAGE} successfully." >> ${BASEPATH}/build_result.log
    echo "[INFO] Clear the temp branch now"
    git checkout -- ${SCRIPT_FILE}
    git checkout master
    git branch -D branch_${HISTORY_TAG}
    docker push $IMAGE
    if [ X"$?" == X"0" ]; then
        echo "[INFO] Push $image successfully"
	    docker rmi $IMAGE
	    rm -fr ${BASEPATH}/${PROJECT_NAME}
    else
        echo "[ERROR] Push image ${IMAGE} to docker-registry ${DR} failed"
    fi
else
    echo "[ERROR] `date '+%Y-%m-%d %H:%M:%S'` - Build image ${IMAGE} failed." >> ${BASEPATH}/build_result.log
fi

