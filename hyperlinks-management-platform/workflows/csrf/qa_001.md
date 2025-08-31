# CSRF Workflow

## QA1

**Question**
I am planning to build a SPA using Vite + Vanilla TS, with no frameworks support. This SPA needs to interact with dual backend - Auth Server and Resource Server. Spring auth federates to Google which acts as external identity providers in case of google logins, alongside it also exposes endpoints for traditional user management system endpoints such as registration, login, confirm account via email, forgot password, reset password, resend email verification etc. Irrespective of the login mechanism, Spring auth server issues access token (with user claims, expiry etc) and refresh tokens in separate HttpOnly cookies.
Once the SPA has the both HttpOnly cookies, it can send a httponly cookie containing access token to Auth Server (as it has some secured endpoints) or Resource server for invoking the actual business functionalites. Now I understand that CSRF protection is needed (since cookies are auto-sent). So I am planning to implement an endpoints as mentioned below,

Endpoint: /auth/csrf
Method GET	
Purpose(Optional) Fetches a CSRF token for making state-changing requests (like logout). Returns {csrfToken: "value"}.

Can you please explain the workflow between these application - Frontend (SPA), Auth Server and Resource Server?

**Answer**
Of course. This is an excellent architecture that follows modern security best practices. Let's break down the complete workflow between your SPA, Auth Server, and Resource Server.

### Core Security Concepts in Your Architecture

1.  **Authentication:** Proving "who you are". Handled by the Auth Server via Google OAuth or traditional login.
2.  **Authorization:** Proving "you have permission to do this". Handled by the access token.
3.  **Session Management:** Using **HttpOnly, Secure, SameSite=Strict/Lax** cookies for tokens prevents them from being stolen via XSS. This is your primary defense.
4.  **CSRF Protection:** Since cookies are auto-sent, we need to ensure the request originated from our legitimate frontend. This is done with anti-CSRF tokens.

---

### Detailed Workflow

Here is a step-by-step flow covering all major interactions.

#### Phase 1: Initial Page Load & CSRF Token Acquisition

1.  **User** navigates to `https://your-spa.com`.
2.  **SPA (Vite + TS)** loads. As part of its initialization boot sequence, it immediately makes a call to a safe endpoint to get a CSRF token.
3.  **SPA** -> **Auth Server**: `GET /auth/csrf`
    *   This is a **safe** HTTP GET request. It does not need CSRF protection itself.
    *   The Auth Server's session middleware (e.g., Spring Security) will automatically attach a session identifier cookie (e.g., `JSESSIONID`) in the response if one doesn't exist. This cookie is also `HttpOnly`.
4.  **Auth Server** generates a cryptographically random CSRF token, associates it with the user's new session (stored in memory or a database), and sends it in the response body.
    *   `Response Body: { "csrfToken": "abc123def456..." }`
    *   **Crucially, it does NOT set a cookie for the CSRF token.** The token must be accessible to JavaScript to be added to headers.
5.  **SPA** receives the response and stores the `csrfToken` value in memory (e.g., a global variable or a state management store). It now has the "secret key" needed for all subsequent state-changing requests.

#### Phase 2: User Authentication (Traditional Login Example)

6.  **User** fills out the login form (email, password) and clicks "Log In".
7.  **SPA** -> **Auth Server**: `POST /auth/login`
    *   **Headers:**
        *   `Content-Type: application/json`
        *   `X-CSRF-TOKEN: abc123def456...` (The token stored from step 5)
    *   **Body:** `{ "email": "user@example.com", "password": "..." }`
    *   The browser **automatically** includes the `JSESSIONID` cookie (and any other auth-related cookies) with this request.
8.  **Auth Server** receives the request.
    *   It validates the `JSESSIONID` cookie to find the session.
    *   It compares the `X-CSRF-TOKEN` header value with the token stored for that session. If they match, the request is legitimate.
    *   It then validates the email and password.
