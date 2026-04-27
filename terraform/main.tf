# ══════════════════════════════════════
# Small Business Cloud Platform
# Terraform + EKS + Karpenter + ArgoCD
# ══════════════════════════════════════

# ──────────────────────────────────────
# Phase 1: VPC
# ──────────────────────────────────────
module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ──────────────────────────────────────
# Phase 1: EKS Cluster + Node Group + ALB Controller
# ──────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  cluster_version     = var.eks_cluster_version
  vpc_id              = module.vpc.vpc_id
  public_subnet_ids   = module.vpc.public_subnet_ids
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = var.eks_node_instance_types
}

# ──────────────────────────────────────
# Phase 2: RDS
# ──────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  vpc_cidr           = var.vpc_cidr
  private_subnet_ids = module.vpc.private_subnet_ids
  db_instance_class  = var.db_instance_class
  db_name            = var.db_name
  db_username        = var.db_username
  db_password        = var.db_password
}

# ──────────────────────────────────────
# Phase 2: ArgoCD (via Helm)
# ClusterIP + ALB Ingress (production pattern)
# ──────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "6.4.0"
  timeout          = 600

  # Server: ClusterIP (not LoadBalancer)
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  # Enable Ingress via ALB
  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "alb"
  }

  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
    value = "internet-facing"
  }

  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }

  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
    value = "[{\"HTTP\": 80}]"
  }

  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/healthcheck-path"
    value = "/healthz"
  }

  # Disable TLS on Argo side (ALB handles it or HTTP for dev)
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  depends_on = [module.eks]
}
