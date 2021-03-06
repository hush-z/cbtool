#!/usr/bin/env bash

#/*******************************************************************************
# Copyright (c) 2012 IBM Corp.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#/*******************************************************************************

source $(echo $0 | sed -e "s/\(.*\/\)*.*/\1.\//g")/cb_hadoop_common.sh

#####################################################################################
# Hadoop cluster preparation
# - Editing configuration files
#####################################################################################

#####################################################################################
# Assumptions: 
#   1. There is only one master VM which serves as a NameNode and a 
#      Jobtracker / Resource Manager, and is not also a slave (meaning DataNode, TaskTracker).
#   2. There is at least one slave VM which is a different machine from
#       master vm.
#####################################################################################

START=`provision_application_start`

syslog_netcat "Updating local Hadoop cluster configuration files..."

hadoop_version_string=`$HADOOP_HOME/bin/hadoop version | sed '1!d'`
syslog_netcat "Hadoop home directory is ${HADOOP_HOME}"
syslog_netcat "Hadoop version is $hadoop_version_string"
syslog_netcat "Hadoop configuration directory is ${HADOOP_CONF_DIR}"

DFS_NAME_DIR=`get_my_ai_attribute_with_default dfs_name_dir /tmp/cbhadoopname`
eval DFS_NAME_DIR=${DFS_NAME_DIR}
syslog_netcat "Local directory for Hadoop namenode is ${DFS_NAME_DIR}"

DFS_DATA_DIR=`get_my_ai_attribute_with_default dfs_data_dir /tmp/cbhadoopdata`
eval DFS_DATA_DIR=${DFS_DATA_DIR}
syslog_netcat "Local directory for Hadoop datanode is ${DFS_NAME_DIR}"

mount_filesystem_on_volume $DFS_NAME_DIR ext4 ${my_login_username}

JVM_HEAP_MEM_MB=`get_my_ai_attribute_with_default jvm_heap_mem_mb 200`
eval JVM_HEAP_MEM_MB=${JVM_HEAP_MEM_MB}
syslog_netcat "JVM heap size in MB is ${JVM_HEAP_MEM_MB}"

if [[ ${hadoop_use_yarn} -eq 1 ]]
then
	syslog_netcat "Hadoop will be configured to use MRv2 (YARN)"
	syslog_netcat "Switching to the \"yarn\" branch in Hibench on ${HIBENCH_HOME}"
	cd ${HIBENCH_HOME}
	git checkout yarn
	cd ~
else
	syslog_netcat "Hadoop will be configured to use MRv1"
	syslog_netcat "Switching to the \"dev\" branch in Hibench on ${HIBENCH_HOME}"
	cd ${HIBENCH_HOME}
	git checkout dev
	cd ~	
fi

check_write_access

disable_ip_version_six

create_master_and_slaves_files

create_hadoop_config_files

update_hadoop_config_files

###################################################################
# Editing hadoop conf.xml files for the optional confs 
# as defined in cb_hadoop_common.sh
###################################################################
syslog_netcat "Applying any additional Hadoop parameters specified in cb_hadoop_common.sh..."

#core-site.xml
output_file=$HADOOP_CONF_DIR/core-site.xml
sudo sed -i -e "s/<\/configuration>//" $output_file
for k in "${!CORE_SITE_PROPERTIES[@]}"
do
	echo "<property>" >> $output_file

	content="<name>""${k}""</name>"
	echo "${content}" >> $output_file 
	content="<value>""${CORE_SITE_PROPERTIES[$k]}""</value>"
	echo "${content}" >> $output_file 

	echo "</property>" >> $output_file

done
echo "</configuration>" >> $output_file 

#hdfs-site.xml
output_file=$HADOOP_CONF_DIR/hdfs-site.xml
sudo sed -i -e "s/<\/configuration>//" $output_file
for k in "${!HDFS_SITE_PROPERTIES[@]}"
do
	echo "<property>" >> $output_file

	content="<name>""${k}""</name>"
	echo "${content}" >> $output_file 
	content="<value>""${HDFS_SITE_PROPERTIES[$k]}""</value>"
	echo "${content}" >> $output_file 

	echo "</property>" >> $output_file

done
echo "</configuration>" >> $output_file 

#mapred-site.xml
output_file=$HADOOP_CONF_DIR/mapred-site.xml
sudo sed -i -e "s/<\/configuration>//" $output_file
for k in "${!MAPRED_SITE_PROPERTIES[@]}"
do
	echo "<property>" >> $output_file

	content="<name>""${k}""</name>"
	echo "${content}" >> $output_file 
	content="<value>""${MAPRED_SITE_PROPERTIES[$k]}""</value>"
	echo "${content}" >> $output_file 

	echo "</property>" >> $output_file

done
echo "</configuration>" >> $output_file
syslog_netcat "...Done applying any additional Hadoop parameters."

copy_hadoop_config_files_to_etc

configure_hadoop_ganglia_collection

#####################################################################################
# If there is an updated example benchmarks jar, put it in its right place.
#####################################################################################

if [[ -f ~/${REMOTE_DIR_NAME}/scripts/giraph/giraph-examples-1.1.0-SNAPSHOT-for-hadoop-1.2.1-jar-with-dependencies.jar ]]
then 
    mv ~/${REMOTE_DIR_NAME}/scripts/giraph/giraph-examples-1.1.0-SNAPSHOT-for-hadoop-1.2.1-jar-with-dependencies.jar ${GIRAPH_HOME}/giraph-examples/target/
    rm -f ~/giraph-examples-1.1.0-SNAPSHOT-for-hadoop-1.2.1-jar-with-dependencies.jar
fi

#####################################################################################
# Create Ramdisk backing for out-of-core giraph if required.
#####################################################################################

USE_OUT_OF_CORE=`get_my_ai_attribute_with_default use_out_of_core false`
OUT_OF_CORE_BASE_DIRECTORY=`get_my_ai_attribute_with_default out_of_core_base_directory /tmp`
USE_RAMDISK=`get_my_ai_attribute_with_default use_ramdisk false`
RAMDISK_SIZE_MB=`get_my_ai_attribute_with_default ramdisk_size_mb 100`

if [[ ${USE_OUT_OF_CORE} == "True" ]]
then

    if [[ ${USE_RAMDISK} == "True" ]]
    then
    	mount_filesystem_on_memory $OUT_OF_CORE_BASE_DIRECTORY tmpfs ${RAMDISK_SIZE_MB}m
    fi

    sudo mkdir $OUT_OF_CORE_BASE_DIRECTORY/partitions 2> /dev/null
    sudo mkdir $OUT_OF_CORE_BASE_DIRECTORY/messages 2> /dev/null
    sudo rm -rf $OUT_OF_CORE_BASE_DIRECTORY/partitions/* 2> /dev/null
    sudo rm -rf $OUT_OF_CORE_BASE_DIRECTORY/messages/* 2> /dev/null
    sudo chmod -R a+rw $OUT_OF_CORE_BASE_DIRECTORY 2> /dev/null
fi

###

syslog_netcat "Done updating local Hadoop cluster configuration files."
exit 0
