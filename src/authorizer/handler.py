"""Cortex Custom Authorizer Lambda — Validates JWT tokens for API Gateway."""

import os
import re

import jwt

from shared.logger import LambdaContext, Tracer, get_logger

logger = get_logger(service="cortex-authorizer")
tracer = Tracer(service="cortex-authorizer")

# JWT Secret injected via Terraform / Environment
JWT_SECRET = os.environ.get("JWT_SECRET", "default-secret-key-for-local-dev")


def _generate_policy(principal_id: str, effect: str, resource: str) -> dict:
    """Generate an IAM Policy for API Gateway."""
    auth_response: dict = {"principalId": principal_id}
    
    if effect and resource:
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": resource,
                }
            ],
        }
        auth_response["policyDocument"] = policy_document
        
    return auth_response


@logger.inject_lambda_context(log_event=True)
@tracer.capture_lambda_handler
def handler(event: dict, context: LambdaContext) -> dict:
    """Lambda Authorizer entrypoint."""
    token = event.get("authorizationToken", "")
    method_arn = event.get("methodArn", "")

    # Clean the "Bearer " prefix if present
    match = re.match(r"^Bearer\s+(.*)$", token, re.IGNORECASE)
    if match:
        token = match.group(1)

    if not token:
        logger.warning("Missing token")
        return _generate_policy("unauthorized", "Deny", method_arn)

    try:
        # Validate JWT
        decoded = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
        principal_id = decoded.get("sub", "unknown")
        
        logger.info("Token validated successfully", extra={"principal": principal_id})
        return _generate_policy(principal_id, "Allow", method_arn)
        
    except jwt.ExpiredSignatureError:
        logger.warning("Token expired")
        return _generate_policy("unauthorized", "Deny", method_arn)
    except jwt.InvalidTokenError as e:
        logger.warning("Invalid token", extra={"error": str(e)})
        return _generate_policy("unauthorized", "Deny", method_arn)
    except Exception:
        logger.exception("Authorizer internal error")
        return _generate_policy("unauthorized", "Deny", method_arn)
