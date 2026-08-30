locals {
  observability_namespace = "monitoring"

  # Keep AMP ingestion bounded. The collector may discover additional Kubernetes targets,
  # but only metrics used by the prepared dashboards cross the remote-write boundary.
  prometheus_remote_write_metric_allowlist = join("|", [
    "up",
    "application_.*",
    "process_.*",
    "system_cpu_.*",
    "jvm_.*",
    "hikaricp_.*",
    "http_server_requests_seconds_.*",
    "cache_.*",
    "bigquery_.*",
    "tomcat_threads_.*",
    "pg_.*",
  ])
}

resource "aws_prometheus_workspace" "production" {
  count = var.enable_observability ? 1 : 0

  alias = local.name
}

resource "aws_prometheus_workspace_configuration" "production" {
  count = var.enable_observability ? 1 : 0

  workspace_id             = aws_prometheus_workspace.production[0].id
  retention_period_in_days = var.prometheus_retention_days
}

data "aws_iam_policy_document" "prometheus_assume_role" {
  count = var.enable_observability ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:${local.observability_namespace}:amp-collector"]
    }
  }
}

data "aws_iam_policy_document" "prometheus_remote_write" {
  count = var.enable_observability ? 1 : 0

  statement {
    sid       = "RemoteWriteMetrics"
    effect    = "Allow"
    actions   = ["aps:RemoteWrite"]
    resources = [aws_prometheus_workspace.production[0].arn]
  }
}

resource "aws_iam_role" "prometheus" {
  count = var.enable_observability ? 1 : 0

  name               = "${local.name}-prometheus"
  assume_role_policy = data.aws_iam_policy_document.prometheus_assume_role[0].json
}

resource "aws_iam_role_policy" "prometheus_remote_write" {
  count = var.enable_observability ? 1 : 0

  name   = "${local.name}-amp-remote-write"
  role   = aws_iam_role.prometheus[0].id
  policy = data.aws_iam_policy_document.prometheus_remote_write[0].json
}

resource "helm_release" "prometheus_collector" {
  count = var.enable_observability ? 1 : 0

  name             = "amp-collector"
  namespace        = local.observability_namespace
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = "29.27.0"

  atomic  = true
  timeout = 900
  wait    = true

  values = [yamlencode({
    serviceAccounts = {
      server = {
        create = true
        name   = "amp-collector"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.prometheus[0].arn
        }
      }
    }
    server = {
      global = {
        scrape_interval     = var.prometheus_scrape_interval
        scrape_timeout      = "10s"
        evaluation_interval = "1m"
      }
      persistentVolume = {
        enabled = false
      }
      retention = "2h"
      remoteWrite = [{
        url = "${aws_prometheus_workspace.production[0].prometheus_endpoint}api/v1/remote_write"
        sigv4 = {
          region = var.aws_region
        }
        write_relabel_configs = [{
          source_labels = ["__name__"]
          regex         = "^(${local.prometheus_remote_write_metric_allowlist})$"
          action        = "keep"
        }]
      }]
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }
    }
    scrapeConfigs = {
      prometheus                        = { enabled = false }
      kubernetes-api-servers            = { enabled = false }
      kubernetes-nodes                  = { enabled = false }
      kubernetes-nodes-cadvisor         = { enabled = false }
      kubernetes-service-endpoints      = { enabled = false }
      kubernetes-service-endpoints-slow = { enabled = false }
      prometheus-pushgateway            = { enabled = false }
      kubernetes-services               = { enabled = false }
      kubernetes-pods                   = { enabled = false }
      kubernetes-pods-slow              = { enabled = false }
    }
    extraScrapeConfigs = yamlencode([
      {
        job_name     = "operational-hub-api"
        metrics_path = "/actuator/prometheus"
        kubernetes_sd_configs = [{
          role = "endpointslice"
          namespaces = {
            names = [local.app_namespace]
          }
        }]
        relabel_configs = [
          {
            source_labels = ["__meta_kubernetes_service_name"]
            regex         = "operational-hub-api"
            action        = "keep"
          },
          {
            source_labels = ["__meta_kubernetes_endpointslice_port_name"]
            regex         = "http"
            action        = "keep"
          },
          {
            source_labels = ["__meta_kubernetes_namespace"]
            target_label  = "namespace"
          },
          {
            source_labels = ["__meta_kubernetes_pod_name"]
            target_label  = "pod"
          },
          {
            target_label = "service"
            replacement  = "operational-hub-api"
          },
          {
            target_label = "environment"
            replacement  = var.environment
          },
        ]
      },
      {
        job_name = "operational-hub-postgresql"
        kubernetes_sd_configs = [{
          role = "endpointslice"
          namespaces = {
            names = [local.app_namespace]
          }
        }]
        relabel_configs = [
          {
            source_labels = ["__meta_kubernetes_service_name"]
            regex         = "postgres-exporter-prometheus-postgres-exporter"
            action        = "keep"
          },
          {
            source_labels = ["__meta_kubernetes_endpointslice_port_name"]
            regex         = "http"
            action        = "keep"
          },
          {
            source_labels = ["__meta_kubernetes_namespace"]
            target_label  = "namespace"
          },
          {
            source_labels = ["__meta_kubernetes_pod_name"]
            target_label  = "pod"
          },
          {
            target_label = "service"
            replacement  = "operational-hub-postgresql"
          },
          {
            target_label = "environment"
            replacement  = var.environment
          },
        ]
      },
    ])
    alertmanager = {
      enabled = false
    }
    prometheus-pushgateway = {
      enabled = false
    }
    kube-state-metrics = {
      enabled = false
    }
    prometheus-node-exporter = {
      enabled = false
    }
  })]

  depends_on = [
    module.eks,
    aws_iam_role_policy.prometheus_remote_write,
    aws_prometheus_workspace_configuration.production,
  ]
}

