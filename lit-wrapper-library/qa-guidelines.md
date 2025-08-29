# QA

## QA1

**Question**

Hi, I want to develop a SPA using Vite + Vanilla TS. I want to understand the benefits of the below,

Use Lit to build UI vs create a wrapper library on top of Lit and use this wrapper in the project?

From long term perspective, I want to build multiple projects, I feel wrapper ui-library would help, but really not sure what functionalities should I add into this wrapper library?

**Answer**

Excellent question. This is a very forward-thinking approach for a Vanilla TS SPA, and you're right to consider the long-term architectural implications.

Let's break down the benefits of each approach and, most importantly, what your wrapper library should contain.

### Direct Lit Usage: The Quick Start

**Benefits:**
1.  **Simplicity & Speed:** You start building UI components immediately. No upfront cost of designing and building an abstraction layer.
2.  **Full Power & Flexibility:** You have direct access to the entire Lit API. You can use any feature, workaround, or lifecycle method without being constrained by your wrapper's design.
3.  **Easier Debugging:** Stack traces and errors point directly to your code and the Lit source, not an intermediate layer. This is simpler for a single project.
4.  **No Overhead:** There is zero abstraction overhead. Your components are Lit components, pure and simple.

**Drawbacks:**
1.  **Vendor Lock-in:** All your component code is tightly coupled to Lit. If you ever wanted to change the underlying technology (e.g., move to Stencil, Solid, or a custom solution), the migration would be a massive, painful rewrite of every component.
2.  **Inconsistency:** Across multiple projects, different developers might use different Lit patterns, leading to an inconsistent codebase.
3.  **Boilerplate:** You'll likely end up repeating the same patterns (e.g., for theming, validation, common properties) in every project.

---

### Wrapper Library: The Strategic Investment

**Benefits:**
1.  **Technology Agnosticism (The Biggest Win):** This is the primary reason to do this. Your wrapper library defines **your** company's/team's component interface. The fact that it's implemented with Lit is an implementation detail. If in 3 years Lit becomes obsolete or a better technology emerges, you only need to re-write the **wrapper library's components**, not every single project that uses them. The applications themselves only interface with your stable, abstracted API.
2.  **Consistency & Standardization:** You enforce a single, unified way of doing things. All buttons *will* have a `size` prop that *only* accepts `'sm' | 'md' | 'lg'`. All components *will* emit events with the same naming convention. This is invaluable across multiple teams and projects.
3.  **Reduced Boilerplate:** The wrapper can encapsulate common logic. For example, every input component can automatically integrate with your form validation library, without the app developer having to wire it up every time.
4.  **Centralized Maintenance:** A bug fix, security patch, or design tweak (e.g., changing the color of all error states) is made in one place (the wrapper library) and instantly benefits all consuming projects upon update.
5.  **Simplified API:** You can hide Lit's complexity. Your app developers don't need to know about `@property`, `@state`, or the `render()` method. They just need to know your simple, well-documented API.

**Drawbacks:**
1.  **Upfront Investment:** It requires significant design and development time before you can write your first application component.
2.  **Abstraction Layer:** Adds a layer of complexity. Debugging might require jumping into the wrapper library code.
3.  **Potential for Bloat:** If not designed carefully, the wrapper can become a "kitchen sink" that is difficult to maintain.

---

### What Should Your Wrapper Library Contain? (The Blueprint)

Your wrapper library shouldn't just be a rename of Lit elements. It should be a curated, opinionated framework for building UIs *your way*.

