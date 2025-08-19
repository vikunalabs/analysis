# 

## QA1

Question:

I've built a spring auth server which lets a single page application to use google authentication. Am I right to use the words "spring auth server federates to google for oauth2"?

Answer:

Yes, you're on the right track!  

The phrase:  
**"The Spring Auth Server federates to Google for OAuth2"**  
is technically correct and conveys that your Spring-based authentication server delegates (or "federates") authentication to Google using OAuth2.  

### Key Points Supporting Your Statement:  
1. **Federation** means delegating authentication to an external identity provider (Google, in this case).  
2. **OAuth2** is the protocol used for authorization (and often authentication via OpenID Connect).  
3. **Spring Auth Server** acts as a *Relying Party (RP)* or *OAuth2 Client* that integrates with Google (the *Identity Provider, IdP*).  

### Alternative Phrasing (If You Want Clarification):  
- *"The Spring Auth Server uses Google OAuth2 for federated login."*  
- *"The Spring Auth Server delegates authentication to Google via OAuth2."*  
- *"The Spring Auth Server integrates with Google as an external identity provider using OAuth2."*  

### What’s Happening Behind the Scenes?  
- Your SPA (Single Page Application) likely talks to your Spring Auth Server.  
- The Spring Auth Server redirects the user to Google for authentication (OAuth2/OpenID Connect flow).  
- After Google authenticates the user, it sends back an identity token (JWT) or authorization code to your Spring server.  
- Your Spring server then manages the session or issues its own tokens to the SPA.  

So yes, your wording is correct! 🚀 Would you like any refinements based on your exact architecture?

## QA2

Question:

Thanks for the insights! I have a question - since Spring server is managing the sessions. Can it use the JWT tokens issued by Google and store it in a httpOnly cookie (JSESSIONID)?

Answer:

Great question! Let's break this down to understand how JWTs from Google can (or shouldn't) be used alongside `JSESSIONID` cookies in your Spring Auth Server.  

### **Short Answer**  
**No**, you typically *should not* store Google's raw JWT (like `id_token` or `access_token`) in an `HttpOnly` cookie (e.g., `JSESSIONID`). Instead:  
- **Option 1**: Use Google’s JWT to authenticate the user, then create a **separate session cookie** (`JSESSIONID`) for your Spring app.  
- **Option 2**: If you want stateless auth, extract claims from Google’s JWT and issue your own JWT in a secure `HttpOnly` cookie.  

---

### **Detailed Explanation**  

#### 1. **`JSESSIONID` vs. JWT**  
- **`JSESSIONID`** is a session cookie tied to Spring’s `HttpSession` (server-side state).  
- **Google’s JWT** (e.g., `id_token`) is a signed token from Google, meant for verification, not session storage.  

#### 2. **Why Not Store Google’s JWT Directly in `JSESSIONID`?**  
- `JSESSIONID` is just a random ID—it doesn’t store data. Spring maps it to server-side session storage.  
- Google’s JWT is **too large** for most cookies (limited to ~4KB).  
- **Security Risk**: If you somehow embedded Google’s JWT into `JSESSIONID`, it would defeat the purpose of `HttpOnly` (since JWTs are meant to be parsed by the app).  

#### 3. **Better Approaches**  

##### **Option 1: Traditional Session (Spring-Managed `JSESSIONID`)**  
1. User logs in via Google OAuth2.  
2. Spring Auth Server validates Google’s JWT (`id_token`).  
3. Spring creates a **server-side session** and sets an `HttpOnly` + `Secure` `JSESSIONID` cookie.  
4. The SPA uses this cookie for subsequent requests (transparently via browser).  

✅ **Pros**: Simple, secure, no token leakage risk.  
❌ **Cons**: Stateful server (requires session storage).  

##### **Option 2: Stateless JWT (Custom `HttpOnly` Cookie)**  
1. User logs in via Google OAuth2.  
2. Spring validates Google’s JWT, then **issues its own short-lived JWT**.  
3. Stores this JWT in an `HttpOnly` + `Secure` + `SameSite=Lax` cookie.  
4. SPA sends this cookie automatically; Spring validates it statelessly.  

