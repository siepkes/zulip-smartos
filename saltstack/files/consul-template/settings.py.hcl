template {
  # Source file is deployed via Terraform because we also need to configure 
  # some deployment time variables in it.
  source = "/etc/consul-template/settings.py.ctmpl"  
  destination = "/etc/zulip/settings.py"
  perms = 0640
  
  # Don't leave config files with passwords lingering.
  backup = false
  
  command = "/usr/local/bin/zulip-settings-changed.sh"
  
  // This is the quiescence timers; it defines the minimum and maximum amount of
  // time to wait for the cluster to reach a consistent state before rendering a
  // template. This is useful to enable in systems that have a lot of flapping,
  // because it will reduce the the number of times a template is rendered.
  wait {
    min = "3s"
    max = "25s"
  }
}