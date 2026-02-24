from flask import Flask, request, jsonify
import requests
import os
import logging
import uuid
from datetime import datetime
from typing import Optional, Dict, Tuple
from requests.exceptions import RequestException, Timeout, ConnectionError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://localhost:11434")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "llama3")
SLACK_BOT_TOKEN = os.getenv("SLACK_BOT_TOKEN")
REQUEST_TIMEOUT = int(os.getenv("REQUEST_TIMEOUT", "30"))
OLLAMA_TIMEOUT = int(os.getenv("OLLAMA_TIMEOUT", "60"))

# Validate required configuration
if not SLACK_BOT_TOKEN:
    logger.warning("SLACK_BOT_TOKEN not set. Slack functionality will be unavailable.")


def create_error_response(
    message: str,
    status_code: int,
    error_code: Optional[str] = None,
    details: Optional[Dict] = None
) -> Tuple[Dict, int]:
    """Create standardized error response"""
    response = {
        "error": {
            "message": message,
            "status_code": status_code,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
    }
    if error_code:
        response["error"]["code"] = error_code
    if details:
        response["error"]["details"] = details
    return jsonify(response), status_code


def create_success_response(
    data: Dict,
    status_code: int = 200,
    message: Optional[str] = None
) -> Tuple[Dict, int]:
    """Create standardized success response"""
    response = {
        "success": True,
        "data": data,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }
    if message:
        response["message"] = message
    return jsonify(response), status_code


def validate_email(email: str) -> bool:
    """Basic email validation"""
    if not email or "@" not in email:
        return False
    return True


def get_slack_user_by_email(email: str) -> Tuple[Optional[str], Optional[str]]:
    """
    Find Slack user ID by email
    
    Returns:
        Tuple of (user_id, error_message). If successful, error_message is None.
    """
    if not SLACK_BOT_TOKEN:
        return None, "Slack bot token not configured"
    
    if not validate_email(email):
        return None, f"Invalid email format: {email}"
    
    headers = {
        "Authorization": f"Bearer {SLACK_BOT_TOKEN}",
        "Content-Type": "application/json"
    }
    
    try:
        response = requests.get(
            f"https://slack.com/api/users.lookupByEmail?email={email}",
            headers=headers,
            timeout=REQUEST_TIMEOUT
        )
        response.raise_for_status()
        
        data = response.json()
        
        if not data.get("ok"):
            error = data.get("error", "Unknown error")
            if error == "users_not_found":
                return None, f"Slack user not found for email: {email}"
            return None, f"Slack API error: {error}"
        
        user_id = data.get("user", {}).get("id")
        if not user_id:
            return None, "User ID not found in Slack response"
        
        return user_id, None
        
    except Timeout:
        logger.error(f"Timeout while looking up Slack user: {email}")
        return None, "Slack API request timeout"
    except ConnectionError:
        logger.error(f"Connection error while looking up Slack user: {email}")
        return None, "Unable to connect to Slack API"
    except RequestException as e:
        logger.error(f"Request error while looking up Slack user: {str(e)}")
        return None, f"Slack API request failed: {str(e)}"
    except Exception as e:
        logger.error(f"Unexpected error while looking up Slack user: {str(e)}")
        return None, f"Unexpected error: {str(e)}"


def analyze_with_ollama(logs: str, error: str, repo: str) -> Tuple[Optional[str], Optional[str]]:
    """
    Analyze build failure with Ollama
    
    Returns:
        Tuple of (analysis, error_message). If successful, error_message is None.
    """
    # Limit log size to prevent token overflow
    logs_truncated = logs[:5000] if len(logs) > 5000 else logs
    
    prompt = f"""Analyze this build failure. Be concise.

Repo: {repo}
Error: {error}

Logs:
{logs_truncated}

Give:
1. Root cause (1 sentence)
2. Fix recommendation
3. Known issue? (if applicable)"""

    try:
        response = requests.post(
            f"{OLLAMA_URL}/api/generate",
            json={
                "model": OLLAMA_MODEL,
                "prompt": prompt,
                "stream": False
            },
            timeout=OLLAMA_TIMEOUT
        )
        response.raise_for_status()
        
        data = response.json()
        analysis = data.get("response")
        
        if not analysis:
            return None, "Ollama returned empty response"
        
        return analysis, None
        
    except Timeout:
        logger.error("Timeout while analyzing with Ollama")
        return None, "Ollama request timeout"
    except ConnectionError:
        logger.error("Connection error while connecting to Ollama")
        return None, "Unable to connect to Ollama service"
    except RequestException as e:
        logger.error(f"Request error while analyzing with Ollama: {str(e)}")
        if hasattr(e.response, 'status_code'):
            if e.response.status_code == 404:
                return None, f"Ollama model '{OLLAMA_MODEL}' not found"
            return None, f"Ollama API error (HTTP {e.response.status_code}): {e.response.text}"
        return None, f"Ollama API request failed: {str(e)}"
    except Exception as e:
        logger.error(f"Unexpected error while analyzing with Ollama: {str(e)}")
        return None, f"Unexpected error: {str(e)}"


def send_slack_dm(user_id: str, message: str) -> Tuple[bool, Optional[str]]:
    """
    Send DM to Slack user
    
    Returns:
        Tuple of (success, error_message). If successful, error_message is None.
    """
    if not SLACK_BOT_TOKEN:
        return False, "Slack bot token not configured"
    
    headers = {
        "Authorization": f"Bearer {SLACK_BOT_TOKEN}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "channel": user_id,
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": message
                }
            }
        ]
    }
    
    try:
        response = requests.post(
            "https://slack.com/api/chat.postMessage",
            headers=headers,
            json=payload,
            timeout=REQUEST_TIMEOUT
        )
        response.raise_for_status()
        
        result = response.json()
        
        if not result.get("ok"):
            error = result.get("error", "Unknown error")
            logger.error(f"Slack API error: {error}")
            return False, f"Slack API error: {error}"
        
        return True, None
        
    except Timeout:
        logger.error("Timeout while sending Slack message")
        return False, "Slack API request timeout"
    except ConnectionError:
        logger.error("Connection error while sending Slack message")
        return False, "Unable to connect to Slack API"
    except RequestException as e:
        logger.error(f"Request error while sending Slack message: {str(e)}")
        return False, f"Slack API request failed: {str(e)}"
    except Exception as e:
        logger.error(f"Unexpected error while sending Slack message: {str(e)}")
        return False, f"Unexpected error: {str(e)}"


