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
- Amazon Managed Grafana with AMP access.
- Four dashboards under `grafana/`.

## Dashboard coverage

- `operational-hub-api.json`: API health, traffic, response codes, percentiles,
  average duration, p1 minimum estimate, and rolling maximum duration, with
  independent pod and endpoint selectors.
- `operational-hub-bigquery.json`: BigQuery read/write execution counts,
  average and maximum duration, cache, cost, slot, and row signals, with
  independent pod and operation selectors.
- `operational-hub-jvm-hikari.json`: JVM uptime, CPU, heap, GC, threads, file
  descriptors, Hikari connection-pool behavior, and local JCache statistics,
  with a pod selector.
- `operational-hub-postgresql.json`: connections, transactions, scans, cache
  hit rate, deadlocks, temporary files, locks, long-running transactions,
  checkpoints, and live/dead rows.

Token/user labels, request bodies, Debezium panels, and VM-specific panels are
intentionally excluded. They are either sensitive, high-cardinality, or not
part of this EKS/RDS architecture.

Infrastructure, CloudFront, ALB, EKS workload, deployment-marker, and
CloudWatch Logs dashboards are intentionally excluded. The collector disables
the Kubernetes and node exporters and remote-writes only application and
PostgreSQL metrics.

## Cost guardrails

- Scrape every 60 seconds, not every 15 seconds.
- Remote-write only dashboard metrics; discovered but unused series stay local.
- Keep only two hours in the non-persistent in-cluster collector and 30 days in
  AMP.
- Use the in-cluster collector instead of the separately billed AMP agentless
  collector.
- Do not enable Grafana Enterprise plugins.
- RDS Database Insights / Performance Insights is disabled. Slow-query storage
  is intentionally out of scope; the PostgreSQL dashboard uses only exporter
  metrics.

The expected working range is roughly 5,000-10,000 active series. At a
60-second interval that is about 223-446 million samples per 31-day month,
before any free-tier allowance. Confirm the real series count and first AWS
bill before adding more exporters or labels.

## Activation checklist

1. Review an explicit production plan with `enable_observability = true`.
2. Apply the approved plan.
3. Import dashboards through the Grafana UI as an existing administrator. Do
   not create an API user, service account, or token for dashboard imports;
   Amazon Managed Grafana bills those identities as active editors.
4. Open the `Operational Hub` folder in Grafana and verify
   `up{job="operational-hub-api"}` and `pg_up` before relying on panels.

The application must expose `/actuator/prometheus` to the cluster collector and
enable JCache statistics. The endpoint is not routed through the public ALB.
