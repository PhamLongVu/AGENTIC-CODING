# =============================================================================
# IAM module — least-privilege Bedrock access for the platform instance
# =============================================================================
# ONLY the LiteLLM gateway may invoke Bedrock (ADR-0004). The instance
# profile grants exactly bedrock:InvokeModel* on foundation models plus
# ListFoundationModels for startup discovery. Nothing else. No S3, no EC2
# API, no IAM pass-role, no secrets access.
#
# Credential flow: LiteLLM (host network) -> EC2 IMDSv2 -> this role.
# Workspace containers CANNOT reach IMDS (hop limit 1, enforced in the ec2
# module) and have no static AWS keys — see docs/architecture/security-model.md.
#
# Operator access: the AWS-managed SSM policy below is attached so Session
# Manager works even when `ssh_key_name` is unset (the module default) —
# otherwise the default config has no SSH key AND no SSM path and the
# operator is locked out of the instance. SSM requires no inbound port.
# =============================================================================

data "aws_iam_policy_document" "instance_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.instance_trust.json

  tags = var.tags
}

data "aws_iam_policy_document" "bedrock_invoke" {
  statement {
    sid = "BedrockModelInvocationOnly"

    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]

    # Scoped to foundation models (incl. inference profiles), not provisioned
    # custom models, agents, knowledge bases or anything else.
    resources = [
      "arn:aws:bedrock:*:::foundation-model/*",
      "arn:aws:bedrock:*:${var.account_id}:inference-profile/*",
    ]
  }

  statement {
    sid = "BedrockModelDiscovery"

    actions   = ["bedrock:ListFoundationModels"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "bedrock_invoke" {
  name = "${var.name}-bedrock-invoke"
  role = aws_iam_role.instance.id

  policy = data.aws_iam_policy_document.bedrock_invoke.json
}

# Session Manager access for operators (AWS-managed policy, read-only data
# source — no credentials needed at plan time).
data "aws_iam_policy" "ssm_managed_core" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_session_manager" {
  role       = aws_iam_role.instance.name
  policy_arn = data.aws_iam_policy.ssm_managed_core.arn
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.instance.name

  tags = var.tags
}
