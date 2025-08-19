# Spring Resource Server Implementation Guide

## Table of Contents
1. [Prerequisites and Dependencies](#prerequisites-and-dependencies)
2. [Security Configuration](#security-configuration)
3. [JWT Validation Setup](#jwt-validation-setup)
4. [User Profile Management](#user-profile-management)
5. [API Endpoints](#api-endpoints)
6. [Database Schema](#database-schema)
7. [Event-Driven User Creation](#event-driven-user-creation)
8. [Error Handling and Security](#error-handling-and-security)

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
        <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
    </dependency>
    <dependency>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-data-jpa</artifactId>
    </dependency>
    
    <!-- JWT Validation -->
    <dependency>
        <groupId>com.nimbusds</groupId>
        <artifactId>nimbus-jose-jwt</artifactId>
    </dependency>
    
    <!-- Event Processing (Optional - for async user creation) -->
    <dependency>
        <groupId>org.springframework.kafka</groupId>
        <artifactId>spring-kafka</artifactId>
    </dependency>
</dependencies>
```

### Application Configuration
```yaml
# application.yml
server:
  port: 8081

spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          # Option 1: Use shared secret key (same as Auth Server)
          secret-key: ${JWT_SECRET_KEY}
          
          # Option 2: Use JWKS endpoint (recommended for production)
          # jwk-set-uri: https://auth-server.com/.well-known/jwks.json

  datasource:
    url: jdbc:postgresql://localhost:5432/resource_db
    username: ${DB_USERNAME}
    password: ${DB_PASSWORD}

  jpa:
    hibernate:
      ddl-auto: validate
    properties:
      hibernate:
        dialect: org.hibernate.dialect.PostgreSQLDialect

# JWT Configuration
jwt:
  secret-key: ${JWT_SECRET_KEY}  # Must match Auth Server
  issuer: https://auth-server.com

# CORS Configuration
cors:
  allowed-origins:
    - https://your-spa-domain.com
  allowed-methods:
    - GET
    - POST
    - PUT
    - DELETE
    - OPTIONS

# Event Configuration (if using async user creation)
kafka:
  bootstrap-servers: localhost:9092
  consumer:
    group-id: resource-server
    topics:
      user-created: user.created
```

## Security Configuration

### Main Security Configuration
```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity(prePostEnabled = true)
public class ResourceServerSecurityConfig {

    @Autowired
    private JwtAuthenticationEntryPoint jwtAuthenticationEntryPoint;

    @Autowired
    private CookieJwtAuthenticationFilter cookieJwtAuthenticationFilter;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())  // Using JWT, CSRF not needed
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS)
            )
            .authorizeHttpRequests(auth -> auth
                // Internal endpoints (for Auth Server communication)
                .requestMatchers("/internal/**").hasRole("SYSTEM")
                // Health check endpoints
                .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                // All other endpoints require authentication
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt
                    .decoder(jwtDecoder())
                    .jwtAuthenticationConverter(jwtAuthenticationConverter())
                )
                .authenticationEntryPoint(jwtAuthenticationEntryPoint)
            )
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint(jwtAuthenticationEntryPoint)
            );

        // Add custom cookie JWT filter before OAuth2ResourceServerFilter
        http.addFilterBefore(cookieJwtAuthenticationFilter, 
                           OAuth2ResourceServerFilter.class);

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

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter() {
        JwtGrantedAuthoritiesConverter authoritiesConverter = new JwtGrantedAuthoritiesConverter();
        authoritiesConverter.setAuthorityPrefix("ROLE_");
        authoritiesConverter.setAuthoritiesClaimName("roles");

        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(authoritiesConverter);
        return converter;
    }
}
```

### Custom JWT Authentication Entry Point
```java
@Component
public class JwtAuthenticationEntryPoint implements AuthenticationEntryPoint {

    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response,
                        AuthenticationException authException) throws IOException {
        
        // Set the WWW-Authenticate header to signal SPA to refresh token
        response.setHeader("WWW-Authenticate", "Refresh");
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json");
        
        Map<String, Object> errorDetails = new HashMap<>();
        errorDetails.put("error", "Unauthorized");
        errorDetails.put("message", "Access token is invalid or expired");
        errorDetails.put("timestamp", new Date());
        errorDetails.put("path", request.getRequestURI());
        
        ObjectMapper mapper = new ObjectMapper();
        response.getWriter().write(mapper.writeValueAsString(errorDetails));
    }
}
```

## JWT Validation Setup

### JWT Decoder Configuration
```java
@Configuration
public class JwtConfig {

    @Value("${jwt.secret-key}")
    private String secretKey;

    @Value("${jwt.issuer}")
    private String expectedIssuer;

    @Bean
    public JwtDecoder jwtDecoder() {
        // Option 1: Using shared secret key (HMAC)
        SecretKeySpec secretKeySpec = new SecretKeySpec(
            secretKey.getBytes(), SignatureAlgorithm.HS256.getJcaName());
        
        return NimbusJwtDecoder.withSecretKey(secretKeySpec)
            .and()
            .build();

        // Option 2: Using JWKS endpoint (RSA - recommended for production)
        // return NimbusJwtDecoder.withJwkSetUri("https://auth-server.com/.well-known/jwks.json")
        //     .build();
    }

    @Bean
    public JwtValidator jwtValidator() {
        List<OAuth2TokenValidator<Jwt>> validators = new ArrayList<>();
        validators.add(new JwtTimestampValidator());
        validators.add(new JwtIssuerValidator(expectedIssuer));
        
        return new DelegatingOAuth2TokenValidator<>(validators);
    }
}
```

### Cookie JWT Authentication Filter
```java
@Component
public class CookieJwtAuthenticationFilter extends OncePerRequestFilter {

    @Autowired
    private JwtDecoder jwtDecoder;

    @Autowired
    private JwtAuthenticationConverter jwtAuthenticationConverter;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                  FilterChain filterChain) throws ServletException, IOException {
        
        // Skip if already authenticated or is internal endpoint
        if (SecurityContextHolder.getContext().getAuthentication() != null ||
            request.getRequestURI().startsWith("/internal/")) {
            filterChain.doFilter(request, response);
            return;
        }

        String token = extractJwtFromCookie(request);
        
        if (token != null) {
            try {
                Jwt jwt = jwtDecoder.decode(token);
                Authentication authentication = jwtAuthenticationConverter.convert(jwt);
                
                if (authentication != null) {
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                }
            } catch (JwtException e) {
                // Token is invalid - will be handled by AuthenticationEntryPoint
                logger.debug("Invalid JWT token: " + e.getMessage());
            }
        }

        filterChain.doFilter(request, response);
    }

    private String extractJwtFromCookie(HttpServletRequest request) {
        Cookie[] cookies = request.getCookies();
        if (cookies != null) {
            return Arrays.stream(cookies)
                .filter(cookie -> "access_token".equals(cookie.getName()))
                .findFirst()
                .map(Cookie::getValue)
                .orElse(null);
        }
        return null;
    }
}
```

## User Profile Management

### User Profile Entity
```java
@Entity
@Table(name = "user_profiles")
public class UserProfile {
    
    @Id
    @Column(name = "user_id", columnDefinition = "uuid")
    private UUID userId;  // Same as UserAccount.id from Auth Server

    @Column(nullable = false)
    private String email;

    @Column(name = "first_name")
    private String firstName;

    @Column(name = "last_name")
    private String lastName;

    @Column(name = "profile_picture_url")
    private String profilePictureUrl;

    @Column(name = "subscription_tier")
    @Enumerated(EnumType.STRING)
    private SubscriptionTier subscriptionTier = SubscriptionTier.FREE;

    @Column(name = "payment_status")
    @Enumerated(EnumType.STRING)
    private PaymentStatus paymentStatus = PaymentStatus.CURRENT;

    @Column(name = "account_limits")
    @Type(JsonType.class)
    private AccountLimits accountLimits;

    @Column(name = "preferences")
    @Type(JsonType.class)
    private UserPreferences preferences;

    @Column(name = "created_date")
    @Temporal(TemporalType.TIMESTAMP)
    private Date createdDate;

    @Column(name = "last_updated")
    @Temporal(TemporalType.TIMESTAMP)
    private Date lastUpdated;

    @PrePersist
    protected void onCreate() {
        createdDate = new Date();
        lastUpdated = new Date();
    }

    @PreUpdate
    protected void onUpdate() {
        lastUpdated = new Date();
    }

    // Constructors, getters, setters
}

// Supporting Enums and Classes
public enum SubscriptionTier {
    FREE, PREMIUM, ENTERPRISE
}

public enum PaymentStatus {
    CURRENT, OVERDUE, CANCELLED
}

@JsonIgnoreProperties(ignoreUnknown = true)
public static class AccountLimits {
    private int maxProjects = 3;
    private int maxStorageGB = 1;
    private boolean analyticsEnabled = false;
    
    // getters, setters
}

@JsonIgnoreProperties(ignoreUnknown = true)
public static class UserPreferences {
    private String theme = "light";
    private String language = "en";
    private boolean emailNotifications = true;
    
    // getters, setters
}
```

### Payment History Entity
```java
@Entity
@Table(name = "payment_history")
public class PaymentHistory {
    
    @Id
    @GeneratedValue
    @Column(columnDefinition = "uuid")
    private UUID id;

    @Column(name = "user_id", nullable = false, columnDefinition = "uuid")
    private UUID userId;

    @Column(name = "transaction_id", unique = true)
    private String transactionId;

    @Column(nullable = false)
    private BigDecimal amount;

    @Column(nullable = false)
    private String currency;

    @Column(name = "payment_method")
    private String paymentMethod;

    @Column(nullable = false)
    @Enumerated(EnumType.STRING)
    private PaymentStatus status;

    @Column(name = "subscription_period_start")
    @Temporal(TemporalType.DATE)
    private Date subscriptionPeriodStart;

    @Column(name = "subscription_period_end")
    @Temporal(TemporalType.DATE)
    private Date subscriptionPeriodEnd;

    @Column(name = "created_date")
    @Temporal(TemporalType.TIMESTAMP)
    private Date createdDate;

    // Constructors, getters, setters
}
```

### User Profile Service
```java
@Service
@Transactional
public class UserProfileService {

    @Autowired
    private UserProfileRepository userProfileRepository;

    @Autowired
    private PaymentHistoryRepository paymentHistoryRepository;

    public UserProfile createUserProfile(UUID userId, String email, String firstName, 
                                       String lastName, String profilePictureUrl) {
        if (userProfileRepository.existsById(userId)) {
            throw new UserProfileAlreadyExistsException("User profile already exists for ID: " + userId);
        }

        UserProfile profile = new UserProfile();
        profile.setUserId(userId);
        profile.setEmail(email);
        profile.setFirstName(firstName);
        profile.setLastName(lastName);
        profile.setProfilePictureUrl(profilePictureUrl);
        profile.setSubscriptionTier(SubscriptionTier.FREE);
        profile.setPaymentStatus(PaymentStatus.CURRENT);
        
        // Set default account limits for free tier
        AccountLimits defaultLimits = new AccountLimits();
        defaultLimits.setMaxProjects(3);
        defaultLimits.setMaxStorageGB(1);
        defaultLimits.setAnalyticsEnabled(false);
        profile.setAccountLimits(defaultLimits);
        
        // Set default preferences
        UserPreferences defaultPreferences = new UserPreferences();
        profile.setPreferences(defaultPreferences);

        return userProfileRepository.save(profile);
    }

    public Optional<UserProfile> getUserProfile(UUID userId) {
        return userProfileRepository.findById(userId);
    }

    public UserProfile updateUserProfile(UUID userId, UserProfileUpdateRequest request) {
        UserProfile profile = userProfileRepository.findById(userId)
            .orElseThrow(() -> new UserProfileNotFoundException("User profile not found: " + userId));

        if (request.getFirstName() != null) {
            profile.setFirstName(request.getFirstName());
        }
        if (request.getLastName() != null) {
            profile.setLastName(request.getLastName());
        }
        if (request.getProfilePictureUrl() != null) {
            profile.setProfilePictureUrl(request.getProfilePictureUrl());
        }
        if (request.getPreferences() != null) {
            profile.setPreferences(request.getPreferences());
        }

        return userProfileRepository.save(profile);
    }

    public UserProfile upgradeSubscription(UUID userId, SubscriptionTier newTier) {
        UserProfile profile = userProfileRepository.findById(userId)
            .orElseThrow(() -> new UserProfileNotFoundException("User profile not found: " + userId));

        profile.setSubscriptionTier(newTier);
        profile.setPaymentStatus(PaymentStatus.CURRENT);
        
        // Update account limits based on subscription tier
        AccountLimits limits = updateLimitsForTier(newTier);
        profile.setAccountLimits(limits);

        return userProfileRepository.save(profile);
    }

    public List<PaymentHistory> getPaymentHistory(UUID userId) {
        return paymentHistoryRepository.findByUserIdOrderByCreatedDateDesc(userId);
    }

    private AccountLimits updateLimitsForTier(SubscriptionTier tier) {
        AccountLimits limits = new AccountLimits();
        
        switch (tier) {
            case FREE:
                limits.setMaxProjects(3);
                limits.setMaxStorageGB(1);
                limits.setAnalyticsEnabled(false);
                break;
            case PREMIUM:
                limits.setMaxProjects(25);
                limits.setMaxStorageGB(10);
                limits.setAnalyticsEnabled(true);
                break;
            case ENTERPRISE:
                limits.setMaxProjects(-1);  // Unlimited
                limits.setMaxStorageGB(100);
                limits.setAnalyticsEnabled(true);
                break;
        }
        
        return limits;
    }
}
```

## API Endpoints

### User Profile Controller
```java
@RestController
@RequestMapping("/api/profile")
@PreAuthorize("hasRole('USER')")
public class UserProfileController {

    @Autowired
    private UserProfileService userProfileService;

    @GetMapping
    public ResponseEntity<UserProfile> getCurrentUserProfile(Authentication authentication) {
        UUID userId = UUID.fromString(authentication.getName());
        
        Optional<UserProfile> profile = userProfileService.getUserProfile(userId);
        if (profile.isPresent()) {
            return ResponseEntity.ok(profile.get());
        } else {
            return ResponseEntity.notFound().build();
        }
    }

    @PutMapping
    public ResponseEntity<UserProfile> updateCurrentUserProfile(
            @RequestBody @Valid UserProfileUpdateRequest request,
            Authentication authentication) {
        UUID userId = UUID.fromString(authentication.getName());
        
        try {
            UserProfile updatedProfile = userProfileService.updateUserProfile(userId, request);
            return ResponseEntity.ok(updatedProfile);
        } catch (UserProfileNotFoundException e) {
            return ResponseEntity.notFound().build();
        }
    }

    @GetMapping("/subscription")
    public ResponseEntity<SubscriptionInfo> getSubscriptionInfo(Authentication authentication) {
        UUID userId = UUID.fromString(authentication.getName());
        
        Optional<UserProfile> profile = userProfileService.getUserProfile(userId);
        if (profile.isPresent()) {
            UserProfile p = profile.get();
            SubscriptionInfo info = new SubscriptionInfo();
            info.setTier(p.getSubscriptionTier());
            info.setStatus(p.getPaymentStatus());
            info.setLimits(p.getAccountLimits());
            return ResponseEntity.ok(info);
        } else {
            return ResponseEntity.notFound().build();
        }
    }

    @PostMapping("/subscription/upgrade")
    public ResponseEntity<UserProfile> upgradeSubscription(
            @RequestBody @Valid SubscriptionUpgradeRequest request,
            Authentication authentication) {
        UUID userId = UUID.fromString(authentication.getName());
        
        try {
            UserProfile updatedProfile = userProfileService.upgradeSubscription(userId, request.getTier());
            return ResponseEntity.ok(updatedProfile);
        } catch (UserProfileNotFoundException e) {
            return ResponseEntity.notFound().build();
        }
    }

    @GetMapping("/payment-history")
    public ResponseEntity<List<PaymentHistory>> getPaymentHistory(Authentication authentication) {
        UUID userId = UUID.fromString(authentication.getName());
        
        List<PaymentHistory> history = userProfileService.getPaymentHistory(userId);
        return ResponseEntity.ok(history);
    }
}

### Internal Controller (for Auth Server communication)
@RestController
@RequestMapping("/internal")
@PreAuthorize("hasRole('SYSTEM')")
public class InternalController {

    @Autowired
    private UserProfileService userProfileService;

    @PostMapping("/user-profiles")
    public ResponseEntity<UserProfile> createUserProfile(@RequestBody @Valid CreateUserProfileRequest request) {
        try {
            UserProfile profile = userProfileService.createUserProfile(
                request.getUserId(),
                request.getEmail(),
                request.getFirstName(),
                request.getLastName(),
                request.getProfilePictureUrl()
            );
            return ResponseEntity.status(HttpStatus.CREATED).body(profile);
        } catch (UserProfileAlreadyExistsException e) {
            return ResponseEntity.status(HttpStatus.CONFLICT).build();
        }
    }

    @DeleteMapping("/user-profiles/{userId}")
    public ResponseEntity<Void> deleteUserProfile(@PathVariable UUID userId) {
        userProfileService.deleteUserProfile(userId);
        return ResponseEntity.noContent().build();
    }
}

### Business API Controllers
@RestController
@RequestMapping("/api/projects")
@PreAuthorize("hasRole('USER')")
public class ProjectController {

    @Autowired
    private ProjectService projectService;

    @GetMapping
    public ResponseEntity<List<Project>> getUserProjects(Authentication authentication) {
        UUID userId = UUID.fromString(authentication.getName());
        List<Project> projects = projectService.getProjectsByUser(userId);
        return ResponseEntity.ok(projects);
    }

    @PostMapping
    @PreAuthorize("@projectService.canCreateProject(authentication.name)")
    public ResponseEntity<Project> createProject(@RequestBody @Valid CreateProjectRequest request,
                                               Authentication authentication) {
        UUID userId = UUID.fromString(authentication.getName());
        
        try {
            Project project = projectService.createProject(userId, request);
            return ResponseEntity.status(HttpStatus.CREATED).body(project);
        } catch (AccountLimitExceededException e) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
    }

    @GetMapping("/{projectId}")
    @PreAuthorize("@projectService.isProjectOwner(#projectId, authentication.name)")
    public ResponseEntity<Project> getProject(@PathVariable UUID projectId) {
        Optional<Project> project = projectService.getProject(projectId);
        return project.map(ResponseEntity::ok).orElse(ResponseEntity.notFound().build());
    }

    @PutMapping("/{projectId}")
    @PreAuthorize("@projectService.isProjectOwner(#projectId, authentication.name)")
    public ResponseEntity<Project> updateProject(@PathVariable UUID projectId,
                                               @RequestBody @Valid UpdateProjectRequest request) {
        try {
            Project project = projectService.updateProject(projectId, request);
            return ResponseEntity.ok(project);
        } catch (ProjectNotFoundException e) {
            return ResponseEntity.notFound().build();
        }
    }

    @DeleteMapping("/{projectId}")
    @PreAuthorize("@projectService.isProjectOwner(#projectId, authentication.name)")
    public ResponseEntity<Void> deleteProject(@PathVariable UUID projectId) {
        projectService.deleteProject(projectId);
        return ResponseEntity.noContent().build();
    }
}
```

## Database Schema

### SQL Schema Creation
```sql
-- User Profiles Table (Primary key is also foreign key to Auth Server's user_accounts.id)
CREATE TABLE user_profiles (
    user_id UUID PRIMARY KEY,  -- References auth_db.user_accounts.id
    email VARCHAR(255) NOT NULL,
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    profile_picture_url TEXT,
    subscription_tier VARCHAR(20) NOT NULL DEFAULT 'FREE',
    payment_status VARCHAR(20) NOT NULL DEFAULT 'CURRENT',
    account_limits JSONB,
    preferences JSONB,
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Payment History Table
CREATE TABLE payment_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    transaction_id VARCHAR(255) UNIQUE,
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'USD',
    payment_method VARCHAR(50),
    status VARCHAR(20) NOT NULL,
    subscription_period_start DATE,
    subscription_period_end DATE,
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Projects Table (Business Logic Example)
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    storage_used_bytes BIGINT DEFAULT 0,
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Project Files Table (Business Logic Example)
CREATE TABLE project_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    filename VARCHAR(255) NOT NULL,
    file_path TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(100),
    created_date TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX idx_user_profiles_email ON user_profiles(email);
CREATE INDEX idx_user_profiles_subscription ON user_profiles(subscription_tier);
CREATE INDEX idx_payment_history_user ON payment_history(user_id);
CREATE INDEX idx_payment_history_status ON payment_history(status);
CREATE INDEX idx_payment_history_created ON payment_history(created_date);
CREATE INDEX idx_projects_user ON projects(user_id);
CREATE INDEX idx_projects_status ON projects(status);
CREATE INDEX idx_project_files_project ON project_files(project_id);

-- Triggers for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_last_updated_column()
RETURNS TRIGGER AS $
BEGIN
    NEW.last_updated = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$ language 'plpgsql';

CREATE TRIGGER update_user_profiles_last_updated 
    BEFORE UPDATE ON user_profiles 
    FOR EACH ROW EXECUTE FUNCTION update_last_updated_column();

CREATE TRIGGER update_projects_last_updated 
    BEFORE UPDATE ON projects 
    FOR EACH ROW EXECUTE FUNCTION update_last_updated_column();
```

### Repository Interfaces
```java
@Repository
public interface UserProfileRepository extends JpaRepository<UserProfile, UUID> {
    Optional<UserProfile> findByEmail(String email);
    List<UserProfile> findBySubscriptionTier(SubscriptionTier tier);
    List<UserProfile> findByPaymentStatus(PaymentStatus status);
    
    @Query("SELECT COUNT(p) FROM UserProfile p WHERE p.subscriptionTier = :tier")
    long countBySubscriptionTier(@Param("tier") SubscriptionTier tier);
}

@Repository
public interface PaymentHistoryRepository extends JpaRepository<PaymentHistory, UUID> {
    List<PaymentHistory> findByUserIdOrderByCreatedDateDesc(UUID userId);
    List<PaymentHistory> findByUserIdAndStatus(UUID userId, PaymentStatus status);
    
    @Query("SELECT ph FROM PaymentHistory ph WHERE ph.userId = :userId AND ph.createdDate >= :fromDate")
    List<PaymentHistory> findByUserIdAndCreatedDateAfter(@Param("userId") UUID userId, 
                                                        @Param("fromDate") Date fromDate);
}

@Repository
public interface ProjectRepository extends JpaRepository<Project, UUID> {
    List<Project> findByUserIdOrderByCreatedDateDesc(UUID userId);
    List<Project> findByUserIdAndStatus(UUID userId, ProjectStatus status);
    
    @Query("SELECT COUNT(p) FROM Project p WHERE p.userId = :userId AND p.status = 'ACTIVE'")
    long countActiveProjectsByUser(@Param("userId") UUID userId);
    
    @Query("SELECT SUM(p.storageUsedBytes) FROM Project p WHERE p.userId = :userId")
    Long getTotalStorageUsedByUser(@Param("userId") UUID userId);
}
```

## Event-Driven User Creation

### Event Configuration
```java
@Configuration
@EnableKafka
public class KafkaConfig {

    @Value("${kafka.bootstrap-servers}")
    private String bootstrapServers;

    @Bean
    public ConsumerFactory<String, String> consumerFactory() {
        Map<String, Object> configProps = new HashMap<>();
        configProps.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        configProps.put(ConsumerConfig.GROUP_ID_CONFIG, "resource-server");
        configProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        configProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        configProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        
        return new DefaultKafkaConsumerFactory<>(configProps);
    }

    @Bean
    public ConcurrentKafkaListenerContainerFactory<String, String> kafkaListenerContainerFactory() {
        ConcurrentKafkaListenerContainerFactory<String, String> factory = 
            new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(consumerFactory());
        return factory;
    }
}
```

### Event Listener
```java
@Component
public class UserEventListener {

    @Autowired
    private UserProfileService userProfileService;

    @Autowired
    private ObjectMapper objectMapper;

    @KafkaListener(topics = "user.created", groupId = "resource-server")
    public void handleUserCreatedEvent(String message) {
        try {
            UserCreatedEvent event = objectMapper.readValue(message, UserCreatedEvent.class);
            
            userProfileService.createUserProfile(
                event.getUserId(),
                event.getEmail(),
                event.getFirstName(),
                event.getLastName(),
                event.getProfilePictureUrl()
            );
            
            logger.info("Successfully created user profile for user: {}", event.getUserId());
        } catch (Exception e) {
            logger.error("Failed to process user created event: {}", message, e);
            // Implement retry logic or dead letter queue handling
        }
    }

    @KafkaListener(topics = "user.deleted", groupId = "resource-server")
    public void handleUserDeletedEvent(String message) {
        try {
            UserDeletedEvent event = objectMapper.readValue(message, UserDeletedEvent.class);
            userProfileService.deleteUserProfile(event.getUserId());
            
            logger.info("Successfully deleted user profile for user: {}", event.getUserId());
        } catch (Exception e) {
            logger.error("Failed to process user deleted event: {}", message, e);
        }
    }
}

// Event DTOs
public class UserCreatedEvent {
    private UUID userId;
    private String email;
    private String firstName;
    private String lastName;
    private String profilePictureUrl;
    private Date timestamp;
    
    // Constructors, getters, setters
}

public class UserDeletedEvent {
    private UUID userId;
    private Date timestamp;
    
    // Constructors, getters, setters
}
```

## Error Handling and Security

### Custom Exception Classes
```java
public class UserProfileNotFoundException extends RuntimeException {
    public UserProfileNotFoundException(String message) {
        super(message);
    }
}

public class UserProfileAlreadyExistsException extends RuntimeException {
    public UserProfileAlreadyExistsException(String message) {
        super(message);
    }
}

public class AccountLimitExceededException extends RuntimeException {
    public AccountLimitExceededException(String message) {
        super(message);
    }
}

public class InsufficientPrivilegesException extends RuntimeException {
    public InsufficientPrivilegesException(String message) {
        super(message);
    }
}
```

### Global Exception Handler
```java
@ControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(UserProfileNotFoundException.class)
    public ResponseEntity<Map<String, String>> handleUserProfileNotFound(UserProfileNotFoundException ex) {
        Map<String, String> error = new HashMap<>();
        error.put("error", ex.getMessage());
        error.put("code", "USER_PROFILE_NOT_FOUND");
        return ResponseEntity.status(HttpStatus.NOT_FOUND).body(error);
    }

    @ExceptionHandler(AccountLimitExceededException.class)
    public ResponseEntity<Map<String, String>> handleAccountLimitExceeded(AccountLimitExceededException ex) {
        Map<String, String> error = new HashMap<>();
        error.put("error", ex.getMessage());
        error.put("code", "ACCOUNT_LIMIT_EXCEEDED");
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(error);
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<Map<String, String>> handleAccessDenied(AccessDeniedException ex) {
        Map<String, String> error = new HashMap<>();
        error.put("error", "Access denied");
        error.put("code", "ACCESS_DENIED");
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(error);
    }

    @ExceptionHandler(JwtException.class)
    public ResponseEntity<Map<String, String>> handleJwtException(JwtException ex) {
        Map<String, String> error = new HashMap<>();
        error.put("error", "Invalid or expired token");
        error.put("code", "INVALID_TOKEN");
        
        HttpServletResponse response = ((ServletRequestAttributes) RequestContextHolder.currentRequestAttributes())
            .getResponse();
        response.setHeader("WWW-Authenticate", "Refresh");
        
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(error);
    }
}
```

### Security Service for Authorization Checks
```java
@Service
public class SecurityService {

    @Autowired
    private UserProfileService userProfileService;

    @Autowired
    private ProjectRepository projectRepository;

    public boolean canCreateProject(String userId) {
        try {
            UUID userUuid = UUID.fromString(userId);
            UserProfile profile = userProfileService.getUserProfile(userUuid)
                .orElseThrow(() -> new UserProfileNotFoundException("User profile not found"));

            AccountLimits limits = profile.getAccountLimits();
            if (limits.getMaxProjects() == -1) {
                return true; // Unlimited
            }

            long currentProjectCount = projectRepository.countActiveProjectsByUser(userUuid);
            return currentProjectCount < limits.getMaxProjects();
        } catch (Exception e) {
            return false;
        }
    }

    public boolean isProjectOwner(UUID projectId, String userId) {
        try {
            UUID userUuid = UUID.fromString(userId);
            Optional<Project> project = projectRepository.findById(projectId);
            return project.isPresent() && project.get().getUserId().equals(userUuid);
        } catch (Exception e) {
            return false;
        }
    }

    public boolean hasStorageCapacity(String userId, long additionalBytes) {
        try {
            UUID userUuid = UUID.fromString(userId);
            UserProfile profile = userProfileService.getUserProfile(userUuid)
                .orElseThrow(() -> new UserProfileNotFoundException("User profile not found"));

            AccountLimits limits = profile.getAccountLimits();
            long maxStorageBytes = limits.getMaxStorageGB() * 1024L * 1024L * 1024L;
            
            Long currentUsage = projectRepository.getTotalStorageUsedByUser(userUuid);
            if (currentUsage == null) currentUsage = 0L;
            
            return (currentUsage + additionalBytes) <= maxStorageBytes;
        } catch (Exception e) {
            return false;
        }
    }
}
```

This completes the comprehensive Spring Resource Server implementation guide, covering JWT validation, user profile management, business logic APIs, database design, event-driven architecture, and security considerations.