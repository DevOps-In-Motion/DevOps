kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io <name> -o yaml > <name>.yaml 


kubectl apply -k patch-weebhooks-config-ignore-kubiya-namespace.yaml