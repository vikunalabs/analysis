# Social Login (Google) Flow

Your plan for social login is correct. Here is the detailed flow:

1.  User clicks "Sign in with Google".
2.  Your backend receives an OAuth callback with the user's Google profile data (Google User ID, email, name, etc.).
3.  **Check the `federated_identities` table:** Search for a record with the `provider_name = 'google'` and `provider_subject_id` = (the unique ID from Google).
    *   **If found:** Retrieve the `user_id` linked to this identity. Fetch the `user_accounts` and `user_profiles` for this `user_id` and log the user in.
4.  **If not found:** This is a new user signing up via Google.
    *   Check if the user's email from Google already exists in the `user_accounts` table. This handles the case where someone registered with a password first and then tries to use Google.
        *   **If email exists:** You can link the new Google identity to the existing account by creating a record in `federated_identities` for this user. Then log them in.
        *   **If email does not exist:** This is a brand new user.
            *   **Start a Database Transaction.**
            *   **Create `user_accounts` record:** For social logins, you might leave the `password` field NULL. You can populate the `email` and `username` (perhaps from the email prefix or a generated one).
            *   **Create `user_profiles` record:** Use the name information from Google to pre-populate the `first_name` and `last_name` fields. You may set `terms_consent` to `true` and timestamp it, as they consented at the Google consent screen.
            *   **Create `federated_identities` record:** Insert a record linking the new `user_id` to the Google `provider_subject_id`.
            *   **Commit the Transaction.**
            *   Publish a `UserRegisteredEvent` (perhaps with a `registration_method: 'google'` property) for async jobs.

### Summary

| Operation | Primary DB Actions (Transactional) | Async Event For |
| :--- | :--- | :--- |
| **Form Registration** | 1. Insert `user_accounts`<br>2. Insert `user_profiles` | Welcome Email, Analytics, etc. |
| **Google Sign-In (New User)** | 1. Insert `user_accounts`<br>2. Insert `user_profiles`<br>3. Insert `federated_identities` | Welcome Email, Analytics, etc. |
| **Google Sign-In (Existing User)** | None (only read operations) | - |

This approach ensures data integrity, a good user experience, and a scalable, maintainable architecture.