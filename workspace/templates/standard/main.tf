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
      version = "~> 2.20"
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

variable "litellm_base_url" {
  type        = string
  default     = "http://host.docker.internal:4000/v1"
  description = "AI gateway endpoint as seen from inside workspaces"
}

# Rich parameters (provider 2.x: DATA blocks). Values are read at build time
# via data.coder_parameter.<name>.value — a same-named `variable` does NOT
# receive the parameter value (verified the hard way: env came up empty).
data "coder_parameter" "litellm_virtual_key" {
  name         = "litellm_virtual_key"
  display_name = "LiteLLM virtual key"
  type         = "string"
  mutable      = false
  description  = "Your personal AI gateway key (sk-...). Ask the operator if you don't have one. NEVER the master key."
  validation {
    # empty is tolerated so `templates create`'s import-provision dry-run
    # passes (no parameter default yet); the create-workspace form still
    # requires input, and a wrong key is rejected by the gateway (401).
    regex = "^$|^sk-[a-zA-Z0-9_-]{10,}$"
    error = "Must look like a virtual key (sk-…). Ask the operator."
  }
}

data "coder_parameter" "profile" {
  name         = "profile"
  display_name = "Workspace profile"
  type         = "string"
  default      = "small"
  mutable      = false
  description  = "Resource envelope: small 1CPU/2GiB · medium 2CPU/4GiB · large 4CPU/8GiB."
  option {
    name  = "small"
    value = "small"
  }
  option {
    name  = "medium"
    value = "medium"
  }
  option {
    name  = "large"
    value = "large"
  }
}

locals {
  profile_resources = {
    # cpu: whole vCPUs, memory in MiB. (No pids cap: the kreuzwerker/docker
    # provider does not expose PidsLimit — docs/architecture/overview.md.)
    small  = { cpu = 1, memory = 2048 }
    medium = { cpu = 2, memory = 4096 }
    large  = { cpu = 4, memory = 8192 }
  }
  # read the parameter VALUE, not a same-named variable (see note above)
  resources   = local.profile_resources[data.coder_parameter.profile.value]
  owner_slug  = lower(replace(data.coder_workspace_owner.owner.name, "/[^a-zA-Z0-9_-]/", "-"))
  ws_slug     = lower(replace(data.coder_workspace.ws.name, "/[^a-zA-Z0-9_-]/", "-"))
  volume_name = "coder-${local.owner_slug}-${local.ws_slug}-home"
}

data "coder_workspace" "ws" {}
data "coder_workspace_owner" "owner" {}

# --- agent + apps ---------------------------------------------------------------

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  # startup_script takes the script CONTENT — file() reads it from the
  # bundled template dir (a bare path string gets executed as a command:
  # "./startup_script.sh: No such file or directory").
  startup_script = file("${path.module}/startup_script.sh")

  # provider 2.x: env is a map argument, not repeated blocks
  env = {
    LITELLM_BASE_URL          = var.litellm_base_url
    OPENCODE_PROVIDER_API_KEY = data.coder_parameter.litellm_virtual_key.value
    GIT_AUTHOR_NAME           = data.coder_workspace_owner.owner.name
    GIT_COMMITTER_NAME        = data.coder_workspace_owner.owner.name
    GIT_AUTHOR_EMAIL          = data.coder_workspace_owner.owner.email
    GIT_COMMITTER_EMAIL       = data.coder_workspace_owner.owner.email
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
    value = data.coder_parameter.profile.value
  }
}

# --- the workspace container ------------------------------------------------------

resource "docker_container" "workspace" {
  count = data.coder_workspace.ws.start_count # 0 when stopped => volume kept

  name     = "coder-ws-${local.owner_slug}-${local.ws_slug}"
  image    = var.docker_image
  hostname = lower(data.coder_workspace.ws.name)

  # Coder agent is the container entrypoint (PID 1); it runs the startup
  # script and supervises code-server + OpenCode.
  command = ["sh", "-c", replace(coder_agent.main.init_script, "\r\n", "\n")]
  env     = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  networks_advanced {
    name = docker_network.workspace.name
  }

  # one URL for browser AND container: host.docker.internal -> host gateway
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    volume_name    = docker_volume.home.name
    container_path = "/home/coder"
    read_only      = false
  }

  # profile resource limits (verified by tests/integration/test_e2e_workspace.sh)
  # NB: provider `memory` is in MB (it multiplies by 1024*1024 itself) — the
  # profile map stores MiB, so pass it through unchanged.
  cpus   = local.resources.cpu
  memory = local.resources.memory

  # hardening
  capabilities {
    drop = ["ALL"]
  }
  security_opts = ["no-new-privileges:true"]
  # NOTE: no privileged, no docker.sock mount, no host paths, by design.

  restart               = "on-failure"
  destroy_grace_seconds = 30
}

# --- README shown in the Coder UI ---------------------------------------------------

resource "coder_metadata" "workspace_info" {
  resource_id = docker_container.workspace[0].id
  count       = data.coder_workspace.ws.start_count

  item {
    key   = "profile"
    value = data.coder_parameter.profile.value
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
