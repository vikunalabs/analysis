Of course. I can complete the file by providing the missing sections and enhancing the existing ones with best practices. The original content provided a strong foundation, particularly with the Docker Compose and Nginx setup.

Here is the completed and enhanced `deployment_security_guide.md`:

[file name]: deployment_security_guide.md
[file content begin]
# Deployment and Security Configuration Guide

## Table of Contents
1. [Production Environment Setup](#production-environment-setup)
2. [HTTPS and SSL Configuration](#https-and-ssl-configuration)
3. [Domain and CORS Configuration](#domain-and-cors-configuration)
4. [Cookie Security Settings](#cookie-security-settings)
5. [Security Headers](#security-headers)
6. [Database Security](#database-security)
7. [Monitoring and Logging](#monitoring-and-logging)
8. [Backup and Disaster Recovery](#backup-and-disaster-recovery)

## Production Environment Setup

### Infrastructure Requirements
```yaml
# docker-compose.yml
version: '3.8'
services:
  auth-server:
    image: your-registry/auth-server:latest
    container_name: auth-server
    environment:
      - SPRING_PROFILES_ACTIVE=production
      - DATABASE_URL=postgresql://auth_db_host:5432/auth_db
      - DATABASE_USERNAME=${AUTH_DB_USERNAME}
      - DATABASE_PASSWORD=${AUTH_DB_PASSWORD}
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
      - GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
      - GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
      - CORS_ALLOWED_ORIGINS=https://app.your-domain.com
    ports:
      - "8080:8080"
    networks:
      - backend
    depends_on:
      - auth-db
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  resource-server:
    image: your-registry/resource-server:latest
    container_name: resource-server
    environment:
      - SPRING_PROFILES_ACTIVE=production
      - DATABASE_URL=postgresql://resource_db_host:5432/resource_db
      - DATABASE_USERNAME=${RESOURCE_DB_USERNAME}
      - DATABASE_PASSWORD=${RESOURCE_DB_PASSWORD}
      - JWT_SECRET_KEY=${JWT_SECRET_KEY}
      - AUTH_SERVER_URL=http://auth-server:8080
      - CORS_ALLOWED_ORIGINS=https://app.your-domain.com
    ports:
      - "8081:8081"
    networks:
      - backend
    depends_on:
      - resource-db
      - auth-server
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8081/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  auth-db:
    image: postgres:15-alpine
    container_name: auth-db
    environment:
      - POSTGRES_DB=auth_db
      - POSTGRES_USER=${AUTH_DB_USERNAME}
      - POSTGRES_PASSWORD=${AUTH_DB_PASSWORD}
    volumes:
      - auth_db_data:/var/lib/postgresql/data
      - ./init-scripts/auth-db.sql:/docker-entrypoint-initdb.d/01-init.sql
    networks:
      - backend
    restart: unless-stopped

  resource-db:
    image: postgres:15-alpine
    container_name: resource-db
    environment:
      - POSTGRES_DB=resource_db
      - POSTGRES_USER=${RESOURCE_DB_USERNAME}
      - POSTGRES_PASSWORD=${RESOURCE_DB_PASSWORD}
    volumes:
      - resource_db_data:/var/lib/postgresql/data
      - ./init-scripts/resource-db.sql:/docker-entrypoint-initdb.d/01-init.sql
    networks:
      - backend
    restart: unless-stopped

  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/ssl:/etc/nginx/ssl
      - ./spa/dist:/usr/share/nginx/html
    networks:
      - frontend
      - backend
    depends_on:
      - auth-server
      - resource-server
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    container_name: redis-cache
    command: redis-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    networks:
      - backend
    restart: unless-stopped

volumes:
  auth_db_data:
  resource_db_data:
  redis_data:

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true
```

### Environment Variables
```bash
# .env (production)
# Database Credentials
AUTH_DB_USERNAME=auth_user
AUTH_DB_PASSWORD=<secure-random-password>
RESOURCE_DB_USERNAME=resource_user
RESOURCE_DB_PASSWORD=<secure-random-password>

# JWT Configuration
JWT_SECRET_KEY=<256-bit-base64-encoded-key>

# Google OAuth2
GOOGLE_CLIENT_ID=<your-google-client-id>
GOOGLE_CLIENT_SECRET=<your-google-client-secret>

# Redis
REDIS_PASSWORD=<secure-redis-password>

# Email Service (SendGrid/AWS SES)
EMAIL_SERVICE_API_KEY=<email-service-api-key>
EMAIL_FROM_ADDRESS=noreply@your-domain.com

# External Services
SENTRY_DSN=<your-sentry-dsn>
```

## HTTPS and SSL Configuration

### Nginx SSL Configuration
```nginx
# nginx/nginx.conf
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # SSL Configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://auth.your-domain.com https://api.your-domain.com; frame-ancestors 'none';" always;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Rate Limiting
    limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/m;
    limit_req_zone $binary_remote_addr zone=api:10m rate=100r/m;

    # SPA (Frontend)
    server {
        listen 80;
        server_name app.your-domain.com;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name app.your-domain.com;

        ssl_certificate /etc/nginx/ssl/app.your-domain.com.crt;
        ssl_certificate_key /etc/nginx/ssl/app.your-domain.com.key;

        root /usr/share/nginx/html;
        index index.html;

        # SPA Routing
        location / {
            try_files $uri $uri/ /index.html;
            
            # Cache static assets
            location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2)$ {
                expires 1y;
                add_header Cache-Control "public, immutable";
            }
        }

        # Security.txt
        location /.well-known/security.txt {
            return 200 "Contact: security@your-domain.com\n";
            add_header Content-Type text/plain;
        }
    }

    # Auth Server
    server {
        listen 80;
        server_name auth.your-domain.com;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name auth.your-domain.com;

        ssl_certificate /etc/nginx/ssl/auth.your-domain.com.crt;
        ssl_certificate_key /etc/nginx/ssl/auth.your-domain.com.key;

        # Rate limiting for auth endpoints
        location /auth/login {
            limit_req zone=auth burst=3 nodelay;
            proxy_pass http://auth-server:8080;
            include proxy_params;
        }

        location /auth/register {
            limit_req zone=auth burst=3 nodelay;
            proxy_pass http://auth-server:8080;
            include proxy_params;
        }

        location /oauth2/ {
            proxy_pass http://auth-server:8080;
            include proxy_params;
        }

        location /login/oauth2/ {
            proxy_pass http://auth-server:8080;
            include proxy_params;
        }

        location / {
            proxy_pass http://auth-server:8080;
            include proxy_params;
        }
    }

    # API Server
    server {
        listen 80;
        server_name api.your-domain.com;
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name api.your-domain.com;

        ssl_certificate /etc/nginx/ssl/api.your-domain.com.crt;
        ssl_certificate_key /etc/nginx/ssl/api.your-domain.com.key;

        location / {
            limit_req zone=api burst=50 nodelay;
            proxy_pass http://resource-server:8081;
            include proxy_params;
        }

        # Health check (no rate limiting)
        location /actuator/health {
            proxy_pass http://resource-server:8081;
            include proxy_params;
        }
    }
}

# nginx/proxy_params
proxy_set_header Host $http_host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $server_name;
proxy_set_header X-Forwarded-Port $server_port;
proxy_redirect off;
proxy_buffering off;
proxy_request_buffering off;
```

### SSL Certificate Management (Let's Encrypt)
```bash
#!/bin/bash
# scripts/setup-ssl.sh

# Install Certbot
curl -s https://api.github.com/repos/certbot/certbot/releases/latest | \
    grep browser_download_url | \
    grep linux_x86_64 | \
    cut -d '"' -f 4 | \
    wget -qi -

chmod +x certbot-auto

# Get certificates
./certbot-auto certonly --standalone --agree-tos --no-eff-email \
    --email admin@your-domain.com \
    -d app.your-domain.com \
    -d auth.your-domain.com \
    -d api.your-domain.com

# Set up automatic renewal
echo "0 12 * * * /opt/certbot/certbot-auto renew --quiet --post-hook \"systemctl reload nginx\"" | crontab -
```

## Domain and CORS Configuration

### Application Configuration
Configure your applications (e.g., in `application-production.properties` for Spring Boot) to be aware of the production domains.

```properties
# Auth Server application-production.properties
server.servlet.session.cookie.domain=.your-domain.com
server.servlet.session.cookie.secure=true

# Allowed redirect URIs for OAuth2
app.oauth2.authorized-redirect-uris[0]=https://app.your-domain.com/oauth2/redirect
app.oauth2.authorized-redirect-uris[1]=https://app.your-domain.com/login/oauth2/code/google

# CORS configuration
cors.allowed-origins=https://app.your-domain.com
cors.allowed-methods=GET,POST,PUT,DELETE,OPTIONS
cors.allowed-headers=*
cors.allow-credentials=true
```

### Spring Security CORS Configuration
```java
// Example CORS Configuration in a Spring Security Config class
@Bean
CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration configuration = new CorsConfiguration();
    configuration.setAllowedOrigins(Arrays.asList("https://app.your-domain.com"));
    configuration.setAllowedMethods(Arrays.asList("GET", "POST", "PUT", "DELETE", "OPTIONS"));
    configuration.setAllowedHeaders(Arrays.asList("*"));
    configuration.setAllowCredentials(true);
    configuration.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", configuration);
    return source;
}
```

## Cookie Security Settings

### Secure Cookie Configuration
Ensure all cookies, especially session and authentication cookies, are configured with the `Secure`, `HttpOnly`, `SameSite`, and appropriate `Path` attributes.

**Spring Security Configuration:**
```java
// In your Security Filter Chain configuration
http
    // ... other configurations
    .sessionManagement(session -> session
        .sessionCreationPolicy(SessionCreationPolicy.IF_REQUIRED)
    )
    .oauth2Login(oauth2 -> oauth2
        .redirectionEndpoint(redirection -> redirection
            .baseUri("/oauth2/redirect")
        )
    )
    .rememberMe(rememberMe -> rememberMe
        .key("your-remember-me-key")
        .tokenValiditySeconds(86400) // 24 hours
        .alwaysRemember(false)
    );
```

**Servlet Cookie Configuration (for JSESSIONID):**
```properties
# application-production.properties
server.servlet.session.cookie.name=__Secure-Auth-Session
server.servlet.session.cookie.http-only=true
server.servlet.session.cookie.secure=true
server.servlet.session.cookie.same-site=lax
server.servlet.session.cookie.path=/
server.servlet.session.timeout=3600 # 1 hour
```

**JWT Token in Cookie (if used):**
When setting a JWT in a cookie from your server, use the following attributes:
- `HttpOnly`: true (inaccessible to JavaScript, prevents XSS theft)
- `Secure`: true (only sent over HTTPS)
- `SameSite`: `Lax` or `Strict` (prevents CSRF)
- `Path`: `/` (or a restricted path)
- `Domain`: `.your-domain.com` (if sharing across subdomains)

## Security Headers

### Nginx-Level Headers
As shown in the Nginx configuration, the following headers are applied globally:
- `X-Frame-Options: SAMEORIGIN`
- `X-Content-Type-Options: nosniff`
- `X-XSS-Protection: 1; mode=block`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Content-Security-Policy`
- `Strict-Transport-Security`

### Application-Level Headers (Spring Boot)
For defense in depth, also configure headers at the application level using Spring Security.

```java
// In your Security Filter Chain configuration
http
    // ... other configurations
    .headers(headers -> headers
        .contentSecurityPolicy(csp -> csp
            .policyDirectives("default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://auth.your-domain.com https://api.your-domain.com; frame-ancestors 'none';")
        )
        .frameOptions(frame -> frame
            .sameOrigin()
        )
        .httpStrictTransportSecurity(hsts -> hsts
            .includeSubDomains(true)
            .maxAgeInSeconds(31536000)
            .preload(false) // Only set to true if you are sure you can commit to HSTS preload
        )
        .xssProtection(xss -> xss
            .headerValue("1; mode=block")
        )
        .contentTypeOptions(ContentTypeOptionsConfig::disable) // Let Nginx handle this if it already is
    );
```
*Note: It's often best practice to let the reverse proxy (Nginx) handle these headers to avoid duplication and potential conflicts.*

## Database Security

### PostgreSQL Configuration Hardening
Modify your `init-scripts/*.sql` files to implement security best practices upon database initialization.

**Example `init-scripts/auth-db.sql`:**
```sql
-- Revoke default public privileges
REVOKE ALL ON DATABASE auth_db FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- Create application-specific user and grant minimal privileges
GRANT CONNECT ON DATABASE auth_db TO auth_user;
GRANT USAGE ON SCHEMA public TO auth_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO auth_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO auth_user;

-- Set up Row Level Security (RLS) on sensitive tables (e.g., users)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Create a policy for RLS (example - adjust based on your auth logic)
CREATE POLICY user_select_policy ON users FOR SELECT USING (true); -- Placeholder policy
CREATE POLICY user_modify_policy ON users FOR ALL TO auth_user USING (true); -- Placeholder policy

-- Ensure the search_path is set correctly for the user
ALTER ROLE auth_user SET search_path TO public;
```

### Connection Security
- **Use SSL for Database Connections:** Ensure connections between your application servers and databases are encrypted. In your Spring Boot `application-production.properties`:
    ```properties
    spring.datasource.url=jdbc:postgresql://auth_db_host:5432/auth_db?ssl=true&sslmode=verify-full&sslrootcert=/etc/ssl/certs/ca-certificates.crt
    ```
- **Database Firewall:** Use the internal Docker network (`backend`) as configured to isolate the database. In a cloud environment, use VPCs and security groups to restrict access solely to the application servers.

## Monitoring and Logging

### Application Logging (Spring Boot)
Configure structured logging (e.g., JSON format) for easy ingestion by monitoring tools.

**`application-production.properties`:**
```properties
# Logging
logging.level.com.yourcompany=INFO
logging.level.org.springframework.security=DEBUG # Be cautious in production
logging.level.org.springframework.web=INFO
logging.pattern.console=%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n
# For JSON logging with Logstash (optional)
# logging.pattern.console={"@timestamp": "%d{yyyy-MM-dd HH:mm:ss.SSS}", "level": "%-5level", "logger": "%logger{36}", "thread": "%thread", "message": "%msg", "traceId": "%mdc{traceId}", "spanId": "%mdc{spanId}"}%n

# Actuator Endpoints for monitoring
management.endpoints.web.exposure.include=health,info,metrics,loggers
management.endpoint.health.show-details=when_authorized
management.endpoint.health.roles=ACTUATOR
# Secure the actuator endpoints with a separate role/user
spring.security.user.roles=ACTUATOR
```

### Centralized Logging with the ELK Stack (Optional)
Extend your `docker-compose.yml` to include Filebeat or another log shipper to send logs to a centralized Elasticsearch, Logstash, and Kibana (ELK) stack for analysis.

### Performance Monitoring
Integrate with tools like **Prometheus** and **Grafana** for metrics collection and visualization. Use the Spring Boot Actuator's `micrometer` integration.

```properties
# application-production.properties
management.endpoints.web.exposure.include=health,info,metrics,prometheus
management.metrics.export.prometheus.enabled=true
```

## Backup and Disaster Recovery

### Database Backup Strategy
Implement automated, encrypted backups for your PostgreSQL databases.

**Example Backup Script (`scripts/backup-db.sh`):**
```bash
#!/bin/bash
# Variables
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/opt/backups"
RETENTION_DAYS=30

# Auth DB Backup
docker exec auth-db pg_dump -U $AUTH_DB_USERNAME auth_db | gzip > "$BACKUP_DIR/auth_db_backup_$DATE.sql.gz"
openssl enc -aes-256-cbc -salt -in "$BACKUP_DIR/auth_db_backup_$DATE.sql.gz" -out "$BACKUP_DIR/auth_db_backup_$DATE.sql.gz.enc" -pass pass:$BACKUP_ENCRYPTION_KEY
rm "$BACKUP_DIR/auth_db_backup_$DATE.sql.gz"

# Resource DB Backup
docker exec resource-db pg_dump -U $RESOURCE_DB_USERNAME resource_db | gzip > "$BACKUP_DIR/resource_db_backup_$DATE.sql.gz"
openssl enc -aes-256-cbc -salt -in "$BACKUP_DIR/resource_db_backup_$DATE.sql.gz" -out "$BACKUP_DIR/resource_db_backup_$DATE.sql.gz.enc" -pass pass:$BACKUP_ENCRYPTION_KEY
rm "$BACKUP_DIR/resource_db_backup_$DATE.sql.gz"

# Clean up old backups
find $BACKUP_DIR -name "*.enc" -type f -mtime +$RETENTION_DAYS -delete

echo "Backup completed successfully at $DATE"
```

**Scheduling Backups with Cron:**
```bash
# Add to crontab -e
0 2 * * * /opt/scripts/backup-db.sh >> /var/log/db-backup.log 2>&1
```

### Disaster Recovery Plan
1.  **Recovery Point Objective (RPO):** Aim for a maximum data loss of 1 hour (aligns with hourly backups).
2.  **Recovery Time Objective (RTO):** Aim to restore service within 4 hours.
3.  **Recovery Procedure:**
    *   Spin up infrastructure in a recovery environment.
    *   Restore the most recent encrypted database backups.
    *   `openssl enc -d -aes-256-cbc -in backup_file.sql.gz.enc -out backup_file.sql.gz -pass pass:$BACKUP_ENCRYPTION_KEY`
    *   `gunzip backup_file.sql.gz`
    *   `docker exec -i new-auth-db psql -U $AUTH_DB_USERNAME auth_db < backup_file.sql`
    *   Update DNS records to point to the recovery environment.
    *   Perform validation tests before switching traffic.
4.  **Documentation:** Ensure this entire recovery process is documented in a runbook and tested regularly.

### Infrastructure as Code (IaC)
For a more robust production setup, consider managing your servers and networking with IaC tools like **Terraform** or **Ansible** instead of solely relying on Docker Compose, which is better suited for development and simple deployments.
[file content end]