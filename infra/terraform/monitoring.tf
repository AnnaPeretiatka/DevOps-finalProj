# --------------------------------------------- Loki ----------------------------------------------
resource "helm_release" "loki" {
  name             = "loki"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "6.6.5"

  set { 
    name = "singleBinary.enabled" 
    value = "true" 
  }
  set { 
    name = "loki.commonConfig.replication_factor" 
    value = "1" 
  }
  set { 
    name = "loki.storage.type" 
    value = "filesystem" 
  }

  #  ----------- persistence to EBS (via default StorageClass)---
  set { 
    name = "loki.persistence.enabled"
    value = "true" 
  }

  set { 
    name = "loki.persistence.size"    
    value = "7Gi" 
  }  

  set { 
    name = "backend.enabled" 
    value = "false" 
  }

  set { 
    name = "read.enabled"    
    value = "false" 
  }

  set { 
    name = "write.enabled"  
    value = "false" 
  }

  set { 
    name = "gateway.enabled"
    value = "false" 
  }

  #  ----------- Network ------------------------
  set { 
    name = "loki.auth_enabled" 
    value = "false" 
  }

  # Service on 3100
  set { 
    name = "service.type" 
    value = "ClusterIP" 
  }
  set { 
    name = "service.port" 
    value = "3100" 
  }
  
  #  ---------- # retention (time-based) ----------

  set { 
    name = "loki.limits_config.retention_period"
    value = "168h"  # 7d
  } 

  # Make sure cluster is ready first
  depends_on = [
    aws_eks_node_group.default,
    helm_release.alb
  ]
}

# --------------------------------------------- Promtail (ship node/container logs to Loki) ----------------------------------------------
resource "helm_release" "promtail" {
  name             = "promtail"
  namespace        = "monitoring"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  version          = "6.15.5"

  set { 
    name = "config.clients[0].url"
    value = "http://loki.monitoring:3100/loki/api/v1/push" 
  }
  set { 
    name = "serviceMonitor.enabled"
    value = "true" 
  }

  depends_on = [ helm_release.loki ]
}

# --------------------------------------------- kube-prometheus-stack (Prometheus + Grafana) with HTTPS ALB Ingress ----------------------------------------------
resource "helm_release" "kps" {
  name             = "kube-prom"
  namespace        = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "61.7.0"

  # Keep Grafana internal service; ALB will route via Ingress
  set { 
    name = "grafana.service.type" 
    value = "ClusterIP" 
  }
  set { 
    name = "grafana.adminPassword"
    value = "change-me" 
  }

  # Root URL / server domain (optional but nice)
  set { 
    name = "grafana.env.GF_SERVER_ROOT_URL" 
    value = "https://grafana.${var.domain_name}" 
  }

  # ----- Ingress (ALB) -----
  set { 
    name = "grafana.ingress.enabled"
    value = "true" 
  }
  set { 
    name = "grafana.ingress.ingressClassName" 
    value = "alb" 
  }
  set { 
    name = "grafana.ingress.hosts[0]"
    value = "grafana.${var.domain_name}" 
  }

  set { 
    name = "grafana.additionalDataSources[0].name"     
    value = "Loki" 
  }
  set { 
    name = "grafana.additionalDataSources[0].type"      
    value = "loki" 
  }
  set { 
    name = "grafana.additionalDataSources[0].url" 
    value = "http://loki.monitoring:3100" 
  }
  set { 
    name = "grafana.additionalDataSources[0].access"  
    value = "proxy" 
  }
  set { 
    name = "grafana.additionalDataSources[0].isDefault" 
    value = "false" 
  }

  # --------------- ALB annotations: 80+443, redirect to 443, attach ACM cert --------------
  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
    value = "internet-facing"
  }
  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }
  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
    value = "'[{\"HTTP\":80},{\"HTTPS\":443}]'"
  }
  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn"
    value = aws_acm_certificate.site[0].arn
  }
  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/ssl-redirect"
    value = "443"
  }

  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/load-balancer-name"
    value = "statuspage-ay-alb"                                                                       # ---- shared alb with app
  }
  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/group.name"
    value = "shared-ext"                                                                              # ---- shared alb with app
  }

  # Make sure cert is validated before ALB/Grafana deploy
  depends_on = [
    aws_eks_node_group.default,
    helm_release.alb,
    aws_acm_certificate_validation.site
  ]
}

# --------------------------------------------- Wait for Grafana Ingress hostname, then add Route53 record ----------------------------------------------
# Wait for Grafana Ingress to get an ALB hostname
resource "null_resource" "wait_for_grafana_ingress" {
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command = <<-EOT
      set -euo pipefail
      for i in $(seq 1 60); do
        host=$(kubectl -n monitoring get ingress kube-prom-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
        if [[ -n "$host" ]]; then
          echo "Grafana ingress hostname: $host"
          exit 0
        fi
        echo "Waiting for Grafana ingress hostname ($i/60)..."
        sleep 10
      done
      echo "Timeout waiting for Grafana ingress hostname"
      exit 1
    EOT
  }
  depends_on = [ helm_release.kps ]
}

data "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "kube-prom-grafana"
    namespace = "monitoring"
  }
  depends_on = [ null_resource.wait_for_grafana_ingress ]
}

# Use the ALB canonical hosted-zone id you already fetch for app
# (you already have: data "aws_lb_hosted_zone_id" "alb")
resource "aws_route53_record" "grafana_alias" {
  zone_id = data.aws_route53_zone.authoritative.zone_id
  name    = "grafana.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.kubernetes_ingress_v1.grafana.status[0].load_balancer[0].ingress[0].hostname
    zone_id                = data.aws_lb_hosted_zone_id.alb.id
    evaluate_target_health = false
  }

  depends_on = [ null_resource.wait_for_grafana_ingress ]
}
