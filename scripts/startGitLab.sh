#!/bin/bash
set -e
set -o pipefail

err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

print() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*"
}

print "Removing existing installation if exists ..."
k3d cluster delete gitlab || true


K3S_IMAGE="rancher/k3s:v1.19.5-k3s2"

print "Installing GitLab cluster ($K3S_IMAGE) ..."
k3d cluster create \
    --image "$K3S_IMAGE" \
    --port 443:443@loadbalancer \
    --k3s-server-arg --disable=traefik \
    --switch-context \
    gitlab

IP=$(ipconfig getifaddr en0)

DOMAIN="dev.$IP.nip.io"

echo "Creating self-signed CA certificates for TLS and installing them in the local trust stores"
CA_CERTS_FOLDER=$(pwd)/.certs

echo ${CA_CERTS_FOLDER}
rm -rf ${CA_CERTS_FOLDER}
mkdir -p ${CA_CERTS_FOLDER}
mkdir -p ${CA_CERTS_FOLDER}/${ENVIRONMENT_DEV}
CAROOT=${CA_CERTS_FOLDER}/${ENVIRONMENT_DEV}

CAROOT=$CAROOT mkcert -install

CAROOT=$CAROOT mkcert \
-cert-file "fullchain.pem" \
-key-file "privkey.pem" \
"$DOMAIN" \
"*.$DOMAIN" \
"*.gitlab.$DOMAIN" \
"*.keptn.$DOMAIN" \

kubectl create ns gitlab

kubectl -n gitlab create secret tls tls-certs \
    --cert="fullchain.pem" \
    --key="privkey.pem"

kubectl -n gitlab create secret generic custom-ca --from-file=unique_name=$(pwd)/.certs/rootCA.pem
# kubectl create secret generic custom-ca --from-file=unique_name=$(pwd)/.certs/rootCA.pem


echo "Adding GitLab Helm Repo"
helm repo add gitlab https://charts.gitlab.io/ || helm repo update


echo "Starting Helm Deployment"
# The resource requests have increased for the Webservice and Sidekiq charts.
# Related merge request: https://gitlab.com/gitlab-org/charts/gitlab/-/merge_requests/1634
helm upgrade --install --namespace gitlab gitlab gitlab/gitlab \
    --set global.hosts.domain=$DOMAIN \
    --set certmanager.install=false \
    --set global.ingress.configureCertmanager=false \
    --set global.ingress.tls.secretName=tls-certs \
    --set global.certificates.customCAs[0].secret=custom-ca \
    --set gitlab.sidekiq.resources.requests.cpu=50m \
    --set gitlab.sidekiq.resources.requests.memory=650M \
    --set gitlab.webservice.resources.requests.memory=1.5G 

echo ""
echo "Connect to https://gitlab.$DOMAIN:8443"

echo "Fetch your Admin Password with"
echo "kubectl get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 --decode | pbcopy"
