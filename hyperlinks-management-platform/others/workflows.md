Excellent. I will focus solely on the workflows, detailing the sequence of events and decisions from the perspectives of the User, the SPA (Frontend), and the Auth Server (Backend).

### **Documentation: Authentication & User Management Workflows**

#### **1. Architecture Overview & Core Security Principles**

*   **Dual-Server Model:** The SPA interacts with two separate backends: the **Auth Server** (handles identity) and the **Resource Server** (handles business data).
*   **Token Storage:** Access and Refresh tokens are issued as `HttpOnly`, `Secure`, `SameSite=Lax/Strict` cookies by the Auth Server. The SPA cannot read these tokens directly.
*   **Session State:** The SPA's knowledge of the user's session is derived from:
    1.  The presence of a valid user object in its local state (e.g., Zustand store).
    2.  A CSRF token stored in memory for making authenticated requests.
*   **Authentication Signal:** A `401 Unauthorized` response with the `WWW-Authenticate: Refresh` header from *any* server is the universal signal for the SPA to attempt a silent token refresh.

---

### **Workflow 1: Traditional User Registration & Email Confirmation**

This workflow involves state changes before a user is authenticated, requiring a CSRF token for protection.

| Step | User Action / System Event | SPA (Frontend) Perspective | Auth Server (Backend) Perspective |
| :--- | :--- | :--- | :--- |
| **1. Pre-Flight** | User loads the registration page. | 1. On application init, fetch an anonymous CSRF token via `GET /auth/csrf`.<br>2. Store this token in memory. | 1. Generate a cryptographically secure random value.<br>2. Sign it with the private RSA key to create a single-use, anonymous CSRF token.<br>3. Return `{ csrfToken: "value" }` in the response body. |
| **2. Submission** | User fills and submits the registration form. | 1. Collect form data (`email`, `password`, `organization`, etc.).<br>2. Send `POST /auth/register` with the JSON body and the `X-CSRF-TOKEN` header containing the anonymous token.<br>3. Show a loading state. | 1. **Validate the CSRF token's signature** using the public key.<br>2. Validate the request payload (email format, password strength, unique email).<br>3. **Within a DB transaction:**<br>   - Create a `user_accounts` entry (email, hashed password).<br>   - Create a `user_profiles` entry (organization, consent flags).<br>   - Generate an email confirmation token (e.g., a UUID) and store it associated with the account.<br>4. Commit transaction.<br>5. **Async:** Queue a job to send the confirmation email with a link containing the token.<br>6. Respond `202 Accepted` (always, to prevent email enumeration). |
| **3. Feedback** | User sees feedback. | 1. Receive `202` response.<br>2. Redirect user to a page instructing them to check their email to confirm their account. | (Email service processes the queued job and sends the email) |
| **4. Confirmation** | User clicks the confirmation link in their email. | 1. The link points to `GET /auth/confirm-account?token=<token>` on the Auth Server.<br>2. **The SPA is not involved in this request.** The user's browser makes a direct request to the backend. | 1. Receive the request with the token parameter.<br>2. Validate the token: find it in the DB, check expiry, link it to the correct user account.<br>3. Update the `user_accounts` table to mark the email as verified.<br>4. **Invalidate the used confirmation token.**<br>5. **Redirect** the user's browser back to a predefined SPA URL (e.g., `https://spa.com/confirm-account?status=success`). |
| **5. Completion** | User lands back on the SPA. | 1. The SPA router loads the `/confirm-account` page.<br>2. It parses the URL query parameter (`?status=success`).<br>3. Renders a UI confirming their email is verified and prompting them to log in. | (Process is complete) |

---

### **Workflow 2: Traditional Login & Session Establishment**

This workflow transitions the user from an anonymous to an authenticated state.

