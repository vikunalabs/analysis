Your `build.gradle` looks good, but there are a few adjustments needed for JitPack to work properly:

## Issues to Fix:

1. **Group ID format**: JitPack expects `com.github.YourUsername` format
2. **Missing `settings.gradle`**: Required for JitPack to identify the project
3. **Missing source/javadoc jars**: Good practice for library distribution
4. **Version format**: SNAPSHOT versions might cause issues with JitPack

## Updated build.gradle:

```gradle
plugins {
    id 'java-library'
    id 'maven-publish'
    id 'com.diffplug.spotless' version '7.1.0'
}

// ✅ FIXED: JitPack requires this specific group format
group = 'com.github.vikunalabs'  // Changed from 'com.github.vikunalabs.libs'
version = '0.0.1'  // ✅ REMOVED -SNAPSHOT (JitPack works better with stable versions)

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(21)
    }
    // ✅ ADDED: Generate sources and javadoc jars for better library experience
    withSourcesJar()
    withJavadocJar()
}

configurations {
    compileOnly {
        extendsFrom annotationProcessor
    }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation 'io.swagger.core.v3:swagger-annotations:2.2.35'
    implementation 'com.fasterxml.jackson.core:jackson-annotations:2.18.0'
    compileOnly 'org.projectlombok:lombok:1.18.38'
    annotationProcessor 'org.projectlombok:lombok:1.18.38'
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.0'
    testImplementation 'org.springframework.boot:spring-boot-starter-test:3.2.0'
    testImplementation 'org.springframework.boot:spring-boot-starter-web:3.2.0'
}

tasks.named('test') {
    useJUnitPlatform()
}

// ✅ ADDED: Publishing configuration for JitPack
publishing {
    publications {
        mavenJava(MavenPublication) {
            from components.java
            // Optional: Add POM metadata
            pom {
                name = 'API Response Library'
                description = 'Standardized API response library for Java projects'
                url = 'https://github.com/vikunalabs/libs'
                licenses {
                    license {
                        name = 'MIT License'
                        url = 'https://opensource.org/licenses/MIT'
                    }
                }
            }
        }
    }
}

// Spotless configuration
spotless {
    java {
        target fileTree('src') {
            include '**/*.java'
            exclude '**/build/**', '**/build-*/**'
        }
        toggleOffOn()
        palantirJavaFormat()
        removeUnusedImports()
        trimTrailingWhitespace()
        endWithNewline()
        importOrder()
        formatAnnotations()
    }
}

tasks.compileJava.dependsOn(spotlessApply)
tasks.compileTestJava.dependsOn(spotlessApply)

// ✅ ADDED: Ensure build task runs tests and spotless
tasks.build.dependsOn(test, spotlessApply)
```

## Step 2: Create settings.gradle

Create a `settings.gradle` file in the root directory:

```gradle
// ✅ REQUIRED for JitPack
rootProject.name = 'libs'  // This should match your repository name

// If you have multiple modules, add them here
// include 'api-response-core'
// include 'api-response-spring'
```

## Step 3: Project Structure

Make sure your project structure looks like this:
```
libs/ (repository root)
├── build.gradle
├── settings.gradle
├── gradle.properties (optional)
└── src/
    └── main/
        └── java/
            └── com/
                └── vikunalabs/
                    └── libs/
                        └── api/
                            └── core/
                                └── model/
                                    ├── FieldError.java
                                    ├── APICode.java
                                    ├── APIResponse.java
                                    ├── BaseAPICode.java
                                    └── APIError.java
```

## Step 4: Create a GitHub Release

```bash
# Commit your changes
git add build.gradle settings.gradle
git commit -m "Configure for JitPack"
git push origin main

# Create and push a tag
git tag -a v0.0.1 -m "Version 0.0.1"
git push origin v0.0.1
```

## Step 5: Usage in Spring Project

In your Spring project's `build.gradle`:

```gradle
repositories {
    mavenCentral()
    maven { url 'https://jitpack.io' }
}

dependencies {
    implementation 'com.github.vikunalabs:libs:v0.0.1'
    
    // If you have Lombok in your library, add these too:
    compileOnly 'org.projectlombok:lombok:1.18.38'
    annotationProcessor 'org.projectlombok:lombok:1.18.38'
}
```

## Important Notes:

1. **Repository Name**: JitPack uses your GitHub repository name (`libs`)
2. **Group Format**: Must be `com.github.vikunalabs` (not `com.github.vikunalabs.libs`)
3. **First Build**: The first build on JitPack might take 2-5 minutes
4. **Check Build**: Visit `https://jitpack.io/#vikunalabs/libs` to see build status

## Testing:

After pushing, go to: `https://jitpack.io/#vikunalabs/libs`
- Wait for the build to complete (green checkmark)
- If it fails, check the build logs on JitPack

Your updated configuration should work with JitPack! The changes I made ensure proper group naming and add the necessary configuration for library publishing.
