# Spring Auth Server Implementation Guide

## Table of Contents
1. [Prerequisites and Dependencies](#prerequisites-and-dependencies)
2. [Google OAuth2 Configuration](#google-oauth2-configuration)
3. [Security Configuration](#security-configuration)
4. [User Management Implementation](#user-management-implementation)
5. [JWT Token Management](#jwt-token-management)
6. [Essential Endpoints](#essential-endpoints)
7. [Database Schema](#database-schema)
8. [Error Handling](#error-handling)

## Prerequisites and Dependencies

### Maven Dependencies
```xml
<dependencies>
    <!-- Spring Boot Starters -->
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-web</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-security</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-oauth2-client</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>

    <!-- JWT Library -->
    <dependency>
        <groupId>io.jsonwebtoken</groupId>
        <artifactId>jjwt-api</artifactId>
        <version>0.12.3</version>
    </dependency>
    <dependency>
        <groupId>io.jsonwebtoken</groupId>
        <artifactId>jjwt-impl</artifactId>
        <version>0.12.3</version>
        <scope>runtime</scope>
    </dependency>
    <dependency>
        <groupId>io.jsonwebtoken</groupId>
        <artifactId>jjwt-jackson</artifactId>
        <version>0.12.3</version>
        <scope>runtime</scope>
    </dependency>
</dependencies>
```

### Application Configuration
```yaml
# application.yml
server:
  port: 8080
  servlet:
    session:
      cookie:
        secure: true
        same-site: lax

spring:
  security:
    oauth2:
      client:
        registration:
          google:
            client-id: ${GOOGLE_CLIENT_ID}
            client-secret: ${GOOGLE_CLIENT_SECRET}
            scope:
              - openid
              - email
              - profile
            redirect-uri: "{baseUrl}/login/oauth2/code/{registrationId}"
        provider:
          google:
            issuer-uri: https://accounts.google.com

  datasource:
    url: jdbc:postgresql://localhost:5432/auth_db
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}

jwt:
  secret-key: ${JWT_SECRET_KEY}
  access-token-expiration: 900000  # 15 minutes
  refresh-token-expiration: 604800000  # 7 days

cors:
  allowed-origins: 
    - https://your-spa-domain.com
  allowed-methods:
    - GET
    - POST
    - PUT
    - DELETE
    - OPTIONS
```

## Google OAuth2 Configuration

### Google Cloud Console Setup
1. Create a new project in [Google Cloud Console](https://console.cloud.google.com/)
2. Enable the Google+ API
3. Configure OAuth consent screen:
   - Application name
   - Authorized domains
   - Scopes: email, profile, openid
4. Create OAuth 2.0 credentials:
   - **Authorized JavaScript origins**: `https://your-spa-domain.com`
   - **Authorized redirect URIs**: `https://auth-server.com/login/oauth2/code/google`

## Security Configuration

### Main Security Configuration
```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Autowired
    private OAuth2AuthenticationSuccessHandler successHandler;

    @Autowired
    private CustomOAuth2UserService customOAuth2UserService;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf
                .ignoringRequestMatchers("/auth/refresh", "/auth/logout")
                .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
            )
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.IF_REQUIRED)
            )
            .authorizeHttpRequests(auth -> auth
                // Public endpoints
                .requestMatchers("/auth/register", "/auth/login", "/auth/confirm-account/**", 
                               "/auth/forgot-password", "/auth/reset-password/**", 
                               "/auth/resend-verification", "/oauth2/**", "/login/**").permitAll()
                // Protected endpoints
                .requestMatchers("/auth/refresh").permitAll()  // Special handling in controller
                .anyRequest().authenticated()
            )
            .oauth2Login(oauth2 -> oauth2
                .loginPage("/login")
                .userInfoEndpoint(userInfo -> userInfo
                    .userService(customOAuth2UserService)
                )
                .successHandler(successHandler)
                .failureUrl("/login?error=oauth2")
            )
            .logout(logout -> logout
                .logoutUrl("/auth/logout")
                .logoutSuccessHandler(customLogoutSuccessHandler())
                .deleteCookies("access_token", "refresh_token")
            );

        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOriginPatterns(Arrays.asList("https://your-spa-domain.com"));
        configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(Arrays.asList("*"));
        configuration.setAllowCredentials(true);
        
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", configuration);
        return source;
    }
}
```

### Custom OAuth2 User Service
```java
@Service
public class CustomOAuth2UserService implements OAuth2UserService<OAuth2UserRequest, OAuth2User> {

    @Autowired
    private UserAccountService userAccountService;

    @Autowired
    private FederatedIdentityService federatedIdentityService;

    private final DefaultOAuth2UserService delegate = new DefaultOAuth2UserService();

    @Override
    public OAuth2User loadUser(OAuth2UserRequest userRequest) throws OAuth2AuthenticationException {
        OAuth2User oauth2User = delegate.loadUser(userRequest);
        
        String registrationId = userRequest.getClientRegistration().getRegistrationId();
        String providerSubjectId = oauth2User.getAttribute("sub");
        String email = oauth2User.getAttribute("email");
        String name = oauth2User.getAttribute("name");
        String picture = oauth2User.getAttribute("picture");

        // Find or create user account
        UserAccount userAccount = processOAuth2User(registrationId, providerSubjectId, email, name, picture);
        
        // Return custom OAuth2User implementation
        return new CustomOAuth2User(oauth2User, userAccount);
    }

    private UserAccount processOAuth2User(String provider, String providerSubjectId, 
                                        String email, String name, String picture) {
        // Look for existing federated identity
        Optional<FederatedIdentity> existingIdentity = federatedIdentityService
            .findByProviderAndSubjectId(provider, providerSubjectId);

        if (existingIdentity.isPresent()) {
            // Update last login
            UserAccount userAccount = existingIdentity.get().getUserAccount();
            userAccount.setLastLogin(new Date());
            return userAccountService.save(userAccount);
        } else {
            // Create new user account and federated identity
            UserAccount newUser = userAccountService.createUserAccount(email, name, true);
            federatedIdentityService.createFederatedIdentity(newUser, provider, 
                                                           providerSubjectId, email);
            
            // Notify resource server to create user profile
            notifyResourceServerForUserCreation(newUser, email, name, picture);
            
            return newUser;
        }
    }

    private void notifyResourceServerForUserCreation(UserAccount user, String email, 
                                                   String name, String picture) {
        // Option 1: Synchronous HTTP call to Resource Server
        // restTemplate.postForEntity("https://resource-server/internal/user-profiles", 
        //                           userProfileData, Void.class);
        
        // Option 2: Asynchronous event publishing (recommended)
        // eventPublisher.publishEvent(new UserCreatedEvent(user.getId(), email, name, picture));
    }
}
```

## User Management Implementation

### Entity Classes
```java
@Entity
@Table(name = "user_accounts")
public class UserAccount {
    @Id
    @GeneratedValue
    @Column(columnDefinition = "uuid")
    private UUID id;

    @Column(unique = true)
    private String username;  // Could be email

    @Column(name = "password_hash")
    private String passwordHash;  // Nullable for OAuth-only users

    @Column(nullable = false)
    private Boolean enabled = true;

    @Column(name = "account_non_locked")
    private Boolean accountNonLocked = true;

    @Column(name = "email_verified")
    private Boolean emailVerified = false;

    @Column(name = "last_login")
    @Temporal(TemporalType.TIMESTAMP)
    private Date lastLogin;

    @Column(name = "created_date")
    @Temporal(TemporalType.TIMESTAMP)
    private Date createdDate;

    @OneToMany(mappedBy = "userAccount", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    private Set<FederatedIdentity> federatedIdentities = new HashSet<>();

    // Constructors, getters, setters
}

@Entity
@Table(name = "federated_identities")
public class FederatedIdentity {
    @Id
    @GeneratedValue
    @Column(columnDefinition = "uuid")
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_account_id", nullable = false)
    private UserAccount userAccount;

    @Column(nullable = false)
    private String provider;  // e.g., "google", "github"

    @Column(name = "provider_subject_id", nullable = false)
    private String providerSubjectId;  // The 'sub' from provider's JWT

    private String email;

    @Column(name = "created_date")
    @Temporal(TemporalType.TIMESTAMP)
    private Date createdDate;

    // Constructors, getters, setters
}

@Entity
@Table(name = "refresh_tokens")
public class RefreshToken {
    @Id
    @GeneratedValue
    @Column(columnDefinition = "uuid")
    private UUID id;

    @Column(nullable = false, unique = true)
    private String token;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_account_id", nullable = false)
    private UserAccount userAccount;

    @Column(name = "expires_at", nullable = false)
    @Temporal(TemporalType.TIMESTAMP)
    private Date expiresAt;

    @Column(name = "created_date")
    @Temporal(TemporalType.TIMESTAMP)
    private Date createdDate;

    @Column(name = "last_used")
    @Temporal(TemporalType.TIMESTAMP)
    private Date lastUsed;

    private Boolean revoked = false;

    // Constructors, getters, setters
}
```

### Service Implementations
```java
@Service
@Transactional
public class UserAccountService {

    @Autowired
    private UserAccountRepository userAccountRepository;

    @Autowired
    private PasswordEncoder passwordEncoder;

    public UserAccount createUserAccount(String email, String name, boolean enabled) {
        UserAccount userAccount = new UserAccount();
        userAccount.setUsername(email);
        userAccount.setEnabled(enabled);
        userAccount.setEmailVerified(true);  // OAuth users are pre-verified
        userAccount.setCreatedDate(new Date());
        
        return userAccountRepository.save(userAccount);
    }

    public UserAccount createTraditionalUser(String email, String password, String firstName, String lastName) {
        if (userAccountRepository.findByUsername(email).isPresent()) {
            throw new UserAlreadyExistsException("User with email " + email + " already exists");
        }

        UserAccount userAccount = new UserAccount();
        userAccount.setUsername(email);
        userAccount.setPasswordHash(passwordEncoder.encode(password));
        userAccount.setEnabled(false);  // Requires email verification
        userAccount.setEmailVerified(false);
        userAccount.setCreatedDate(new Date());
        
        UserAccount savedUser = userAccountRepository.save(userAccount);
        
        // Send verification email
        emailService.sendVerificationEmail(savedUser, firstName, lastName);
        
        return savedUser;
    }

    public void confirmAccount(String token) {
        // Verify token and activate account
        EmailVerificationToken verificationToken = tokenRepository.findByToken(token)
            .orElseThrow(() -> new InvalidTokenException("Invalid verification token"));

        if (verificationToken.isExpired()) {
            throw new ExpiredTokenException("Verification token has expired");
        }

        UserAccount user = verificationToken.getUserAccount();
        user.setEnabled(true);
        user.setEmailVerified(true);
        userAccountRepository.save(user);
        
        tokenRepository.delete(verificationToken);
    }
}
```

## JWT Token Management

### JWT Service Implementation
```java
@Service
public class JwtTokenService {

    @Value("${jwt.secret-key}")
    private String secretKey;

    @Value("${jwt.access-token-expiration}")
    private long accessTokenExpiration;

    @Value("${jwt.refresh-token-expiration}")
    private long refreshTokenExpiration;

    private Key getSigningKey() {
        return Keys.hmacShaKeyFor(secretKey.getBytes());
    }

    public String generateAccessToken(UserAccount user) {
        Map<String, Object> claims = new HashMap<>();
        claims.put("roles", getUserRoles(user));
        claims.put("email", user.getUsername());
        claims.put("email_verified", user.getEmailVerified());

        return Jwts.builder()
            .header().type("JWT").and()
            .issuer("https://auth-server.com")
            .subject(user.getId().toString())
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + accessTokenExpiration))
            .claims(claims)
            .signWith(getSigningKey(), SignatureAlgorithm.HS256)
            .compact();
    }

    public String generateRefreshToken() {
        return UUID.randomUUID().toString() + "-" + System.currentTimeMillis();
    }

    public boolean validateAccessToken(String token) {
        try {
            Jwts.parser()
                .setSigningKey(getSigningKey())
                .build()
                .parseClaimsJws(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            return false;
        }
    }

    public Claims getClaimsFromToken(String token) {
        return Jwts.parser()
            .setSigningKey(getSigningKey())
            .build()
            .parseClaimsJws(token)
            .getBody();
    }

    private List<String> getUserRoles(UserAccount user) {
        // Implement role extraction logic
        return Arrays.asList("USER");
    }
}
```

### Cookie Management Service
```java
@Service
public class CookieService {

    @Value("${app.cookie.domain}")
    private String cookieDomain;

    @Value("${app.cookie.secure}")
    private boolean cookieSecure;

    public void setAuthenticationCookies(HttpServletResponse response, 
                                       String accessToken, String refreshToken) {
        // Access token cookie
        ResponseCookie accessCookie = ResponseCookie.from("access_token", accessToken)
            .httpOnly(true)
            .secure(cookieSecure)
            .path("/")
            .maxAge(Duration.ofMinutes(15))
            .sameSite("Lax")
            .domain(cookieDomain)
            .build();

        // Refresh token cookie
        ResponseCookie refreshCookie = ResponseCookie.from("refresh_token", refreshToken)
            .httpOnly(true)
            .secure(cookieSecure)
            .path("/auth/refresh")
            .maxAge(Duration.ofDays(7))
            .sameSite("Strict")
            .domain(cookieDomain)
            .build();

        response.addHeader(HttpHeaders.SET_COOKIE, accessCookie.toString());
        response.addHeader(HttpHeaders.SET_COOKIE, refreshCookie.toString());
    }

    public void clearAuthenticationCookies(HttpServletResponse response) {
        ResponseCookie accessCookie = ResponseCookie.from("access_token", "")
            .httpOnly(true)
            .secure(cookieSecure)
            .path("/")
            .maxAge(Duration.ZERO)
            .sameSite("Lax")
            .domain(cookieDomain)
            .build();

        ResponseCookie refreshCookie = ResponseCookie.from("refresh_token", "")
            .httpOnly(true)
            .secure(cookieSecure)
            .path("/auth/refresh")
            .maxAge(Duration.ZERO)
            .sameSite("Strict")
            .domain(cookieDomain)
            .build();

        response.addHeader(HttpHeaders.SET_COOKIE, accessCookie.toString());
        response.addHeader(HttpHeaders.SET_COOKIE, refreshCookie.toString());
    }

    public String extractTokenFromCookie(HttpServletRequest request, String cookieName) {
        Cookie[] cookies = request.getCookies();
        if (cookies != null) {
            return Arrays.stream(cookies)
                .filter(cookie -> cookieName.equals(cookie.getName()))
                .findFirst()
                .map(Cookie::getValue)
                .orElse(null);
        }
        return null;
    }
}
```

## Essential Endpoints

### Authentication Controller
```java
@RestController
@RequestMapping("/auth")
public class AuthController {

    @Autowired
    private UserAccountService userAccountService;
    
    @Autowired
    private JwtTokenService jwtTokenService;
    
    @Autowired
    private RefreshTokenService refreshTokenService;
    
    @Autowired
    private CookieService cookieService;

    @PostMapping("/register")
    public ResponseEntity<Map<String, String>> register(@RequestBody @Valid RegisterRequest request) {
        try {
            userAccountService.createTraditionalUser(
                request.getEmail(), 
                request.getPassword(), 
                request.getFirstName(), 
                request.getLastName()
            );
            
            Map<String, String> response = new HashMap<>();
            response.put("message", "Registration successful. Please check your email for verification.");
            return ResponseEntity.status(HttpStatus.CREATED).body(response);
        } catch (UserAlreadyExistsException e) {
            Map<String, String> error = new HashMap<>();
            error.put("error", e.getMessage());
            return ResponseEntity.status(HttpStatus.CONFLICT).body(error);
        }
    }

    @PostMapping("/login")
    public ResponseEntity<Map<String, Object>> login(@RequestBody @Valid LoginRequest request,
                                                   HttpServletResponse response) {
        // Authenticate user
        Authentication auth = authenticationManager.authenticate(
            new UsernamePasswordAuthenticationToken(request.getEmail(), request.getPassword())
        );
        
        UserAccount user = (UserAccount) auth.getPrincipal();
        
        // Generate tokens
        String accessToken = jwtTokenService.generateAccessToken(user);
        String refreshToken = jwtTokenService.generateRefreshToken();
        
        // Store refresh token
        refreshTokenService.saveRefreshToken(user, refreshToken);
        
        // Set cookies
        cookieService.setAuthenticationCookies(response, accessToken, refreshToken);
        
        // Return user info (without sensitive data)
        Map<String, Object> userInfo = new HashMap<>();
        userInfo.put("id", user.getId());
        userInfo.put("email", user.getUsername());
        userInfo.put("emailVerified", user.getEmailVerified());
        
        return ResponseEntity.ok(userInfo);
    }

    @PostMapping("/refresh")
    public ResponseEntity<Void> refreshToken(HttpServletRequest request, 
                                           HttpServletResponse response) {
        String refreshToken = cookieService.extractTokenFromCookie(request, "refresh_token");
        
        if (refreshToken == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        try {
            RefreshToken storedToken = refreshTokenService.validateAndUseRefreshToken(refreshToken);
            UserAccount user = storedToken.getUserAccount();
            
            // Generate new tokens
            String newAccessToken = jwtTokenService.generateAccessToken(user);
            String newRefreshToken = jwtTokenService.generateRefreshToken();
            
            // Store new refresh token and revoke old one
            refreshTokenService.rotateRefreshToken(storedToken, newRefreshToken);
            
            // Set new cookies
            cookieService.setAuthenticationCookies(response, newAccessToken, newRefreshToken);
            
            return ResponseEntity.noContent().build();
        } catch (InvalidTokenException | ExpiredTokenException e) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
    }

    @GetMapping("/user")
    public ResponseEntity<Map<String, Object>> getCurrentUser(HttpServletRequest request) {
        String accessToken = cookieService.extractTokenFromCookie(request, "access_token");
        
        if (accessToken == null || !jwtTokenService.validateAccessToken(accessToken)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        try {
            Claims claims = jwtTokenService.getClaimsFromToken(accessToken);
            String userId = claims.getSubject();
            UserAccount user = userAccountService.findById(UUID.fromString(userId))
                .orElseThrow(() -> new UserNotFoundException("User not found"));

            Map<String, Object> userInfo = new HashMap<>();
            userInfo.put("id", user.getId());
            userInfo.put("email", user.getUsername());
            userInfo.put("emailVerified", user.getEmailVerified());
            userInfo.put("roles", claims.get("roles"));
            
            return ResponseEntity.ok(userInfo);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
    }

    @GetMapping("/validate")
    public ResponseEntity<Void> validateToken(HttpServletRequest request) {
        String accessToken = cookieService.extractTokenFromCookie(request, "access_token");
        
        if (accessToken != null && jwtTokenService.validateAccessToken(accessToken)) {
            return ResponseEntity.ok().build();
        }
        
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
    }

    @PostMapping("/logout")
    public ResponseEntity<Map<String, String>> logout(HttpServletRequest request, 
                                                    HttpServletResponse response) {
        String refreshToken = cookieService.extractTokenFromCookie(request, "refresh_token");
        
        if (refreshToken != null) {
            // Revoke refresh token in database
            refreshTokenService.revokeRefreshToken(refreshToken);
        }
        
        // Clear cookies
        cookieService.clearAuthenticationCookies(response);
        
        Map<String, String> result = new HashMap<>();
        result.put("message", "Logged out successfully");
        return ResponseEntity.ok(result);
    }

    @GetMapping("/confirm-account")
    public ResponseEntity<String> confirmAccount(@RequestParam String token) {
        try {
            userAccountService.confirmAccount(token);
            return ResponseEntity.ok("Account confirmed successfully");
        } catch (InvalidTokenException | ExpiredTokenException e) {
            return ResponseEntity.badRequest().body("Invalid or expired token");
        }
    }

    @PostMapping("/forgot-password")
    public ResponseEntity<Map<String, String>> forgotPassword(@RequestBody @Valid ForgotPasswordRequest request) {
        // Always return success to prevent email enumeration
        userAccountService.initiatePasswordReset(request.getEmail());
        
        Map<String, String> response = new HashMap<>();
        response.put("message", "If the email exists, a password reset link has been sent.");
        return ResponseEntity.accepted().body(response);
    }

    @PostMapping("/reset-password")
    public ResponseEntity<Map<String, String>> resetPassword(@RequestBody @Valid ResetPasswordRequest request) {
        try {
            userAccountService.resetPassword(request.getToken(), request.getNewPassword());
            
            Map<String, String> response = new HashMap<>();
            response.put("message", "Password reset successfully");
            return ResponseEntity.ok(response);
        } catch (InvalidTokenException | ExpiredTokenException e) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Invalid or expired reset token");
            return ResponseEntity.badRequest().body(error);
        }
    }

    @PostMapping("/resend-verification")
    public ResponseEntity<Map<String, String>> resendVerification(@RequestBody @Valid ResendVerificationRequest request) {
        // Always return success to prevent email enumeration
        userAccountService.resendVerificationEmail(request.getEmail());
        
        Map<String, String> response = new HashMap<>();
        response.put("message", "If the email exists and is unverified, a verification link has been sent.");
        return ResponseEntity.accepted().body(response);
    }

    @GetMapping("/csrf")
    public ResponseEntity<Map<String, String>> getCsrfToken(HttpServletRequest request) {
        CsrfToken csrfToken = (CsrfToken) request.getAttribute(CsrfToken.class.getName());
        if (csrfToken != null) {
            Map<String, String> response = new HashMap<>();
            response.put("csrfToken", csrfToken.getToken());
            return ResponseEntity.ok(response);
        }
        return ResponseEntity.badRequest().build();
    }
}
```

## Database Schema

### SQL Schema Creation
```sql
-- User Accounts Table
CREATE TABLE user_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255), -- Nullable for OAuth-only users
    enabled BOOLEAN NOT NULL DEFAULT true,
    account_non_locked BOOLEAN NOT NULL DEFAULT true,
    email_verified BOOLEAN NOT NULL DEFAULT false,
    last_login TIMESTAMP,
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Federated Identities Table
CREATE TABLE federated_identities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_account_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    provider VARCHAR(50) NOT NULL,
    provider_subject_id VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(provider, provider_subject_id)
);

-- Refresh Tokens Table
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token VARCHAR(255) UNIQUE NOT NULL,
    user_account_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL,
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used TIMESTAMP,
    revoked BOOLEAN NOT NULL DEFAULT false
);

-- Email Verification Tokens Table
CREATE TABLE email_verification_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token VARCHAR(255) UNIQUE NOT NULL,
    user_account_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL,
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Password Reset Tokens Table
CREATE TABLE password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    token VARCHAR(255) UNIQUE NOT NULL,
    user_account_id UUID NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL,
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    used BOOLEAN NOT NULL DEFAULT false
);

-- Indexes for performance
CREATE INDEX idx_user_accounts_username ON user_accounts(username);
CREATE INDEX idx_user_accounts_enabled ON user_accounts(enabled);
CREATE INDEX idx_federated_identities_provider_subject ON federated_identities(provider, provider_subject_id);
CREATE INDEX idx_refresh_tokens_token ON refresh_tokens(token);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_account_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);
```

### Repository Interfaces
```java
@Repository
public interface UserAccountRepository extends JpaRepository<UserAccount, UUID> {
    Optional<UserAccount> findByUsername(String username);
    Optional<UserAccount> findByUsernameAndEnabledTrue(String username);
}

@Repository
public interface FederatedIdentityRepository extends JpaRepository<FederatedIdentity, UUID> {
    Optional<FederatedIdentity> findByProviderAndProviderSubjectId(String provider, String providerSubjectId);
    List<FederatedIdentity> findByUserAccount(UserAccount userAccount);
}

@Repository
public interface RefreshTokenRepository extends JpaRepository<RefreshToken, UUID> {
    Optional<RefreshToken> findByTokenAndRevokedFalse(String token);
    List<RefreshToken> findByUserAccountAndRevokedFalse(UserAccount userAccount);
    void deleteByUserAccount(UserAccount userAccount);
    
    @Query("DELETE FROM RefreshToken rt WHERE rt.expiresAt < :now")
    void deleteExpiredTokens(@Param("now") Date now);
}
```

## Error Handling

### Custom Exception Classes
```java
public class UserAlreadyExistsException extends RuntimeException {
    public UserAlreadyExistsException(String message) {
        super(message);
    }
}

public class UserNotFoundException extends RuntimeException {
    public UserNotFoundException(String message) {
        super(message);
    }
}

public class InvalidTokenException extends RuntimeException {
    public InvalidTokenException(String message) {
        super(message);
    }
}

public class ExpiredTokenException extends RuntimeException {
    public ExpiredTokenException(String message) {
        super(message);
    }
}
```

### Global Exception Handler
```java
@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(UserAlreadyExistsException.class)
    public ResponseEntity<Map<String, String>> handleUserAlreadyExists(UserAlreadyExistsException ex) {
        Map<String, String> error = new HashMap<>();
        error.put("error", ex.getMessage());
        error.put("code", "USER_ALREADY_EXISTS");
        return ResponseEntity.status(HttpStatus.CONFLICT).body(error);
    }

    @ExceptionHandler(UserNotFoundException.class)
    public ResponseEntity<Map<String, String>> handleUserNotFound(UserNotFoundException ex) {
        Map<String, String> error = new HashMap<>();
        error.put("error", ex.getMessage());
        error.put("code", "USER_NOT_FOUND");
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @ExceptionHandler(InvalidTokenException.class)
    public ResponseEntity<Map<String, String>> handleInvalidToken(InvalidTokenException ex) {
        Map<String, String> error = new HashMap<>();
        error.put("error", ex.getMessage());
        error.put("code", "INVALID_TOKEN");
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(error);
    }

    @ExceptionHandler(ExpiredTokenException.class)
    public ResponseEntity<Map<String, String>> handleExpiredToken(ExpiredTokenException ex) {
        Map<String, String> error = new HashMap<>();
        error.put("error", ex.getMessage());
        error.put("code", "EXPIRED_TOKEN");
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(error);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, Object>> handleValidationExceptions(MethodArgumentNotValidException ex) {
        Map<String, Object> errors = new HashMap<>();
        Map<String, String> fieldErrors = new HashMap<>();
        
        ex.getBindingResult().getFieldErrors().forEach(error -> 
            fieldErrors.put(error.getField(), error.getDefaultMessage())
        );
        
        errors.put("error", "Validation failed");
        errors.put("code", "VALIDATION_ERROR");
        errors.put("fieldErrors", fieldErrors);
        
        return ResponseEntity.badRequest().body(errors);
    }
}
```

This completes the comprehensive Spring Auth Server implementation guide covering all aspects from configuration to database schema and error handling.