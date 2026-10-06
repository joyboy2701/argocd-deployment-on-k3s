output "releases" {
  description = "Release names, namespaces, charts, and versions keyed by their configured identifiers."
  value = {
    for key, release in helm_release.this : key => {
      name      = release.name
      namespace = release.namespace
      chart     = release.chart
      version   = release.version
    }
  }
}