✅ **Pros**: Stateless, scalable, still secure (`HttpOnly` prevents XSS theft).  
❌ **Cons**: Slightly more complex (need JWT signing/key management).  

---

### **Example Flow (Option 2 - Stateless JWT Cookie)**  
```java
// After Google OAuth2 success:
@GetMapping("/login/oauth2/code/google")  
public String handleGoogleAuth(@RequestParam String code) {  
    // 1. Exchange 'code' for Google's JWT (id_token)  
    OAuth2AccessTokenResponse tokenResponse = ...;  
    String idToken = tokenResponse.getAccessToken().getTokenValue();  

    // 2. Validate Google's JWT and extract claims  
    Jwt jwt = jwtDecoder.decode(idToken);  
    String email = jwt.getClaim("email");  

    // 3. Create your own JWT  
    String myJwt = Jwts.builder()  
        .subject(email)  
        .expiration(...)  
        .signWith(yourPrivateKey)  
        .compact();  

    // 4. Set HttpOnly cookie  
    ResponseCookie cookie = ResponseCookie.from("AUTH_TOKEN", myJwt)  
        .httpOnly(true)  
        .secure(true)  
        .path("/")  
        .maxAge(Duration.ofHours(1))  
        .sameSite("Lax")  
        .build();  

    response.addHeader(HttpHeaders.SET_COOKIE, cookie.toString());  
    return "redirect:/home";  
}
```

---

### **Key Takeaways**  
- **Never store Google’s raw JWT in `JSESSIONID`**—it’s not designed for that.  
- **Either**:  
  - Use `JSESSIONID` for classic server-side sessions, or  
  - Issue your own JWT in an `HttpOnly` cookie for stateless auth.  
- **Always use `Secure`, `HttpOnly`, and `SameSite` cookie attributes** for security.  

Would you like me to elaborate on any part?

## QA3

Question:

Another question on Option 2 - Stateless JWT Cookie

a) User logs in via Google OAuth2.
b) Spring validates Google’s JWT, then issues its own short-lived JWT.
c) Stores this JWT in an HttpOnly + Secure + SameSite=Lax cookie.
d) SPA sends this cookie automatically; Spring validates it statelessly.

Now lets say SPA sends this cookie to a Resource server (different from Spring Auth Server). How should Resource validate the token? Explain the flow here

Answer:

Great follow-up! Let’s break down how the **Resource Server** (separate from your Spring Auth Server) should validate the JWT issued by your Auth Server.  

---

### **Flow: Resource Server Validating the JWT Cookie**  

#### **1. High-Level Steps**  
1. **SPA** makes a request to the **Resource Server** (e.g., `GET /api/data`).  
2. The browser **automatically includes the `HttpOnly` cookie** (containing your Auth Server’s JWT).  
3. **Resource Server**:  
   - Extracts the JWT from the cookie.  
   - Validates the JWT’s signature, expiry, and claims.  
   - Grants/denies access based on the token.  

#### **2. Key Requirements**  
- The **Resource Server** must **trust the Auth Server’s JWT**.  
- The JWT must be **signed** (e.g., RS256/HS256) so the Resource Server can verify it.  
- Both servers must agree on:  
  - **Signing Key** (if using symmetric HMAC) **OR**  
  - **Public Key** (if using asymmetric RSA).  

---

### **Detailed Flow**  

#### **Step 1: Auth Server Issues JWT**  
When the user logs in, your **Auth Server**:  
1. Generates a JWT (e.g., using `jjwt` or `Nimbus JOSE`).  
   ```java
   String jwt = Jwts.builder()
       .subject("user123")
       .issuer("https://auth-server.com")  // Identifies your Auth Server
       .expiration(new Date(System.currentTimeMillis() + 3600000)) // 1 hour
       .signWith(Keys.hmacShaKeyFor(secretKey.getBytes())) // HS256
       .compact();
   ```
2. Sets it in an `HttpOnly` cookie (as shown earlier).  

