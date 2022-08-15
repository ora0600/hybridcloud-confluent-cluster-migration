#!/bin/bash
export ENVID=$(awk '/id:/{print $NF}' env)
export CLUSTERID2KEY=$(awk '/key:/{print $NF}' clusterid2_key)
export CLUSTERID2SECRET=$(awk '/secret:/{print $NF}' clusterid2_key )
export CCLOUD_CLUSTERID2_BOOTSTRAP=$(awk '/endpoint: SASL_SSL:\/\//{print $NF}' clusterid2 | sed 's/SASL_SSL:\/\///g')
export CCLOUD_CLUSTERID2=$(awk '/id:/{print $NF}' clusterid2)
export topic2=project.b1.inventory
export topic1=project.a1.orders

echo "delete everything form this demo"
echo "destination cluster topics and link"
# delete topics in destination
confluent kafka topic delete $topic1 --cluster $CCLOUD_CLUSTERID2 --environment $ENVID 
confluent kafka topic delete $topic2 --cluster $CCLOUD_CLUSTERID2 --environment $ENVID 
# drop cluster link
confluent kafka link delete from-on-prem-link --cluster $CCLOUD_CLUSTERID2 --environment $ENVID

echo "Source cluster"
kafka-topics --delete --topic $topic1 --bootstrap-server localhost:9092 --command-config $BASEDIR/CP-command.config
kafka-topics --delete --topic $topic2 --bootstrap-server localhost:9092 --command-config $BASEDIR/CP-command.config
kafka-cluster-links --bootstrap-server localhost:9092 \
     --delete --link from-on-prem-link \
     --config-file $CONFLUENT_CONFIG/clusterlink-CP-src.config \
     --cluster-id $CC_CLUSTER_ID --command-config $BASEDIR/CP-command.config

echo "ccloud API Keys"
confluent api-key delete $CLUSTERID2KEY

echo "ccloud cluster"
confluent kafka cluster delete $CCLOUD_CLUSTERID2 --environment $envirENVIDonment

echo "ccloud environment"
confluent environment delete $ENVID

# stop cluster
echo "stop on-prem cluster"
zookeeper-server-stop
kafka-server-stop
confluent local destroy

echo "files"
rm CP-command.config
rm basedir
rm clusterID
rm clusterid2
rm clusterid2_key
rm env
rm clusterlink-CP-src.config
rm clusterlink-hybrid-dst.config
rm server-clusterlinking.properties 
rm zookeeper-clusterlinking.properties

echo "Demo Environment deleted"