## The Complete Forgot Password Workflow

The process involves two main parts: **1) Requesting the reset** and **2) Actually resetting the password**. It's a multi-step process that happens across your SPA, your Spring API, and the user's email client.

---

### Phase 1: Requesting a Password Reset

This phase begins when the user enters their email and submits the form.

1.  **SPA (User Action):** The user enters their email address into the form in your Vite/TS application and clicks "Submit".

2.  **SPA (API Call):** Your vanilla JavaScript/TypeScript code captures the form submission. It makes an **asynchronous `POST` request** (using  `axios`) to your Spring Auth API endpoint (e.g., `POST /api/v1/auth/forgot-password`). The body of this request contains only the user's email.
    ```json
    {
      "email": "user@example.com"
    }
    ```

3.  **Spring API (Receive Request):** The Spring Boot controller receives the request and validates the email format.

4.  **Spring API (Check Existence):** The service layer checks if a user with that email exists in the database.
    *   **If the email does NOT exist:** The API should **still return a generic "success" response** (e.g., `HTTP 200 OK` or `202 Accepted`) with a message like "If an account with that email exists, a reset link has been sent." This is a critical security practice to prevent user enumeration attacks (where an attacker can find out which emails are registered based on API responses).
    *   **If the email EXISTS:** The workflow continues.

5.  **Spring API (Generate Token):** For the existing user, the service layer:
    *   **Generates a unique, cryptographically secure token.** This is often a long, random string (e.g., using `UUID.randomUUID().toString()` or a SecureRandom byte array encoded to Base64).
    *   **Sets an expiration timestamp** for this token (e.g., 1 hour from now).
    *   **Saves this token and the expiry** in the database, associated with the user's account. It's common to have fields like `password_reset_token` and `password_reset_token_expiry` on the User entity, or a separate "token" table.

6.  **Spring API (Send Email):** The API uses its email service (e.g., JavaMailSender, SendGrid, Amazon SES) to construct and send an email to the user's address. This email contains a link back to your SPA. The link has the reset token as a query parameter.
    *   **Example Link:** `https://your-spa-domain.com/reset-password?token=abc123def456...`

7.  **Spring API (Response):** The API sends a response back to your SPA. As mentioned in step 4, this response should be generic and not reveal whether the email was found.

8.  **SPA (Handle Response):** Your SPA receives the response and displays a generic success message to the user (e.g., "Check your email for a link to reset your password."), regardless of the outcome. The user is now waiting for their email.

---

### Phase 2: Resetting the Password

This phase begins when the user clicks the link in their email.

1.  **User Action:** The user finds the email in their inbox and clicks the link. This link points to a route in **your SPA** (e.g., `/reset-password`).

2.  **SPA (Load Reset Page):** Your Vite application loads the "Reset Password" component/page. The page's code immediately parses the URL to extract the `token` query parameter.

3.  **SPA (Optional Token Validation):** As a UX improvement, your SPA can make an initial API call to your Spring backend to validate the token *before* the user even fills out the form. A request to `GET /api/v1/auth/validate-reset-token?token=abc123...` would check if the token exists and is not expired. This allows you to immediately show an error message ("This link is invalid or has expired") instead of letting the user type a new password only to then get an error.

4.  **SPA (User Action):** The user enters their new password and confirms it (by typing it twice). Your SPA code should perform basic client-side validation (e.g., password length, matching fields).

5.  **SPA (API Call):** When the user submits the new password, your SPA makes a **second API call** to a different endpoint on your Spring Auth API (e.g., `POST /api/v1/auth/reset-password`). The body of this request contains the token (to identify the user) and the new password.
    ```json
    {
      "token": "abc123def456...",
      "newPassword": "user's_new_secure_password_123"
    }
    ```

6.  **Spring API (Reset Request):** The Spring controller receives the reset request.

7.  **Spring API (Token Validation):** The service layer performs crucial validation:
    *   **Finds the user** associated with the provided token.
    *   **Checks if the token has expired** (by comparing the current time to the saved `expiry` timestamp).
    *   **If the token is invalid or expired:** It returns an error response (e.g., `HTTP 400 Bad Request` or `410 Gone`).

8.  **Spring API (Password Update):** If the token is valid:
    *   The user's password is **hashed** (using a strong algorithm like BCrypt) and updated in the database.
    *   The **reset token is invalidated** (e.g., set to `null` or deleted from the database). This makes the link usable only once.

9.  **Spring API (Response):** The API sends a success response back to the SPA.

10. **SPA (Handle Response):** Your SPA receives the success response, displays a confirmation message to the user (e.g., "Your password has been successfully reset!"), and automatically redirects them to the login page.

11. **User Flow:** The user can now return to the login page and sign in with their new password.

### Summary of Key API Endpoints in Your Spring App:
1.  `POST /api/v1/auth/forgot-password`: Accepts an email, generates a token, and sends an email.
2.  `GET /api/v1/auth/validate-reset-token?token={token}`: (Optional) Validates a token for the SPA.
3.  `POST /api/v1/auth/reset-password`: Accepts a token and new password, validates the token, and updates the password.

This workflow is secure, user-friendly, and follows standard practices for a modern web application.