#### **Step 2: SPA Calls Resource Server**  
The browser automatically sends the cookie to the **Resource Server**:  
```http
GET /api/data HTTP/1.1
Cookie: AUTH_TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

#### **Step 3: Resource Server Validates JWT**  
The **Resource Server**:  
1. Extracts the JWT from the `Cookie` header.  
2. Verifies:  
   - **Signature** (using the Auth Server’s public key or shared secret).  
   - **Expiry** (`exp` claim).  
   - **Issuer** (`iss` claim, to ensure it’s from your Auth Server).  

**Example (Spring Resource Server):**  
```java
@Configuration
@EnableWebSecurity
public class ResourceServerConfig {
    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.decoder(jwtDecoder()))
            );
        return http.build();
    }

    @Bean
    JwtDecoder jwtDecoder() {
        // For HMAC (shared secret):
        return NimbusJwtDecoder.withSecretKey(Keys.hmacShaKeyFor(secretKey.getBytes())).build();

        // For RSA (public key):
        // return NimbusJwtDecoder.withPublicKey(rsaPublicKey).build();
    }
}
```

#### **Step 4: Access Granted/Denied**  
- If valid, the Resource Server processes the request.  
- If invalid (expired/tampered), it returns `401 Unauthorized`.  

---

### **Key Considerations**  

#### **1. How Does the Resource Server Get the Signing Key?**  
- **Option A: Symmetric HMAC (HS256)**  
  - Auth Server and Resource Server **share a secret key**.  
  - Simple but less secure (key must be distributed securely).  

- **Option B: Asymmetric RSA (RS256)**  
  - Auth Server signs with a **private key**.  
  - Resource Server validates with a **public key** (fetched from Auth Server’s JWKS endpoint).  
  - More secure (recommended for production).  

**Example (JWKS Endpoint):**  
Your Auth Server exposes:  
```http
GET /.well-known/jwks.json  
Response: { "keys": [ { "kty": "RSA", "use": "sig", "kid": "1", "n": "...", "e": "..." } ] }  
```  
The Resource Server fetches this to validate JWTs.  

#### **2. Stateless vs. Stateful Validation**  
- **Stateless**: Resource Server validates the JWT **without calling the Auth Server** (standard for JWTs).  
- **Stateful**: If you need token revocation, use a **token introspection endpoint** (OAuth2 `introspect`), but this adds latency.  

#### **3. Cookie Handling in Resource Server**  
- By default, Spring’s `JwtDecoder` expects tokens in the `Authorization: Bearer <token>` header.  
- To extract from cookies, add a **custom filter**:  
  ```java
  public class CookieJwtFilter extends OncePerRequestFilter {
      @Override
      protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) {
          String jwt = Arrays.stream(request.getCookies())
              .filter(c -> c.getName().equals("AUTH_TOKEN"))
              .findFirst()
              .map(Cookie::getValue)
              .orElse(null);

          if (jwt != null) {
              var bearerToken = new BearerTokenAuthenticationToken(jwt);
              SecurityContextHolder.getContext().setAuthentication(bearerToken);
          }
          chain.doFilter(request, response);
      }
  }
  ```
  Then add it to your security config.  

---

### **Final Flow Summary**  
1. **Auth Server** → Issues JWT in `HttpOnly` cookie.  
2. **SPA** → Sends cookie automatically to Resource Server.  
3. **Resource Server** → Extracts JWT from cookie, validates it statelessly (via HMAC/RSA).  
4. **Access Control** → Grants/denies based on JWT claims.  

---

### **Recommendation**  
For production:  
- Use **RS256** (asymmetric keys) with a **JWKS endpoint**.  
- Keep JWTs **short-lived** (e.g., 15-60 mins) and use **refresh tokens** if needed.  
- Ensure cookies are `Secure`, `HttpOnly`, and `SameSite=Lax`.  

Would you like a deeper dive into any part (e.g., JWKS setup, refresh tokens)?

## QA4

Question:

Couple of questions

1. Hope this flow doesn't expose the JWTs to the SPA? Please confirm.
2) If the resource server finds the JWT available within the cookie invalid (expired/tampered), it returns 401 Unauthorized. If the token is expired, don't we need to use refresh token? I don't know if refresh tokens would make sense in such flow, just asking.

Answer:

Great questions! Let’s address them one by one.  

---

### **1. Does This Flow Expose the JWT to the SPA?**  
**No, the JWT is not exposed to the SPA** if implemented correctly. Here’s why:  
- The JWT is stored in an **`HttpOnly` cookie**, which is:  
  - **Inaccessible to JavaScript** (cannot be read via `document.cookie`).  
  - **Automatically sent by the browser** only to the same domain (or subdomains if configured).  
- The SPA **never sees or handles the JWT directly**—it just makes requests, and the browser attaches the cookie.  

✅ **Security Benefit**:  
- Mitigates **XSS attacks** (since malicious JS can’t steal the token).  

⚠️ **Important Caveat**:  
- Ensure the cookie’s `SameSite` attribute is set (`Lax` or `Strict`) to prevent **CSRF attacks**.  
- Use `Secure` flag (HTTPS-only) to prevent interception.  

---

### **2. Handling Expired JWTs and Refresh Tokens**  
#### **If the JWT is expired (401 Unauthorized):**  
Yes, the traditional OAuth2 approach is to use a **refresh token** to get a new JWT silently. However, in this cookie-based flow:  

#### **Option A: No Refresh Token (Simpler, Less Seamless)**  
- When the JWT expires (401), the SPA **redirects the user to the Auth Server** (e.g., `/login`).  
- The Auth Server checks the user’s session (if using server-side sessions) or re-initiates Google OAuth2 silently (if possible).  
- **Pros**: Simpler, no long-lived refresh tokens to secure.  
- **Cons**: User may see a flash of redirects if the session expired.  

#### **Option B: Use Refresh Tokens (More Complex, Smoother UX)**  
1. **Auth Server issues both:**  
   - Short-lived JWT (in `HttpOnly` cookie).  
   - Long-lived refresh token (in a **separate `HttpOnly` cookie**, or stored server-side).  
2. **When JWT expires (401):**  
   - SPA **cannot handle this directly** (since it’s cookie-based). Instead:  
     - The **Resource Server** could return `401 + WWW-Authenticate: Refresh` header.  
     - The SPA **detects 401** and makes a silent call to the Auth Server’s `/refresh` endpoint (via hidden iframe or fetch).  
3. **Auth Server’s `/refresh` endpoint:**  
   - Validates the refresh token (from cookie or server-side store).  
   - Issues a **new JWT** (sets a fresh `HttpOnly` cookie).  
   - SPA retries the original request (now with a valid cookie).  

✅ **Pros**:  
- Seamless UX (no redirects).  
- Refresh tokens can be revoked (unlike long-lived JWTs).  

❌ **Cons**:  
- More complex to implement securely.  
- Refresh tokens must be **stored/transmitted carefully** (e.g., in a second `HttpOnly` cookie or server-side DB).  

---

### **Key Recommendations**  
1. **For most SPAs**: Start with **Option A (no refresh tokens)** unless you need ultra-smooth UX (e.g., finance/enterprise apps).  
   - Redirect to login on 401.  
   - Keep JWTs short-lived (e.g., 15–30 mins).  

2. **If using refresh tokens**:  
   - Store them **server-side** (e.g., in a database with user binding + expiry).  
   - If using cookies, set:  
     ```http
     Set-Cookie: refresh_token=xyz; HttpOnly; Secure; SameSite=Strict; Path=/auth/refresh
     ```  
   - Limit the `/refresh` endpoint to **POST requests only** (CSRF protection).  

3. **Stateless alternative**: Use **sliding sessions** (extend JWT expiry on each request), but this is less secure.  

---

### **Example Refresh Flow (Option B)**  
#### **Auth Server’s `/refresh` Endpoint**  
```java
@PostMapping("/refresh")  
public ResponseEntity<Void> refreshToken(HttpServletRequest request, HttpServletResponse response) {  
    // 1. Extract refresh token from cookie  
    String refreshToken = Arrays.stream(request.getCookies())  
        .filter(c -> c.getName().equals("REFRESH_TOKEN"))  
        .findFirst()  
        .map(Cookie::getValue)  
        .orElseThrow(() -> new InvalidCookieException("No refresh token"));  

    // 2. Validate refresh token (e.g., check DB)  
    if (!tokenService.isValidRefreshToken(refreshToken)) {  
        throw new InvalidCookieException("Expired/revoked refresh token");  
    }  

    // 3. Issue new JWT  
    String newJwt = jwtService.createJwt(...);  
    ResponseCookie jwtCookie = ResponseCookie.from("AUTH_TOKEN", newJwt)  
        .httpOnly(true).secure(true).sameSite("Lax").build();  

    response.addHeader(HttpHeaders.SET_COOKIE, jwtCookie.toString());  
    return ResponseEntity.ok().build();  
}  
```  

#### **SPA Handling 401**  
```javascript
// Axios interceptor example  
axios.interceptors.response.use(  
  response => response,  
  error => {  
    if (error.response.status === 401) {  
      // Attempt silent refresh  
      return axios.post('/auth/refresh', {}, { withCredentials: true })  
        .then(() => axios.request(error.config)); // Retry original request  
    }  
    return Promise.reject(error);  
  }  
);  
```  

---

### **Final Notes**  
- **Refresh tokens add complexity** but improve UX. Only use them if needed.  
- **Always prioritize security**: `HttpOnly`, `Secure`, `SameSite`, and short-lived JWTs.  
- **CSRF protection**: Use `SameSite=Lax/Strict` and/or anti-CSRF tokens for state-changing requests.  

Would you like me to refine any part further?

## QA5

Question:

Good! I am clear with the explanations for my questions. Now I would like to 

1) Create a full summary (in markdown format) of the entire oauth 2 flow involving SPA, User, Spring Auth Server, Spring Resource Server, Google exhanging JWTs in httponly cookie, as described above. Do not add any code, just keep it conceptual for later readings.

2) Create a detailed implement guide in markdown format

Ask me if you have any questions, before you generate any markdown doc.

Answer

Understood! Before generating the markdown documents, let me confirm the scope to ensure alignment with your needs:  

### **Clarifications Needed**  
1. **For the *Conceptual Summary***:  
   - Should it include **all variants** (e.g., both with/without refresh tokens)?  
   - Focus only on the **recommended flow** (e.g., stateless JWT in `HttpOnly` cookie + optional refresh)?  

2. **For the *Implementation Guide***:  
   - Should it assume:  
     - **Spring Boot 3.x** + **Spring Security 6.x**?  
     - **Google OAuth2** as the only identity provider?  
   - Include **SPA-side steps** (e.g., Axios interceptors for 401 handling)?  
   - Cover **deployment considerations** (HTTPS, cookie domains, etc.)?  

3. **Audience**:  
   - Is this for **your reference** or **team documentation** (adjust depth/formality accordingly)?  

Let me know, and I’ll tailor the markdown precisely!  

---

### **Proposed Structure**  
#### **1. Conceptual Summary**  
```markdown
# OAuth2 Flow with SPA, Spring Auth Server, and Google  

