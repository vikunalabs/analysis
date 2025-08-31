# Token Management (Critical for SPA Session)

These are the most important endpoints for maintaining the session silently.

| Endpoint | Method | Purpose | Request Body | Response                             | Cookies Set (HttpOnly) | Notes                                                                 |
| :--- | :--- | :--- | :--- |:-------------------------------------| :--- |:----------------------------------------------------------------------|
| `/auth/refresh` | `POST` | **Silent Refresh.** Uses refresh token cookie to get new access token. | None | `204 No Content`                     | **New Access Token** | **Must be CSRF-protected.** Called via iframe or fetch.               |
| `/auth/user` | `GET` | Get current user profile & claims. | None | `200 OK`, `{id, email, name, roles}` | None | Used on app load to populate user state.                              |
| `/auth/validate` | `GET` | Lightweight token validation. | None | `200 OK` or `401 Unauthorized`       | None | Optional, can be used instead of a blind call to the resource server. |

#### D. Security

| Endpoint     | Method | Purpose                                                                                                           |
|:-------------|:-------|:------------------------------------------------------------------------------------------------------------------|
| `/auth/csrf` | `GET`  | (Optional) Fetches a CSRF token for making state-changing requests (like logout). Returns `{csrfToken: "value"}`. |


### 1. Why are the Token Management Endpoints Required?

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
    - Stores this JWT in an `HttpOnly + Secure + SameSite`=`Strict` cookie. Each is to be stored in a separate ``HttpOnly` cookie.

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

These endpoints are the **engine room of the silent authentication system**. They allow your SPA to maintain a session without requiring a full page reload or redirecting the user to a login page, which would destroy the single-page application experience.

Let's break down each one:

*   **`POST /auth/refresh`**
    *   **The Problem it Solves:** Access tokens are short-lived (e.g., 5-15 minutes) for security. Without this endpoint, your user's session would end abruptly every 5 minutes, forcing them to log in again constantly.
    *   **The Solution:** This endpoint is the "silent" part of silent refresh. The SPA can call this endpoint *before* the access token expires (or after it gets a 401) to get a new one. Since the request automatically includes the HttpOnly refresh token cookie, the Auth Server can validate it and issue a new access token cookie *without any user interaction*.
    *   **Analogy:** It's like having a key (access token) to get into your office that expires every hour, and a secure, automated system (refresh token) that can make a new key for you as long as you're still an employee.

*   **`GET /auth/user`**
    *   **The Problem it Solves:** The user's information (name, email, roles, etc.) is stored inside the JWT access token. However, the token is in an HttpOnly cookie, which means **JavaScript cannot read it.** The SPA needs to know who is logged in and what they are allowed to see (e.g., display a welcome message, conditionally render admin buttons).
    *   **The Solution:** This endpoint decodes the access token from the cookie (on the server side, where it's accessible) and returns the user's claims in a simple JSON response. The SPA calls this on initial load to populate its authentication state.
    *   **Analogy:** You have a secure ID badge (the HttpOnly cookie). You can't read what's on it yourself, but you can show it to the front desk (`/auth/user` endpoint), and they will tell you your name and access level.

*   **`GET /auth/validate` (Optional)**
    *   **The Problem it Solves:** When the SPA first loads, it doesn't know if the user is logged in. It could try to call a protected resource API, but that might be a "heavy" request.
    *   **The Solution:** This is a lightweight endpoint whose only job is to validate the access token cookie. It answers the question "Do I have a valid session?" quickly and efficiently before the app tries to load any real data.

**In summary:** Without these endpoints, your SPA would be "blind." It wouldn't know who the user is, and it would have no way to automatically renew its session, breaking the core user experience.


● Perfect! Now let me explain why we need WWW-Authenticate header handling and implement it:

Why WWW-Authenticate Header is Critical:

According to your documentation, the Resource Server should return:
- 401 Unauthorized + WWW-Authenticate: Refresh header when tokens expire

This is crucial because:

1. SPA Detection: The SPA needs to distinguish between:
   - 401 = "Access denied" (redirect to login)
   - 401 + WWW-Authenticate: Refresh = "Token expired, try refresh"
2. Silent Refresh Trigger: This header tells the SPA to call /api/auth/refresh instead of redirecting to login
3. HTTP Standard: WWW-Authenticate is the standard way to indicate authentication method requirements
