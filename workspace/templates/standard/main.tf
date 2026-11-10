# =============================================================================
# Coder workspace template: docker-standard
# =============================================================================
# One workspace = one docker container + one named volume (/home/coder,
# persists across stop/start, destroyed only on workspace delete) + one
# private docker network (peer isolation). The Coder agent is PID 1;
# code-server (:8080) and OpenCode (:4096) are supervised by
# start-workspace-services.sh and exposed ONLY through Coder's authenticated
# app proxy (loopback binds inside the container).
#
# Security invariants (docs/architecture/security-model.md):
#   - no docker socket, no AWS credentials, no master key ever enter here
#   - capabilities ALL dropped, no-new-privileges, non-root image user
#   - AI access = per-developer LiteLLM virtual key (gateway/litellm)
# =============================================================================

terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.36"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# --- parameters -----------------------------------------------------------------

variable "docker_image" {
  type        = string
  default     = "cloudcoding-workspace:dev"
  description = "Workspace image (built from workspace/images/development)"
}

variable "profile" {
  type        = string
  default     = "small"
  description = "Workspace size (docs/architecture/overview.md §profiles)"

  validation {
    condition     = contains(["small", "medium", "large"], var.profile)
    error_message = "profile must be small, medium or large."
  }
}

variable "litellm_base_url" {
  type        = string
  default     = "http://host.docker.internal:4000/v1"
  description = "AI gateway endpoint as seen from inside workspaces"
}

variable "litellm_virtual_key" {
  type        = string
  sensitive   = true
  description = "Per-developer LiteLLM virtual key (sk-...). Issued by the platform operator via gateway/litellm/scripts/create-virtual-key.sh. NOT the master key."
}

locals {
  profile_resources = {
    # cpu: whole vCPUs (nano_cpus), memory in MiB, pids: process cap
    small  = { cpu = 1, memory = 2048, pids = 512 }
    medium = { cpu = 2, memory = 4096, pids = 1024 }
    large  = { cpu = 4, memory = 8192, pids = 2048 }
  }
  resources   = local.profile_resources[var.profile]
  owner_slug  = lower(replace(data.coder_workspace_owner.name, "/[^a-zA-Z0-9_-]/", "-"))
  ws_slug     = lower(replace(data.coder_workspace.name, "/[^a-zA-Z0-9_-]/", "-"))
  volume_name = "coder-${local.owner_slug}-${local.ws_slug}-home"
}

data "coder_workspace" "ws" {}
data "coder_workspace_owner" "owner" {}

# --- agent + apps ---------------------------------------------------------------

resource "coder_agent" "main" {
  os                     = "linux"
  arch                   = "amd64"
  startup_script         = "${path.module}/startup_script.sh"
  startup_script_timeout = 300

  env {
    key   = "LITELLM_BASE_URL"
    value = var.litellm_base_url
  }
  env {
    key   = "OPENCODE_PROVIDER_API_KEY"
    value = var.litellm_virtual_key
  }
  env {
    key   = "GIT_AUTHOR_NAME"
    value = data.coder_workspace_owner.name
  }
  env {
    key   = "GIT_COMMITTER_NAME"
    value = data.coder_workspace_owner.name
  }
  env {
    key   = "GIT_AUTHOR_EMAIL"
    value = data.coder_workspace_owner.email
  }
  env {
    key   = "GIT_COMMITTER_EMAIL"
    value = data.coder_workspace_owner.email
  }

  metadata {
    display_name = "CPU"
    key          = "0_cpu_usage"
    interval     = 10
    timeout      = 2
    script       = "ps -o pcpu= -p $PPID | tr -d ' '"
  }
  metadata {
    display_name = "RAM"
    key          = "1_ram_usage"
    interval     = 10
    timeout      = 2
    script       = "free -m | awk '/^Mem/ {printf \"%s/%sMB\", $3, $2}'"
  }
  metadata {
    display_name = "Home volume"
    key          = "2_home_volume"
    interval     = 600
    timeout      = 5
    script       = "df -h /home/coder | awk 'NR==2 {print $4\" free of \"$2}'"
  }
}

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server (IDE)"
  url          = "http://127.0.0.1:8080"
  icon         = "/icon/code.svg"
  subdomain    = false
  healthcheck {
    url       = "http://127.0.0.1:8080/healthz"
    interval  = 5
    threshold = 12
  }
}

resource "coder_app" "opencode" {
  agent_id     = coder_agent.main.id
  slug         = "opencode"
  display_name = "OpenCode (AI chat)"
  url          = "http://127.0.0.1:4096"
  icon         = "/icon/chat.svg"
  subdomain    = false
  healthcheck {
    url       = "http://127.0.0.1:4096/"
    interval  = 5
    threshold = 12
  }
}

# --- per-workspace network + persistent volume -----------------------------------

resource "docker_network" "workspace" {
  name = "ws-${local.owner_slug}-${local.ws_slug}"
  # label for cleanup tooling
  labels {
    label = "managed-by"
    value = "coder"
  }
}

# NOTE: local-docker volumes cannot hard-enforce a size quota; the profile
# sizes (20/30/50 GiB) are monitored, not enforced (docs/architecture/
# data-persistence.md, known limitation).
resource "docker_volume" "home" {
  name = local.volume_name
  labels {
    label = "managed-by"
    value = "coder"
  }
  labels {
    label = "profile"
    value = var.profile
  }
}

# --- the workspace container ------------------------------------------------------

resource "docker_container" "workspace" {
  count = data.coder_workspace.start_count # 0 when stopped => volume kept

  name    = "coder-ws-${local.owner_slug}-${local.ws_slug}"
  image   = var.docker_image
  hostname = lower(data.coder_workspace.name)

  # Coder agent is the container entrypoint (PID 1); it runs the startup
  # script and supervises code-server + OpenCode.
  command = ["sh", "-c", replace(coder_agent.main.init_script, "\r\n", "\n")]
  env     = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  networks_advanced {
    name = docker_network.workspace.name
  }

  # one URL for browser AND container: host.docker.internal -> host gateway
  extra_hosts {
    host    = "host.docker.internal"
    ip      = "host-gateway"
  }

  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
    read_only      = false
  }

  # profile resource limits (verified by tests/integration/test_workspace_image.sh)
  nano_cpus  = local.resources.cpu * 1000000000
  memory     = local.resources.memory * 1024 * 1024
  pids_limit = local.resources.pids

  # hardening
  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]
  # NOTE: no privileged, no docker.sock mount, no host paths, by design.

  restart                = "on-failure"
  destroy_grace_seconds  = 30
}

# --- README shown in the Coder UI ---------------------------------------------------

resource "coder_metadata" "workspace_info" {
  resource_id = docker_container.workspace[0].id
  count       = data.coder_workspace.start_count

  item {
    key   = "profile"
    value = var.profile
  }
  item {
    key   = "cpu"
    value = "${local.resources.cpu} vCPU"
  }
  item {
    key   = "memory"
    value = "${local.resources.memory} MiB"
  }
  item {
    key   = "persistent volume"
    value = local.volume_name
  }
  item {
    key   = "AI gateway"
    value = var.litellm_base_url
  }
}