## Actors  
1. **User**: Interacts with the SPA.  
2. **SPA**: Single-page app (React/Angular/Vue).  
3. **Spring Auth Server**: Handles authentication (delegates to Google).  
4. **Spring Resource Server**: Serves APIs (validates JWTs).  
5. **Google**: Identity Provider (issues OAuth2 tokens).  

## Flow  
1. **Login**  
   - SPA redirects to Auth Server → Google OAuth2.  
   - Auth Server validates Google’s JWT, issues its own JWT in `HttpOnly` cookie.  
2. **API Access**  
   - SPA calls Resource Server (cookie sent automatically).  
   - Resource Server validates JWT (statelessly).  
3. **Expiry Handling**  
   - Option A: Redirect to login on 401.  
   - Option B: Silent refresh via `/refresh` endpoint.  
...  
```  

#### **2. Implementation Guide**  
```markdown
# Implementing OAuth2 with Spring and Google  

## Prerequisites  
- Spring Boot 3.x, Spring Security 6.x.  
- Google OAuth2 client credentials.  

## Steps  
### 1. Auth Server Setup  
- Configure Google OAuth2 client.  
- Customize `OAuth2UserService` to issue JWTs.  
- Set `HttpOnly` cookie post-login.  

### 2. Resource Server Setup  
- Validate JWTs using `JwtDecoder`.  
- Handle cookie extraction (custom filter).  