#### 1. Foundation: The Base Class
Create an abstract base class that extends `LitElement`. This is where you put all your common logic.
```typescript
// ui-library/src/base-element.ts
import { LitElement, PropertyValues } from 'lit';

export abstract class UiElement extends LitElement {
  // 1. Theming: Integrate a centralized theme solution
  static override styles = [yourGlobalThemeStyles];

  // 2. Standard Properties
  @property({ type: Boolean }) disabled = false;
  @property({ type: String }) size: 'small' | 'medium' | 'large' = 'medium';
  @property({ type: String }) variant: 'primary' | 'secondary' | 'outline' = 'primary';

  // 3. Common Lifecycle Hooks
  // e.g., Add logging for all components, performance metrics, etc.
  protected override updated(_changedProperties: PropertyValues) {
    super.updated(_changedProperties);
    if (_changedProperties.has('disabled')) {
      this._handleDisabledChange();
    }
  }

  // 4. Common Methods
  protected _emitEvent(name: string, detail?: any) {
    this.dispatchEvent(new CustomEvent(name, { 
      bubbles: true, 
      composed: true, 
      detail 
    }));
  }

  // 5. Standardized Styling Logic
  protected _getSizeClass() {
    return `size--${this.size}`;
  }
  // ... other helpers
}
```

#### 2. Design System Components
Build your core components on top of the `UiElement` base class.
*   **Basic Inputs:** `Button`, `Checkbox`, `InputText`, `Select`, `Radio`
*   **Surfaces:** `Card`, `Modal`, `Dialog`, `Tooltip`
*   **Layout:** `Box`, `Grid`, `Stack` (This is hugely beneficial for consistent spacing)
*   **Data Display:** `Table`, `Badge`, `Spinner`

**Example (Simplified Button):**
```typescript
// ui-library/src/button/button.ts
import { UiElement } from '../base-element.js';
import { buttonStyles } from './button.styles.js';

export class Button extends UiElement {
  static styles = [buttonStyles];

  @property() label = '';
  @property() icon = '';

  render() {
    return html`
      <button 
        class=${this._getSizeClass()} 
        ?disabled=${this.disabled}
        @click=${this._handleClick}
      >
        ${this.icon ? html`<ui-icon name=${this.icon}></ui-icon>` : ''}
        ${this.label}
      </button>
    `;
  }

  private _handleClick() {
    if (!this.disabled) {
      this._emitEvent('ui-click'); // Use your standardized event emitter
    }
  }
}
```

#### 3. Utility Functions & Services
*   **Form Validation:** A set of reusable validators (`required`, `email`, `minLength`) and a way to easily plug them into your input components.
*   **Theme Service:** A class that holds the current theme (e.g., `light`/`dark`) and provides reactive updates to all components. Your base class can connect to this.
*   **Internationalization (i18n):** If needed, a system for translating text within components.

#### 4. Strict TypeScript Conventions
This is critical. Your library's power comes from its strict contracts.
*   Define and export all possible types for properties (e.g., `type ButtonVariant = 'primary' | 'secondary' | 'outline';`).
*   Use `interface` for all event details.

### Recommendation

For your goal of building **multiple projects in the long term**, the **wrapper library approach is unequivocally the right choice.**

The initial investment will pay for itself many times over through:
*   **Dramatically faster development** of new applications.
*   **Unified user experience** across all products.
*   **Massively reduced maintenance cost.**

**Start Small:** You don't need to build the entire Material Design system on day one. Start with the 5-10 most crucial components (Button, Input, Modal, Card) and the base class. Build your first SPA using these. As the SPA needs a new component, you build it in the wrapper library first, then use it. This iterative approach ensures your library is driven by real-world needs and doesn't become bloated with unused abstractions.


## QA2

**Question**
Can you please give me guidelines or inputs for building a wrapper ui library using Lit.

**Answer**
Of course. Building a wrapper UI library with Lit is an excellent strategic decision. Here is a comprehensive set of guidelines and inputs to help you structure, develop, and maintain it effectively.

---

### 1. Project Structure & Tooling

Start with a monorepo structure. It's ideal for managing a library and multiple consuming applications (or demo sites) in tandem.