| Step | User Action / System Event | SPA (Frontend) Perspective | Auth Server (Backend) Perspective |
| :--- | :--- | :--- | :--- |
| **1. Pre-Flight** | User loads the login page. | 1. Ensure an anonymous CSRF token is fetched and stored in memory (same as Registration Step 1). | 1. Generate a cryptographically secure random value.<br>2. Sign it with the private RSA key to create a single-use, anonymous CSRF token.<br>3. Return `{ csrfToken: "value" }` in the response body. |
| **2. Submission** | User enters credentials and submits. | 1. Send `POST /auth/login` with JSON body `{email, password}` and the `X-CSRF-TOKEN` header.<br>2. Show a loading state. | 1. **Validate the anonymous CSRF token** (signature, single-use).<br>2. Authenticate credentials: find user by email, verify password hash.<br>3. **Check if email is verified.** (Optional but recommended to enforce here).<br>4. **Upon success:**<br>   - Generate a new session ID (`sid`).<br>   - Generate a new Access Token (JWT with `sub`, `sid`, `exp`).<br>   - Generate a new Refresh Token (JWT with `jti`, `sub`, `sid`, `exp`).<br>   - **Persist** the Refresh Token's `jti` and `sid` in the database.<br>   - Generate a new **authenticated CSRF token** (JWT with `purpose: "auth_csrf"`, `sid`, `exp`).<br>5. **Response:**<br>   - Set `access_token` and `refresh_token` cookies (`HttpOnly`, `Secure`).<br>   - Return `200 OK` with body `{ user: {id, email, name}, csrfToken: "<auth_csrf_token>" }`. |
| **3. Session Init** | Login request succeeds. | 1. **Replace** the anonymous CSRF token in memory with the new authenticated CSRF token from the response body.<br>2. Update the global auth state (Zustand store) with `isAuthenticated: true` and the user object.<br>3. Redirect the user to the main application dashboard. | (Process is complete) |
| **4. Accessing Resources** | User uses the app. | 1. To call a protected API (e.g., `GET /api/profiles/me`):<br>   - The browser **automatically** sends the `access_token` cookie.<br>   - For state-changing requests (`POST`, `PATCH`), the SPA must add the `X-CSRF-TOKEN` header with the authenticated CSRF token. | **Resource Server:**<br>1. Validates the JWT from the `access_token` cookie (signature, `exp`, `iss`, `aud`).<br>2. For state-changing requests, validates the CSRF token header (signature, `purpose`, `sid`).<br>3. Returns `200 OK` with data or `401 Unauthorized` with `WWW-Authenticate: Refresh` if the token is expired. |

---

### **Workflow 3: Silent Token Refresh**

This workflow is automatically triggered by the SPA to maintain the user's session without interaction.

| Step | User Action / System Event | SPA (Frontend) Perspective | Auth Server (Backend) Perspective |
| :--- | :--- | :--- | :--- |
| **1. Trigger** | An API call fails. | 1. The Axios response interceptor catches a `401` error with the `WWW-Authenticate: Refresh` header.<br>2. It pauses the failed request and triggers the refresh process. | **Resource/Auth Server:**<br>1. Identifies the expired or invalid access token.<br>2. Responds with `401 Unauthorized` and the `WWW-Authenticate: Refresh` header. |
| **2. Refresh Request** | SPA attempts refresh. | 1. Send `POST /auth/refresh`.<br>2. **The browser automatically sends the `refresh_token` cookie.**<br>3. The SPA includes the current authenticated `X-CSRF-TOKEN` header in this request. | 1. **Validate the CSRF token** (signature, `purpose: "auth_csrf"`).<br>2. **Extract and validate the Refresh Token JWT** from its cookie (signature, `exp`).<br>3. **Check the DB** to ensure the token's `jti` has not been revoked.<br>4. **If valid:**<br>   - Generate a **new** Access Token and a **new** Refresh Token (rotating the token).<br>   - Update the DB: invalidate the old Refresh Token (`jti`), store the new one.<br>   - Generate a new authenticated CSRF token (linked to the same session `sid`).<br>   - **Response:** Set new `access_token` and `refresh_token` cookies. Return `204 No Content` (or a body with the new CSRF token).<br>5. **If invalid:** Respond with `401 Unauthorized`. |
| **3. Refresh Handling** | SPA processes result. | 1. **On Success (`204`):** The new cookies are set. The SPA retries the original failed request with the new, valid access token cookie.<br>2. **On Failure (`401`):** The refresh token is invalid. The SPA triggers a full logout, clearing its local state and redirecting to the login page. | (Process is complete) |

---

### **Workflow 4: Logout**

This workflow terminates the user's session across the system.

| Step | User Action / System Event | SPA (Frontend) Perspective | Auth Server (Backend) Perspective |
| :--- | :--- | :--- | :--- |
| **1. Initiation** | User clicks "Logout". | 1. Send `POST /auth/logout`.<br>2. Include the `X-CSRF-TOKEN` header. | 1. **Validate the CSRF token.**<br>2. Extract the Refresh Token JWT from the cookie to identify the session (`sid` and `jti`).<br>3. **Delete the session record** from the database using the `jti` or `sid`, instantly revoking the Refresh Token and invalidating all associated CSRF tokens.<br>4. **Response:** Clear the `access_token` and `refresh_token` cookies (by setting them to expire immediately). Respond `200 OK`. |
| **2. Cleanup** | Logout request succeeds. | 1. Receive `200` response.<br>2. **Clear the local auth state:** Set `isAuthenticated: false`, `user: null`.<br>3. **Clear the authenticated CSRF token** from memory.<br>4. Redirect the user to the login page. | (Process is complete) |

This concludes the detailed workflow documentation for the core authentication processes. The workflows for "Forgot Password" and "Reset Password" would follow a similar pattern to "Registration" and "Email Confirmation," involving pre-flight CSRF tokens, state-changing POST requests, email generation, and token invalidation.

You are absolutely right. The Google authentication workflow is a critical part of the architecture and deserves its own detailed breakdown. Thank you for pointing out the omission.