### 3. SPA Adjustments  
- Axios: Intercept 401 for silent refresh.  
- Ensure CORS/cookie policies align.  
...  
```  

Let me know if you'd like any adjustments!

## QA6

Question:
I want a more detailed documentation, one you generated is not a comprehensive one.

For the Conceptual Summary:
- Should it include all variants (e.g., both with/without refresh tokens)? YES
- Focus only on the recommended flow (e.g., stateless JWT in HttpOnly cookie + Refresh Tokens)?  Use Stateless JWT in HttpOnly cookie + Refresh Tokens

For the Implementation Guide:
- Should it assume:
  - Spring Boot 3.x + Spring Security 6.x? Yes
  - Google OAuth2 as the only identity provider? Yes
- Include SPA-side steps (e.g., Axios interceptors for 401 handling)? Yes, keep it very detailed.
- Cover deployment considerations (HTTPS, cookie domains, etc.)? Yes

Audience:
- Is this for your reference or team documentation (adjust depth/formality accordingly)? Both for me and the team.


Answer:

Here are the detailed, comprehensive markdown documents as requested:

---

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
   - Issues own JWT with user claims
   - Sets JWT in secure `HttpOnly` cookie

### 2. API Access Flow
1. SPA makes API request to Resource Server
2. Browser automatically includes auth cookie
3. Resource Server:
   - Extracts JWT from cookie
   - Validates signature using Auth Server's public key
   - Checks standard claims (exp, iss, aud)
   - Processes request if valid

### 3. Token Refresh Flow
1. On 401 response (expired token):
2. SPA detects 401 and initiates silent refresh:
   - Calls Auth Server's `/refresh` endpoint (with credentials)
3. Auth Server:
   - Validates refresh token (from separate cookie)
   - Issues new JWT + refresh token
   - Sets new secure cookies
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

# OAuth2 Implementation Guide (Spring Boot 3 + Security 6)

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Auth Server Setup](#auth-server-setup)
3. [Resource Server Setup](#resource-server-setup)
4. [SPA Integration](#spa-integration)
5. [Deployment Checklist](#deployment-checklist)

## Prerequisites

### 1. Dependencies
```gradle
implementation 'org.springframework.boot:spring-boot-starter-oauth2-client'
implementation 'org.springframework.boot:spring-boot-starter-oauth2-resource-server'
implementation 'io.jsonwebtoken:jjwt-api:0.12.3'
runtimeOnly 'io.jsonwebtoken:jjwt-impl:0.12.3'
runtimeOnly 'io.jsonwebtoken:jjwt-jackson:0.12.3'
```

### 2. Google OAuth2 Configuration
1. Create project in [Google Cloud Console](https://console.cloud.google.com/)
2. Configure OAuth consent screen
3. Create credentials:
   - Authorized JavaScript origins: `https://your-spa-domain`
   - Authorized redirect URIs: `https://auth-server/login/oauth2/code/google`

