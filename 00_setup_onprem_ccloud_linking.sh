#!/bin/bash
# on-prem with source intiated link to ccloud, follow Official Site https://docs.confluent.io/cloud/current/multi-cloud/cluster-linking/hybrid-cc.html
# prereq confluent cli, java 11 are installed, ccloud account

pwd > basedir
export BASEDIR=$(cat basedir)
echo $BASEDIR
echo ">>>>>>>>>>>> Start setup..."
echo ">> Download Confluent and install Software"
#download software Confluent Software
#cd WHERETOINSTALL
#wget https://packages.confluent.io/archive/7.2/confluent-7.2.1.tar.gz
#tar -xvf confluent-7.2.1.tar.gz
#rm confluent-7.2.1.tar.gz
#rm confluent
#ln -s confluent-7.2.1/ confluent
# set environment
export CONFLUENT_HOME=YOURPATH
#export CONFLUENT_CONFIG=$CONFLUENT_HOME/etc/kafka
# set Java11
export JAVA_HOME=YOURPATH

export topic1=project.a1.orders
export topic2=project.b1.inventory

echo ">> create on-prem cluster config files"
# switch to demo dir
cd $BASEDIR
# prepare on-prem cluster
# zookeeper
echo "dataDir=/tmp/zookeeper
clientPort=2181" > $BASEDIR/zookeeper-clusterlinking.properties
# broker
echo "broker.id=0
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/tmp/kafka-logs
num.partitions=1
num.recovery.threads.per.data.dir=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=localhost:2181
zookeeper.connection.timeout.ms=18000
group.initial.rebalance.delay.ms=0
confluent.license.topic.replication.factor=1
confluent.metadata.topic.replication.factor=1
confluent.security.event.logger.exporter.kafka.topic.replicas=1
confluent.balancer.enable=true
confluent.balancer.topic.replication.factor=1
#These must be added to the existing file:
inter.broker.listener.name=SASL_PLAINTEXT
sasl.enabled.mechanisms=SCRAM-SHA-512
sasl.mechanism.inter.broker.protocol=SCRAM-SHA-512
listener.name.sasl_plaintext.scram-sha-512.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="kafka" password="kafka-secret";
confluent.reporters.telemetry.auto.enable=false
confluent.cluster.link.enable=true
password.encoder.secret=encoder-secret
listeners=SASL_PLAINTEXT://:9092
advertised.listeners=SASL_PLAINTEXT://:9092" > $BASEDIR/server-clusterlinking.properties

# run each component in a differen cluster
echo ">> start zookeeper"
zookeeper-server-start -daemon $BASEDIR//zookeeper-clusterlinking.properties
echo ">> started zookeeper wait 30 sec"
sleep 30
#Run commands to create SASL SCRAM credentials on the cluster for two users
# User 1
kafka-configs --zookeeper localhost:2181 --alter --add-config 'SCRAM-SHA-512=[iterations=8192,password=kafka-secret]' --entity-type users --entity-name kafka
# User 2
kafka-configs --zookeeper localhost:2181 --alter --add-config 'SCRAM-SHA-512=[iterations=8192,password=admin-secret]' --entity-type users --entity-name admin
# Create a file with the admin credentials to authenticate when you run commands against the Confluent Platform cluster.
echo "sasl.mechanism=SCRAM-SHA-512
security.protocol=SASL_PLAINTEXT
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"admin\" password=\"admin-secret\";" > $BASEDIR//CP-command.config  
echo "Zookeeper started"  

# Start Broker
echo ">> start Broker"
kafka-server-start -daemon $BASEDIR//server-clusterlinking.properties
echo ">> started broker wait 30 sec"
sleep 30
# get the cluster ID
kafka-cluster cluster-id --bootstrap-server localhost:9092 --config $BASEDIR/CP-command.config > clusterID
export CP_CLUSTER_ID=$(awk '/Cluster ID:/{print $NF}' clusterID)
echo ">> Broker started"
echo ">> please check errors on console, if so stop here (CTRL+C).If no errors, continue with dedicated cluster creation by PRESSING ENTER..."
read

# Create topics in source cluster on-prem
echo ">> Start: create Topic $topic1 in source cluster and produce and consume data"
# Create topics
echo ">>   create topic1"
kafka-topics --create --topic $topic1 --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 --command-config $BASEDIR/CP-command.config
# produce
echo ">>   produce data"
seq 1 5 | kafka-console-producer --topic $topic1 --bootstrap-server localhost:9092 --producer.config $BASEDIR/CP-command.config
# consume
echo ">>   consume data, end with CTRL+c"
kafka-console-consumer --topic $topic1 --from-beginning --bootstrap-server localhost:9092 --consumer.config $BASEDIR/CP-command.config
# second topic
echo ">> Start: create Topic $topic2 in source cluster and produce and consume data"
echo ">>   create topic"
kafka-topics --create --topic $topic2 --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 --command-config $BASEDIR/CP-command.config
# produce
echo ">>   produce data"
seq 1 5 | kafka-console-producer --topic $topic2 --bootstrap-server localhost:9092 --producer.config $BASEDIR/CP-command.config
# consume
echo ">>   consume data, end with CTRL+c"
kafka-console-consumer --topic $topic2 --from-beginning --bootstrap-server localhost:9092 --consumer.config $BASEDIR/CP-command.config


