# LinkForge

## Overview

---

### **Project Introduction**

**Project Name:** LinkForge (or a name of your choice, e.g., NexusLink, ShortCircuit)

**Vision:** To build a robust, secure, and user-friendly platform for comprehensive link management, offering services beyond simple shortening. LinkForge aims to be a one-stop solution for individuals, content creators, and enterprises to manage their digital footprint, enhance engagement through custom landing pages, and integrate powerful link analytics into their workflows.

**Core Features:**
*   **URL Shortening:** Create memorable, short links from long URLs.
*   **QR Code & Barcode Generation:** Generate and manage dynamic QR codes and barcodes linked to your shortened URLs.
*   **Custom Landing Pages:** Build and customize landing pages for marketing campaigns, complete with tracking.
*   **Analytics Dashboard:** View detailed click-through rates, geographic data, referral sources, and device information.
*   **Enterprise API:** A full-featured REST API for programmatic management of links and assets, enabling integration into other business systems.
*   **User Management:** Secure registration, authentication, and profile management.

---

### **System Architecture & Components**

This architecture is designed for security, scalability, and a clean separation of concerns.

```mermaid
graph TB
    subgraph "Client Layer (SPA)"
        A[Vite + Vanilla TS App] --> B[Auth Service Module]
        A --> C[API Service Module]
        A --> D[Router & UI Components]
        B -- Manages Auth Flow --> E[Auth Server]
        C -- Sends Requests With Cookie --> F[Resource Server]
    end

    subgraph "Backend Layer (Spring Boot Microservices)"
        E[Auth Server]
        F[Resource Server]
    end

    subgraph "External Services"
        G[Google Identity Platform]
        H[Email Service e.g., SES, SendGrid]
        I[Database PostgreSQL]
        J[Cache Redis]
    end

    E --> G
    E --> H
    E --> I
    F --> I
    F --> J
    
    style A fill:#cde4ff,stroke:#333,stroke-width:2px
    style E fill:#ffcc99,stroke:#333,stroke-width:2px
    style F fill:#ffcc99,stroke:#333,stroke-width:2px

```

#### **1. Client Application (SPA - Single Page Application)**
*   **Technology:** Vite + Vanilla TypeScript.
*   **Responsibility:** Provides the entire user interface. It is a static bundle of HTML, CSS, and JS served from a simple web server (like Nginx) or a CDN. It contains no application logic other than presentation and client-side routing.