resource "helm_release" "postgres_exporter" {
  count = var.enable_observability ? 1 : 0

  name       = "postgres-exporter"
  namespace  = local.app_namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-postgres-exporter"
  version    = "8.2.0"

  atomic  = true
  timeout = 600
  wait    = true

  values = [yamlencode({
    service = {
      annotations = {
        "prometheus.io/scrape" = "true"
        "prometheus.io/path"   = "/metrics"
        "prometheus.io/port"   = "9187"
      }
    }
    config = {
      datasource = {
        host = aws_db_instance.postgres.address
        userSecret = {
          name = "operational-hub-api-secret"
          key  = "POSTGRES_USER"
        }
        passwordSecret = {
          name = "operational-hub-api-secret"
          key  = "POSTGRES_PASSWORD"
        }
        port     = tostring(aws_db_instance.postgres.port)
        database = var.database_name
        sslmode  = "require"
      }
      extraArgs = [
        "--collector.long_running_transactions",
      ]
      logFormat = "json"
      logLevel  = "info"
    }
    resources = {
      requests = {
        cpu    = "25m"
        memory = "64Mi"
      }
      limits = {
        cpu    = "250m"
        memory = "192Mi"
      }
    }
  })]

  depends_on = [
    aws_db_instance.postgres,
    helm_release.secrets_store_csi,
    helm_release.prometheus_collector,
  ]
}

data "aws_iam_policy_document" "grafana_assume_role" {
  count = var.enable_observability ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.aws_account_id]
    }
  }
}

data "aws_iam_policy_document" "grafana_data_sources" {
  count = var.enable_observability ? 1 : 0

  statement {
    sid    = "QueryPrometheus"
    effect = "Allow"
    actions = [
      "aps:DescribeWorkspace",
      "aps:GetLabels",
      "aps:GetMetricMetadata",
      "aps:GetSeries",
      "aps:ListWorkspaces",
      "aps:QueryMetrics",
    ]
    resources = ["*"]
  }

}

resource "aws_iam_role" "grafana" {
  count = var.enable_observability ? 1 : 0

  name               = "${local.name}-grafana"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume_role[0].json
}

resource "aws_iam_role_policy" "grafana_data_sources" {
  count = var.enable_observability ? 1 : 0

  name   = "${local.name}-grafana-data-sources"
  role   = aws_iam_role.grafana[0].id
  policy = data.aws_iam_policy_document.grafana_data_sources[0].json
}

resource "aws_grafana_workspace" "production" {
  count = var.enable_observability ? 1 : 0

  name                     = local.name
  description              = "Production observability for AIAE Operational Hub"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["PROMETHEUS"]
  grafana_version          = "12.4"

  depends_on = [aws_iam_role_policy.grafana_data_sources]
}

resource "aws_grafana_role_association" "production" {
  for_each = var.enable_observability ? var.grafana_rbac_role_mappings : {}

  workspace_id = aws_grafana_workspace.production[0].id
  role         = each.value.role
  group_ids    = each.value.group_ids
  user_ids     = each.value.user_ids
}
