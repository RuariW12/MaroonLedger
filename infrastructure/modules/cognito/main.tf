resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # Email is the sign-in identifier. Cognito requires this to be set at
  # creation -- it cannot be changed later without replacing the pool.
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  # Software TOTP only. SMS is deliberately not offered: SIM-swap attacks make
  # it the weakest common second factor, and it carries a per-message cost.
  mfa_configuration = "OPTIONAL"
  software_token_mfa_configuration {
    enabled = true
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    # Users sign themselves up; this only governs admin-created accounts.
    allow_admin_create_user_only = false
  }

  # Threat protection (compromised-credential detection, adaptive auth) is a
  # paid Cognito tier, so it defaults off to keep this project's running cost
  # near zero. ENFORCED is the right setting for anything holding real data.
  dynamic "user_pool_add_ons" {
    for_each = var.advanced_security_mode == "OFF" ? [] : [1]
    content {
      advanced_security_mode = var.advanced_security_mode
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

# Hosted UI domain. Using the Cognito-provided domain avoids needing a
# certificate and a Route 53 record for a custom auth subdomain.
resource "aws_cognito_user_pool_domain" "main" {
  domain       = var.hosted_ui_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.project_name}-web"
  user_pool_id = aws_cognito_user_pool.main.id

  # No client secret. This client runs in a browser, where a secret cannot be
  # kept, so the authorization-code flow is secured with PKCE instead.
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # SRP proves knowledge of the password without transmitting it.
  # ALLOW_USER_PASSWORD_AUTH is excluded on purpose: it sends the plaintext
  # password to the Cognito API.
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Without this, Cognito's error responses differ for a real versus an unknown
  # email, which lets an attacker enumerate registered users.
  prevent_user_existence_errors = "ENABLED"

  # Allows a refresh token to be invalidated on sign-out rather than remaining
  # valid until it expires.
  enable_token_revocation = true
}
