resource "helm_release" "this" {
  for_each = var.releases

  name             = coalesce(each.value.name, each.key)
  repository       = each.value.repository
  chart            = each.value.chart
  version          = each.value.version
  namespace        = each.value.namespace
  create_namespace = each.value.create_namespace
  values           = each.value.values
  wait             = each.value.wait
  wait_for_jobs    = each.value.wait_for_jobs
  timeout          = each.value.timeout
  atomic           = each.value.atomic
  cleanup_on_fail  = each.value.cleanup_on_fail
  skip_crds        = each.value.skip_crds

  set = [
    for name, value in each.value.set : {
      name  = name
      value = value
    }
  ]
}