@app.route('/webhook/build-failure', methods=['POST'])
def handle_build_failure():
    """Handle GitHub build failure webhook"""
    request_id = str(uuid.uuid4())
    logger.info(f"[{request_id}] Received build failure webhook")
    
    # Validate Content-Type
    if not request.is_json:
        logger.warning(f"[{request_id}] Request is not JSON")
        return create_error_response(
            "Content-Type must be application/json",
            400,
            "INVALID_CONTENT_TYPE"
        )
    
    data = request.get_json()
    
    if not data:
        logger.warning(f"[{request_id}] Empty request body")
        return create_error_response(
            "Request body is empty or invalid JSON",
            400,
            "INVALID_BODY"
        )
    
    # Extract and validate required fields
    commit_sha = data.get('commit_sha', '').strip()
    author_email = data.get('author_email', '').strip()
    repo = data.get('repo', '').strip()
    logs = data.get('logs', '')
    error = data.get('error', '')
    
    # Validate required fields
    missing_fields = []
    if not commit_sha:
        missing_fields.append('commit_sha')
    if not author_email:
        missing_fields.append('author_email')
    if not repo:
        missing_fields.append('repo')
    
    if missing_fields:
        logger.warning(f"[{request_id}] Missing required fields: {missing_fields}")
        return create_error_response(
            f"Missing required fields: {', '.join(missing_fields)}",
            400,
            "MISSING_REQUIRED_FIELDS",
            {"missing_fields": missing_fields}
        )
    
    # Validate email format
    if not validate_email(author_email):
        logger.warning(f"[{request_id}] Invalid email format: {author_email}")
        return create_error_response(
            f"Invalid email format: {author_email}",
            400,
            "INVALID_EMAIL_FORMAT"
        )
    
    try:
        # 1. Analyze with Ollama
        logger.info(f"[{request_id}] Analyzing failure for {repo}...")
        analysis, analysis_error = analyze_with_ollama(logs, error, repo)
        
        if analysis_error:
            logger.error(f"[{request_id}] Analysis failed: {analysis_error}")
            return create_error_response(
                f"Failed to analyze build failure: {analysis_error}",
                503,
                "OLLAMA_SERVICE_ERROR",
                {"service": "ollama", "error": analysis_error}
            )
        
        # 2. Find Slack user
        logger.info(f"[{request_id}] Looking up Slack user: {author_email}")
        slack_user_id, slack_lookup_error = get_slack_user_by_email(author_email)
        
        if slack_lookup_error:
            logger.warning(f"[{request_id}] Slack user lookup failed: {slack_lookup_error}")
            if "not found" in slack_lookup_error.lower():
                return create_error_response(
                    slack_lookup_error,
                    404,
                    "SLACK_USER_NOT_FOUND",
                    {"email": author_email}
                )
            return create_error_response(
                f"Failed to lookup Slack user: {slack_lookup_error}",
                503,
                "SLACK_SERVICE_ERROR",
                {"service": "slack", "error": slack_lookup_error}
            )
        
        # 3. Format message
        commit_short = commit_sha[:7] if len(commit_sha) >= 7 else commit_sha
        message = f"""🚨 *Build Failed* - `{repo}`

*Commit:* `{commit_short}`

*Analysis:*
{analysis}

<https://github.com/{repo}/commit/{commit_sha}|View Commit>"""
        
        # 4. Send to Slack
        logger.info(f"[{request_id}] Sending message to Slack user: {slack_user_id}")
        success, slack_error = send_slack_dm(slack_user_id, message)
        
        if not success:
            logger.error(f"[{request_id}] Failed to send Slack message: {slack_error}")
            return create_error_response(
                f"Failed to send Slack notification: {slack_error}",
                503,
                "SLACK_SERVICE_ERROR",
                {"service": "slack", "error": slack_error}
            )
        
        logger.info(f"[{request_id}] Successfully processed build failure notification")
        return create_success_response(
            {
                "request_id": request_id,
                "repo": repo,
                "commit_sha": commit_sha,
                "slack_user_id": slack_user_id,
                "analysis_preview": analysis[:100] + "..." if len(analysis) > 100 else analysis
            },
            200,
            "Build failure notification sent successfully"
        )
        
    except Exception as e:
        logger.exception(f"[{request_id}] Unexpected error: {str(e)}")
        return create_error_response(
            "An internal server error occurred",
            500,
            "INTERNAL_SERVER_ERROR",
            {"request_id": request_id}
        )


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "services": {}
    }
    
    overall_healthy = True
    
    # Check Ollama connection
    try:
        response = requests.get(
            f"{OLLAMA_URL}/api/tags",
            timeout=5
        )
        if response.status_code == 200:
            health_status["services"]["ollama"] = {
                "status": "healthy",
                "url": OLLAMA_URL,
                "model": OLLAMA_MODEL
            }
        else:
            health_status["services"]["ollama"] = {
                "status": "unhealthy",
                "url": OLLAMA_URL,
                "error": f"HTTP {response.status_code}"
            }
            overall_healthy = False
    except Timeout:
        health_status["services"]["ollama"] = {
            "status": "unreachable",
            "url": OLLAMA_URL,
            "error": "Connection timeout"
        }
        overall_healthy = False
    except ConnectionError:
        health_status["services"]["ollama"] = {
            "status": "unreachable",
            "url": OLLAMA_URL,
            "error": "Connection refused"
        }
        overall_healthy = False
    except Exception as e:
        health_status["services"]["ollama"] = {
            "status": "error",
            "url": OLLAMA_URL,
            "error": str(e)
        }
        overall_healthy = False
    
    # Check Slack configuration
    if SLACK_BOT_TOKEN:
        health_status["services"]["slack"] = {
            "status": "configured"
        }
    else:
        health_status["services"]["slack"] = {
            "status": "not_configured",
            "warning": "SLACK_BOT_TOKEN not set"
        }
    
    if not overall_healthy:
        health_status["status"] = "degraded"
        return jsonify(health_status), 503
    
    return jsonify(health_status), 200


