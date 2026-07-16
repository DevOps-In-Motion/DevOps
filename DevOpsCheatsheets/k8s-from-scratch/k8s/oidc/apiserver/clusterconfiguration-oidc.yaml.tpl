# Durable kubeadm ClusterConfiguration fragment — OIDC via apiServer.extraArgs.
# Render with envsubst (see render-kubeadm-oidc.sh). Never hand-edit the static Pod.
#
# Tokens: ${OIDC_ISSUER_URL} ${OIDC_CLIENT_ID} ${OIDC_USERNAME_CLAIM}
#         ${OIDC_GROUPS_CLAIM} ${OIDC_USERNAME_PREFIX} ${OIDC_GROUPS_PREFIX}
#         ${OIDC_CA_FILE}

apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v1.36.2"
controlPlaneEndpoint: "192.168.56.101:6443"
apiServer:
  extraArgs:
    - name: enable-admission-plugins
      value: NodeRestriction
    - name: audit-log-path
      value: /var/log/kubernetes/audit.log
    - name: oidc-issuer-url
      value: "${OIDC_ISSUER_URL}"
    - name: oidc-client-id
      value: "${OIDC_CLIENT_ID}"
    - name: oidc-username-claim
      value: "${OIDC_USERNAME_CLAIM}"
    - name: oidc-groups-claim
      value: "${OIDC_GROUPS_CLAIM}"
    - name: oidc-username-prefix
      value: "${OIDC_USERNAME_PREFIX}"
    - name: oidc-groups-prefix
      value: "${OIDC_GROUPS_PREFIX}"
    - name: oidc-ca-file
      value: "${OIDC_CA_FILE}"
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  dnsDomain: "cluster.local"