**Recommended Structure:**
```
your-ui-library-repo/
├── packages/
│   ├── ui-library/          # The core component library
│   │   ├── src/
│   │   │   ├── components/  # Individual component directories
│   │   │   │   ├── button/
│   │   │   │   │   ├── button.ts
│   │   │   │   │   ├── button.styles.ts
│   │   │   │   │   ├── button.test.ts
│   │   │   │   │   └── index.ts
│   │   │   ├── foundations/ # Tokens, base classes, utilities
│   │   │   │   ├── themes/
│   │   │   │   ├── tokens.ts
│   │   │   │   └── base-element.ts
│   │   │   └── index.ts     # Main entry point (exports everything)
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── demo-app/            # A Vite-based SPA for development/demo
│       ├── src/
│       ├── package.json
│       └── vite.config.ts
├── package.json             # Root workspace config (using npm/yarn/pnpm workspaces)
└── README.md
```

**Essential Tooling:**
*   **Package Manager:** Use **PNPM** or **NPM** workspaces. They handle linking between packages in the monorepo seamlessly.
*   **Bundler:** Use **Vite** both for your demo app and to build the library itself (`vite build --config vite.lib.config.ts`). It's fast and outputs modern ES modules.
*   **Testing:** **Web Test Runner** (from the Modern Web project) is the gold standard for testing web components. Pair it with **@open-wc/testing** helpers (`fixture`, `expect`, `a11ySnapshot`).
*   **Linting/Formatting:** **ESLint** and **Prettier**. Use the `@open-wc/eslint-config` and `@lit/eslint-plugin` for Lit-specific rules.

---

### 2. The Foundation: Base Class and Tokens

This is the most critical part of your wrapper. Don't skip this.

#### A. Design Tokens (CSS Custom Properties)
Define your design system's raw values in a TypeScript file and generate CSS for them.
**`packages/ui-library/src/foundations/tokens.ts`**
```typescript
// Design Tokens (JS representation)
export const tokens = {
  color: {
    primary: {
      50: '#f0f9ff',
      500: '#0ea5e9',
      900: '#0c4a6e',
    },
    neutral: {
      100: '#f3f4f6',
      500: '#6b7280',
      900: '#111827',
    },
    // ... more colors, spacing, typography, radii, etc.
  },
  spacing: {
    xs: '0.25rem',
    sm: '0.5rem',
    md: '1rem',
    // ...
  },
  font: {
    size: { sm: '0.875rem', md: '1rem', lg: '1.125rem' },
    family: { body: 'Inter, sans-serif' },
  },
};

// Function to flatten and prefix tokens for CSS
export function createTheme() {
  return `
    :host, :root {
      --color-primary-500: ${tokens.color.primary[500]};
      --color-neutral-500: ${tokens.color.neutral[500]};
      --spacing-md: ${tokens.spacing.md};
      --font-size-md: ${tokens.font.size.md};
      --font-family-body: ${tokens.font.family.body};
    }
  `;
}
```

#### B. The Base Class (`UiElement`)
**`packages/ui-library/src/foundations/base-element.ts`**
```typescript
import { LitElement, PropertyValues } from 'lit';
import { createTheme } from './tokens.js';

// This is the heart of your wrapper. All components will extend this.
export class UiElement extends LitElement {
  // 1. Inject global theme tokens and base styles
  static override styles = [createTheme()];

  // 2. Standardized Properties for ALL components
  @property({ type: String, reflect: true }) theme: 'light' | 'dark' | 'auto' = 'light';
  @property({ type: Boolean, reflect: true }) disabled = false;
  @property({ type: String }) testId = ''; // For QA/testing

  // 3. Lifecycle: Apply theme to the host element
  protected override firstUpdated(_changedProperties: PropertyValues) {
    super.firstUpdated(_changedProperties);
    this._applyTheme();
  }

  // 4. Common Methods
  // Standardized event dispatch
  protected emit<T>(eventName: string, detail?: T) {
    const options = { bubbles: true, composed: true, detail };
    this.dispatchEvent(new CustomEvent(eventName, options));
  }

  // Helper to apply theme as a data-attribute for CSS selectors
  private _applyTheme() {
    const effectiveTheme = this.theme === 'auto' ? 
      (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : 
      this.theme;
    this.setAttribute('data-theme', effectiveTheme);
  }

  // Helper to generate CSS class strings based on props
  protected getClassMap(...classLists: (string | undefined)[]) {
    return classLists.filter(cls => cls != null).join(' ');
  }
}
```

