#

##

**Question**: I'm building a spring boot resource server, but its a modular modulith. This project includes modules such as user profile management, subscription, url shortening with qr codes, barcodes, landing pages, analytics, payments etc. I want you to suggest a good package structure. 

**Answer**: That’s a great use case for a **modular modulith** in Spring Boot — organizing it right from the start will save you a lot of pain as the application grows. Since you’re already following the modular approach (modulith), the package structure should reflect clear **boundaries** between modules, while still allowing for internal cohesion and encapsulation.

---

### ✅ Goals for the Package Structure:

* **High cohesion within modules**
* **Low coupling between modules**
* Clear **API vs. internal** separation per module
* **Consistency** in naming and structure
* Easy for developers to understand and navigate

---

### 📦 Suggested Top-Level Package Structure

Assuming your root package is `com.example.app`:

```
com.example.app
├── common             # Shared utilities, constants, annotations, etc.
├── infrastructure     # Configurations, security, DB, messaging, etc.
├── userprofile        # User profile management module
├── subscription       # Subscription & plan management
├── shortening         # URL shortening, QR code & barcode generation
├── landingpage        # Landing page creation and hosting
├── analytics          # Click/event tracking and analysis
├── payment            # Payment processing
└── api                # Public API entry points (REST controllers, etc.)
```

---

### 📦 Internal Structure per Module

Each module (like `userprofile`, `shortening`, etc.) should follow a **DDD-inspired substructure** internally:

```
com.example.app.userprofile
├── application        # Application services / use cases
├── domain             # Domain model (entities, value objects, aggregates)
├── infrastructure     # Module-specific infrastructure (e.g., repositories, adapters)
├── interfaces         # REST controllers or external interfaces (if separated from `api`)
└── config             # Module-specific config if needed
```

> 🔄 Depending on your API exposure strategy, you might keep all REST controllers in `com.example.app.api`, or co-locate them in each module under `interfaces`.

---

### 💡 Example: `shortening` module

```
com.example.app.shortening
├── application
│   └── ShortenUrlService.java
├── domain
│   ├── UrlShortener.java
│   ├── ShortenedUrl.java
│   └── QrCode.java
├── infrastructure
│   ├── JpaShortenedUrlRepository.java
│   └── QrCodeGenerator.java
├── interfaces
│   └── ShorteningController.java
└── config
    └── ShorteningModuleConfig.java
```

---

### 📦 `common` & `infrastructure` Modules

* `common`: Reusable pieces (e.g., exception handling, DTOs, custom annotations)
* `infrastructure`: Application-wide configuration, security setup, database config, external system integrations (e.g., Stripe, mail services)

Example:

```
com.example.app.common
├── exceptions
├── dto
└── utils

com.example.app.infrastructure
├── security
├── database
├── events
└── messaging
```

---

### 🔐 Special Note on Security in a Resource Server

* Consider a `security` subpackage under `infrastructure` for configuring your Spring Security resource server, including:

  * JWT decoder
  * OAuth2 resource server config
  * Method-level security

Example:

```
com.example.app.infrastructure.security
├── ResourceServerConfig.java
├── JwtAuthenticationConverter.java
└── MethodSecurityConfig.java
```

---

### 🧩 Modulith-Friendly Practices

* Use **Spring Modulith** (or `spring-modulith` dependency) to enforce module boundaries
* Annotate each module’s main config with `@ApplicationModule`
* Separate module APIs using Spring’s `@RestController` or `@EventListener` within the module
* Use **domain events** for cross-module communication (avoiding tight coupling)

---

### ✅ Summary Checklist

* ✅ One top-level package per **bounded context**
* ✅ Uniform structure per module: `application`, `domain`, `infrastructure`, `interfaces`, `config`
* ✅ Common code in `common` module
* ✅ Shared infrastructure/configs in `infrastructure`
* ✅ Clear REST API strategy — centralized or per-module
* ✅ Use domain events for inter-module communication

Would you like me to scaffold this out with actual Java packages and files as an example?

##

**Question**: Can you please expain the functionalities of each classes that you have listed below?

```
com.example.app.shortening
├── application
│   └── ShortenUrlService.java
├── domain
│   ├── UrlShortener.java
│   ├── ShortenedUrl.java
│   └── QrCode.java
├── infrastructure
│   ├── JpaShortenedUrlRepository.java
│   └── QrCodeGenerator.java
├── interfaces
│   └── ShorteningController.java
└── config
    └── ShorteningModuleConfig.java
```

