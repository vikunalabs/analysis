# **Authentication & API Flow: Vite SPA with Spring Auth & Resource Servers**

### **Core Security Principles**

1.  **HttpOnly Cookies:** Access and Refresh tokens are stored in `HttpOnly`, `Secure`, `SameSite=Strict/Lax` cookies to mitigate XSS attacks.
2.  **CSRF Tokens:** All state-changing requests (POST, PUT, PATCH, DELETE) require a valid CSRF token in a request header to mitigate CSRF attacks.
3.  **Stateless JWT Validation:** The Resource Server validates Access Tokens using the Auth Server's public key, requiring no shared state.
4.  **Key-Based Signing:** All tokens (Access, Refresh, CSRF) are signed using the Auth Server's **private RSA key** and validated by other services using its corresponding **public key**.

### **Architecture Components**

*   **Frontend (SPA):** Vite + TypeScript application. Manages UI and session state (including CSRF token in memory).
*   **Auth Server:** Spring Boot service. Handles authentication, token issuance, and token refresh. **Holds the private RSA key.**
*   **Resource Server:** Spring Boot service. Serves business data. **Holds the public RSA key** to validate tokens.

---

## **Phase 1: Initial Load & Pre-Login (Anonymous State)**

This phase protects endpoints like `login` and `register` that change state but don't require authentication.

### **Step 1.1: Fetch Anonymous CSRF Token**

*   **SPA -> Auth Server:** `GET /auth/csrf`
*   **Purpose:** To obtain a token for making pre-login state-changing requests (e.g., login, register).
*   **Auth Server Response:**
    *   **Body:** `{ "csrfToken": "base64(header).base64(payload).base64(signature)" }`
    *   **How it's made:**
        1.  **Payload:** `{ "purpose": "anon_csrf", "exp": 1679875200 }` (short-lived, e.g., 10 mins)
        2.  **Signing:** The Auth Server signs the token header and payload with its **private RSA key**.
*   **SPA Action:** Stores the received `csrfToken` in memory (e.g., a global variable or store).

### **Step 1.2: User Login**

*   **SPA -> Auth Server:** `POST /auth/login`
*   **Headers:**
    *   `Content-Type: application/json`
    *   `X-CSRF-TOKEN: <anonymous_csrf_token>` (from Step 1.1)
*   **Body:** `{ "email": "user@example.com", "password": "..." }`
*   **Auth Server Action:**
    1.  Validates the `X-CSRF-TOKEN` by checking its signature using the **public key**. The `purpose: "anon_csrf"` claim confirms it's for this use.
    2.  Validates user credentials.
    3.  If valid, proceeds to **Step 2.1**.

---

## **Phase 2: Authentication & Session Establishment**

### **Step 2.1: Auth Server Issues Tokens**

Upon successful login, the Auth Server:
1.  **Generates a Session Identifier:** Creates a unique `sessionId` (e.g., a UUID).
2.  **Creates Tokens:**
    *   **Access Token (JWT):** `{ "sub": "user-123", "exp": ... }`. Signed with the **private key**.
    *   **Refresh Token (JWT):** `{ "jti": "uuid", "sub": "user-123", "sid": "<sessionId>", "exp": ... }`. Signed with the **private key**. The `sid` claim binds it to the session.
    *   **Authenticated CSRF Token (JWT):** `{ "purpose": "auth_csrf", "sid": "<sessionId>", "exp": ... }`. Signed with the **private key**. The `sid` claim binds it to the session.
3.  **Stores Session:** Persists the `refreshToken.jti` and `sessionId` in a database (e.g., for logout functionality).
4.  **Sends HTTP Response:**
    *   **Cookies:** Sets `access_token` and `refresh_token` as `HttpOnly`, `Secure` cookies.
    *   **Body:** `{ "user": { "id": "user-123", "name": "John" }, "csrfToken": "<authenticated_csrf_token>" }`

### **Step 2.2: SPA Updates State**

*   The SPA receives the login response.
*   It **replaces** the anonymous CSRF token in memory with the new, more powerful **authenticated CSRF token**.
*   It updates its UI to reflect the logged-in state using the user data from the response body.

---

## **Phase 3: Accessing Protected Resources**

### **Step 3.1: Read Request (No CSRF needed)**

*   **SPA -> Resource Server:** `GET /api/profiles/me`
*   **Cookies:** Browser automatically sends the `access_token` cookie.
*   **Resource Server Action:**
    1.  Extracts JWT from cookie.
    2.  Validates the JWT's signature using the **public RSA key** and checks its expiry.
    3.  If valid, processes the request and returns data (`200 OK`).

### **Step 3.2: State-Changing Request (CSRF required)**

*   **SPA -> Resource Server:** `PATCH /api/profiles/me`
*   **Headers:**
    *   `Content-Type: application/json`
    *   `X-CSRF-TOKEN: <authenticated_csrf_token>` (from Step 2.2)
*   **Cookies:** Browser automatically sends the `access_token` cookie.
*   **Body:** `{ "name": "New Name" }`
*   **Resource Server Action:**
    1.  Validates the Access Token JWT from the cookie (as in Step 3.1).
    2.  **Validates the CSRF Token:**
        *   Decodes the JWT and verifies its signature using the **public key**.
        *   Checks the `purpose: "auth_csrf"` claim.
        *   *(Optional but recommended)*: Can check if the `sid` claim matches a valid, non-revoked session in the shared database. This is crucial for instant logout.
    3.  If all checks pass, processes the request.

---

## **Phase 4: Token Refresh**

### **Step 4.1: Access Token Expires**

*   **SPA -> Resource Server:** A request fails with `401 Unauthorized`.
*   **SPA** detects this error.

### **Step 4.2: Request New Access Token**

*   **SPA -> Auth Server:** `POST /auth/refresh`
*   **Headers:** `X-CSRF-TOKEN: <authenticated_csrf_token>`
*   **Cookies:** Browser automatically sends the `refresh_token` cookie.
*   **Auth Server Action:**
    1.  Validates the CSRF token (signature + `purpose` + `sid`).
    2.  Extracts the Refresh Token JWT from the cookie, validates its signature with the **public key**, and checks its expiry.
    3.  Checks the `jti` and `sid` against the database to ensure it hasn't been revoked.
    4.  If valid, **repeats Step 2.1**: Issues a new Access Token, a new Refresh Token (with the same `sid`), and a new CSRF token. Sets new cookies and returns the new CSRF token in the body.
*   **SPA Action:** Replaces the old CSRF token in memory with the new one from the response.

---

## **Phase 5: Logout**

### **Step 5.1: User Initiates Logout**

*   **SPA -> Auth Server:** `POST /auth/logout`
*   **Headers:** `X-CSRF-TOKEN: <authenticated_csrf_token>`
*   **Cookies:** Browser automatically sends all cookies.

### **Step 5.2: Auth Server Invalidates Session**

*   **Auth Server Action:**
    1.  Validates the CSRF token. The `sid` inside it identifies the session to terminate.
    2.  **Deletes the session record** (identified by the `sid`) from the database. This instantly invalidates the Refresh Token and all associated CSRF tokens.
    3.  Sends a response that instructs the browser to clear the `access_token` and `refresh_token` cookies (by setting them to expire immediately).

### **Step 5.3: SPA Cleans Up**

*   The SPA clears the authenticated CSRF token from its memory.
*   It updates its UI to show the user as logged out.

This workflow provides a robust, secure, and scalable foundation for your application, leveraging the best of both cookie-based token storage and key-based cryptographic signatures.