---

### 3. Component Implementation Guidelines

#### A. Styling
*   **Use CSS-in-JS ( tagged template literals):** Co-locate styles with the component.
*   **Leverage Design Tokens:** Always use CSS variables from your tokens.
*   **Use `:host` and `:part()`:** Style the component itself with `:host` and expose stylable hooks with `exportparts`.

**`button.styles.ts`**
```typescript
import { css } from 'lit';

export const buttonStyles = css`
  :host {
    display: inline-block;
  }

  .button {
    font-family: var(--font-family-body);
    font-size: var(--font-size-md);
    padding: var(--spacing-md) var(--spacing-lg);
    background-color: var(--color-primary-500);
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
  }

  .button:hover:not([disabled]) {
    background-color: var(--color-primary-600);
  }

  :host([disabled]) .button {
    cursor: not-allowed;
    opacity: 0.6;
  }

  /* Variant and size styles would go here */
`;
```

#### B. The Component Class
**`button.ts`**
```typescript
import { UiElement } from '../foundations/base-element.js';
import { buttonStyles } from './button.styles.js';

export class Button extends UiElement {
  // 1. Use static styles field
  static styles = [buttonStyles];

  // 2. Define a well-typed API
  @property() label = '';
  @property() icon = '';
  @property({ type: Boolean }) loading = false;
  @property() variant: 'primary' | 'secondary' = 'primary';
  @property() size: 'sm' | 'md' | 'lg' = 'md';

  // 3. Render using your tokens and base class logic
  render() {
    return html`
      <button
        class=${this.getClassMap(
          'button',
          `button--${this.variant}`,
          `button--${this.size}`
        )}
        ?disabled=${this.disabled || this.loading}
        part="button"
        data-testid=${this.testId || 'ui-button'}
        @click=${this._handleClick}
      >
        ${this.loading ? html`<ui-spinner size="sm"></ui-spinner>` : ''}
        ${this.icon ? html`<ui-icon name=${this.icon}></ui-icon>` : ''}
        ${this.label}
      </button>
    `;
  }

  // 4. Use the base class emit method
  private _handleClick() {
    if (!this.disabled && !this.loading) {
      this.emit('ui-click', { originalTarget: this });
    }
  }
}
```

#### C. Exports
**`packages/ui-library/src/components/button/index.ts`**
```typescript
export { Button } from './button.js';
export { buttonStyles } from './button.styles.js';
// Re-export types if needed
```

**`packages/ui-library/src/index.ts` (Barrel File)**
```typescript
// Foundations
export { UiElement } from './foundations/base-element.js';
export { tokens, createTheme } from './foundations/tokens.js';

// Components
export { Button } from './components/button/index.js';
export { Icon } from './components/icon/index.js';
// ... export all other components
```

---

### 4. Documentation & Development

*   **Storybook:** **Use Storybook for your library.** It's the industry standard for developing and showcasing UI components in isolation. The `@storybook/web-components-vite` builder works perfectly with Lit and Vite.
*   **API Documentation:** Use **TypeScript** and **JSDoc** comments religiously. Tools like `@custom-elements-manifest/analyzer` can parse your components and generate a JSON manifest, which can be used by web-component-friendly tools and IDE plugins to provide autocomplete.
*   **Demo App:** Your Vite-based `demo-app` is still crucial for integration testing and proving the library works in a real application context.

---

### 5. Consumption in your SPA

In your main project (`demo-app` or another SPA), consumption becomes very clean:

```typescript
// Import from your library
import { Button, tokens } from 'ui-library';

// Define the component (or do this in your lib entry)
customElements.define('ui-button', Button);

// You can now use it in your HTML or JS
// <ui-button 
//    label="Click Me" 
//    variant="primary" 
//    @ui-click="${(e) => console.log('Clicked!', e.detail)}"
// </ui-button>
```

