# 1. Create a Kubernetes Secret for your TLS certificate
# 2. Use the certificate directly in the Ingress resource

resource "kubernetes_secret" "hextris_tls" {
  metadata {
    name      = "hextris-tls"
    namespace = kubernetes_namespace.hextris.metadata[0].name
  }

  data = {
    "tls.crt" = file("${path.module}/ssl/hextris.work.gd.cer")
    "tls.key" = file("${path.module}/ssl/hextris.work.gd.key")
  }

  type = "kubernetes.io/tls"

  depends_on = [kubernetes_namespace.hextris]
}

# Create the namespace resource
resource "kubernetes_namespace" "hextris" {
  metadata {
    name = "hextris"
    labels = {
      name = "hextris"
    }
  }
}