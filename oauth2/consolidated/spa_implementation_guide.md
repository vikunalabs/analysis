# SPA Implementation Guide (Vite + Vanilla TypeScript)

## Table of Contents
1. [Project Setup](#project-setup)
2. [Authentication State Management](#authentication-state-management)
3. [HTTP Client Configuration](#http-client-configuration)
4. [Authentication Flow Implementation](#authentication-flow-implementation)
5. [Route Management](#route-management)
6. [UI Components](#ui-components)
7. [Error Handling](#error-handling)
8. [Development and Production Configuration](#development-and-production-configuration)

## Project Setup

### Initial Project Structure
```
spa-project/
├── src/
│   ├── components/
│   │   ├── auth/
│   │   ├── profile/
│   │   └── common/
│   ├── services/
│   │   ├── api.ts
│   │   ├── auth.ts
│   │   └── storage.ts
│   ├── types/
│   │   ├── auth.ts
│   │   ├── user.ts
│   │   └── api.ts
│   ├── utils/
│   │   ├── constants.ts
│   │   ├── helpers.ts
│   │   └── validators.ts
│   ├── styles/
│   │   ├── globals.css
│   │   └── components/
│   ├── main.ts
│   └── index.html
├── public/
├── package.json
├── tsconfig.json
├── vite.config.ts
└── README.md
```

### Package.json Dependencies
```json
{
  "name": "oauth2-spa",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "type-check": "tsc --noEmit"
  },
  "dependencies": {
    "axios": "^1.6.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "typescript": "^5.0.0",
    "vite": "^5.0.0"
  }
}
```

### Vite Configuration
```typescript
// vite.config.ts
import { defineConfig } from 'vite';

export default defineConfig({
  server: {
    port: 3000,
    cors: true,
    proxy: {
      '/api': {
        target: 'https://api.your-domain.com',
        changeOrigin: true,
        secure: true,
        credentials: 'include'
      },
      '/auth': {
        target: 'https://auth.your-domain.com',
        changeOrigin: true,
        secure: true,
        credentials: 'include'
      }
    }
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['axios'],
        },
      },
    },
  },
  define: {
    __APP_VERSION__: JSON.stringify(process.env.npm_package_version),
  },
});
```

### TypeScript Configuration
```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "preserve",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["src/**/*.ts", "src/**/*.d.ts"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

## Authentication State Management

### Type Definitions
```typescript
// src/types/auth.ts
export interface User {
  id: string;
  email: string;
  emailVerified: boolean;
  roles: string[];
}

export interface AuthState {
  isAuthenticated: boolean;
  user: User | null;
  isLoading: boolean;
  error: string | null;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegisterRequest {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
}

export interface ForgotPasswordRequest {
  email: string;
}

export interface ResetPasswordRequest {
  token: string;
  newPassword: string;
}

// src/types/api.ts
export interface ApiResponse<T = any> {
  data?: T;
  error?: string;
  code?: string;
  message?: string;
}

export interface ErrorResponse {
  error: string;
  code: string;
  message?: string;
  fieldErrors?: Record<string, string>;
}
```

### Authentication State Manager
```typescript
// src/services/auth.ts
import { apiClient } from './api';
import type { User, AuthState, LoginRequest, RegisterRequest } from '../types/auth';

class AuthStateManager {
  private state: AuthState = {
    isAuthenticated: false,
    user: null,
    isLoading: true,
    error: null
  };

  private listeners: Array<(state: AuthState) => void> = [];

  constructor() {
    this.initializeAuth();
  }

  // Subscribe to auth state changes
  subscribe(listener: (state: AuthState) => void) {
    this.listeners.push(listener);
    // Return unsubscribe function
    return () => {
      this.listeners = this.listeners.filter(l => l !== listener);
    };
  }

  // Get current state
  getState(): AuthState {
    return { ...this.state };
  }

  // Private method to update state and notify listeners
  private setState(updates: Partial<AuthState>) {
    this.state = { ...this.state, ...updates };
    this.listeners.forEach(listener => listener(this.getState()));
  }

  // Initialize authentication on app load
  private async initializeAuth() {
    try {
      this.setState({ isLoading: true, error: null });
      
      // Check if user is authenticated by calling /auth/user
      const response = await apiClient.get('/auth/user');
      
      if (response.status === 200) {
        this.setState({
          isAuthenticated: true,
          user: response.data,
          isLoading: false
        });
      } else {
        this.setState({
          isAuthenticated: false,
          user: null,
          isLoading: false
        });
      }
    } catch (error) {
      console.log('User not authenticated');
      this.setState({
        isAuthenticated: false,
        user: null,
        isLoading: false
      });
    }
  }

  // Login with email/password
  async login(credentials: LoginRequest): Promise<{ success: boolean; error?: string }> {
    try {
      this.setState({ isLoading: true, error: null });
      
      const response = await apiClient.post('/auth/login', credentials);
      
      if (response.status === 200) {
        this.setState({
          isAuthenticated: true,
          user: response.data,
          isLoading: false
        });
        return { success: true };
      } else {
        const error = response.data?.error || 'Login failed';
        this.setState({ isLoading: false, error });
        return { success: false, error };
      }
    } catch (error: any) {
      const errorMessage = error.response?.data?.error || 'Login failed';
      this.setState({ isLoading: false, error: errorMessage });
      return { success: false, error: errorMessage };
    }
  }

  // Register new user
  async register(userData: RegisterRequest): Promise<{ success: boolean; error?: string }> {
    try {
      this.setState({ isLoading: true, error: null });
      
      const response = await apiClient.post('/auth/register', userData);
      
      if (response.status === 201) {
        this.setState({ isLoading: false });
        return { success: true };
      } else {
        const error = response.data?.error || 'Registration failed';
        this.setState({ isLoading: false, error });
        return { success: false, error };
      }
    } catch (error: any) {
      const errorMessage = error.response?.data?.error || 'Registration failed';
      this.setState({ isLoading: false, error: errorMessage });
      return { success: false, error: errorMessage };
    }
  }

  // Initiate Google OAuth login
  initiateGoogleLogin() {
    window.location.href = `${import.meta.env.VITE_AUTH_SERVER_URL}/oauth2/authorization/google`;
  }

  // Logout
  async logout(): Promise<void> {
    try {
      await apiClient.post('/auth/logout');
    } catch (error) {
      console.error('Logout error:', error);
    } finally {
      this.setState({
        isAuthenticated: false,
        user: null,
        error: null
      });
      // Redirect to login page
      window.location.href = '/login';
    }
  }

  // Refresh user data
  async refreshUser(): Promise<void> {
    try {
      const response = await apiClient.get('/auth/user');
      if (response.status === 200) {
        this.setState({ user: response.data });
      }
    } catch (error) {
      console.error('Failed to refresh user data:', error);
    }
  }

  // Clear error
  clearError() {
    this.setState({ error: null });
  }
}

// Export singleton instance
export const authManager = new AuthStateManager();
```

## HTTP Client Configuration

### Axios Configuration with Interceptors
```typescript
// src/services/api.ts
import axios, { AxiosInstance, AxiosRequestConfig, AxiosResponse, AxiosError } from 'axios';

interface RetryConfig extends AxiosRequestConfig {
  _retry?: boolean;
}

class ApiClient {
  private client: AxiosInstance;
  private refreshing = false;
  private failedQueue: Array<{
    resolve: (value: any) => void;
    reject: (reason: any) => void;
  }> = [];

  constructor() {
    this.client = axios.create({
      baseURL: import.meta.env.VITE_API_BASE_URL || '',
      timeout: 10000,
      withCredentials: true,
      headers: {
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    });

    this.setupInterceptors();
  }

  private setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        // Add any request modifications here
        return config;
      },
      (error) => {
        return Promise.reject(error);
      }
    );

    // Response interceptor for token refresh
    this.client.interceptors.response.use(
      (response: AxiosResponse) => response,
      async (error: AxiosError) => {
        const originalRequest = error.config as RetryConfig;

        if (error.response?.status === 401 && !originalRequest._retry) {
          const wwwAuthenticate = error.response.headers['www-authenticate'];
          
          // Check if server is requesting token refresh
          if (wwwAuthenticate?.includes('Refresh')) {
            if (this.refreshing) {
              // If already refreshing, queue this request
              return new Promise((resolve, reject) => {
                this.failedQueue.push({ resolve, reject });
              }).then(() => {
                return this.client(originalRequest);
              }).catch(err => {
                return Promise.reject(err);
              });
            }

            originalRequest._retry = true;
            this.refreshing = true;

            try {
              // Attempt to refresh token
              await this.refreshToken();
              
              // Process queued requests
              this.processQueue(null);
              
              // Retry original request
              return this.client(originalRequest);
            } catch (refreshError) {
              // Refresh failed, redirect to login
              this.processQueue(refreshError);
              this.redirectToLogin();
              return Promise.reject(refreshError);
            } finally {
              this.refreshing = false;
            }
          } else {
            // Not a refresh-related 401, redirect to login
            this.redirectToLogin();
          }
        }

        return Promise.reject(error);
      }
    );
  }

  private async refreshToken(): Promise<void> {
    const response = await fetch(`${import.meta.env.VITE_AUTH_SERVER_URL}/auth/refresh`, {
      method: 'POST',
      credentials: 'include',
      headers: {
        'X-Requested-With': 'XMLHttpRequest'
      }
    });

    if (!response.ok) {
      throw new Error('Token refresh failed');
    }
  }

  private processQueue(error: any) {
    this.failedQueue.forEach(({ resolve, reject }) => {
      if (error) {
        reject(error);
      } else {
        resolve(null);
      }
    });
    
    this.failedQueue = [];
  }

  private redirectToLogin() {
    // Clear any auth state before redirecting
    window.location.href = '/login';
  }

  // Public methods
  get(url: string, config?: AxiosRequestConfig) {
    return this.client.get(url, config);
  }

  post(url: string, data?: any, config?: AxiosRequestConfig) {
    return this.client.post(url, data, config);
  }

  put(url: string, data?: any, config?: AxiosRequestConfig) {
    return this.client.put(url, data, config);
  }

  delete(url: string, config?: AxiosRequestConfig) {
    return this.client.delete(url, config);
  }

  patch(url: string, data?: any, config?: AxiosRequestConfig) {
    return this.client.patch(url, data, config);
  }
}

// Export singleton instance
export const apiClient = new ApiClient();
```

### CSRF Token Management
```typescript
// src/services/csrf.ts
import { apiClient } from './api';

class CSRFManager {
  private csrfToken: string | null = null;

  async getCSRFToken(): Promise<string> {
    if (!this.csrfToken) {
      try {
        const response = await apiClient.get('/auth/csrf');
        if (response.status === 200 && response.data.csrfToken) {
          this.csrfToken = response.data.csrfToken;
        }
      } catch (error) {
        console.warn('Failed to fetch CSRF token:', error);
        return '';
      }
    }
    return this.csrfToken || '';
  }

  async addCSRFHeader(headers: Record<string, string> = {}): Promise<Record<string, string>> {
    const token = await this.getCSRFToken();
    if (token) {
      return {
        ...headers,
        'X-CSRF-TOKEN': token
      };
    }
    return headers;
  }

  clearToken() {
    this.csrfToken = null;
  }
}

export const csrfManager = new CSRFManager();
```

## Authentication Flow Implementation

### Login Component
```typescript
// src/components/auth/LoginForm.ts
export class LoginForm {
  private element: HTMLElement;
  private emailInput: HTMLInputElement;
  private passwordInput: HTMLInputElement;
  private submitButton: HTMLButtonElement;
  private errorElement: HTMLElement;
  private loadingElement: HTMLElement;

  constructor(container: HTMLElement) {
    this.element = this.createElement();
    container.appendChild(this.element);
    this.bindElements();
    this.setupEventListeners();
  }

  private createElement(): HTMLElement {
    const form = document.createElement('form');
    form.className = 'login-form';
    form.innerHTML = `
      <div class="form-header">
        <h2>Sign In</h2>
        <p>Welcome back! Please sign in to your account.</p>
      </div>
      
      <div class="form-body">
        <div class="form-group">
          <label for="email">Email</label>
          <input type="email" id="email" name="email" required 
                 placeholder="Enter your email" />
          <div class="field-error" id="email-error"></div>
        </div>

        <div class="form-group">
          <label for="password">Password</label>
          <input type="password" id="password" name="password" required 
                 placeholder="Enter your password" />
          <div class="field-error" id="password-error"></div>
        </div>

        <div class="form-actions">
          <button type="submit" class="btn-primary" id="submit-btn">
            <span class="btn-text">Sign In</span>
            <div class="btn-loading" id="loading" style="display: none;">
              <div class="spinner"></div>
            </div>
          </button>
        </div>

        <div class="form-error" id="form-error" style="display: none;"></div>

        <div class="form-divider">
          <span>or</span>
        </div>

        <button type="button" class="btn-google" id="google-login">
          <svg width="20" height="20" viewBox="0 0 24 24">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
          </svg>
          Continue with Google
        </button>

        <div class="form-links">
          <a href="/forgot-password">Forgot your password?</a>
          <a href="/register">Don't have an account? Sign up</a>
        </div>
      </div>
    `;
    return form;
  }

  private bindElements() {
    this.emailInput = this.element.querySelector('#email') as HTMLInputElement;
    this.passwordInput = this.element.querySelector('#password') as HTMLInputElement;
    this.submitButton = this.element.querySelector('#submit-btn') as HTMLButtonElement;
    this.errorElement = this.element.querySelector('#form-error') as HTMLElement;
    this.loadingElement = this.element.querySelector('#loading') as HTMLElement;
  }

  private setupEventListeners() {
    // Form submission
    this.element.addEventListener('submit', this.handleSubmit.bind(this));
    
    // Google login
    const googleButton = this.element.querySelector('#google-login') as HTMLButtonElement;
    googleButton.addEventListener('click', this.handleGoogleLogin.bind(this));
    
    // Clear errors on input
    this.emailInput.addEventListener('input', () => this.clearFieldError('email'));
    this.passwordInput.addEventListener('input', () => this.clearFieldError('password'));
  }

  private async handleSubmit(event: Event) {
    event.preventDefault();
    
    const email = this.emailInput.value.trim();
    const password = this.passwordInput.value;

    // Basic validation
    if (!email || !password) {
      this.showError('Please fill in all fields');
      return;
    }

    this.setLoading(true);
    this.clearErrors();

    try {
      const { authManager } = await import('../../services/auth');
      const result = await authManager.login({ email, password });

      if (result.success) {
        // Redirect to dashboard or intended page
        const redirectUrl = new URLSearchParams(window.location.search).get('redirect') || '/dashboard';
        window.location.href = redirectUrl;
      } else {
        this.showError(result.error || 'Login failed');
      }
    } catch (error) {
      this.showError('An unexpected error occurred');
    } finally {
      this.setLoading(false);
    }
  }

  private handleGoogleLogin() {
    const authServerUrl = import.meta.env.VITE_AUTH_SERVER_URL;
    const currentUrl = encodeURIComponent(window.location.origin + '/dashboard');
    window.location.href = `${authServerUrl}/oauth2/authorization/google?redirect_uri=${currentUrl}`;
  }

  private setLoading(loading: boolean) {
    const btnText = this.submitButton.querySelector('.btn-text') as HTMLElement;
    
    if (loading) {
      this.submitButton.disabled = true;
      btnText.style.display = 'none';
      this.loadingElement.style.display = 'flex';
    } else {
      this.submitButton.disabled = false;
      btnText.style.display = 'inline';
      this.loadingElement.style.display = 'none';
    }
  }

  private showError(message: string) {
    this.errorElement.textContent = message;
    this.errorElement.style.display = 'block';
  }

  private clearErrors() {
    this.errorElement.style.display = 'none';
    this.clearFieldError('email');
    this.clearFieldError('password');
  }

  private clearFieldError(fieldName: string) {
    const errorElement = this.element.querySelector(`#${fieldName}-error`) as HTMLElement;
    if (errorElement) {
      errorElement.textContent = '';
    }
  }

  destroy() {
    this.element.remove();
  }
}
```

### Registration Component
```typescript
// src/components/auth/RegisterForm.ts
import type { RegisterRequest } from '../../types/auth';
import { validateEmail, validatePassword } from '../../utils/validators';

export class RegisterForm {
  private element: HTMLElement;
  private formFields: Record<string, HTMLInputElement> = {};

  constructor(container: HTMLElement) {
    this.element = this.createElement();
    container.appendChild(this.element);
    this.bindElements();
    this.setupEventListeners();
  }

  private createElement(): HTMLElement {
    const form = document.createElement('form');
    form.className = 'register-form';
    form.innerHTML = `
      <div class="form-header">
        <h2>Create Account</h2>
        <p>Join us today! Please fill in the information below.</p>
      </div>
      
      <div class="form-body">
        <div class="form-row">
          <div class="form-group">
            <label for="firstName">First Name</label>
            <input type="text" id="firstName" name="firstName" required 
                   placeholder="Enter your first name" />
            <div class="field-error" id="firstName-error"></div>
          </div>

          <div class="form-group">
            <label for="lastName">Last Name</label>
            <input type="text" id="lastName" name="lastName" required 
                   placeholder="Enter your last name" />
            <div class="field-error" id="lastName-error"></div>
          </div>
        </div>

        <div class="form-group">
          <label for="email">Email</label>
          <input type="email" id="email" name="email" required 
                 placeholder="Enter your email" />
          <div class="field-error" id="email-error"></div>
        </div>

        <div class="form-group">
          <label for="password">Password</label>
          <input type="password" id="password" name="password" required 
                 placeholder="Create a password" />
          <div class="field-error" id="password-error"></div>
          <div class="password-requirements">
            <ul>
              <li>At least 8 characters long</li>
              <li>Contains uppercase and lowercase letters</li>
              <li>Contains at least one number</li>
              <li>Contains at least one special character</li>
            </ul>
          </div>
        </div>

        <div class="form-group">
          <label for="confirmPassword">Confirm Password</label>
          <input type="password" id="confirmPassword" name="confirmPassword" required 
                 placeholder="Confirm your password" />
          <div class="field-error" id="confirmPassword-error"></div>
        </div>

        <div class="form-group checkbox-group">
          <label class="checkbox-label">
            <input type="checkbox" id="terms" name="terms" required />
            <span class="checkmark"></span>
            I agree to the <a href="/terms" target="_blank">Terms of Service</a> 
            and <a href="/privacy" target="_blank">Privacy Policy</a>
          </label>
          <div class="field-error" id="terms-error"></div>
        </div>

        <div class="form-actions">
          <button type="submit" class="btn-primary" id="submit-btn">
            <span class="btn-text">Create Account</span>
            <div class="btn-loading" id="loading" style="display: none;">
              <div class="spinner"></div>
            </div>
          </button>
        </div>

        <div class="form-error" id="form-error" style="display: none;"></div>
        <div class="form-success" id="form-success" style="display: none;"></div>

        <div class="form-divider">
          <span>or</span>
        </div>

        <button type="button" class="btn-google" id="google-register">
          <svg width="20" height="20" viewBox="0 0 24 24">
            <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
            <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
            <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
            <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
          </svg>
          Sign up with Google
        </button>

        <div class="form-links">
          <a href="/login">Already have an account? Sign in</a>
        </div>
      </div>
    `;
    return form;
  }

  private bindElements() {
    const fieldNames = ['firstName', 'lastName', 'email', 'password', 'confirmPassword'];
    fieldNames.forEach(name => {
      this.formFields[name] = this.element.querySelector(`#${name}`) as HTMLInputElement;
    });
  }

  private setupEventListeners() {
    this.element.addEventListener('submit', this.handleSubmit.bind(this));
    
    // Google registration
    const googleButton = this.element.querySelector('#google-register') as HTMLButtonElement;
    googleButton.addEventListener('click', this.handleGoogleRegister.bind(this));
    
    // Real-time validation
    Object.keys(this.formFields).forEach(fieldName => {
      this.formFields[fieldName].addEventListener('blur', () => this.validateField(fieldName));
      this.formFields[fieldName].addEventListener('input', () => this.clearFieldError(fieldName));
    });
  }

  private async handleSubmit(event: Event) {
    event.preventDefault();
    
    if (!this.validateForm()) {
      return;
    }

    const formData: RegisterRequest = {
      firstName: this.formFields.firstName.value.trim(),
      lastName: this.formFields.lastName.value.trim(),
      email: this.formFields.email.value.trim(),
      password: this.formFields.password.value
    };

    this.setLoading(true);
    this.clearMessages();

    try {
      const { authManager } = await import('../../services/auth');
      const result = await authManager.register(formData);

      if (result.success) {
        this.showSuccess('Registration successful! Please check your email for verification.');
        this.element.reset();
      } else {
        this.showError(result.error || 'Registration failed');
      }
    } catch (error) {
      this.showError('An unexpected error occurred');
    } finally {
      this.setLoading(false);
    }
  }

  private validateForm(): boolean {
    let isValid = true;
    
    // Validate all fields
    Object.keys(this.formFields).forEach(fieldName => {
      if (!this.validateField(fieldName)) {
        isValid = false;
      }
    });

    // Check terms acceptance
    const termsCheckbox = this.element.querySelector('#terms') as HTMLInputElement;
    if (!termsCheckbox.checked) {
      this.showFieldError('terms', 'You must agree to the terms and conditions');
      isValid = false;
    }

    return isValid;
  }

  private validateField(fieldName: string): boolean {
    const field = this.formFields[fieldName];
    const value = field.value.trim();

    switch (fieldName) {
      case 'firstName':
      case 'lastName':
        if (!value || value.length < 2) {
          this.showFieldError(fieldName, 'Must be at least 2 characters long');
          return false;
        }
        break;

      case 'email':
        if (!validateEmail(value)) {
          this.showFieldError(fieldName, 'Please enter a valid email address');
          return false;
        }
        break;

      case 'password':
        const passwordValidation = validatePassword(value);
        if (!passwordValidation.isValid) {
          this.showFieldError(fieldName, passwordValidation.message);
          return false;
        }
        break;

      case 'confirmPassword':
        if (value !== this.formFields.password.value) {
          this.showFieldError(fieldName, 'Passwords do not match');
          return false;
        }
        break;
    }

    this.clearFieldError(fieldName);
    return true;
  }

  private setLoading(loading: boolean) {
    const submitButton = this.element.querySelector('#submit-btn') as HTMLButtonElement;
    const btnText = submitButton.querySelector('.btn-text') as HTMLElement;
    const loadingElement = submitButton.querySelector('#loading') as HTMLElement;
    
    if (loading) {
      submitButton.disabled = true;
      btnText.style.display = 'none';
      loadingElement.style.display = 'flex';
    } else {
      submitButton.disabled = false;
      btnText.style.display = 'inline';
      loadingElement.style.display = 'none';
    }
  }

  private showError(message: string) {
    const errorElement = this.element.querySelector('#form-error') as HTMLElement;
    errorElement.textContent = message;
    errorElement.style.display = 'block';
  }

  private showSuccess(message: string) {
    const successElement = this.element.querySelector('#form-success') as HTMLElement;
    successElement.textContent = message;
    successElement.style.display = 'block';
  }

  private clearMessages() {
    const errorElement = this.element.querySelector('#form-error') as HTMLElement;
    const successElement = this.element.querySelector('#form-success') as HTMLElement;
    errorElement.style.display = 'none';
    successElement.style.display = 'none';
  }

  private showFieldError(fieldName: string, message: string) {
    const errorElement = this.element.querySelector(`#${fieldName}-error`) as HTMLElement;
    if (errorElement) {
      errorElement.textContent = message;
    }
  }

  private clearFieldError(fieldName: string) {
    const errorElement = this.element.querySelector(`#${fieldName}-error`) as HTMLElement;
    if (errorElement) {
      errorElement.textContent = '';
    }
  }

  private handleGoogleRegister() {
    const authServerUrl = import.meta.env.VITE_AUTH_SERVER_URL;
    const currentUrl = encodeURIComponent(window.location.origin + '/dashboard');
    window.location.href = `${authServerUrl}/oauth2/authorization/google?redirect_uri=${currentUrl}`;
  }

  destroy() {
    this.element.remove();
  }
}
```

## Route Management

### Simple Router Implementation
```typescript
// src/services/router.ts
interface Route {
  path: string;
  component: () => Promise<void>;
  requiresAuth?: boolean;
  title?: string;
}

class Router {
  private routes: Route[] = [];
  private currentRoute: string | null = null;

  constructor() {
    window.addEventListener('popstate', this.handlePopState.bind(this));
  }

  addRoute(route: Route) {
    this.routes.push(route);
  }

  async navigate(path: string, pushState = true) {
    if (pushState && path !== this.currentRoute) {
      history.pushState({}, '', path);
    }

    const route = this.findRoute(path);
    if (!route) {
      this.navigate('/404');
      return;
    }

    // Check authentication requirement
    if (route.requiresAuth) {
      const { authManager } = await import('./auth');
      const authState = authManager.getState();
      
      if (!authState.isAuthenticated && !authState.isLoading) {
        this.navigate(`/login?redirect=${encodeURIComponent(path)}`);
        return;
      }
    }

    // Set page title
    if (route.title) {
      document.title = `${route.title} | Your App`;
    }

    this.currentRoute = path;
    await route.component();
  }

  private findRoute(path: string): Route | null {
    return this.routes.find(route => {
      if (route.path === path) return true;
      
      // Support for dynamic routes (basic implementation)
      const routeParts = route.path.split('/');
      const pathParts = path.split('/');
      
      if (routeParts.length !== pathParts.length) return false;
      
      return routeParts.every((part, index) => {
        return part.startsWith(':') || part === pathParts[index];
      });
    }) || null;
  }

  private handlePopState() {
    this.navigate(window.location.pathname, false);
  }

  getCurrentPath(): string {
    return window.location.pathname;
  }
}

export const router = new Router();
```

### Route Configuration
```typescript
// src/main.ts
import { router } from './services/router';
import { authManager } from './services/auth';

// Define routes
router.addRoute({
  path: '/',
  component: () => import('./pages/Home').then(m => m.renderHome()),
  title: 'Home'
});

router.addRoute({
  path: '/login',
  component: () => import('./pages/Login').then(m => m.renderLogin()),
  title: 'Sign In'
});

router.addRoute({
  path: '/register',
  component: () => import('./pages/Register').then(m => m.renderRegister()),
  title: 'Sign Up'
});

router.addRoute({
  path: '/dashboard',
  component: () => import('./pages/Dashboard').then(m => m.renderDashboard()),
  requiresAuth: true,
  title: 'Dashboard'
});

router.addRoute({
  path: '/profile',
  component: () => import('./pages/Profile').then(m => m.renderProfile()),
  requiresAuth: true,
  title: 'Profile'
});

router.addRoute({
  path: '/forgot-password',
  component: () => import('./pages/ForgotPassword').then(m => m.renderForgotPassword()),
  title: 'Forgot Password'
});

router.addRoute({
  path: '/reset-password',
  component: () => import('./pages/ResetPassword').then(m => m.renderResetPassword()),
  title: 'Reset Password'
});

router.addRoute({
  path: '/404',
  component: () => import('./pages/NotFound').then(m => m.renderNotFound()),
  title: 'Page Not Found'
});

// Initialize app
async function initApp() {
  // Wait for auth initialization
  const authState = authManager.getState();
  if (authState.isLoading) {
    await new Promise(resolve => {
      const unsubscribe = authManager.subscribe((state) => {
        if (!state.isLoading) {
          unsubscribe();
          resolve(void 0);
        }
      });
    });
  }

  // Start routing
  await router.navigate(window.location.pathname, false);
}

initApp();
```

## UI Components

### Navigation Component
```typescript
// src/components/common/Navigation.ts
import { authManager } from '../../services/auth';
import type { User } from '../../types/auth';

export class Navigation {
  private element: HTMLElement;
  private user: User | null = null;

  constructor(container: HTMLElement) {
    this.element = this.createElement();
    container.appendChild(this.element);
    this.setupEventListeners();
    this.subscribeToAuth();
  }

  private createElement(): HTMLElement {
    const nav = document.createElement('nav');
    nav.className = 'main-navigation';
    nav.innerHTML = `
      <div class="nav-container">
        <div class="nav-brand">
          <a href="/">Your App</a>
        </div>
        
        <div class="nav-menu" id="nav-menu">
          <div class="nav-links" id="nav-links"></div>
          <div class="nav-auth" id="nav-auth"></div>
        </div>
        
        <div class="nav-toggle" id="nav-toggle">
          <span></span>
          <span></span>
          <span></span>
        </div>
      </div>
    `;
    return nav;
  }

  private setupEventListeners() {
    // Mobile menu toggle
    const toggle = this.element.querySelector('#nav-toggle') as HTMLElement;
    const menu = this.element.querySelector('#nav-menu') as HTMLElement;
    
    toggle.addEventListener('click', () => {
      menu.classList.toggle('active');
    });
  }

  private subscribeToAuth() {
    authManager.subscribe((state) => {
      this.user = state.user;
      this.updateNavigation(state.isAuthenticated);
    });
  }

  private updateNavigation(isAuthenticated: boolean) {
    const linksContainer = this.element.querySelector('#nav-links') as HTMLElement;
    const authContainer = this.element.querySelector('#nav-auth') as HTMLElement;

    if (isAuthenticated && this.user) {
      // Authenticated navigation
      linksContainer.innerHTML = `
        <a href="/dashboard" class="nav-link">Dashboard</a>
        <a href="/projects" class="nav-link">Projects</a>
        <a href="/profile" class="nav-link">Profile</a>
      `;

      authContainer.innerHTML = `
        <div class="user-menu">
          <button class="user-menu-toggle" id="user-menu-toggle">
            <img src="${this.user.picture || '/default-avatar.png'}" 
                 alt="${this.user.email}" class="user-avatar" />
            <span>${this.user.email}</span>
            <svg class="chevron" width="16" height="16" viewBox="0 0 24 24">
              <path d="M7 10l5 5 5-5z"/>
            </svg>
          </button>
          <div class="user-dropdown" id="user-dropdown">
            <a href="/profile" class="dropdown-item">Profile</a>
            <a href="/settings" class="dropdown-item">Settings</a>
            <hr class="dropdown-divider" />
            <button class="dropdown-item logout-btn" id="logout-btn">Sign Out</button>
          </div>
        </div>
      `;

      // Setup user menu
      this.setupUserMenu();
    } else {
      // Public navigation
      linksContainer.innerHTML = `
        <a href="/features" class="nav-link">Features</a>
        <a href="/pricing" class="nav-link">Pricing</a>
        <a href="/about" class="nav-link">About</a>
      `;

      authContainer.innerHTML = `
        <a href="/login" class="nav-link">Sign In</a>
        <a href="/register" class="btn btn-primary">Sign Up</a>
      `;
    }
  }

  private setupUserMenu() {
    const toggle = this.element.querySelector('#user-menu-toggle') as HTMLElement;
    const dropdown = this.element.querySelector('#user-dropdown') as HTMLElement;
    const logoutBtn = this.element.querySelector('#logout-btn') as HTMLElement;

    if (!toggle || !dropdown || !logoutBtn) return;

    // Toggle dropdown
    toggle.addEventListener('click', (e) => {
      e.stopPropagation();
      dropdown.classList.toggle('active');
    });

    // Close dropdown when clicking outside
    document.addEventListener('click', (e) => {
      if (!toggle.contains(e.target as Node)) {
        dropdown.classList.remove('active');
      }
    });

    // Logout handler
    logoutBtn.addEventListener('click', async () => {
      await authManager.logout();
    });
  }

  destroy() {
    this.element.remove();
  }
}
```

### Loading Component
```typescript
// src/components/common/Loading.ts
export class LoadingSpinner {
  private element: HTMLElement;

  constructor(container: HTMLElement, message = 'Loading...') {
    this.element = this.createElement(message);
    container.appendChild(this.element);
  }

  private createElement(message: string): HTMLElement {
    const loading = document.createElement('div');
    loading.className = 'loading-spinner';
    loading.innerHTML = `
      <div class="spinner-container">
        <div class="spinner"></div>
        <p class="loading-message">${message}</p>
      </div>
    `;
    return loading;
  }

  updateMessage(message: string) {
    const messageElement = this.element.querySelector('.loading-message') as HTMLElement;
    if (messageElement) {
      messageElement.textContent = message;
    }
  }

  destroy() {
    this.element.remove();
  }
}
```

## Error Handling

### Error Service
```typescript
// src/services/errorHandler.ts
interface ErrorContext {
  component?: string;
  action?: string;
  userId?: string;
  additionalData?: Record<string, any>;
}

export class ErrorHandler {
  private static instance: ErrorHandler;

  static getInstance(): ErrorHandler {
    if (!ErrorHandler.instance) {
      ErrorHandler.instance = new ErrorHandler();
    }
    return ErrorHandler.instance;
  }

  handleError(error: any, context?: ErrorContext) {
    console.error('Application Error:', error, context);

    // Log to external service in production
    if (import.meta.env.PROD) {
      this.logToService(error, context);
    }

    // Show user-friendly message
    this.showUserError(error);
  }

  private logToService(error: any, context?: ErrorContext) {
    // Integration with error logging service (e.g., Sentry, LogRocket)
    try {
      const errorData = {
        message: error.message || 'Unknown error',
        stack: error.stack,
        url: window.location.href,
        userAgent: navigator.userAgent,
        timestamp: new Date().toISOString(),
        context
      };

      // Send to logging service
      fetch('/api/errors', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(errorData),
        credentials: 'include'
      }).catch(() => {
        // Ignore logging errors to prevent infinite loops
      });
    } catch (loggingError) {
      console.error('Failed to log error:', loggingError);
    }
  }

  private showUserError(error: any) {
    let message = 'An unexpected error occurred. Please try again.';

    // Customize message based on error type
    if (error.response?.status === 401) {
      message = 'Your session has expired. Please sign in again.';
    } else if (error.response?.status === 403) {
      message = 'You do not have permission to perform this action.';
    } else if (error.response?.status >= 500) {
      message = 'Server error. Please try again later.';
    } else if (error.code === 'NETWORK_ERROR') {
      message = 'Network error. Please check your connection and try again.';
    }

    this.showToast(message, 'error');
  }

  private showToast(message: string, type: 'error' | 'warning' | 'success' = 'error') {
    // Create toast notification
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `
      <div class="toast-content">
        <div class="toast-message">${message}</div>
        <button class="toast-close">&times;</button>
      </div>
    `;

    // Add to page
    document.body.appendChild(toast);

    // Auto remove after 5 seconds
    setTimeout(() => {
      if (toast.parentNode) {
        toast.remove();
      }
    }, 5000);

    // Close button handler
    const closeBtn = toast.querySelector('.toast-close');
    closeBtn?.addEventListener('click', () => toast.remove());
  }
}

export const errorHandler = ErrorHandler.getInstance();
```

### Form Validation Utilities
```typescript
// src/utils/validators.ts
export interface ValidationResult {
  isValid: boolean;
  message: string;
}

export function validateEmail(email: string): boolean {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

export function validatePassword(password: string): ValidationResult {
  const minLength = 8;
  const hasUpperCase = /[A-Z]/.test(password);
  const hasLowerCase = /[a-z]/.test(password);
  const hasNumbers = /\d/.test(password);
  const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);

  if (password.length < minLength) {
    return {
      isValid: false,
      message: `Password must be at least ${minLength} characters long`
    };
  }

  if (!hasUpperCase) {
    return {
      isValid: false,
      message: 'Password must contain at least one uppercase letter'
    };
  }

  if (!hasLowerCase) {
    return {
      isValid: false,
      message: 'Password must contain at least one lowercase letter'
    };
  }

  if (!hasNumbers) {
    return {
      isValid: false,
      message: 'Password must contain at least one number'
    };
  }

  if (!hasSpecialChar) {
    return {
      isValid: false,
      message: 'Password must contain at least one special character'
    };
  }

  return {
    isValid: true,
    message: ''
  };
}

export function validateRequired(value: string, fieldName: string): ValidationResult {
  if (!value || value.trim().length === 0) {
    return {
      isValid: false,
      message: `${fieldName} is required`
    };
  }

  return {
    isValid: true,
    message: ''
  };
}

export function validateMinLength(value: string, minLength: number, fieldName: string): ValidationResult {
  if (value.length < minLength) {
    return {
      isValid: false,
      message: `${fieldName} must be at least ${minLength} characters long`
    };
  }

  return {
    isValid: true,
    message: ''
  };
}
```

## Development and Production Configuration

### Environment Configuration
```typescript
// src/utils/config.ts
interface AppConfig {
  apiBaseUrl: string;
  authServerUrl: string;
  isDevelopment: boolean;
  isProduction: boolean;
  version: string;
}

export const config: AppConfig = {
  apiBaseUrl: import.meta.env.VITE_API_BASE_URL || 'https://api.your-domain.com',
  authServerUrl: import.meta.env.VITE_AUTH_SERVER_URL || 'https://auth.your-domain.com',
  isDevelopment: import.meta.env.DEV,
  isProduction: import.meta.env.PROD,
  version: import.meta.env.VITE_APP_VERSION || '1.0.0'
};
```

### Environment Files
```bash
# .env.development
VITE_API_BASE_URL=http://localhost:8081
VITE_AUTH_SERVER_URL=http://localhost:8080
VITE_APP_VERSION=1.0.0-dev

# .env.production
VITE_API_BASE_URL=https://api.your-domain.com
VITE_AUTH_SERVER_URL=https://auth.your-domain.com
VITE_APP_VERSION=1.0.0
```

### CSS Styles (Basic Structure)
```css
/* src/styles/globals.css */
:root {
  --primary-color: #4f46e5;
  --primary-hover: #4338ca;
  --success-color: #10b981;
  --error-color: #ef4444;
  --warning-color: #f59e0b;
  --gray-50: #f9fafb;
  --gray-100: #f3f4f6;
  --gray-200: #e5e7eb;
  --gray-300: #d1d5db;
  --gray-400: #9ca3af;
  --gray-500: #6b7280;
  --gray-600: #4b5563;
  --gray-700: #374151;
  --gray-800: #1f2937;
  --gray-900: #111827;
  --border-radius: 8px;
  --box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1), 0 1px 2px 0 rgba(0, 0, 0, 0.06);
}

* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  line-height: 1.6;
  color: var(--gray-700);
  background-color: var(--gray-50);
}

/* Form Styles */
.form-group {
  margin-bottom: 1.5rem;
}

.form-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: 500;
  color: var(--gray-700);
}

.form-group input {
  width: 100%;
  padding: 0.75rem;
  border: 1px solid var(--gray-300);
  border-radius: var(--border-radius);
  font-size: 1rem;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.form-group input:focus {
  outline: none;
  border-color: var(--primary-color);
  box-shadow: 0 0 0 3px rgba(79, 70, 229, 0.1);
}

.field-error {
  color: var(--error-color);
  font-size: 0.875rem;
  margin-top: 0.25rem;
}

/* Button Styles */
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0.75rem 1.5rem;
  border: none;
  border-radius: var(--border-radius);
  font-size: 1rem;
  font-weight: 500;
  text-decoration: none;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-primary {
  background-color: var(--primary-color);
  color: white;
}

.btn-primary:hover:not(:disabled) {
  background-color: var(--primary-hover);
}

.btn-primary:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.btn-google {
  background-color: white;
  color: var(--gray-700);
  border: 1px solid var(--gray-300);
  gap: 0.5rem;
}

.btn-google:hover {
  background-color: var(--gray-50);
}

/* Loading Spinner */
.spinner {
  width: 20px;
  height: 20px;
  border: 2px solid transparent;
  border-top: 2px solid currentColor;
  border-radius: 50%;
  animation: spin 1s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.loading-spinner {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 3rem;
}

.spinner-container {
  text-align: center;
}

.spinner-container .spinner {
  width: 40px;
  height: 40px;
  margin-bottom: 1rem;
  border-width: 3px;
  border-top-color: var(--primary-color);
}

/* Toast Notifications */
.toast {
  position: fixed;
  top: 1rem;
  right: 1rem;
  max-width: 400px;
  background: white;
  border-radius: var(--border-radius);
  box-shadow: var(--box-shadow);
  z-index: 1000;
  animation: slideIn 0.3s ease-out;
}

.toast-error {
  border-left: 4px solid var(--error-color);
}

.toast-success {
  border-left: 4px solid var(--success-color);
}

.toast-warning {
  border-left: 4px solid var(--warning-color);
}

.toast-content {
  display: flex;
  align-items: flex-start;
  padding: 1rem;
}

.toast-message {
  flex: 1;
  margin-right: 1rem;
}

.toast-close {
  background: none;
  border: none;
  font-size: 1.5rem;
  cursor: pointer;
  color: var(--gray-400);
  padding: 0;
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
}

@keyframes slideIn {
  from {
    transform: translateX(100%);
    opacity: 0;
  }
  to {
    transform: translateX(0);
    opacity: 1;
  }
}

/* Navigation Styles */
.main-navigation {
  background: white;
  box-shadow: var(--box-shadow);
  position: sticky;
  top: 0;
  z-index: 100;
}

.nav-container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 0 1rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 4rem;
}

.nav-brand a {
  font-size: 1.5rem;
  font-weight: bold;
  color: var(--primary-color);
  text-decoration: none;
}

.nav-menu {
  display: flex;
  align-items: center;
  gap: 2rem;
}

.nav-links {
  display: flex;
  gap: 1.5rem;
}

.nav-link {
  color: var(--gray-700);
  text-decoration: none;
  font-weight: 500;
  padding: 0.5rem 0;
  position: relative;
}

.nav-link:hover {
  color: var(--primary-color);
}

/* User Menu */
.user-menu {
  position: relative;
}

.user-menu-toggle {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  background: none;
  border: none;
  cursor: pointer;
  padding: 0.5rem;
  border-radius: var(--border-radius);
  transition: background-color 0.2s;
}

.user-menu-toggle:hover {
  background-color: var(--gray-100);
}

.user-avatar {
  width: 32px;
  height: 32px;
  border-radius: 50%;
  object-fit: cover;
}

.user-dropdown {
  position: absolute;
  top: 100%;
  right: 0;
  background: white;
  border-radius: var(--border-radius);
  box-shadow: var(--box-shadow);
  min-width: 200px;
  padding: 0.5rem 0;
  display: none;
}

.user-dropdown.active {
  display: block;
}

.dropdown-item {
  display: block;
  width: 100%;
  padding: 0.75rem 1rem;
  color: var(--gray-700);
  text-decoration: none;
  background: none;
  border: none;
  text-align: left;
  cursor: pointer;
  transition: background-color 0.2s;
}

.dropdown-item:hover {
  background-color: var(--gray-50);
}

.dropdown-divider {
  margin: 0.5rem 0;
  border: none;
  border-top: 1px solid var(--gray-200);
}

/* Responsive Design */
@media (max-width: 768px) {
  .nav-toggle {
    display: flex;
    flex-direction: column;
    gap: 4px;
    background: none;
    border: none;
    cursor: pointer;
    padding: 0.5rem;
  }

  .nav-toggle span {
    width: 24px;
    height: 2px;
    background-color: var(--gray-700);
    transition: all 0.3s;
  }

  .nav-menu {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    background: white;
    box-shadow: var(--box-shadow);
    flex-direction: column;
    padding: 1rem;
    display: none;
  }

  .nav-menu.active {
    display: flex;
  }

  .nav-links {
    flex-direction: column;
    gap: 1rem;
    width: 100%;
  }
}
```

This completes the comprehensive SPA implementation guide covering authentication state management, HTTP client configuration, form components, routing, error handling, and styling. The implementation provides a secure, maintainable foundation for a modern single-page application with OAuth2 authentication.