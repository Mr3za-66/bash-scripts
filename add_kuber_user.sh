#!/bin/bash
set -e
set -o pipefail

if [[ -z "$1" ]] || [[ -z "$2" ]]; then
 echo "run export KUBECONFIG=/root/.kube/stage/config before running the script. make sure instead of kube.indraproject.ir, you are accessing to kuber API via masters IP."
 echo "usage: $0 <service_account_name> <namespace>"
 exit 1
fi

SERVICE_ACCOUNT_NAME=$1
NAMESPACE="$2"
KUBECFG_FILE_NAME="/tmp/kube/k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"
TARGET_FOLDER="/tmp/kube"

create_target_folder() {
    echo -n "Creating target directory to hold files in ${TARGET_FOLDER}..."
    mkdir -p "${TARGET_FOLDER}"
    printf "done"
}

create_service_account() {
    echo -e "\\nCreating a service account in ${NAMESPACE} namespace: ${SERVICE_ACCOUNT_NAME}"
    kubectl create sa "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}"
}


extract_ca_crt_from_secret() {
    echo -e -n "\\nExtracting ca.crt from Config..."
    kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > "${TARGET_FOLDER}/ca.crt"
    printf "done"
}

get_user_token_from_secret() {
    echo -e -n "\\nGetting user token from secret..."
    USER_TOKEN=$(kubectl create token "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}")
    printf "done"
}

set_kube_config_values() {
    context=$(kubectl config current-context)
    echo -e "\\nSetting current context to: $context"

    CLUSTER_NAME=$(kubectl config get-contexts "$context" | awk '{print $3}' | tail -n 1)
    echo "Cluster name: ${CLUSTER_NAME}"

    ENDPOINT=$(kubectl config view \
    -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")
    echo "Endpoint: ${ENDPOINT}"

    # Set up the config
    echo -e "\\nPreparing k8s-${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-conf"
    echo -n "Setting a cluster entry in kubeconfig..."
    kubectl config set-cluster "${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --server="${ENDPOINT}" \
    --certificate-authority="${TARGET_FOLDER}/ca.crt" \
    --embed-certs=true

    echo -n "Setting token credentials entry in kubeconfig..."
    kubectl config set-credentials \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --token="${USER_TOKEN}"

    echo -n "Setting a context entry in kubeconfig..."
    kubectl config set-context \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --namespace="${NAMESPACE}"

    echo -n "Setting the current-context in the kubeconfig file..."
    kubectl config use-context "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}"
}
create_rbac() {
echo "start applying RBAC"
   cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${SERVICE_ACCOUNT_NAME}-clusterrole
rules:
- apiGroups:
  - ""
  - apps
  - extensions
  - batch
  resources:
  - deployments
  - replicasets
  - services
  - jobs
  - cronjobs
  - pods
  - secrets
  - configmaps
  verbs:
  - create
  - get
  - list
  - patch
  - update
  - watch
- apiGroups:
  - networking.k8s.io
  - autoscaling
  - monitoring.coreos.com
  resources:
  - ingresses
  - horizontalpodautoscalers
  - podmonitors
  - servicemonitors
  verbs: ["get", "list", "watch", "create", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ${SERVICE_ACCOUNT_NAME}-clusterrole
subjects:
- kind: User
  name: system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

}
create_target_folder
create_service_account
extract_ca_crt_from_secret
get_user_token_from_secret
create_rbac
set_kube_config_values

echo -e "\\nAll done!"
echo -e "\\n Kubeconfig directory: ${KUBECFG_FILE_NAME}"