# create a dedicated cluster
echo ">> start creation of dedicated cluster in Confluent Cloud"
export uuid=$(uuidgen)
export env=clinking-$uuid
# create cluster source and env
confluent login
# Environments
echo ">> confluent environment create $env"
confluent environment create $env -o yaml > env
export ENVID=$(awk '/id:/{print $NF}' env)
echo $ENVID
# Cluster
confluent kafka cluster create clinkingcluster --cloud 'gcp' --region 'europe-west1' --type dedicated --availability single-zone --cku 1 --environment $ENVID -o yaml > clusterid2
echo ">> clusters created wait 30 sec"
sleep 30
# set cluster id as parameter
export CCLOUD_CLUSTERID2=$(awk '/id:/{print $NF}' clusterid2)
echo ">> Wait for dedicated cluster created wait 30 minutes"
sleep 1800
echo ">> 30 minutes are over, please check dedicated cluster is runing, then PRESS ENTER..."
read
echo ">> Describe cluster"
confluent kafka cluster describe $CCLOUD_CLUSTERID2 --environment $ENVID -o yaml > clusterid2
export CCLOUD_CLUSTERID2_BOOTSTRAP=$(awk '/endpoint: SASL_SSL:\/\//{print $NF}' clusterid2 | sed 's/SASL_SSL:\/\///g')
cat clusterid2
# Create API Keys for destination cluster
confluent api-key create --resource $CCLOUD_CLUSTERID2 --description " Key for $CCLOUD_CLUSTERID2" --environment $ENVID -o yaml > clusterid2_key
export CLUSTERID2KEY=$(awk '/key:/{print $NF}' clusterid2_key)
export CLUSTERID2SECRET=$(awk '/secret:/{print $NF}' clusterid2_key )
echo ">> Key for cloudcluster"
cat clusterid2_key
echo ">> API key for cluster created wait 30 sec..."
sleep 30

export environment=$ENVID
export source_id=$CP_CLUSTER_ID
export source_endpoint=localhost:9092
export destination_id=$CCLOUD_CLUSTERID2
export destination_endpoint=$CCLOUD_CLUSTERID2_BOOTSTRAP
export destinationkey=$CLUSTERID2KEY
export destinationsecret=$CLUSTERID2SECRET

echo ">> ccloud cluster are created:$source_id on-prem and $CCLOUD_CLUSTERID2 in Confluent cloud"

# use created environment
confluent environment use $environment

echo ">>  Start Setup of linkingCluster in Confluent cloud"
# Create a link configuration file $BASEDIR/clusterlink-hybrid-dst.config with the following entries
echo ">> Create cluster link in cluster in cloud with mode inbound"
echo "link.mode=DESTINATION
connection.mode=INBOUND" > $BASEDIR/clusterlink-hybrid-dst.config
# Create the destination cluster link on Confluent Cloud.
confluent kafka link create from-on-prem-link --cluster $destination_id \
  --source-cluster-id $CP_CLUSTER_ID \
  --config-file $BASEDIR/clusterlink-hybrid-dst.config
# Describe cluster link
confluent kafka link describe from-on-prem-link --cluster $destination_id

# Create security credentials for the cluster link on Confluent Platform. This security credential will be used to read topic data and metadata from the source cluster.
kafka-configs --bootstrap-server localhost:9092 --alter --add-config \
  'SCRAM-SHA-512=[iterations=8192,password=1LINK2RUL3TH3MALL]' \
  --entity-type users --entity-name cp-to-cloud-link \
  --command-config $BASEDIR/CP-command.config
# Create a link configuration file $BASEDIR/clusterlink-CP-src.config for the source cluster link on Confluent Platform with the following entries:
echo "link.mode=SOURCE
connection.mode=OUTBOUND
bootstrap.servers=$destination_endpoint
ssl.endpoint.identification.algorithm=https
security.protocol=SASL_SSL
sasl.mechanism=PLAIN
sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='$destinationkey' password='$destinationsecret';

local.listener.name=SASL_PLAINTEXT
local.security.protocol=SASL_PLAINTEXT
local.sasl.mechanism=SCRAM-SHA-512
local.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"cp-to-cloud-link\" password=\"1LINK2RUL3TH3MALL\";" > $BASEDIR/clusterlink-CP-src.config

# Create link on on-prem cluster
kafka-cluster-links --bootstrap-server localhost:9092 \
     --create --link from-on-prem-link \
     --config-file $BASEDIR/clusterlink-CP-src.config \
     --cluster-id $destination_id --command-config $BASEDIR/CP-command.config

# list link
kafka-cluster-links --list --bootstrap-server localhost:9092 --command-config $BASEDIR/CP-command.config

# create mirror topics
echo ">> create mirror topics"
confluent environment use $ENVID
confluent kafka cluster use $destination_id
confluent kafka mirror create $topic1 --cluster $destination_id --link from-on-prem-link
confluent kafka mirror create $topic2 --cluster $destination_id --link from-on-prem-link
confluent kafka mirror list --cluster $destination_id

# Produce data to source
echo ">> produce data to source"
seq 6 10 | kafka-console-producer --topic $topic1 --bootstrap-server localhost:9092 --producer.config $BASEDIR/CP-command.config
echo ">> Consume data from destination"
confluent kafka topic consume $topic1 --from-beginning --environment $environment --cluster $destination_id --api-key $destinationkey

# End of DR Cluster Setup
echo "<<<<<<<<<<<< End of Cluster Setup"