9.  If credentials are valid, the **Auth Server**:
    *   Generates an **Access Token** (JWT) and a **Refresh Token**.
    *   Sets two new `HttpOnly`, `Secure`, `SameSite=Strict` cookies:
        *   `access_token=<JWT>`
        *   `refresh_token=<opaque-token>`
    *   Returns a `200 OK` response. The response body can contain user claims (e.g., `{ "user": { "id": "123", "name": "John" } }`) decoded from the JWT *or* fetched from the DB.
10. The SPA is now "logged in". The tokens are stored securely in cookies and are completely inaccessible to JavaScript.

#### Phase 3: Accessing Protected Resources

11. **User** performs an action in the SPA that requires data (e.g., loads their profile page).
12. **SPA** -> **Resource Server**: `GET /api/profiles/me`
    *   The browser **automatically** includes the `access_token` cookie with this request.
    *   **No CSRF token is needed here.** Why? This is a **read-only** GET request. CSRF attacks aim to execute state-changing actions (POST, PUT, DELETE, PATCH). It is common practice to not protect safe methods. (You could protect them, but it's often considered unnecessary overhead).
13. **Resource Server** receives the request.
    *   It reads the JWT from the `access_token` cookie.
    *   It validates the JWT's signature, issuer (`iss`), audience (`aud`), and expiry.
    *   If valid, it processes the request and returns the user's profile data (`200 OK`).

#### Phase 4: Making a State-Changing Request

14. **User** updates their profile name and clicks "Save".
15. **SPA** -> **Resource Server**: `PATCH /api/profiles/me`
    *   **Headers:**
        *   `Content-Type: application/json`
        *   `X-CSRF-TOKEN: abc123def456...` (The SPA must still have this in memory)
    *   **Body:** `{ "name": "New Name" }`
    *   The browser **automatically** includes the `access_token` cookie.
16. **Resource Server** receives the request.
    *   It validates the JWT from the cookie (just like step 13).
    *   **It then checks for the `X-CSRF-TOKEN` header.** The resource server must also be configured to validate this token against the user's session. This means your Auth Server and Resource Server must share a common session store (e.g., Redis) or the CSRF token validation mechanism (if you use a signed token).
    *   If both the JWT and CSRF token are valid, it updates the profile and returns a success response.

#### Phase 5: Token Refresh (When Access Token Expires)

17. Eventually, the `access_token` cookie expires. The next request to the Resource Server will fail with `401 Unauthorized`.
18. **SPA** detects the `401` error.
19. **SPA** -> **Auth Server**: `POST /auth/refresh`
    *   The browser **automatically** includes the `refresh_token` cookie.
    *   **Headers:** `X-CSRF-TOKEN: ...` (The SPA uses its stored CSRF token for this state-changing request).
20. **Auth Server** receives the request.
    *   Validates the `refresh_token` cookie and the CSRF token.
    *   If valid, it issues a new **Access Token** (and potentially a new Refresh Token following rotation policies).
    *   It sets the new `access_token` cookie (and `refresh_token` cookie if rotated) on the response.
21. **SPA** automatically retries the original failed request to the Resource Server with the new, valid access token cookie.

#### Phase 6: Logout

22. **User** clicks "Logout".
23. **SPA** -> **Auth Server**: `POST /auth/logout`
    *   **Headers:** `X-CSRF-TOKEN: ...`
    *   The browser sends all cookies (`JSESSIONID`, `access_token`, `refresh_token`).
24. **Auth Server** receives the request, validates the CSRF token, and then:
    *   Invalidates the user's session on the server-side.
    *   Instructs the browser to delete the cookies by setting them to expire immediately in the response headers:
        `Set-Cookie: access_token=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; HttpOnly; Secure; SameSite=Strict`
    *   Does the same for `refresh_token` and `JSESSIONID`.
25. The SPA clears its in-memory CSRF token and updates its UI to show the user as logged out.

---

### Critical Implementation Considerations

*   **Session Storage:** For the Auth Server and Resource Server to validate the same CSRF token, they must share a session state. A distributed session store like **Redis** is mandatory for this architecture unless you use a stateless CSRF token (e.g., a signed token where the secret is shared between servers).
*   **CORS (Cross-Origin Resource Sharing):** If your SPA, Auth Server, and Resource Server are on different domains, you must configure CORS correctly on the servers. The Auth Server must allow credentials (`Access-Control-Allow-Credentials: true`) and specify the SPA's origin in `Access-Control-Allow-Origin` (cannot be `*`).
*   **SameSite Cookies:** Setting `SameSite=Lax` (default in modern browsers) is a good balance. It prevents CSRF from other sites but allows cookies to be sent when navigating to your site from an external link. `SameSite=Strict` is more secure but can break navigation from emails.
*   **SPA Routing:** Ensure your SPA's routing (e.g., `https://spa.com/protected-route`) is protected. If the user refreshes the page, the SPA should check on load if it has a valid session (e.g., by calling a `/auth/me` endpoint) before rendering protected content.

This workflow provides a robust, secure foundation for your SPA that effectively mitigates the primary web vulnerabilities (XSS and CSRF).


## QA2

**Question**
Thank for a good walkthrough of the flow! As I mentioned the auth server generates JWT (access and refresh) tokens after successful authentication, I am trying to keep it Stateless but store store only refresh token for logout mechanisms. So do I need to have a storage for CSRF token as explained above?
You mentioned about stateless CSRF token, can you please explain how this works?

**Answer**
Excellent question. This gets to the heart of a key architectural decision: stateful vs. stateless tokens.

You are absolutely right to aim for a stateless Auth Server using JWT. The need for a shared session store (like Redis) purely for CSRF tokens is a major drawback of the traditional stateful approach and undermines the stateless goal.

The solution is a **stateless, signed CSRF token**. This is a fantastic and secure alternative.

### How Stateless Signed CSRF Tokens Work

The core idea is to create a token that is **self-validating**. The server can verify that the token was issued by it and hasn't been tampered with, without having to store it anywhere.

Here's the process:

#### 1. Generating the Token (Auth Server)

When the SPA calls `GET /auth/csrf`:
*   The Auth Server generates a random value (e.g., a cryptographically secure random string of 32 bytes). This is the "claim".
*   The server then creates a signature for this random value.
    *   `signature = HMAC-SHA256(secretKey, randomValue)`
*   It combines the random value and the signature into a single token, often in a format like: `base64UrlEncode(randomValue) + "." + base64UrlEncode(signature)`
*   It sends this compound token to the client in the response body: `{ "csrfToken": "abc123.def456..." }`

**Crucially, the server does NOT store this token.** It forgets about it immediately.

#### 2. Client Stores and Sends the Token

The workflow for the SPA remains identical:
1.  Store the received `csrfToken` in memory.
2.  For any state-changing request (POST, PUT, DELETE, PATCH), add it to a header: `X-CSRF-TOKEN: abc123.def456...`

#### 3. Validating the Token (Auth Server or Resource Server)

When a request with the `X-CSRF-TOKEN` header arrives:
1.  The server splits the token on the dot `.` to separate the original `randomValue` and the `signature`.
2.  It recalculates the signature using the same `secretKey` and the `randomValue` it received from the client.
    *   `expectedSignature = HMAC-SHA256(secretKey, receivedRandomValue)`
3.  It compares the newly calculated `expectedSignature` with the `receivedSignature` from the client's header.
    *   **If they match perfectly**, the token is valid. It proves:
        *   The token was originally issued by this server (only it has the `secretKey` to create a valid signature).
        *   The token was not tampered with during transit (any change to the `randomValue` would invalidate the signature).
    *   **If they don't match**, the request is rejected with a `403 Forbidden` error.

---

### How This Fits Your Revised (Stateless) Architecture

This approach dovetails perfectly with your goal.

| | **Stateful (Session-Stored) CSRF** | **Stateless (Signed) CSRF** | **Your Stateless Architecture** |
| :--- | :--- | :--- | :--- |
| **Server State** | Requires a shared session store (e.g., Redis) for all servers. | **No server-side state.** Completely stateless. | ✅ Perfect Fit |
| **Secret** | The session ID acts as the secret. | A single, shared `secretKey` is configured on all servers. | ✅ Easy to configure. |
| **Validation** | Server must lookup the session and compare tokens. | Server performs a cryptographic signature verification. | ✅ Very fast. |
| **Logout** | Invalidating the session automatically invalidates all CSRF tokens for that user. | **The main challenge.** You cannot individually invalidate CSRF tokens. | ⚠️ Requires a strategy. |

### The Logout Challenge and The Solution

The one downside of stateless tokens is that they are valid until they expire. If an attacker steals a CSRF token, they could use it until the victim's login session ends (which deletes the cookies). This is often considered an acceptable risk, but we can do better.

**Solution: Bind the CSRF Token to the User's Session Token**

The most common and effective strategy is to link the validity of the CSRF token to the refresh token. Here’s how:

1.  **Include a "Session Identifier" in the CSRF Token:**
    Instead of using a purely random value, the "claim" part of your CSRF token should be a structured payload. You can use a JWT for this as well!

    **Payload of the CSRF "JWT":**
    ```json
    {
      "jti": "a-random-uuid", // Unique ID for this CSRF token
      "sub": "user-123",       // User identifier
      "sid": "session-456",    // The ID of the refresh token session!
      "exp": 1679875200        // Expiration time (e.g., 30 minutes)
    }
    ```
2.  **Sign this payload** with your HMAC secret key. This becomes your stateless CSRF token.
3.  **Store the Session ID (`sid`) with the Refresh Token:**
    When you create a refresh token (which you are storing in the database for logout), also store a `sessionId` (e.g., a UUID) with it.
4.  **Validation on Logout:**
    When a user logs out, you **invalidate the refresh token** in the database. As part of this, you also delete or mark the associated `sessionId` as invalid.
5.  **Enhanced CSRF Validation:**
    When validating a CSRF token, after verifying the signature, the server can also check the `sid` claim in the CSRF token against the database.
    *   If the `sid` is found and is still valid, the CSRF token is accepted.
    *   If the `sid` is not found (because the user logged out), the CSRF token is rejected.

This creates a powerful link: **Logging out instantly invalidates all CSRF tokens** that were issued for that specific login session, without requiring a shared session store for the CSRF tokens themselves.

### Revised Stateless Workflow Summary

1.  **Login:** Auth Server issues JWT access token (cookie), creates a refresh token with a `sessionId` (stored in DB, sent in HttpOnly cookie), and generates a signed CSRF token bound to that `sessionId` (sent in response body).
2.  **API Call:** SPA sends access token (cookie) + CSRF token (header).
3.  **Validation:** Resource Server validates JWT signature & expiry. It then validates the CSRF token's signature and checks that its `sid` matches a valid session in the refresh token DB.
4.  **Logout:** Auth Server deletes the refresh token record (and its `sessionId`) from the DB. This instantly invalidates the associated CSRF token.

This architecture gives you the best of both worlds: the scalability of a stateless server with the security of being able to instantly invalidate sessions upon logout.


## QA3

**Question**
I'm confused here - In Phase 1, Frontend SPA expect the tokens on initial page load, here the user is not authenticated yet and the suggestion was to use a random value , create a signature for this random value and share the value. So we don't store this random id in any DB because we haven't created any refresh token as the user is not logged in. But this contradicts the logout solution that you've suggested.

**Answer**
You have hit on a critical and subtle point. **You are absolutely right to be confused.** My previous answer blended two distinct concepts and created a contradiction. Thank you for catching this. Let's clarify this by separating the two different states of the application:

1.  **The Anonymous State (Pre-Login)**
2.  **The Authenticated State (Post-Login)**

Each state requires a different CSRF strategy because the threat model and available information change.

---

### 1. CSRF for Anonymous Users (Pre-Login)

This is for endpoints that change state but don't require authentication. The most common example is the **login endpoint itself**, but also user registration.

*   **The Problem:** You need to protect `POST /auth/login` from CSRF. An attacker could trick a user into submitting a login form to your server, potentially logging them in as the attacker and capturing any data they enter post-login.
*   **The Solution:** Use a **simple, stateless, signed CSRF token** exactly as described initially.
    *   **Workflow:**
        1.  User loads the SPA. They are anonymous.
        2.  SPA calls `GET /auth/csrf`.
        3.  Auth Server generates a random value, signs it, and returns the compound token. **It does not store this anywhere.** It's a one-time-use key for the next state-changing action.
        4.  User submits login form. SPA sends the credentials + the CSRF token in the header.
        5.  Auth Server validates the signature of the CSRF token. If it's valid, it processes the login.
*   **Why this is secure:** The token is short-lived (e.g., 20-30 minutes) and single-use. The signature validation proves the request originated from your genuine frontend. There is no "session" to invalidate here, so the stateless nature is perfect.

### 2. CSRF for Authenticated Users (Post-Login)

This is for endpoints that change state **and** require an authenticated user. Examples: changing profile data, making a purchase, and **logout**.

*   **The Problem:** Now the user has a session. We need to ensure that a CSRF token cannot be used after the user has intentionally ended their session (logged out).
*   **The Solution:** Use a **session-bound, stateless, signed CSRF token**. This is what my previous answer described.

    *   **Workflow (Revised Correctly):**
        1.  **During Login:** After the user's credentials are verified in step 5 above, the Auth Server now does several things:
            *   Generates a Refresh Token and stores it in the database **with a unique `sessionId`**.
            *   Generates an Access Token (JWT).
            *   **Generates a new CSRF token.** This new token's payload contains the `sessionId` (e.g., `{"sid": "session-456"}`). It signs this payload and creates the token.
            *   It sets the `access_token` and `refresh_token` cookies. It also sends the new **session-bound CSRF token** in the response body (e.g., along with the user profile info).
        2.  **SPA Behavior:** The SPA receives this new CSRF token and **replaces** the anonymous one it had in memory. All future requests will use this new, stronger token.
        3.  **Making an Authenticated Request:** SPA sends the access token (cookie) + the new session-bound CSRF token (header).
        4.  **Server Validation:** The Resource Server validates the JWT *and* the CSRF token. It checks the CSRF signature and can also check that the `sid` inside it is still valid (if you implement the enhanced check).
        5.  **Logout:** When the user logs out, the Auth Server **invalidates the refresh token record** (and its `sessionId`) in the database. Any subsequent CSRF token validation that checks the `sid` will now fail, instantly protecting the logged-out user.

### Summary: Resolving the Contradiction

| | **Anonymous State** | **Authenticated State** |
| :--- | :--- | :--- |
| **Purpose** | Protect login, registration | Protect all other state-changing actions |
| **Token Type** | Simple Signed Token | Session-Bound Signed Token |
| **Token Content** | `randomValue.signature` | `base64({"sid": "abc"}).signature` |
| **Server Storage** | **None.** Stateless. | The `sessionId` is stored as part of the **refresh token** in the DB. |
| **Invalidation** | Token expires naturally. | Invalidated when the refresh token is deleted during logout. |

**The key takeaway:** Your SPA will handle **two different CSRF tokens** during a user's visit:
1.  One **before login** (for protecting the login itself).
2.  A completely different one **after login** (for protecting everything else).

The initial `GET /auth/csrf` endpoint serves the first purpose. The login response (`POST /auth/login`) provides the second, more powerful token. This elegantly solves the problem without any contradiction.
