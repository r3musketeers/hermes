#!/usr/bin/env sh
export KUBERNETES_DIR=$1
export N_CLIENTS=$2
export N_THREADS=$3
export READ_RATE=$4
export SCENE=$5

export SERVICE_NAME=hermes-leader

echo "apply leader..."
kubectl apply -f $KUBERNETES_DIR/hermes-leader.yml

sleep 5

echo "wait all replicas to be ready..."
until [ "$(kubectl get deployments -l app=hermes-leader -o jsonpath="{.items[0].status.replicas}")" = "$(kubectl get deployments -l app=hermes-leader -o jsonpath="{.items[0].status.readyReplicas}")" ]
do
  sleep 5;
done

echo "wait server to be running..."
until [ "$(kubectl get pods -l app=hermes-leader -o jsonpath="{.items[0].status.phase}")" = "Running" ]
do
  sleep 5;
done

echo "apply followers..."
kubectl apply -f $KUBERNETES_DIR/hermes-followers.yml

sleep 10

echo "wait all replicas to be ready..."
until [ "$(kubectl get deployments -l app=hermes-followers -o jsonpath="{.items[0].status.replicas}")" = "$(kubectl get deployments -l app=hermes-followers -o jsonpath="{.items[0].status.readyReplicas}")" ]
do
  sleep 5;
done

echo "wait server to be running..."
until [ "$(kubectl get pods -l app=hermes-followers -o jsonpath="{.items[0].status.phase}")" = "Running" ]
do
  sleep 5;
done

sleep 10

echo "apply clients..."
envsubst < $KUBERNETES_DIR/tcp-kv-client.yml | kubectl apply -f -

echo "wait job to complete..."
kubectl wait --for=condition=complete --timeout=1h job.batch/tcp-kv-client

TEST=$(expr $N_CLIENTS \* $N_THREADS)-$N_CLIENTS

echo "collecting throughput log..."
kubectl cp $(kubectl get pods -l app=hermes-leader -o=jsonpath='{.items[0].metadata.name}'):/tmp/throughput.log logs/$SCENE/throughput/$TEST.log

echo "collecting latency log..."
kubectl logs $(kubectl get pods -l app=tcp-kv-client -o=jsonpath='{.items[0].metadata.name}') > logs/$SCENE/latency/$TEST.log

echo "deleting client..."
kubectl delete -f $KUBERNETES_DIR/tcp-kv-client.yml

echo "deleting server..."
kubectl delete -f $KUBERNETES_DIR/hermes-leader.yml
kubectl delete -f $KUBERNETES_DIR/hermes-followers.yml