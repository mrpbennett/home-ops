#!/bin/bash

echo "=== Step 1: Check if PrometheusRule was created ==="
kubectl get prometheusrules -n monitoring
echo ""

echo "=== Step 2: Check the specific rule we created ==="
kubectl get prometheusrule -n monitoring -l app.kubernetes.io/name=kube-prometheus-stack -o yaml | grep -A 5 "pod-memory"
echo ""

echo "=== Step 3: Check Prometheus targets are up ==="
echo "Check if these targets are healthy in Prometheus UI:"
echo "https://prometheus.70ld.dev/targets"
echo ""

echo "=== Step 4: Check if alerts are loaded in Prometheus ==="
echo "Go to: https://prometheus.70ld.dev/alerts"
echo "Look for: PodMemoryRequestsExceeded, PodMemoryRequestsCritical, etc."
echo ""

echo "=== Step 5: Test the PromQL queries directly ==="
echo "Go to Prometheus and run these queries:"
echo ""
echo "# Check if metrics exist:"
echo "container_memory_working_set_bytes{container!=\"\",container!=\"POD\"}"
echo ""
echo "kube_pod_container_resource_requests{resource=\"memory\"}"
echo ""
echo "# Test the actual alert expression:"
echo "(container_memory_working_set_bytes{container!=\"\",container!=\"POD\"} / (kube_pod_container_resource_requests{resource=\"memory\"} > 0)) > 0.8"
echo ""

echo "=== Step 6: Check if your test pods are running ==="
kubectl get pods -n default -o wide | grep -E "memory-|cpu-|oom-|frequent"
echo ""

echo "=== Step 7: Check pod resource metrics ==="
echo "Run this to see actual memory usage vs requests:"
kubectl get pods -n default -o json | jq -r '.items[] | select(.metadata.name | test("memory|oom")) | {
  name: .metadata.name,
  containers: [.spec.containers[] | {
    name: .name,
    requests: .resources.requests,
    limits: .resources.limits
  }]
}'
echo ""

echo "=== Step 8: Check Prometheus Operator logs ==="
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator --tail=50
echo ""

echo "=== Step 9: Check if Prometheus is scraping kube-state-metrics ==="
echo "Run this query in Prometheus:"
echo "up{job=\"kube-state-metrics\"}"
echo ""

echo "=== Step 10: Verify alertmanager is receiving alerts ==="
echo "Check: https://alertmanager.70ld.dev"
echo ""

echo "=== Step 11: Check Alertmanager config ==="
kubectl get secret -n monitoring alertmanager-kube-prometheus-stack-alertmanager -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
echo ""

echo "=== Step 12: Manual test - Create a simple firing alert ==="
cat <<'EOF'
Run this in Prometheus UI to create an instant alert:
Go to: https://prometheus.70ld.dev/graph

Query: vector(1) > 0
This should always fire.

Then check if it appears in Alertmanager.
EOF
echo ""

echo "=== Step 13: Check the namespace of test pods ==="
echo "Your alerts are looking for pods in any namespace."
echo "Verify your test pods are visible to Prometheus:"
kubectl get pods --all-namespaces | grep -E "memory-|cpu-|oom-"
echo ""

echo "=== Step 14: Force Prometheus to reload configuration ==="
kubectl rollout restart statefulset -n monitoring prometheus-kube-prometheus-stack-prometheus
echo "Wait 1-2 minutes for Prometheus to restart..."
echo ""
