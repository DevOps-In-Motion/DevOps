"""Kubernetes web application ComponentResource.

Encapsulates a Deployment + LoadBalancer Service that run the Dockerized
Node app and inject the Pulumi-configured greeting via the NAME env var.
"""

from __future__ import annotations

import pulumi
from pulumi import ComponentResource, Input, ResourceOptions
import pulumi_kubernetes as k8s


class WebAppArgs:
    """Inputs for WebApp."""

    def __init__(
        self,
        image: Input[str],
        greeting: str,
        replicas: int = 2,
        container_port: int = 8080,
    ):
        self.image = image
        self.greeting = greeting
        self.replicas = replicas
        self.container_port = container_port


class WebApp(ComponentResource):
    """Deploys the greeting web app onto a Kubernetes cluster."""

    def __init__(self, name: str, args: WebAppArgs, opts: ResourceOptions | None = None):
        super().__init__("interview:kubernetes:WebApp", name, None, opts)

        child_opts = ResourceOptions(parent=self)
        labels = {"app": name}

        self.deployment = k8s.apps.v1.Deployment(
            f"{name}-deployment",
            metadata=k8s.meta.v1.ObjectMetaArgs(
                name=name,
                labels=labels,
            ),
            spec=k8s.apps.v1.DeploymentSpecArgs(
                replicas=args.replicas,
                selector=k8s.meta.v1.LabelSelectorArgs(match_labels=labels),
                template=k8s.core.v1.PodTemplateSpecArgs(
                    metadata=k8s.meta.v1.ObjectMetaArgs(labels=labels),
                    spec=k8s.core.v1.PodSpecArgs(
                        containers=[
                            k8s.core.v1.ContainerArgs(
                                name=name,
                                image=args.image,
                                ports=[
                                    k8s.core.v1.ContainerPortArgs(
                                        container_port=args.container_port,
                                    )
                                ],
                                # Pulumi config → container env → server.js process.env.NAME
                                env=[
                                    k8s.core.v1.EnvVarArgs(
                                        name="NAME",
                                        value=args.greeting,
                                    )
                                ],
                                resources=k8s.core.v1.ResourceRequirementsArgs(
                                    requests={"cpu": "100m", "memory": "128Mi"},
                                    limits={"cpu": "250m", "memory": "256Mi"},
                                ),
                            )
                        ],
                    ),
                ),
            ),
            opts=child_opts,
        )

        self.service = k8s.core.v1.Service(
            f"{name}-service",
            metadata=k8s.meta.v1.ObjectMetaArgs(
                name=name,
                labels=labels,
            ),
            spec=k8s.core.v1.ServiceSpecArgs(
                type="LoadBalancer",
                selector=labels,
                ports=[
                    k8s.core.v1.ServicePortArgs(
                        port=80,
                        target_port=args.container_port,
                        protocol="TCP",
                    )
                ],
            ),
            opts=child_opts,
        )

        # Hostname / IP from the AWS load balancer provisioned for the Service
        self.endpoint = self.service.status.apply(_service_endpoint)

        self.register_outputs(
            {
                "endpoint": self.endpoint,
                "deployment": self.deployment.metadata.apply(lambda m: m.name if m else None),
                "service": self.service.metadata.apply(lambda m: m.name if m else None),
            }
        )


def _service_endpoint(status) -> str | None:
    if not status or not status.load_balancer or not status.load_balancer.ingress:
        return None
    ingress = status.load_balancer.ingress[0]
    return ingress.hostname or ingress.ip