### Summary of Key Guidelines:

1.  **Monorepo:** Use a monorepo with workspaces.
2.  **Foundation First:** Invest heavily in a robust base class (`UiElement`) and a design token system.
3.  **Strict Typing:** Leverage TypeScript to enforce your API contract.
4.  **Standardized Patterns:** Enforce consistent patterns for styling, events, properties, and testing across all components.
5.  **Isolated Development:** Use Storybook for building components.
6.  **Automate:** Use the right tools (Vite, Web Test Runner) for building, testing, and bundling.

By following these guidelines, you'll create a scalable, maintainable, and powerful foundation for all your future projects.

## QA3

**Question**
I heard about issues with Shadow DOM form submission, does your guidelines above take care of this? Also are there more issues like this to care?

**Answer**
Excellent and very important questions. You've hit on one of the most practical pain points of using Web Components in real-world applications.

### The Shadow DOM Form Submission Problem

**The Problem:** Yes, there is a significant issue. By default, elements inside a Shadow DOM (like your `<ui-button>` or `<ui-input>`) are **not visible to the native `<form>` element's submission mechanism**.

*   A native `<form>` gathers all its form elements (`<input>`, `<select>`, `<textarea>`) by looking for elements with a `name` attribute that are its direct children or in the **light DOM**.
*   Elements inside a shadow root are encapsulated and hidden from this process. So if you have `<form><ui-input name="email"></ui-input></form>`, the form will not include the `email` value when submitted, causing it to be silently ignored.

**Do the guidelines above take care of this?**
The base guidelines provide the *foundation* to solve it, but you must actively implement the solution. Here’s how to extend the guidelines to **definitively solve this problem**:

#### The Solution: The `ElementInternals` API

The modern, standards-based solution is to use the `ElementInternals` API, which allows a web component to participate in forms natively.

**Step 1: Enhance Your `UiElement` Base Class**
```typescript
// packages/ui-library/src/foundations/base-element.ts
export class UiElement extends LitElement {
  // ... [previous code] ...

  // @ts-ignore: TypeScript might not know about `attachInternals` yet
  readonly internals: ElementInternals;

  constructor() {
    super();
    // Attach ElementInternals to the component
    // @ts-ignore
    this.internals = this.attachInternals?.();
  }

  // Optional: A common method for form-associated components to call
  protected setFormValue(value: string | FormData | null) {
    this.internals?.setFormValue(value);
  }

  // Optional: Reflect the component's validity state
  protected setValidity(flags: ValidityStateFlags, message?: string) {
    this.internals?.setValidity(flags, message);
  }
}
```

**Step 2: Build a Specialized `FormAssociatedElement` Base Class (Recommended)**
For components that need to be part of a form (Input, Select, Checkbox), create a second base class that extends `UiElement` and fully implements the form association.

```typescript
// packages/ui-library/src/foundations/form-associated-element.ts
import { UiElement } from './base-element.js';

export abstract class FormAssociatedElement extends UiElement {
  static formAssociated = true; // This is the magic flag

  // @ts-ignore
  declare internals: ElementInternals;

  @property() name: string = '';
  @property() value: string = '';

  constructor() {
    super();
    // @ts-ignore
    this.internals = this.attachInternals();
  }

  // Called when the form is reset
  formResetCallback() {
    this.value = '';
  }

  // A method to call from child components when their value changes
  protected handleValueChange(newValue: string) {
    this.value = newValue;
    this.internals.setFormValue(newValue);
    // Also fire a custom event for Lit-based form libraries to listen to
    this.emit('ui-input-change', { value: newValue });
  }
}
```

