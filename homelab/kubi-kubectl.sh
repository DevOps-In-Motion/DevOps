debug pod/agent-manager-6ffc98ff98-7fsbk -n kubiya --image=busybox --target=agent-manager -- sleep 3600


Which pods are consuming the most CPU and memory in the last hour?
Are there any pods running with privileged containers?
can you help me to understand traffic routing to pods in kubiya namespace?
Check the services defined in the kubiya namespace to see which pods they route to?
can you validate all the CA certs within this cluster and let me know the expiration date?
Can you analysis the reason of "Crashloopback" pod on default namespace?
can you send me the list of node names having events?
Can you enable debug container for pod/agent-manager-5b85f7f6d8-n92sc
Can you send me the list of all the pods having more than 5 restarts in all namespaces?
Can you get me the list of pods where resource is not defined?
Can you get me the list of incorrect configuration on this k8s clusters?




{
    "communication": {
        "destination": "#kubiya-teammate",
        "method": "Slack"
    },
    "logs": "Can you send me the list of all the pods having more than 5 restarts in all namespaces?"
}