**Key Client-Side Modules:**
*   **Auth Service:** A central TypeScript module responsible for all interactions with the Auth Server.
    *   Initiates the OAuth2 flow with Google (redirects to Auth Server).
    *   Handles traditional login/registration forms.
    *   Manages the silent token refresh process (using a hidden iframe or a fetch call to the Auth Server's `/refresh` endpoint).
    *   Exposes functions like `isAuthenticated()`, `getUserInfo()` (from access token claims), and `logout()`.
*   **API Service:** A module for all communication with the Resource Server.
    *   Automatically attaches credentials (`credentials: 'include'`) to all fetch requests to the Resource Server domain, ensuring the HttpOnly access token cookie is sent.
    *   Intercepts `401` responses with the `WWW-Authenticate: Refresh` header and triggers the `Auth Service` to get a new token before retrying the original request.
*   **Router:** A client-side router (e.g., based on `window.location` or a lightweight library like `navigo`) to handle navigation between "pages" (e.g., Dashboard, Login, Analytics) without full page reloads.
*   **UI Components:** Reusable TypeScript classes/functions to create dynamic UI elements (modals, tables, forms).

#### **2. Authentication Server (Spring Boot Application)**
*   **Technology:** Spring Boot, Spring Security, Spring Data JPA, OAuth2 Client/Resource Server.
*   **Responsibility:** The central hub for all identity and access management. It is the only system that issues tokens.

**Key Endpoints & Features:**
*   **OAuth2 Federation:** `/oauth2/authorization/google` - Initiates the login flow with Google.
*   **Traditional Auth Endpoints:**
    *   `POST /api/auth/register` - User registration.
    *   `POST /api/auth/login` - Traditional login (username/password).
    *   `POST /api/auth/refresh` - Issues a new access token using a valid refresh token. **Must be callable from an iframe (CORS configured).**
    *   `POST /api/auth/logout` - Logs the user out and clears the cookies.
*   **User Management Endpoints:**
    *   `GET /api/auth/confirm-account` - Email confirmation.
    *   `POST /api/auth/forgot-password` - Initiates password reset.
    *   `POST /api/auth/reset-password` - Completes password reset.
    *   `POST /api/auth/resend-verification` - Resends verification email.
*   **Token Issuance:** Upon successful authentication (via Google or traditional login), it sets two **secure, HTTP-only, same-site** cookies in the response:
    *   `access_token`: A signed JWT containing user claims (e.g., `sub`, `email`, `roles`). Short-lived (e.g., 5-15 minutes).
    *   `refresh_token`: An opaque token stored in the database. Longer-lived (e.g., 7 days).

#### **3. Resource Server (Spring Boot Application)**
*   **Technology:** Spring Boot, Spring Security (OAuth2 Resource Server), Spring Data JPA.
*   **Responsibility:** Serves all business data and functionality. It is completely unaware of login mechanisms; it only validates the JWT access token.

**Key Features & Endpoints:**
*   **Security:** Configured to validate the JWT `access_token` cookie on every incoming request. It uses the Auth Server's public key to verify the token's signature.
*   **Business Endpoints:**
    *   `GET /api/links` - Get user's shortened links.
    *   `POST /api/links` - Create a new short link.
    *   `GET /api/analytics/{linkId}` - Get analytics for a link.
    *   `POST /api/qrcodes` - Generate a QR code.
    *   `GET /api/enterprise/**` - Enterprise API endpoints.
*   **Token Refresh Handling:** If a token is expired, it returns a `401 Unauthorized` status with a clear header: `WWW-Authenticate: Refresh`. This is a signal to the SPA's `API Service` module that it needs to refresh the token.

#### **4. Data Store & External Services**
*   **Primary Database (PostgreSQL):** Stores user data (Auth Server), links, QR codes, analytics data (Resource Server).
*   **Cache (Redis):** Used by the Resource Server for caching frequently accessed short codes -> original URL mappings for ultra-fast redirection and rate-limiting.
*   **Email Service (AWS SES/SendGrid):** Integrated with the Auth Server for sending account confirmation, password reset emails, etc.
*   **Google Identity Platform:** The external IdP for federated login.

---

### **Detailed Tech Stack**

| Layer | Component | Technology | Justification |
| :--- | :--- | :--- | :--- |
| **Build Tool** | Vite | Vite | Blazing fast development server (HMR) and optimized builds for production. Perfect for Vanilla TS. |
| **Client-Side** | Language | TypeScript | Adds static typing, reducing runtime errors and improving developer experience and tooling. |
| | HTTP Client | Native `fetch()` | Modern, built-in, and supports the `credentials: 'include'` option necessary for cookies. |
| | Routing | Custom or `navigo` | A simple router is sufficient for a Vanilla TS app to handle different "views". |
| **Auth Server** | Framework | Spring Boot (Java 17+) | Industry standard, excellent Spring Security support for OAuth2 and JWT. |
| | Security | Spring Security OAuth2 | Provides a robust, secure, and customizable framework for implementing the auth server. |
| | Token Format | JWT (JSON Web Tokens) | Stateless, self-contained, and easily verifiable by the Resource Server. |
| **Resource Server** | Framework | Spring Boot (Java 17+) | Consistency with Auth Server, strong ecosystem. |
| | Security | Spring Security OAuth2 Resource Server | Simplifies JWT validation and endpoint protection. |
| | Data Access | Spring Data JPA / Hibernate | Simplifies database interactions. |
| **Database** | Primary DB | PostgreSQL | Powerful, open-source, relational database with strong performance and JSON support. |
| | Cache | Redis | In-memory data store for high-speed caching of URLs and session data. |
| **Infrastructure** | Deployment | Docker & Docker Compose (Dev) | Containerization for easy local development and environment consistency. |
| | Production | Kubernetes / AWS ECS (Prod) | Orchestration for scaling the backend services independently. |
| | Hosting (SPA) | AWS S3 + CloudFront / Netlify | Global CDN for serving the static SPA assets with low latency. |
| **Others** | Email | AWS SES / SendGrid | Reliable and scalable transactional email services. |
| | External IdP | Google Identity Platform | User-friendly, trusted, and widely adopted social login. |

---

### **Security Considerations**

1.  **Cookie Attributes:** The `access_token` and `refresh_token` cookies **must** be set with:
    *   `HttpOnly=true` (inaccessible to JavaScript, preventing XSS theft).
    *   `Secure=true` (only sent over HTTPS).
    *   `SameSite=Lax` or `Strict` (prevents CSRF attacks). `Lax` is often needed for OAuth redirects.
    *   `Path=/refresh` (especially for the refresh token cookie to limit its scope).
2.  **CORS:** The Auth and Resource servers must be configured with proper CORS headers to only allow requests from the SPA's domain.
3.  **JWT Signing:** The Auth Server must use a strong RSA key pair to sign JWTs. The Resource Server must have the public key to verify them.
4.  **Refresh Token Endpoint:** The `/refresh` endpoint must be protected against CSRF. Using the `SameSite` cookie attribute is the primary defense. Spring Security provides built-in protection here.
5.  **Silent Refresh (Iframe):** The Auth Server's `/refresh` endpoint must send the header `X-Frame-Options: SAMEORIGIN` (or be configured to allow embedding in an iframe from your SPA's domain) to work correctly.

This architecture provides a solid, secure, and scalable foundation for your LinkForge application.