**Step 3: Implement a Form Component (e.g., `<ui-input>`)**
```typescript
// packages/ui-library/src/components/input/input.ts
import { FormAssociatedElement } from '../../foundations/form-associated-element.js';
import { inputStyles } from './input.styles.js';

export class Input extends FormAssociatedElement {
  static styles = [inputStyles];

  @property() type: 'text' | 'email' | 'password' = 'text';
  @property() placeholder: string = '';

  render() {
    return html`
      <input
        class="input"
        part="input"
        .type=${this.type}
        .value=${this.value}
        .placeholder=${this.placeholder}
        @input=${this._handleInput}
      >
    `;
  }

  private _handleInput(e: InputEvent) {
    const target = e.target as HTMLInputElement;
    this.handleValueChange(target.value); // Method from FormAssociatedElement
  }
}
```

Now, when you place `<ui-input name="email">` inside a form, it will work perfectly with native form submission, validation, and the `FormData` API.

---

### Other Critical Issues to Consider and Address

Absolutely. Here are other major issues you must design for in your wrapper library:

#### 1. Server-Side Rendering (SSR) & Hydration
*   **The Problem:** Lit components are client-side JavaScript. Without SSR, your initial page load might show empty holes where components should be (bad for SEO and perceived performance).
*   **The Solution:** The Lit team is actively working on SSR support. For now, you can use the `@lit-labs/ssr` package, but it requires a Node.js server. Plan for this by ensuring your components are mostly functional without JavaScript as a progressive enhancement. Your wrapper library should have a clear story for generating static HTML placeholders.

#### 2. Accessibility (A11y)
*   **The Problem:** It's very easy to create inaccessible components that break screen readers and keyboard navigation if you just render a `<div>` and add a `click` listener.
*   **The Solution:** This is a first-class concern, not an afterthought.
    *   **Base Class:** Bake a11y into your `UiElement`. Add standard ARIA property handling (`ariaLabel`, `ariaHidden`).
    *   **Component Contracts:** Enforce accessibility in every component.
        *   **`<ui-button>`** must render a native `<button>` or have `role="button"`, `tabindex="0"`, and respond to Enter/Spacebar keys.
        *   **`<ui-modal>`** must manage focus trapping, `aria-modal="true"`, and `aria-labelledby`.
    *   **Testing:** Use `@web/test-runner-axe` or Storybook's a11y addon to run automated accessibility tests on every component.

#### 3. Global Theming (Beyond Tokens)
*   **The Problem:** How do you switch the entire app from a light to a dark theme when your components are encapsulated in Shadow DOM? The Shadow DOM protects components from outside CSS, which breaks traditional theming.
*   **The Solution:** The guideline's use of CSS variables is the correct path. Extend it:
    *   **`:host, :root` selector** in your base style injects variables into the light DOM and each component's shadow root.
    *   Use a `data-theme="dark"` attribute on the `html` or component element and override the variable values inside your CSS.
    *   **Provide a Theme Controller:** Create a small, reactive class that holds the current theme and notifies all components (e.g., via a CSS class or a Context API). Your base class can subscribe to this controller.

#### 4. Scoped CSS and "Leaking" Styles
*   **The Problem:** Sometimes you *want* to style internal parts of your component from the outside (e.g., change the padding of a button inside a card).
*   **The Solution:** Use CSS `::part()` and `exportparts`.
    *   In your component, mark elements with `part="some-name"` (as shown in the button example: `part="button"`).
    *   In your library's documentation, clearly list the available parts for each component.
    *   Consumers can then style them from the outside: `my-card::part(button) { padding: 0; }`.

#### 5. Bundle Size and Tree-Shaking
*   **The Problem:** If you have a large library, importing the main barrel file (`import * from 'ui-library'`) could pull in all components, even if the app only uses one.
*   **The Solution:** Configure your Vite build to output **individual component files** (in addition to a bundled version). This allows for deep imports and better tree-shaking.
    *   In `vite.lib.config.ts`, ensure you don't bundle everything into a single monolithic file.
    *   In your `package.json`, point to the individual entry points:
        ```json
        {
          "main": "./my-library.js", // Bundled build
          "module": "./my-library.js", // ES Module build
          "exports": {
            "./button": "./src/components/button/index.js",
            "./input": "./src/components/input/index.js"
          }
        }
        ```
    *   This allows users to import only what they need: `import '@ui-library/button'`.