Here is the detailed workflow for Google Authentication.

---

### **Workflow 5: Google Federation (OAuth2 Login)**

This workflow delegates the authentication process to Google, leveraging the OAuth 2.0 protocol. The SPA's role is primarily to initiate and handle the redirect, while the heavy lifting of exchanging codes for tokens and creating sessions is done by the Auth Server.

| Step | User Action / System Event | SPA (Frontend) Perspective | Auth Server (Backend) Perspective |
| :--- | :--- | :--- | :--- |
| **1. Initiation** | User clicks "Sign in with Google" on the SPA's login page. | 1. **Redirect** the user's browser to the Auth Server's Google endpoint: `GET /oauth2/authorization/google`.<br><br>*This is a simple navigation, not an AJAX call. The SPA does not handle the response from this request directly.* | 1. Spring Security's OAuth2 client infrastructure intercepts this request.<br>2. It constructs the correct URL to redirect the user to **Google's authorization server**, including your app's client ID, requested scopes (`profile`, `email`), and a generated `state` parameter (for CSRF protection).<br>3. **Redirects** the user's browser to Google. |
| **2. Authentication & Consent** | User authenticates on Google's domain. | **The SPA is completely uninvolved in this step.** The user is on `accounts.google.com`. | **Google's Servers:**<br>1. Google presents a login and consent screen to the user.<br>2. If the user approves, Google generates an authorization `code`.<br>3. Google **redirects** the user's browser back to your Auth Server's pre-configured **redirect URI** (e.g., `/login/oauth2/code/google`), appending the `code` and `state` parameters. |
| **3. Token Exchange & Session Creation** | User is redirected back to your Auth Server. | **The SPA is still not involved.** The browser makes a request to the Auth Server's callback URL. | 1. The Auth Server receives the request at the redirect URI.<br>2. It validates the `state` parameter to prevent CSRF.<br>3. **Exchanges the authorization `code`** with Google for the user's **ID Token** and **Access Token**.<br>4. **Fetches user profile** from Google's `userinfo` endpoint using the access token.<br>5. **Checks the `federated_identities` table** for an existing entry with `provider='google'` and `provider_subject_id=`(Google's unique user ID).<br>   - **If Found:** Retrieve the linked `user_id`.<br>   - **If Not Found (New User):** <br>     a. Check if the user's email from Google already exists in the `user_accounts` table.<br>     b. **If email exists:** Link the Google identity to the existing account by creating a record in `federated_identities`.<br>     c. **If email does not exist:** Create a new user. **Within a DB transaction:** <br>        - Insert into `user_accounts` (email, mark as verified).<br>        - Insert into `user_profiles` (populate name from Google profile).<br>        - Insert into `federated_identities` (link the new `user_id` to Google's ID).<br>6. **Session Establishment:** <br>   - Generate a new session ID (`sid`), Access Token, Refresh Token, and authenticated CSRF token (just like in Traditional Login).<br>   - Persist the Refresh Token's `jti` and `sid` in the database.<br>7. **Final Response:** <br>   - Set the `access_token` and `refresh_token` as `HttpOnly` cookies on the response.<br>   - **Redirect** the user's browser **back to the SPA's main application page** (e.g., `https://spa.com/dashboard`). |
| **4. Session Load** | User lands back on the SPA. | 1. The user is now on the SPA at `/dashboard`.<br>2. **The SPA discovers it is authenticated because the `access_token` cookie is now present.**<br>3. To populate its UI, the SPA must call a user profile endpoint (e.g., `GET /auth/user`).<br>4. This call includes the cookie automatically and returns the user's data, allowing the SPA to update its global state (Zustand store) with `isAuthenticated: true` and the user object. | 1. The protected endpoint `GET /auth/user` validates the JWT from the cookie.<br>2. It decodes the user claims (`sub`, `email`, etc.) and returns them in the response body. |

---

### **Key Differences from Traditional Login:**

| Aspect | Traditional Login | Google Federation |
| :--- | :--- | :--- |
| **SPA Involvement** | SPA manages the entire flow with fetch requests. | SPA only initiates and finishes the flow; the middle steps are HTTP redirects handled by the browser and backend. |
| **Credentials** | SPA sends email/password in a POST request. | SPA never sees Google credentials. The Auth Server exchanges a code for tokens directly with Google. |
| **CSRF Protection** | Protected by a pre-flight anonymous CSRF token. | Protected by the OAuth2 `state` parameter. |
| **User Creation** | Explicitly triggered by a `POST /auth/register` request. | Implicitly happens during the OAuth2 callback if the user is new. |

This workflow highlights the power of the backend-for-frontend (BFF) pattern with the Auth Server. It keeps the sensitive token exchange and user creation logic secure on the backend while providing a seamless login experience for the end-user. The SPA's final state after both traditional and Google login is identical: it has the necessary HttpOnly cookies and a user object in memory.