## Auth Server Setup

### 1. Security Configuration
```java
@EnableWebSecurity
@Configuration
public class AuthSecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/refresh").permitAll()
                .anyRequest().authenticated()
            )
            .oauth2Login(oauth2 -> oauth2
                .userInfoEndpoint(userInfo -> userInfo
                    .userService(customOAuth2UserService())
                )
                .successHandler(authenticationSuccessHandler())
            )
            .csrf(csrf -> csrf.ignoringRequestMatchers("/refresh"));
        return http.build();
    }
}
```

### 2. JWT Generation
```java
public String generateJwt(OAuth2User user) {
    return Jwts.builder()
        .header().type("JWT").and()
        .issuer("https://auth-server.com")
        .issuedAt(new Date())
        .expiration(new Date(System.currentTimeMillis() + 15 * 60 * 1000)) // 15 min
        .subject(user.getName())
        .claim("roles", extractRoles(user))
        .signWith(Keys.hmacShaKeyFor(secretKey.getBytes()))
        .compact();
}
```

### 3. Cookie Management
```java
private void setAuthCookies(HttpServletResponse response, String jwt, String refreshToken) {
    ResponseCookie jwtCookie = ResponseCookie.from("auth_token", jwt)
        .httpOnly(true)
        .secure(true)
        .path("/")
        .sameSite("Lax")
        .maxAge(15 * 60) // 15 min
        .build();

    ResponseCookie refreshCookie = ResponseCookie.from("refresh_token", refreshToken)
        .httpOnly(true)
        .secure(true)
        .path("/refresh")
        .sameSite("Lax")
        .maxAge(7 * 24 * 60 * 60) // 7 days
        .build();

    response.addHeader(HttpHeaders.SET_COOKIE, jwtCookie.toString());
    response.addHeader(HttpHeaders.SET_COOKIE, refreshCookie.toString());
}
```

