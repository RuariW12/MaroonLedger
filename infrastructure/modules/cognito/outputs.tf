output "user_pool_id" {
  description = "Cognito user pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "client_id" {
  description = "App client ID the API validates the token's client_id claim against"
  value       = aws_cognito_user_pool_client.web.id
}

# The exact string Cognito puts in the `iss` claim. The API compares against
# this verbatim, so it is derived here rather than reassembled by callers.
output "issuer" {
  description = "OIDC issuer URL for this user pool"
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "jwks_url" {
  description = "JWKS endpoint serving the pool's public signing keys"
  value       = "https://cognito-idp.${data.aws_region.current.region}.amazonaws.com/${aws_cognito_user_pool.main.id}/.well-known/jwks.json"
}

output "hosted_ui_url" {
  description = "Base URL of the Cognito hosted sign-in UI"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.region}.amazoncognito.com"
}