### Summary

Your initial guidelines provide the perfect architecture to **solve these problems systematically**, rather than with hacks in each project.

1.  **Form Submission:** Solve it in the **`FormAssociatedElement`** base class using `ElementInternals`.
2.  **SSR:** Plan for it by keeping components simple and staying aware of `@lit-labs/ssr`.
3.  **A11y:** Enforce it in the **`UiElement`** base class and each component's contract.
4.  **Theming:** Solve it with **CSS Variables** and a theme controller.
5.  **Styling:** Control it with **CSS Parts** (`::part()`).
6.  **Bundle Size:** Address it in your **Vite build config** and `package.json` exports.

By thinking about these issues upfront and baking the solutions into the foundation of your wrapper library, you create a truly robust, enterprise-grade tool.

## QA3

**Question**
I have another question - if a project wants to use this library and has its own UX designs, does this library provide flexiblity to add project's own CSS (or Tailwind CSS) designs?

**Answer**

Yes, this is a crucial consideration. A well-designed wrapper library must provide flexibility for consumers to adapt it to their own UX designs. Your library should act as a **foundation**, not a straitjacket.

The guidelines provided earlier actually set the stage for excellent flexibility. Here’s how a project can use your library while applying its own designs, including with Tailwind CSS.

---

### 1. The Built-in Flexibility: CSS Custom Properties (Design Tokens)

This is your **primary and most powerful** method for customization. Since your components are built using CSS variables for everything (colors, spacing, typography, etc.), a consuming project can simply override these variables at the global level to re-skin the entire library.

**How it works in practice:**

1.  **Your Library defines the tokens:**
    ```css
    /* Injected by your base element styles */
    :host, :root {
      --ui-color-primary: #0ea5e9;
      --ui-font-family: 'Inter', sans-serif;
      --ui-spacing-md: 1rem;
      --ui-border-radius: 0.25rem;
    }
    ```

2.  **The Consuming Project overrides them:**
    ```css
    /* In the main.css of the Vite SPA */
    :root {
      /* Rebrand the entire library with new colors */
      --ui-color-primary: #f97316; /* Orange instead of blue */
      --ui-color-primary-hover: #fdba74;
      
      /* Change the visual style */
      --ui-border-radius: 0.5rem;
      
      /* Change typography */
      --ui-font-family: 'Poppins', sans-serif;
    }
    ```
    Because your components' internal styles are written like `background: var(--ui-color-primary)`, they will automatically adopt the new orange color without any need to change the library's source code. This is a clean, contract-based approach.

---

### 2. Targeting Internal Parts with `::part()`

Your components should expose their internal, stylable structures using the `part` attribute.

**How it works in practice:**

1.  **Your Library exposes parts:**
    ```typescript
    // In your button component's render()
    return html`<button part="button base" class="button"><slot></slot></button>`;
    ```

2.  **The Consuming Project targets those parts:**
    ```css
    /* The project can now style the internal button */
    ui-button::part(base) {
      border-radius: 9999px; /* Make it a pill button */
      text-transform: uppercase;
      font-weight: 900;
    }
    ```
    This allows for significant structural style changes without breaking the component's functionality.

---

### 3. Using CSS Shadow Parts with Tailwind CSS

This is a common requirement. Tailwind doesn't naturally penetrate the Shadow DOM, but you can make it work with your library.

**Method 1: Using `@apply` in Component Styles (Recommended)**
The most maintainable approach is to use your library's built-in styling system. Since your tokens are CSS variables, you can define styles that feel Tailwind-like.

