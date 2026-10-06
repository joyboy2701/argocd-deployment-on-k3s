variable "releases" {
  description = "Helm releases keyed by a stable identifier. YAML values must be supplied as strings, for example file(path) or yamlencode(object)."
  type = map(object({
    name             = optional(string)
    repository       = optional(string)
    chart            = string
    version          = optional(string)
    namespace        = optional(string, "default")
    create_namespace = optional(bool, true)
    values           = optional(list(string), [])
    set              = optional(map(string), {})
    wait             = optional(bool, true)
    wait_for_jobs    = optional(bool, false)
    timeout          = optional(number, 600)
    atomic           = optional(bool, false)
    cleanup_on_fail  = optional(bool, false)
    skip_crds        = optional(bool, false)
  }))

  validation {
    condition     = alltrue([for release in var.releases : release.timeout > 0])
    error_message = "Each release timeout must be greater than zero."
  }
}
