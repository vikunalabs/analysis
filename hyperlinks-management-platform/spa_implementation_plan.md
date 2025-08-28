# Frontend SPA Implementation Plan

## Table of Contents
1. [Project Overview](#project-overview)
2. [Backend Architecture](#backend-architecture)
3. [Frontend Architecture](#frontend-architecture)
4. [Technology Stack](#technology-stack)
5. [Planned Features](#planned-features)
6. [Detailed Implementation Plan](#detailed-implementation-plan)
7. [Project Structure](#project-structure)
8. [Implementation Timeline](#implementation-timeline)

---

## Project Overview

This document outlines the comprehensive implementation plan for a Single Page Application (SPA) that interacts with a dual backend system consisting of a Spring Auth Server and Spring Resource Server. The frontend will be built using Vite + Vanilla TypeScript with carefully selected open-source libraries for optimal performance and maintainability.

### Key Objectives
- Build a production-ready SPA with no framework dependencies
- Implement secure authentication with token-based system
- Create modular, maintainable, and scalable architecture
- Provide seamless user experience across all features
- Ensure proper security practices and error handling

---

## Backend Architecture

The backend consists of two Spring Boot applications working in tandem:

### 1. Authentication Server (Spring Boot Application)

**Technology Stack:**
- Spring Boot, Spring Security, Spring Data JPA, OAuth2 Client/Resource Server

**Primary Responsibility:**
Central hub for all identity and access management. The only system authorized to issue tokens.

**Key Endpoints & Features:**

#### OAuth2 Federation
- `GET /oauth2/authorization/google` - Initiates Google login flow

#### Traditional Authentication
- `POST /api/v1/auth/register` - User registration
- `POST /api/v1/auth/login` - Traditional login (username/password)
- `POST /api/v1/auth/logout` - User logout with cookie cleanup

#### User Management
- `GET /api/v1/auth/confirm-account` - Email confirmation
- `POST /api/v1/auth/forgot-password` - Initiates password reset
- `POST /api/v1/auth/reset-password` - Completes password reset
- `POST /api/v1/auth/resend-verification` - Resends verification email

#### Security & Token Management
- `GET /api/v1/auth/csrf` - Fetches CSRF token for state-changing requests
- `POST /api/v1/auth/refresh` - Issues new access token (CORS configured for iframe calls)
- `GET /api/v1/auth/validate` - Lightweight token validation (optional)
- `GET /api/v1/auth/user` - Get current user profile & claims

#### Token Issuance Strategy
Upon successful authentication, the server sets two **secure, HTTP-only, same-site** cookies:
- `access_token`: Signed JWT with user claims (sub, email, roles) - Short-lived (5-15 minutes)
- `refresh_token`: Opaque database-stored token - Longer-lived (7 days)

#### Token Refresh Handling
- Returns `401 Unauthorized` with `WWW-Authenticate: Refresh` header when tokens expire
- Signals SPA to initiate token refresh process

### 2. Resource Server (Spring Boot Application)

**Technology Stack:**
- Spring Boot, Spring Security (OAuth2 Resource Server), Spring Data JPA

**Primary Responsibility:**
Serves all business data and functionality. Completely unaware of login mechanisms; only validates JWT access tokens.

**Key Features & Endpoints:**

#### Business Logic Endpoints
- `GET /api/links` - Get user's shortened links
- `POST /api/links` - Create new short link
- `GET /api/analytics/{linkId}` - Get link analytics
- `POST /api/qrcodes` - Generate QR codes
- `GET /api/enterprise/**` - Enterprise API endpoints

#### Security Configuration
- Validates JWT `access_token` cookie on every request
- Uses Auth Server's public key for token signature verification
- Returns `401 Unauthorized` with `WWW-Authenticate: Refresh` header for expired tokens

### 3. Supporting Infrastructure

#### Data Storage
- **PostgreSQL**: Primary database for user data (Auth Server) and business data (Resource Server)
- **Redis**: Caching layer for short codes → URL mappings and rate limiting (Future Implementation)

#### External Services
- **Email Service**: AWS SES/SendGrid for account confirmation and password reset emails (Future Implementation)
- **Google Identity Platform**: External IdP for federated login

**Current Status**: Both Spring servers are implemented and ready for frontend integration.

---

## Frontend Architecture

### Core Architectural Principles
- **Modular Design**: Clear separation of concerns across services, stores, and components
- **Security-First**: Proper handling of HTTP-only cookies and CSRF tokens
- **Production-Ready**: Robust error handling, loading states, and user experience
- **No Boilerplate**: Clean, maintainable code without unnecessary complexity

### Key Client-Side Modules

#### 1. Auth Service
Central TypeScript service using Axios for all Auth Server interactions:
- Manages OAuth2 flow with Google (redirects to Auth Server)
- Handles traditional login/registration forms
- Manages silent token refresh via hidden iframe or Axios calls
- Coordinates with CSRF service for secure state-changing operations

#### 2. API Service
Dedicated Axios instance for Resource Server communication:
- Pre-configured with `withCredentials: true` for automatic cookie transmission
- Implements Axios Response Interceptors for elegant `401` handling
- Automatically triggers token refresh and retries failed requests
- Centralized error handling for business logic endpoints

#### 3. State Management (Zustand)
Centralized stores for application state:
- **Auth Store**: Authentication state, user profile, loading states
- **App Store**: Global UI state (modals, notifications, theme)
- **Data Stores**: Feature-specific caching (links, analytics, etc.)

#### 4. Router (Navigo)
Lightweight client-side routing:
- Maps routes to rendering functions without full page reloads
- Handles navigation between application views (Dashboard, Login, Analytics)
- Supports protected routes and authentication guards

#### 5. UI Components (Custom Library)
Reusable TypeScript/Web Component classes:
- Consistent interface building blocks (buttons, modals, tables, forms, charts)
- Pre-built and battle-tested components
- Seamless Tailwind CSS integration for styling

---

## Technology Stack

### Core Technologies
- **Build Tool**: Vite (Fast development and optimized production builds)
- **Language**: Vanilla TypeScript (Type safety without framework overhead)
- **Styling**: Tailwind CSS (Utility-first CSS framework)

### Selected Libraries
- **HTTP Client**: Axios (Robust HTTP client with interceptors)
- **State Management**: zustand-vanilla (Lightweight, framework-agnostic state management)
- **Routing**: Navigo (Small, powerful client-side router)
- **UI Foundation**: Custom UI Library (Pre-built, production-ready components)

### Rationale for Library Selection
- **No Framework Dependencies**: Reduces bundle size and complexity
- **Production Proven**: All libraries are mature and widely adopted
- **TypeScript Native**: Full type safety across the application
- **Minimal Learning Curve**: Simple APIs that don't require extensive training

---

## Planned Features

The application will be developed in feature-based phases:

### Phase A: User Authentication & Account Management
- User registration with email verification
- Traditional login/logout functionality
- Google OAuth2 integration
- Account confirmation flow
- Password reset and forgot password functionality
- Resend verification email
- Basic dashboard with user information display

### Phase B: URL Shortening Features
- Create short links from long URLs
- Manage user's collection of shortened links
- Link analytics and statistics
- Custom alias support

### Phase C: QR Code Generation
- Generate QR codes for URLs
- Customizable QR code styling
- Download and sharing capabilities

### Phase D: Barcode Generation
- Generate various barcode formats
- Integration with business workflows
- Batch generation capabilities

### Phase E: User Profile Management
- Edit user profile information
- Account settings and preferences
- Security settings management
- Account deletion and data export

### Phase F: Advanced Features
- Enterprise-level functionality
- Advanced analytics and reporting
- Team collaboration features
- API access and management

---

## Detailed Implementation Plan

### Phase A: User Authentication & Account Management

This phase establishes the foundation for all subsequent features by implementing secure authentication and basic user management.

#### Phase A.1: Core Infrastructure Setup

**File Structure:**
```
src/
├── services/
│   ├── http.service.ts      # Base Axios configuration and shared interceptors
│   ├── auth.service.ts      # Auth Server communication layer
│   └── csrf.service.ts      # CSRF token management service
├── stores/
│   ├── auth.store.ts        # Authentication state management
│   └── app.store.ts         # Global application state
├── types/
│   └── auth.types.ts        # TypeScript interfaces and type definitions
└── utils/
    ├── constants.ts         # API endpoints, configuration constants
    └── validators.ts        # Form validation helper functions
```

**Key Components:**
- **HTTP Service**: Base Axios instance with default configurations, request/response interceptors
- **CSRF Service**: Fetches and manages CSRF tokens for secure state-changing operations
- **Auth Store**: Centralized authentication state with reactive updates
- **Type Definitions**: Comprehensive TypeScript interfaces for type safety

#### Phase A.2: Authentication Service Implementation

**Auth Service Methods:**
```typescript
// Traditional Authentication
login(credentials: LoginCredentials): Promise<AuthResponse>
register(userData: RegistrationData): Promise<AuthResponse>
logout(): Promise<void>

// Password Management
forgotPassword(email: string): Promise<void>
resetPassword(token: string, password: string): Promise<void>

// Account Verification
confirmAccount(token: string): Promise<void>
resendVerification(email: string): Promise<void>

// User Profile & Token Management
getCurrentUser(): Promise<UserProfile>
refreshToken(): Promise<void>

// Google OAuth2
initiateGoogleLogin(): void // Redirects to Auth Server OAuth endpoint
```

**Integration Points:**
- CSRF token inclusion for all POST/PUT/DELETE requests
- Automatic cookie handling with `withCredentials: true`
- Comprehensive error handling with user-friendly messages
- Loading state management during async operations

#### Phase A.3: State Management Implementation

**Auth Store State Structure:**
```typescript
interface AuthState {
  // User Data
  user: User | null
  isAuthenticated: boolean
  
  // Loading States
  isLoading: boolean
  isRefreshing: boolean
  
  // Error Handling
  error: string | null
  
  // Actions
  login: (credentials: LoginCredentials) => Promise<void>
  register: (data: RegistrationData) => Promise<void>
  logout: () => Promise<void>
  setUser: (user: User) => void
  clearAuth: () => void
  setLoading: (loading: boolean) => void
  setError: (error: string | null) => void
}
```

**App Store for Global State:**
```typescript
interface AppState {
  // UI State
  isLoading: boolean
  notifications: Notification[]
  theme: 'light' | 'dark'
  
  // Actions
  showNotification: (notification: Notification) => void
  clearNotifications: () => void
  setTheme: (theme: 'light' | 'dark') => void
}
```

#### Phase A.4: Routing & Page Structure

**Route Configuration:**
```
/ (root)                    → DashboardPage (protected)
/login                      → LoginPage
/register                   → RegisterPage
/forgot-password           → ForgotPasswordPage
/reset-password/:token     → ResetPasswordPage
/confirm-account/:token    → ConfirmAccountPage
/resend-verification       → ResendVerificationPage
```

**Page Components Structure:**
```
src/pages/
├── auth/
│   ├── LoginPage.ts           # Traditional login with Google OAuth option
│   ├── RegisterPage.ts        # User registration form
│   ├── ForgotPasswordPage.ts  # Email input for password reset
│   ├── ResetPasswordPage.ts   # New password form with token validation
│   ├── ConfirmAccountPage.ts  # Account confirmation handler
│   └── ResendVerificationPage.ts # Resend verification email
├── dashboard/
│   └── DashboardPage.ts       # Post-login user dashboard
└── common/
    ├── LoadingPage.ts         # Global loading indicator
    └── ErrorPage.ts           # Error boundary page
```

#### Phase A.5: UI Components (Authentication-Specific)

**Component Library:**
```
src/components/auth/
├── LoginForm.ts              # Email/password input form
├── RegisterForm.ts           # Registration form with validation
├── GoogleLoginButton.ts      # OAuth2 Google authentication button
├── ForgotPasswordForm.ts     # Email input for password reset
├── ResetPasswordForm.ts      # Password reset form
└── AuthGuard.ts             # Route protection wrapper component
```

**Key Features:**
- Real-time form validation with user feedback
- Accessibility compliance (ARIA labels, keyboard navigation)
- Responsive design with Tailwind CSS
- Loading states and error displays
- Consistent styling across all forms

#### Phase A.6: Implementation Timeline

**Week 1: Foundation Architecture**
- **Days 1-2**: HTTP Service setup with base Axios configuration, CSRF service implementation
- **Days 3-4**: Auth Store and Auth Service with core authentication methods
- **Day 5**: Router setup with basic page templates and navigation structure

**Week 2: Core Authentication Flow**
- **Days 1-2**: Login and Register pages with form validation and error handling
- **Day 3**: Google OAuth2 integration with redirect handling
- **Day 4**: Dashboard page with user profile display and navigation
- **Day 5**: AuthGuard implementation for route protection

**Week 3: Extended Authentication Features**
- **Days 1-2**: Forgot password and reset password flow with email integration
- **Day 3**: Account confirmation handling with token validation
- **Day 4**: Resend verification functionality and comprehensive error handling
- **Day 5**: UI polish, accessibility improvements, and cross-browser testing

**Week 4: Security & User Experience**
- **Days 1-2**: Silent token refresh mechanism with iframe implementation
- **Day 3**: Enhanced error handling, toast notifications, and user feedback
- **Day 4**: Loading states optimization, form validation refinement
- **Day 5**: Security hardening, penetration testing, and final quality assurance

### Technical Implementation Details

#### CSRF Integration Pattern
```typescript
// Before any state-changing request
const csrfToken = await csrfService.getToken()
const response = await axios.post('/api/v1/auth/login', data, {
  headers: { 'X-CSRF-TOKEN': csrfToken }
})
```

**Security Considerations:**
- CSRF tokens stored in memory only (never localStorage)
- Automatic token refresh on expiration
- Secure token transmission with proper headers

#### Google OAuth2 Flow Implementation
```typescript
// Initiate OAuth2 flow
window.location.href = '/oauth2/authorization/google'

// Handle callback (Auth Server redirects to dashboard)
// Automatic cookie setting by Auth Server
// SPA detects authentication state change
```

**Flow Details:**
- User clicks Google login button → Redirect to Auth Server
- Auth Server handles Google OAuth2 flow
- Successful authentication → Cookies set, redirect to dashboard
- Error handling for OAuth failures with user-friendly messages

#### Token Refresh Strategy
```typescript
// Axios response interceptor
axios.interceptors.response.use(
  response => response,
  async error => {
    if (error.response?.status === 401 && 
        error.response?.headers['www-authenticate'] === 'Refresh') {
      await authService.refreshToken()
      return axios.request(error.config) // Retry original request
    }
    return Promise.reject(error)
  }
)
```

**Refresh Mechanism:**
- Silent background refresh before token expiration
- Automatic retry for failed requests after token refresh
- Graceful degradation to login page for refresh failures
- User session preservation during refresh process

---

## Project Structure

### Complete Directory Structure
```
frontend-spa/
├── public/
│   ├── index.html
│   └── favicon.ico
├── src/
│   ├── components/
│   │   ├── auth/
│   │   │   ├── LoginForm.ts
│   │   │   ├── RegisterForm.ts
│   │   │   ├── GoogleLoginButton.ts
│   │   │   ├── ForgotPasswordForm.ts
│   │   │   ├── ResetPasswordForm.ts
│   │   │   └── AuthGuard.ts
│   │   ├── ui/
│   │   │   ├── Button.ts
│   │   │   ├── Input.ts
│   │   │   ├── Modal.ts
│   │   │   ├── Toast.ts
│   │   │   └── Spinner.ts
│   │   └── common/
│   │       ├── Header.ts
│   │       ├── Footer.ts
│   │       └── Navigation.ts
│   ├── pages/
│   │   ├── auth/
│   │   │   ├── LoginPage.ts
│   │   │   ├── RegisterPage.ts
│   │   │   ├── ForgotPasswordPage.ts
│   │   │   ├── ResetPasswordPage.ts
│   │   │   ├── ConfirmAccountPage.ts
│   │   │   └── ResendVerificationPage.ts
│   │   ├── dashboard/
│   │   │   └── DashboardPage.ts
│   │   └── common/
│   │       ├── LoadingPage.ts
│   │       ├── ErrorPage.ts
│   │       └── NotFoundPage.ts
│   ├── services/
│   │   ├── http.service.ts
│   │   ├── auth.service.ts
│   │   ├── api.service.ts
│   │   └── csrf.service.ts
│   ├── stores/
│   │   ├── auth.store.ts
│   │   ├── app.store.ts
│   │   └── data.store.ts
│   ├── types/
│   │   ├── auth.types.ts
│   │   ├── api.types.ts
│   │   └── common.types.ts
│   ├── utils/
│   │   ├── constants.ts
│   │   ├── validators.ts
│   │   ├── helpers.ts
│   │   └── storage.ts
│   ├── styles/
│   │   ├── main.css
│   │   └── components.css
│   ├── router/
│   │   ├── index.ts
│   │   └── routes.ts
│   └── main.ts
├── package.json
├── vite.config.ts
├── tsconfig.json
├── tailwind.config.js
└── README.md
```

### File Naming Conventions
- **Services**: `*.service.ts` - Business logic and external API communication
- **Stores**: `*.store.ts` - State management with Zustand
- **Types**: `*.types.ts` - TypeScript interface definitions
- **Pages**: `*Page.ts` - Full-page components
- **Components**: PascalCase for component files
- **Utils**: Lowercase with descriptive names

### Import/Export Patterns
- **Barrel Exports**: Use index.ts files in directories for clean imports
- **Named Exports**: Prefer named exports over default exports for better IDE support
- **Type-Only Imports**: Use `import type` for TypeScript types

---

## Implementation Timeline

### Overall Project Timeline: 16 Weeks

#### Phase A: Authentication & Account Management (4 weeks)
**Week 1**: Core infrastructure and base services
**Week 2**: Authentication flows and basic UI
**Week 3**: Extended auth features and password management
**Week 4**: Security hardening and user experience polish

#### Phase B: URL Shortening Features (3 weeks)
**Week 5**: API service setup and basic link creation
**Week 6**: Link management interface and user dashboard
**Week 7**: Analytics integration and advanced features

#### Phase C: QR Code Generation (2 weeks)
**Week 8**: QR service integration and basic generation
**Week 9**: Customization options and sharing features

#### Phase D: Barcode Generation (2 weeks)
**Week 10**: Barcode service setup and format support
**Week 11**: Batch processing and business workflow integration

#### Phase E: User Profile Management (2 weeks)
**Week 12**: Profile editing and account settings
**Week 13**: Security settings and data management

#### Phase F: Advanced Features & Polish (3 weeks)
**Week 14**: Enterprise features and advanced analytics
**Week 15**: Performance optimization and security audit
**Week 16**: Final testing, documentation, and deployment preparation

### Milestone Deliverables

#### Week 4 Milestone: Authentication System
- Complete user registration and login system
- Google OAuth2 integration
- Password reset functionality
- Protected routing system
- Basic user dashboard

#### Week 7 Milestone: Core Business Features
- URL shortening functionality
- User link management
- Basic analytics dashboard
- Responsive UI implementation

#### Week 11 Milestone: Full Feature Set
- QR code and barcode generation
- Complete user profile management
- Advanced link analytics
- Mobile-optimized interface

#### Week 16 Milestone: Production Ready
- Performance optimized application
- Comprehensive error handling
- Security audit compliance
- Full documentation and deployment guides

---

## Quality Assurance & Best Practices

### Code Quality Standards
- **TypeScript Strict Mode**: Full type safety with strict compiler options
- **ESLint Configuration**: Consistent code style and error prevention
- **Prettier Integration**: Automated code formatting
- **Unit Testing**: Jest/Vitest for component and service testing
- **E2E Testing**: Playwright for user journey testing

### Security Best Practices
- **No localStorage for Tokens**: HTTP-only cookies for token storage
- **CSRF Protection**: Tokens for all state-changing operations
- **Input Validation**: Client-side and server-side validation
- **Error Handling**: No sensitive information in error messages
- **Content Security Policy**: Strict CSP headers for XSS prevention

### Performance Optimization
- **Code Splitting**: Dynamic imports for route-based splitting
- **Bundle Analysis**: Regular bundle size monitoring
- **Asset Optimization**: Image compression and lazy loading
- **Caching Strategy**: Proper HTTP caching headers
- **Performance Monitoring**: Core Web Vitals tracking

### Documentation Requirements
- **API Documentation**: Comprehensive endpoint documentation
- **Component Library**: Storybook for component documentation
- **Development Guide**: Setup and contribution guidelines
- **Deployment Guide**: Production deployment instructions
- **User Guide**: End-user feature documentation

---

## Risk Mitigation & Contingency Planning

### Technical Risks
1. **Token Refresh Complexity**: Mitigation through robust testing and fallback mechanisms
2. **Cross-Origin Issues**: Comprehensive CORS configuration testing
3. **Browser Compatibility**: Progressive enhancement and polyfill strategies
4. **Performance Bottlenecks**: Regular performance auditing and optimization

### Timeline Risks
1. **Feature Scope Creep**: Regular stakeholder reviews and change control process
2. **Integration Delays**: Early API integration testing and mock services
3. **Testing Delays**: Parallel development and testing workflows
4. **Deployment Issues**: Staging environment testing and deployment automation

### Quality Risks
1. **Security Vulnerabilities**: Regular security audits and penetration testing
2. **User Experience Issues**: Continuous user feedback and usability testing
3. **Accessibility Compliance**: Regular accessibility audits and automated testing
4. **Cross-Browser Issues**: Comprehensive browser testing matrix

---

## Success Metrics & Definition of Done

### Technical Metrics
- **Performance**: Lighthouse scores > 90 for all categories
- **Security**: Zero high/critical security vulnerabilities
- **Test Coverage**: >80% unit test coverage, >70% E2E coverage
- **Bundle Size**: <500KB compressed for initial load
- **Load Time**: <3 seconds first contentful paint

### User Experience Metrics
- **Accessibility**: WCAG 2.1 AA compliance
- **Mobile Responsiveness**: 100% feature parity across devices
- **Error Handling**: Graceful degradation for all error scenarios
- **User Feedback**: >4.5/5 usability rating from testing
- **Browser Support**: Full functionality in 95% of target browsers

### Business Metrics
- **Feature Completion**: 100% of planned features implemented
- **Documentation**: Complete technical and user documentation
- **Deployment**: Automated CI/CD pipeline with staging/production environments
- **Monitoring**: Full application and performance monitoring
- **Maintenance**: Comprehensive maintenance and update procedures

---

*This implementation plan serves as the comprehensive guide for developing a production-ready SPA with robust authentication, security, and user experience. Regular reviews and updates to this plan will ensure successful project delivery.*