**Answer**: Absolutely — let’s walk through the `shortening` module's package and class structure and explain the **functionality and responsibility** of each class or component I mentioned. This structure follows **domain-driven design (DDD)** and **clean architecture** principles.

---

## 📦 `com.example.app.shortening` Package Overview

```
com.example.app.shortening
├── application
│   └── ShortenUrlService.java
├── domain
│   ├── UrlShortener.java
│   ├── ShortenedUrl.java
│   └── QrCode.java
├── infrastructure
│   ├── JpaShortenedUrlRepository.java
│   └── QrCodeGenerator.java
├── interfaces
│   └── ShorteningController.java
└── config
    └── ShorteningModuleConfig.java
```

---

## 📂 `application` Package

**Purpose**: Contains the *application layer* (aka *use cases*), coordinating between domain logic and infrastructure.

### 🔹 `ShortenUrlService.java`

* **Responsibility**: Orchestrates the use case of shortening a URL and generating a QR code.
* **Depends on**: Domain services, repositories, infrastructure components
* **Methods might include**:

  ```java
  public ShortenedUrlResponse shorten(String originalUrl);
  public QrCodeResponse generateQrCode(String shortenedUrl);
  ```
* **Typical flow**:

  * Validate input
  * Call `UrlShortener` (domain logic)
  * Persist result using `JpaShortenedUrlRepository`
  * Call `QrCodeGenerator` to generate QR code
  * Return response DTO

---

## 📂 `domain` Package

**Purpose**: Contains the *core business logic*. Should have no dependencies on other layers.

### 🔹 `ShortenedUrl.java`

* **Entity or Aggregate Root**
* Represents a shortened URL
* **Fields**: `id`, `originalUrl`, `shortenedKey`, `createdAt`, `expirationDate`, etc.
* **Behavior**:

  * `isExpired()`
  * `getRedirectUrl()`

### 🔹 `UrlShortener.java`

* **Domain service**
* Contains logic for generating a shortened key (e.g., hashing, random ID, base62 encoding)
* Responsible for ensuring uniqueness or handling collisions
* Might look like:

  ```java
  public class UrlShortener {
      public String generateShortKey(String originalUrl);
  }
  ```

### 🔹 `QrCode.java`

* **Value Object**
* Encapsulates QR code metadata
* Fields like: `byte[] imageData`, `format`, `size`
* Immutable; no identity

---

## 📂 `infrastructure` Package

**Purpose**: Contains technical implementations like repositories, external APIs, and system utilities.

### 🔹 `JpaShortenedUrlRepository.java`

* **Spring Data JPA Repository**
* Handles persistence of `ShortenedUrl` entities
* Interface might look like:

  ```java
  public interface JpaShortenedUrlRepository extends JpaRepository<ShortenedUrl, UUID> {
      Optional<ShortenedUrl> findByShortenedKey(String key);
  }
  ```

### 🔹 `QrCodeGenerator.java`

* **Utility or service for QR code generation**
* Likely uses libraries like ZXing or QRGen
* Converts shortened URL into a QR code image
* Example:

  ```java
  public class QrCodeGenerator {
      public QrCode generate(String url);
  }
  ```

---

## 📂 `interfaces` Package

**Purpose**: Exposes the module’s functionality to the outside world (REST API, GraphQL, etc.)

### 🔹 `ShorteningController.java`

* **REST controller**
* Handles incoming HTTP requests like:

  * `POST /shorten` — to shorten a URL
  * `GET /qr/{shortKey}` — to fetch a QR code
* Delegates logic to `ShortenUrlService`
* Handles input/output mapping (DTOs)

---

## 📂 `config` Package

**Purpose**: Holds module-specific Spring configuration

### 🔹 `ShorteningModuleConfig.java`

* **Spring @Configuration class**
* Configures beans needed by the module
* Could include:

  * Bean definitions for domain services
  * Conditional configuration
  * Module-specific properties binding