```css
// In your component's stylesheet
.button {
  @apply bg-[var(--ui-color-primary)] text-white py-[var(--ui-spacing-md)] px-[var(--ui-spacing-lg)] rounded-[var(--ui-border-radius)];
}
```
The consuming project would still customize the look by overriding the `--ui-*` variables, not by using Tailwind directly on the component.

**Method 2: Tailwind's `::part()` Support**
Tailwind can style shadow parts if you safelist the part names. This is more brittle but possible.

1.  **In the project's `tailwind.config.js`:**
    ```js
    module.exports = {
      content: {
        files: ['./src/**/*.{html,js,ts}', './node_modules/your-ui-library/**/*.js'],
        // This tells Tailwind to also look for `part` attributes in your library's files
      },
      // Safelist all potential parts you want to style with Tailwind
      safelist: [
        { pattern: /ui-button/ }, // careful, can be large
        // Better: safelist specific parts
        'ui-button::part(button)',
        'ui-input::part(input)'
      ]
    }
    ```
2.  **In the project's CSS:**
    ```css
    @tailwind utilities;

    @layer utilities {
      ui-button::part(button) {
        @apply rounded-full uppercase font-black; /* Now you can use Tailwind classes */
      }
    }
    ```
    **Caveat:** This can lead to a large bundle size if overused, as Tailwind will generate CSS for all those utility classes on the `::part()` selector.

---

### 4. Slots for Content and Markup

The most flexible way to handle content is through **slots**. This allows projects to inject their own HTML structure and classes.

**How it works in practice:**

1.  **Your Library uses slots:**
    ```typescript
    // A Card component
    render() {
      return html`
        <div part="base" class="card">
          <header part="header">
            <slot name="header"></slot> <!-- Project can inject its header here -->
          </header>
          <div part="body">
            <slot></slot> <!-- Default slot for main content -->
          </div>
          <footer part="footer">
            <slot name="footer"></slot>
          </footer>
        </div>
      `;
    }
    ```

2.  **The Consuming Project injects its own content with its own classes:**
    ```html
    <ui-card>
      <div slot="header" class="flex items-center justify-between">
        <h3 class="text-lg font-bold text-orange-800">My Project Header</h3>
        <span class="text-sm text-gray-500">#123</span>
      </div>
      
      <p class="text-gray-700">This is my project's content, using all my own Tailwind classes.</p>
      
      <div slot="footer" class="flex justify-end">
        <ui-button>Cancel</ui-button>
        <ui-button variant="primary">Confirm</ui-button>
      </div>
    </ui-card>
    ```
    The content inside the slots is defined by the project, lives in the **light DOM**, and is fully styleable with Tailwind or any other method.

---

### 5. Providing a "Headless" or "Unstyled" Version

For maximum flexibility, you could provide an additional build of your components that **only includes the logic and accessibility foundation, with minimal to no visual styles.**

*   **`ui-library/headless`:** This version would export components that have all the functionality (form association, event handling, aria attributes) but only a bare minimum of structural CSS (e.g., `display: block`, `position: relative`).
*   The consuming project would then be responsible for applying 100% of the styling from scratch, either with Tailwind or their own CSS.

This is the ultimate flexibility but requires more work from the consumer.

### Recommendation for Your Library Design

1.  **Lead with Design Tokens (CSS Variables):** This is the cleanest, most maintainable, and most powerful way to allow customization. Document your variables thoroughly.
2.  **Expose CSS Parts Judiciously:** For each component, decide which internal elements make sense to expose for styling (e.g., `part="button"`, `part="track"`, `part="thumb"`). Don't expose every single `<div>`.
3.  **Use Slots Extensively:** Anywhere content goes, use a slot. This gives projects maximum flexibility over content and light-DOM styling.
4.  **Document the Customization Paths Clearly:** Have a dedicated "Customization" or "Theming" page in your docs that shows:
    *   How to override CSS variables.
    *   A list of all available CSS parts for each component.
    *   Examples of using slots.

By building your library this way, you absolutely provide the flexibility for projects to use their own UX designs and Tailwind CSS, making your library a versatile choice for many different projects and teams.