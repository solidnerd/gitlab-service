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


print "Installing GitLab cluster ..."
k3d cluster create \
    -p 1443:443@loadbalancer \
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
helm repo add gitlab https://charts.gitlab.io/ || helm repo update gitlab


echo "Starting Helm Deployment"
helm upgrade --install --namespace gitlab gitlab gitlab/gitlab \
    --set global.hosts.domain=$DOMAIN \
    --set certmanager.install=false \
    --set global.ingress.configureCertmanager=false \
    --set global.ingress.tls.secretName=tls-certs \
    --set global.certificates.customCAs[0].secret=custom-ca

echo ""
echo "Connect to https://gitlab.$DOMAIN:1443"

echo "Fetch your Admin Password with"
echo "kubectl get secret gitlab-gitlab-initial-root-password -o jsonpath='{.data.password}' | base64 --decode | pbcopy"