* May also be annotated with `@ApplicationModule` if using [Spring Modulith](https://docs.spring.io/spring-modulith/docs/current/reference/html/)

---

## ✅ Typical Flow

Here’s what happens when a user shortens a URL:

1. `ShorteningController` receives a POST request.
2. It calls `ShortenUrlService.shorten(...)`.
3. `ShortenUrlService` delegates to:

   * `UrlShortener` to create a unique short key.
   * `JpaShortenedUrlRepository` to persist the new `ShortenedUrl`.
   * `QrCodeGenerator` to create a QR code.
4. The controller returns the response (shortened URL + QR image).

---

## Optional Enhancements

* `ShortenedUrlEvent.java` in `domain.events` (to emit events like `UrlShortenedEvent`)
* `QrCodeCacheService` in `infrastructure` to cache QR images
* `VisitTrackingService` in `analytics` module that listens for redirect events

---

Would you like a similar breakdown for another module, like `analytics` or `subscription`? Or do you want a skeleton project scaffolding for this?

## 

**Question**: What about ports and adapter pattern? 

**Answer**: Excellent — if you're leaning toward **Hexagonal Architecture** (also known as **Ports and Adapters**), that’s a great choice for maintainability, testability, and decoupling. It works beautifully with **Spring Modulith** and fits naturally with the modular package structure you're building.

Let me walk you through how to **map Ports and Adapters** into your Spring Boot **modular modulith**, and how it aligns with what we already discussed.

---

## 🔁 What is the Ports and Adapters Pattern?

In **Hexagonal Architecture**, the system is viewed as having:

* **Core logic (the Application + Domain)**
* Communicating with the **outside world** (DBs, REST APIs, messaging, external services) through:

  * **Ports**: Interfaces defining input/output
  * **Adapters**: Implementations of those interfaces for specific technologies

So:

* **Ports** are the *contracts*
* **Adapters** are the *implementations*
* Your core logic **depends on abstractions**, never on frameworks or infrastructure

---

## 🔍 Adapting It to Your Module Structure

Let’s map the previous structure into a **Ports and Adapters** structure for the `shortening` module.

---

### 📦 Suggested Package Structure (`shortening` module):

```
com.example.app.shortening
├── domain               # Entities, value objects, and domain services
│   ├── model
│   └── service
├── application          # Use cases (input ports) and application services
│   └── port
│       ├── in           # Input ports (interfaces for use cases)
│       └── out          # Output ports (interfaces for external dependencies)
├── adapter              # Adapters for driving and driven sides
│   ├── in               # Controllers (REST, GraphQL, CLI, etc.)
│   └── out              # Persistence, QR code generators, messaging
├── config               # Spring @Configuration classes
└── ShorteningModule.java  # (Optional) Module root entry point
```

---

## 🧩 Explanation of Each Layer

### 1. `domain.model` & `domain.service`

This is your **pure business logic**.

* `ShortenedUrl.java` – Aggregate Root / Entity
* `QrCode.java` – Value Object
* `UrlShortener.java` – Domain service (pure logic, e.g. for generating a short key)

No framework dependencies here.

---

### 2. `application.port.in`

**Input Ports**: define **use cases** that the system exposes. These are interfaces.

```java
public interface ShortenUrlUseCase {
    ShortenedUrlResponse shorten(ShortenUrlCommand command);
}
```

The `ShortenUrlService` class will implement this.

---

### 3. `application.port.out`

**Output Ports**: define **dependencies** the core needs, like saving to DB or generating QR codes.

```java
public interface UrlRepository {
    void save(ShortenedUrl url);
    Optional<ShortenedUrl> findByKey(String key);
}

public interface QrCodeService {
    QrCode generate(String url);
}
```

The core depends **only on these abstractions** — not on Spring, not on JPA, not on ZXing, etc.

---

### 4. `application` (the Service Layer)

This is where the orchestration happens. Implements **input ports**, and uses **output ports**.

```java
public class ShortenUrlService implements ShortenUrlUseCase {

    private final UrlShortener urlShortener;
    private final UrlRepository urlRepository;
    private final QrCodeService qrCodeService;

    public ShortenUrlService(UrlShortener urlShortener, UrlRepository urlRepository, QrCodeService qrCodeService) {
        this.urlShortener = urlShortener;
        this.urlRepository = urlRepository;
        this.qrCodeService = qrCodeService;
    }

    public ShortenedUrlResponse shorten(ShortenUrlCommand command) {
        String key = urlShortener.generateShortKey(command.getOriginalUrl());
        ShortenedUrl entity = new ShortenedUrl(command.getOriginalUrl(), key);
        urlRepository.save(entity);
        QrCode qr = qrCodeService.generate(entity.getFullUrl());
        return new ShortenedUrlResponse(entity.getFullUrl(), qr.getImage());
    }
}
```

---

### 5. `adapter.in`

**Driving adapters** — external entry points like REST controllers:

```java
@RestController
public class ShorteningController {

    private final ShortenUrlUseCase useCase;

    public ShorteningController(ShortenUrlUseCase useCase) {
        this.useCase = useCase;
    }

    @PostMapping("/shorten")
    public ResponseEntity<ShortenedUrlResponse> shorten(@RequestBody ShortenUrlRequest request) {
        return ResponseEntity.ok(
            useCase.shorten(new ShortenUrlCommand(request.getUrl()))
        );
    }
}
```

> 🎯 This class depends only on the **input port**, never directly on the service or domain.

---

### 6. `adapter.out`

**Driven adapters** — implementations of output ports.

#### a. `JpaUrlRepositoryAdapter`

```java
@Repository
public class JpaUrlRepositoryAdapter implements UrlRepository {

    private final JpaShortenedUrlRepository jpaRepo;

    public JpaUrlRepositoryAdapter(JpaShortenedUrlRepository jpaRepo) {
        this.jpaRepo = jpaRepo;
    }

    @Override
    public void save(ShortenedUrl url) {
        jpaRepo.save(url);
    }

    @Override
    public Optional<ShortenedUrl> findByKey(String key) {
        return jpaRepo.findByShortenedKey(key);
    }
}
```

#### b. `ZxingQrCodeServiceAdapter`

```java
@Component
public class ZxingQrCodeServiceAdapter implements QrCodeService {

    public QrCode generate(String url) {
        // use ZXing to generate QR code and wrap it in a QrCode VO
    }
}
```

---

### 7. `config` / `ShorteningModuleConfig.java`

Here you wire it all together using Spring’s DI:

```java
@Configuration
public class ShorteningModuleConfig {

    @Bean
    public ShortenUrlUseCase shortenUrlUseCase(
            UrlShortener urlShortener,
            UrlRepository urlRepository,
            QrCodeService qrCodeService
    ) {
        return new ShortenUrlService(urlShortener, urlRepository, qrCodeService);
    }

    @Bean
    public UrlShortener urlShortener() {
        return new UrlShortener(); // pure domain service
    }
}
```

---

## ✅ Benefits of This Approach

| Advantage                 | Explanation                                                                       |
| ------------------------- | --------------------------------------------------------------------------------- |
| 🔌 **Pluggable**          | Easily swap adapters — e.g., replace ZXing with another QR generator              |
| 🧪 **Testable**           | You can test the application layer with mocks/stubs for the ports                 |
| 🔄 **Modular**            | Clearly separates concerns and works well with Spring Modulith                    |
| 🔐 **No framework bleed** | Domain and application layers have **zero** dependency on Spring or JPA           |
| 🧭 **Navigable**          | Easy to locate functionality based on whether it’s a port, adapter, or core logic |

---

## 🧱 Summary

### Module (`shortening`) layers:

```
- domain            ← Core entities and logic
- application.port  ← Contracts (in/out)
- application       ← Implements use cases
- adapter.in        ← REST Controller
- adapter.out       ← DB, QR generator
- config            ← Bean wiring
```

Would you like me to scaffold this architecture (classes + packages) as a sample Java structure in a zip or GitHub repo? Or do you want the same breakdown for other modules like `payment` or `analytics`?

## 

**Question**: Where do I check for user subscription and user limits, I mean which layer?

**Answer**: Great question — checking for **user subscriptions and usage limits** is a **cross-cutting concern** that affects your business logic but depends on external or shared data (like subscription status, quotas, etc.).

In a **Hexagonal Architecture** (Ports & Adapters) setup like yours, the **check for user subscription and limits should happen in the Application Layer**, but with proper boundaries. Let’s break this down in a clean and scalable way.

---

## ✅ TL;DR Answer

| Responsibility                                  | Layer                                      |
| ----------------------------------------------- | ------------------------------------------ |
| Define what a limit or subscription check means | **Domain Layer** (policy)                  |
| Perform the check using current data            | **Application Layer** (use case / service) |
| Fetch user subscription/usage data              | **Adapter via Output Port**                |

---

## 💡 Where to Put Subscription & Limit Checks

Let’s say your `shortening` module needs to check:

* Is the user allowed to shorten another URL?
* Do they have an active subscription?
* Have they exceeded their monthly quota?

### ✔️ 1. **Domain Layer** — *Policy/Rule Definition*

Define a **policy** in the domain that expresses **the rule**, without knowing how the data is retrieved:

```java
public class UrlShorteningPolicy {

    private final int maxUrlsPerMonth;

    public UrlShorteningPolicy(int maxUrlsPerMonth) {
        this.maxUrlsPerMonth = maxUrlsPerMonth;
    }

    public boolean canShorten(int currentUsage) {
        return currentUsage < maxUrlsPerMonth;
    }
}
```

> The domain says *what* the rule is — not *how* to check it.

---

### ✔️ 2. **Application Layer** — *Use Case Orchestration*

In `ShortenUrlService`, before proceeding, you:

* Call a **UserSubscriptionService (output port)** to fetch current subscription + usage
* Apply the `UrlShorteningPolicy` to check if they are allowed

```java
public class ShortenUrlService implements ShortenUrlUseCase {

    private final UserSubscriptionPort subscriptionPort;
    private final UrlShorteningPolicyFactory policyFactory;

    public ShortenedUrlResponse shorten(ShortenUrlCommand command) {
        UserSubscription sub = subscriptionPort.getUserSubscription(command.userId());
        int currentUsage = subscriptionPort.getUsageThisMonth(command.userId());

        UrlShorteningPolicy policy = policyFactory.forPlan(sub.getPlan());
        if (!policy.canShorten(currentUsage)) {
            throw new SubscriptionLimitExceededException();
        }

        // proceed with shortening...
    }
}
```

---

### ✔️ 3. **Output Port + Adapter** — *Accessing User Subscription Data*

Define an output port interface:

```java
public interface UserSubscriptionPort {
    UserSubscription getUserSubscription(UUID userId);
    int getUsageThisMonth(UUID userId);
}
```

Implement it in an adapter that talks to the `subscription` module or service:

```java
@Component
public class SubscriptionModuleAdapter implements UserSubscriptionPort {
    // inject repo or REST client to subscription module

    public UserSubscription getUserSubscription(UUID userId) {
        // fetch from subscription module or database
    }

    public int getUsageThisMonth(UUID userId) {
        // fetch usage stats from analytics or usage DB
    }
}
```

---

## 🧠 Why Not in the Controller?

Because:

* Subscription logic is **business logic**, not delivery logic
* You may later use the same use case from another interface (CLI, REST, scheduler)
* Reuse and testability — application layer is easier to test

---

## 🔄 Bonus: Cross-Module Communication

If `userprofile` or `subscription` is a separate Spring Modulith module, you can use:

* `@EventListener` for async events (e.g., on subscription upgrade)
* Or call a **facade/service from another module** if tight consistency is required

> Just be sure to call **ports**, not internal service classes.

---

## 🧱 Summary

| Task                                | Layer                              |
| ----------------------------------- | ---------------------------------- |
| Define rules like “max X per month” | **Domain (policy)**                |
| Enforce the rule                    | **Application (use case/service)** |
| Get subscription or usage data      | **Adapter (via output port)**      |
| Validate in controller?             | ❌ No — delegate to use case        |

---

Would you like a concrete code example or skeleton implementation for this subscription check integration?


## 

**Question**: Yes user profile and/or subscription are separate modules in the same project.



**Answer**: Perfect — since **user profile** and **subscription** are separate **modules within the same Spring Boot modulith**, you can leverage **direct module-to-module communication** through **application-level ports**, **module APIs**, or **domain events**, while still preserving strong modular boundaries.

Let’s walk through **how to design and implement subscription/limit checking between modules** within a modulith using **Hexagonal Architecture + Spring Modulith best practices**.

---

## ✅ Goal

Your `shortening` module wants to:

* Ask the `subscription` module:

  > *“Can user X shorten a URL?”*
* Based on:

  * Subscription plan
  * Usage limits

---

## ✅ Design Summary

| Layer                                              | Responsibility                                 |
| -------------------------------------------------- | ---------------------------------------------- |
| `shortening` → **Application Layer**               | Triggers the rule check                        |
| `shortening` → **Output Port**                     | Defines the contract to talk to another module |
| `subscription` → **Adapter / Application Service** | Implements the contract, handles the check     |
| `subscription` → **Domain Layer**                  | Defines business logic for limits              |

---

## 📦 Suggested Architecture

### 📁 `shortening` module

```
com.example.app.shortening
├── application
│   ├── port
│   │   └── out
│   │       └── SubscriptionAccessPort.java   <-- OUTPUT PORT
│   └── ShortenUrlService.java                <-- Uses port
└── config
    └── ShorteningModuleConfig.java
```

### 📁 `subscription` module

```
com.example.app.subscription
├── application
│   ├── port
│   │   └── in
│   │       └── SubscriptionQueryUseCase.java     <-- INPUT PORT
│   └── SubscriptionService.java                  <-- Implements use case
├── domain
│   └── PlanLimitPolicy.java                      <-- Business logic
└── adapter
    └── in
        └── ShorteningSubscriptionAdapter.java    <-- Implements shortening port
```

---

## 🔁 FLOW

### 1. `shortening` defines an output port:

```java
public interface SubscriptionAccessPort {
    boolean canUserShortenUrl(UUID userId);
}
```

---

### 2. `shortening` service uses it:

```java
public class ShortenUrlService implements ShortenUrlUseCase {

    private final SubscriptionAccessPort subscriptionPort;

    public ShortenUrlResponse shorten(ShortenUrlCommand command) {
        if (!subscriptionPort.canUserShortenUrl(command.userId())) {
            throw new SubscriptionLimitExceededException();
        }

        // continue shortening...
    }
}
```

---

### 3. `subscription` module defines input port (use case):

```java
public interface SubscriptionQueryUseCase {
    boolean canUserShortenUrl(UUID userId);
}
```

---

### 4. Implements logic in `SubscriptionService`:

```java
public class SubscriptionService implements SubscriptionQueryUseCase {

    private final SubscriptionRepository repo;
    private final UsageTracker usageTracker;

    public boolean canUserShortenUrl(UUID userId) {
        SubscriptionPlan plan = repo.getPlanForUser(userId);
        int used = usageTracker.getMonthlyUrlShorteningCount(userId);
        return plan.getLimit().canShorten(used);  // domain logic
    }
}
```

---

### 5. `subscription` module implements the output port from `shortening`

```java
@Component
public class ShorteningSubscriptionAdapter implements SubscriptionAccessPort {

    private final SubscriptionQueryUseCase subscriptionUseCase;

    public boolean canUserShortenUrl(UUID userId) {
        return subscriptionUseCase.canUserShortenUrl(userId);
    }
}
```

> 💡 This adapter class **lives in `subscription`** but **implements the port defined in `shortening`**, establishing a clear module boundary.

---

## ✅ Wiring the Modules (Spring DI)

In `SubscriptionModuleConfig.java`:

```java
@Configuration
public class SubscriptionModuleConfig {

    @Bean
    public SubscriptionQueryUseCase subscriptionService(...) {
        return new SubscriptionService(...);
    }

    @Bean
    public SubscriptionAccessPort shorteningSubscriptionAdapter(
        SubscriptionQueryUseCase useCase
    ) {
        return new ShorteningSubscriptionAdapter(useCase);
    }
}
```

Spring will inject `SubscriptionAccessPort` into the `shortening` module without tight coupling.

---

## 🔒 Optional: Enforce Boundaries with `spring-modulith`

If you’re using [**Spring Modulith**](https://docs.spring.io/spring-modulith/), annotate your module configs with:

```java
@ApplicationModule(
    allowedDependencies = { "subscription", "userprofile" }
)
```

Run `ApplicationModules.of(MyApp.class).verify();` in a test to ensure boundaries.

---

## 🧠 Summary

| Concept       | Where                                                       | Notes                                         |
| ------------- | ----------------------------------------------------------- | --------------------------------------------- |
| Output port   | `shortening.application.port.out.SubscriptionAccessPort`    | Abstraction for subscription check            |
| Input port    | `subscription.application.port.in.SubscriptionQueryUseCase` | Implements business logic                     |
| Adapter       | `subscription.adapter.in.ShorteningSubscriptionAdapter`     | Bridges `shortening`'s port to `subscription` |
| Policy / rule | `subscription.domain.PlanLimitPolicy`                       | Pure logic like `canShorten(int usage)`       |

---

Would you like me to generate a sample folder + class structure (in text or zip) showing this entire flow across both modules?
