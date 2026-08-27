# Production observability

This directory contains the prepared Grafana dashboards for the production
Operational Hub stack. Terraform keeps observability disabled by default. No
AWS or Kubernetes resources are created until `enable_observability = true` is
explicitly planned and applied for production.

## Components

- Amazon Managed Service for Prometheus (AMP), 30-day retention.
- An in-cluster Prometheus collector with a 60-second scrape interval and a
  remote-write allowlist to keep cardinality and cost bounded.
- `postgres_exporter` for mandatory PostgreSQL statistics.
- Amazon Managed Grafana with AMP and CloudWatch access.
- Five dashboards under `grafana/`.

## Dashboard coverage

- `operational-hub-overview.json`: service health, traffic, errors, latency,
  pods, database availability, BigQuery errors, and cache hit ratio.
- `operational-hub-application.json`: HTTP method/route execution, response
  codes, local JCache hit/miss statistics, and BigQuery execution/cache/cost
  signals.
- `operational-hub-jvm-hikari.json`: JVM uptime, CPU, heap, GC, threads, file
  descriptors, and Hikari connection-pool saturation and acquisition latency.
- `operational-hub-postgresql.json`: connections, transactions, scans, cache
  hit rate, deadlocks, temporary files, locks, long-running transactions,
  checkpoints, and live/dead rows.
- `operational-hub-kubernetes.json`: pod readiness/restarts, CPU, throttling,
  memory, deployment replicas, and HPA state.

Token/user labels, request bodies, Debezium panels, and VM-specific panels are
intentionally excluded. They are either sensitive, high-cardinality, or not
part of this EKS/RDS architecture.

## Cost guardrails

- Scrape every 60 seconds, not every 15 seconds.
- Remote-write only dashboard metrics; discovered but unused series stay local.
- Keep only two hours in the non-persistent in-cluster collector and 30 days in
  AMP.
- Use the in-cluster collector instead of the separately billed AMP agentless
  collector.
- Do not enable Grafana Enterprise plugins.

The expected working range is roughly 5,000-10,000 active series. At a
60-second interval that is about 223-446 million samples per 31-day month,
before any free-tier allowance. Confirm the real series count and first AWS
bill before adding more exporters or labels.

## Activation checklist

1. Review an explicit production plan with `enable_observability = true`.
2. Apply the approved plan.
3. In Amazon Managed Grafana, add the created AMP workspace as a Prometheus
   data source using the workspace IAM role.
4. Import the five dashboard JSON files and select that Prometheus data source
   when prompted.
5. Verify `up{job="operational-hub-api"}` and `pg_up` before relying on panels.

The application must expose `/actuator/prometheus` to the cluster collector and
enable JCache statistics. The endpoint is not routed through the public ALB.
