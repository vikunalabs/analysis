# OAuth2 Flow with SPA, Spring Auth Server, and Google (Conceptual Summary)

## Table of Contents
1. [System Components](#system-components)
2. [Core Authentication Flow](#core-authentication-flow)
3. [Token Management](#token-management)
4. [Security Considerations](#security-considerations)
5. [Alternative Flows](#alternative-flows)

## System Components

### 1. Actors
- **User**: End-user accessing the application
- **SPA (Single Page Application)**: Frontend application (React/Angular/Vue)
- **Spring Auth Server**: Backend service handling authentication
- **Spring Resource Server**: Backend service serving protected APIs
- **Google OAuth2**: Identity Provider (IdP)

### 2. Trust Boundaries
- **Browser-Only Zone**: SPA runs here (untrusted environment)
- **Trusted Server Zone**: Auth + Resource Servers (fully controlled)

## Core Authentication Flow

### 1. Initial Login Sequence
1. User clicks "Login with Google" in SPA
2. SPA redirects to Auth Server's `/oauth2/authorization/google` endpoint
3. Auth Server initiates Google OAuth2 flow:
   - Redirects to Google's auth page
   - User authenticates with Google
4. Google redirects back to Auth Server's `/login/oauth2/code/google` with authorization code
5. Auth Server:
   - Exchanges code for Google ID token
   - Validates Google's JWT
   - Issues a short-lived JWT with user claims, along with a long-lived JWT token.
   - Stores this JWT in an `HttpOnly + Secure + SameSite`=`Lax` cookie. Each is to be stored in a separate? ``HttpOnly` cookie.

### 2. API Access Flow
1. SPA makes a request to the Resource Server (e.g., GET /api/data)
2. The browser automatically includes the HttpOnly cookie (containing your Auth Server’s JWT)
3. Resource Server:
   - Extracts JWT from cookie
   - Validates the JWT's signature using Auth Server's public key
   - Checks standard claims (exp, iss, aud)
   - If valid, the Resource Server processes the request
   - If invalid (tampered), it returns 401 Unauthorized
   - If invalid (expired), it return `401` + `WWW-Authenticate: Refresh` header 

### 3. Token Refresh Flow
1. On 401 response (expired token):
2. SPA detects `401` + `WWW-Authenticate: Refresh` header and initiates silent refresh:
   - Calls Auth Server's `/refresh` endpoint (with credentials) (via hiddent iframe or fetch)
3. Auth Server:
   - Validates refresh token (from separate cookie)
   - Issues new JWT + refresh token
   - Sets new secure `HttpOnly` cookies
4. SPA retries original request with fresh token

## Token Management

### 1. Token Types
| Token | Storage | Lifetime | Purpose |
|-------|---------|----------|---------|
| Access JWT | HttpOnly Cookie | 15-30 min | API authentication |
| Refresh Token | HttpOnly Cookie | 7-30 days | Obtain new access tokens |

### 2. Cookie Security
All cookies have:
- `Secure` flag (HTTPS only)
- `HttpOnly` (no JS access)
- `SameSite=Lax` (CSRF protection)
- `Path` restriction (e.g., `/refresh` for refresh token)
- Domain scoping (avoid wildcard domains)

## Security Considerations

### 1. Threat Mitigations
| Threat | Countermeasure |
|--------|---------------|
| XSS | HttpOnly cookies |
| CSRF | SameSite cookies + CORS policies |
| Token Theft | Short-lived JWTs + refresh rotation |
| MITM | HSTS + HTTPS enforcement |

### 2. Session Management
- Refresh tokens are:
  - Bound to user agent
  - Revocable
  - Single-use (rotation policy)
- Active session monitoring via:
  - Last-used timestamps
  - IP fingerprinting

## Alternative Flows

### 1. Without Refresh Tokens
- On 401, redirect to login page
- Auth Server re-initiates Google auth with prompt=none
- Pro: Simpler implementation
- Con: Visible redirect flash

### 2. Server-Side Sessions
- Uses traditional session cookies
- Requires sticky sessions in load-balanced environments
- Easier invalidation but less scalable

---
