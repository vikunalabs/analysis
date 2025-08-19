
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