## Resource Server Setup

### 1. JWT Validation
```java
@Bean
JwtDecoder jwtDecoder() {
    return NimbusJwtDecoder.withSecretKey(Keys.hmacShaKeyFor(secretKey.getBytes()))
        .build();
}
```

### 2. Cookie Extraction Filter
```java
public class CookieAuthFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, 
                                  HttpServletResponse response,
                                  FilterChain chain) throws IOException, ServletException {
        
        String token = Arrays.stream(request.getCookies())
            .filter(c -> c.getName().equals("auth_token"))
            .findFirst()
            .map(Cookie::getValue)
            .orElse(null);

        if (token != null) {
            var auth = new BearerTokenAuthenticationToken(token);
            SecurityContextHolder.getContext().setAuthentication(auth);
        }
        chain.doFilter(request, response);
    }
}
```

## SPA Integration

### 1. Axios Configuration
```javascript
const api = axios.create({
  baseURL: 'https://api.example.com',
  withCredentials: true
});

// Response interceptor
api.interceptors.response.use(
  response => response,
  async error => {
    const originalRequest = error.config;
    
    if (error.response.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true;
      
      try {
        await axios.post('https://auth-server/refresh', 
                        {}, 
                        { withCredentials: true });
        return api(originalRequest);
      } catch (refreshError) {
        window.location.href = '/login';
        return Promise.reject(refreshError);
      }
    }
    
    return Promise.reject(error);
  }
);
```

### 2. Login Flow
```javascript
function initiateLogin() {
  window.location.href = 'https://auth-server/oauth2/authorization/google';
}

function checkAuth() {
  return api.get('/userinfo')
    .then(response => updateUI(response.data))
    .catch(error => showLoginButton());
}
```

## Deployment Checklist

### 1. Infrastructure Requirements
- **HTTPS**: Mandatory for all domains
- **DNS**: Configured with proper CORS origins:
  - SPA: `https://app.example.com`
  - Auth: `https://auth.example.com`
  - API: `https://api.example.com`

### 2. Cookie Policies
```properties
# Auth Server application.properties
server.servlet.session.cookie.secure=true
server.servlet.session.cookie.same-site=lax
```

### 3. Monitoring
- Track failed auth attempts
- Log token refresh events
- Set up alerts for abnormal refresh patterns

### 4. Key Management
- Use Java KeyStore (JKS) for production secrets
- Implement key rotation every 90 days
- Never commit secrets to source control

---

These documents provide:
1. **Conceptual clarity** for architectural discussions
2. **Step-by-step guidance** for implementation
3. **Production-ready practices** for security and deployment

Would you like me to add any specific sections or expand on particular areas?