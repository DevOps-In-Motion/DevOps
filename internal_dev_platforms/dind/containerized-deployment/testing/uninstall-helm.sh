#!/usr/bin/env bash
# Uninstall kube-prometheus-stack (Prometheus operator, Grafana, etc.).
# Matches the install in helm-test.sh: release prometheus-operator in namespace monitoring.

helm uninstall prometheus-operator -n monitoring

helm uninstall wiki-api -n wiki-api