@app.route('/ready', methods=['GET'])
def readiness_check():
    """Readiness check endpoint - verifies all required services are available"""
    if not SLACK_BOT_TOKEN:
        return jsonify({
            "ready": False,
            "reason": "SLACK_BOT_TOKEN not configured"
        }), 503
    
    # Check Ollama
    try:
        response = requests.get(f"{OLLAMA_URL}/api/tags", timeout=5)
        if response.status_code != 200:
            return jsonify({
                "ready": False,
                "reason": f"Ollama service unhealthy (HTTP {response.status_code})"
            }), 503
    except Exception as e:
        return jsonify({
            "ready": False,
            "reason": f"Ollama service unreachable: {str(e)}"
        }), 503
    
    return jsonify({
        "ready": True,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }), 200


@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors"""
    return create_error_response(
        "Endpoint not found",
        404,
        "NOT_FOUND"
    )


@app.errorhandler(405)
def method_not_allowed(error):
    """Handle 405 errors"""
    return create_error_response(
        "Method not allowed",
        405,
        "METHOD_NOT_ALLOWED"
    )


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors"""
    logger.exception("Internal server error")
    return create_error_response(
        "An internal server error occurred",
        500,
        "INTERNAL_SERVER_ERROR"
    )


if __name__ == '__main__':
    logger.info("Starting Flask application")
    logger.info(f"Ollama URL: {OLLAMA_URL}")
    logger.info(f"Ollama Model: {OLLAMA_MODEL}")
    app.run(host='0.0.0.0', port=5000, debug=False)