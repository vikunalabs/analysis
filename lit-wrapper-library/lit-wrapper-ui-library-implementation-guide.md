# Lit Wrapper UI Library Implementation Guide

## 1. Philosophy & Overview

This guide outlines the standards for building our internal UI Library using Lit. The primary goal is to create a **technology-agnostic, consistent, and maintainable** foundation for all our current and future projects.

**Core Principles:**
*   **Abstraction:** Hide Lit's implementation details behind a clean, team-defined API.
*   **Consistency:** Enforce unified patterns for props, events, styling, and accessibility.
*   **Robustness:** Proactively solve common Web Component pitfalls like form submission and theming.
*   **Quality:** Ensure high quality with automated testing, documentation, and type safety.

## 2. Project Setup & Tooling

### Monorepo Structure
We use a monorepo to manage the library and demo applications together.

```
ui-lib-monorepo/
├── packages/
│   ├── ui-library/          # The core component library package
│   │   ├── src/
│   │   │   ├── components/  # Individual component directories
│   │   │   ├── foundations/ # Base classes, tokens, utilities
│   │   │   └── index.ts     # Barrel export file
│   │   ├── package.json
│   │   ├── vite.config.ts   # Vite config for building the lib
│   │   └── tsconfig.json
│   └── demo-app/            # Development & demo SPA
│       ├── src/
│       ├── package.json
│       └── vite.config.ts
├── package.json             # Root workspace config
└── pnpm-workspace.yaml      # (or similar for npm/yarn)
```

### Essential Tooling
*   **Package Manager:** `pnpm` (for its superior workspace support and performance).
*   **Bundler:** `Vite` for building both the library and the demo app.
*   **Testing:** `@web/test-runner` with `@open-wc/testing` helpers.
*   **Linting:** `ESLint` with `@lit/eslint-plugin` and `@open-wc/eslint-config`.
*   **Documentation:** `Storybook` (`@storybook/web-components-vite`).
*   **Language:** `TypeScript`.

## 3. Foundation Implementation

### 3.1. Design Tokens
Define all design values in TypeScript and generate CSS custom properties.

**File:** `packages/ui-library/src/foundations/tokens.ts`
```typescript
export const tokens = {
  color: {
    primary: { 50: '#f0f9ff', 500: '#0ea5e9', 900: '#0c4a6e' },
    neutral: { 100: '#f3f4f6', 500: '#6b7280', 900: '#111827' },
    success: { 500: '#10b981' },
    error: { 500: '#ef4444' },
  },
  spacing: { xs: '0.25rem', sm: '0.5rem', md: '1rem', lg: '1.5rem' },
  font: { size: { sm: '0.875rem', md: '1rem', lg: '1.125rem' }, family: { body: 'Inter, sans-serif' } },
  borderRadius: { sm: '0.25rem', md: '0.375rem', lg: '0.5rem' },
};

export function createTheme() {
  return `
    :host, :root {
      /* Colors */
      --color-primary-500: ${tokens.color.primary[500]};
      --color-neutral-100: ${tokens.color.neutral[100]};
      --color-success-500: ${tokens.color.success[500]};
      --color-error-500: ${tokens.color.error[500]};
      /* Spacing */
      --spacing-xs: ${tokens.spacing.xs};
      --spacing-md: ${tokens.spacing.md};
      /* Typography */
      --font-size-sm: ${tokens.font.size.sm};
      --font-family-body: ${tokens.font.family.body};
      /* Borders */
      --border-radius-md: ${tokens.borderRadius.md};
    }

    @media (prefers-color-scheme: dark) {
      :host[data-theme="auto"], :root[data-theme="auto"] {
        /* Override tokens for dark mode */
      }
    }

    [data-theme="dark"] {
      /* Override tokens for forced dark mode */
    }
  `;
}
```

### 3.2. Base Element Class (`UiElement`)
This is the heart of our wrapper. All components will extend this class.

**File:** `packages/ui-library/src/foundations/base-element.ts`
```typescript
import { LitElement, PropertyValues } from 'lit';
import { createTheme } from './tokens.js';

export class UiElement extends LitElement {
  // 1. Inject global theme tokens and base styles
  static override styles = [createTheme()];

  // 2. Standardized Properties for ALL components
  @property({ type: String, reflect: true }) theme: 'light' | 'dark' | 'auto' = 'light';
  @property({ type: Boolean, reflect: true }) disabled = false;
  @property({ type: String }) testId: string = '';

  // 3. ElementInternals for form association
  // @ts-ignore: TS might not know about `attachInternals`
  readonly internals?: ElementInternals;

  constructor() {
    super();
    // @ts-ignore
    if (this.attachInternals) this.internals = this.attachInternals();
  }

  // 4. Lifecycle: Apply theme on first update and when theme prop changes
  protected override updated(changedProperties: PropertyValues) {
    super.updated(changedProperties);
    if (changedProperties.has('theme')) {
      this._applyTheme();
    }
  }

  // 5. Common Methods
  // Standardized event dispatch
  protected emit<T>(eventName: string, detail?: T, bubbles: boolean = true, composed: boolean = true) {
    this.dispatchEvent(new CustomEvent(eventName, { bubbles, composed, detail }));
  }

  // Helper to generate CSS class strings
  protected getClassMap(...classLists: (string | undefined)[]): string {
    return classLists.filter(cls => cls != null).join(' ');
  }

  // 6. Theme Application Logic
  private _applyTheme() {
    let effectiveTheme = this.theme;
    if (this.theme === 'auto') {
      effectiveTheme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }
    this.setAttribute('data-theme', effectiveTheme);
  }
}
```

### 3.3. Form-Associated Base Class (`FormAssociatedElement`)
**Crucial for solving form submission issues.** Extend this for any component that should work inside a native `<form>`.

**File:** `packages/ui-library/src/foundations/form-associated-element.ts`
```typescript
import { UiElement } from './base-element.js';

export abstract class FormAssociatedElement extends UiElement {
  // Magic flag to enable ElementInternals for forms
  static formAssociated = true;

  // @ts-ignore: Declare we will have internals
  declare internals: ElementInternals;

  // Standard form properties
  @property() name: string = '';
  @property() value: string = '';

  constructor() {
    super();
    // @ts-ignore
    this.internals = this.attachInternals();
  }

  // Lifecycle: Called when the form is reset
  formResetCallback(): void {
    this.value = '';
  }

  // Method for child components to call when value changes
  protected handleValueChange(newValue: string): void {
    const oldValue = this.value;
    this.value = newValue;
    this.internals.setFormValue(newValue);
    this.requestUpdate('value', oldValue);
    this.emit('ui-input-change', { value: newValue }); // Inform Lit-based forms
  }

  // Method to set validity flags
  protected setValidity(flags: ValidityStateFlags, message?: string): void {
    this.internals.setValidity(flags, message, this.shadowRoot?.querySelector('input') || this);
  }
}
```

## 4. Component Implementation Standards

### 4.1. Anatomy of a Component
Each component lives in its own directory:
```
src/components/button/
├── button.ts           # Component class
├── button.styles.ts    # Component styles
├── button.test.ts      # Component tests
├── index.ts           # Barrel export
└── README.md          # Documentation (optional)
```

### 4.2. Example: Implementing a Button
**File:** `packages/ui-library/src/components/button/button.styles.ts`
```typescript
import { css } from 'lit';

export const buttonStyles = css`
  :host {
    display: inline-block;
  }

  .button {
    font-family: var(--font-family-body);
    font-size: var(--font-size-md);
    padding: var(--spacing-sm) var(--spacing-md);
    background-color: var(--color-primary-500);
    color: white;
    border: none;
    border-radius: var(--border-radius-md);
    cursor: pointer;
    transition: background-color 0.2s ease;
  }

  .button:hover:not(.button--disabled) {
    background-color: var(--color-primary-600);
  }

  .button--disabled {
    cursor: not-allowed;
    opacity: 0.6;
  }

  /* Variant: Secondary */
  .button--secondary {
    background-color: var(--color-neutral-100);
    color: var(--color-neutral-900);
  }
  .button--secondary:hover:not(.button--disabled) {
    background-color: var(--color-neutral-200);
  }
`;
```

**File:** `packages/ui-library/src/components/button/button.ts`
```typescript
import { UiElement } from '../../foundations/base-element.js';
import { buttonStyles } from './button.styles.js';

export class Button extends UiElement {
  static styles = [buttonStyles];

  // Define a well-typed API
  @property() label: string = '';
  @property() icon: string = '';
  @property({ type: Boolean }) loading: boolean = false;
  @property() variant: 'primary' | 'secondary' = 'primary';
  @property() size: 'sm' | 'md' | 'lg' = 'md';

  render() {
    return html`
      <button
        class=${this.getClassMap(
          'button',
          `button--${this.variant}`,
          `button--${this.size}`,
          this.disabled || this.loading ? 'button--disabled' : ''
        )}
        ?disabled=${this.disabled || this.loading}
        part="button" <!-- Expose for external styling -->
        aria-label=${this.label || this.icon}
        aria-busy=${this.loading}
        data-testid=${this.testId || 'ui-button'}
        @click=${this._handleClick}
      >
        ${this.loading ? html`<ui-spinner part="spinner"></ui-spinner>` : ''}
        ${this.icon ? html`<ui-icon part="icon" name=${this.icon}></ui-icon>` : ''}
        ${this.label}
      </button>
    `;
  }

  private _handleClick(e: Event) {
    if (this.disabled || this.loading) {
      e.stopPropagation();
      return;
    }
    this.emit('ui-click'); // Use the standardized emit method
  }
}
```

### 4.3. Example: Implementing an Input (Form-Associated)
**File:** `packages/ui-library/src/components/input/input.ts`
```typescript
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
        ?disabled=${this.disabled}
        @input=${this._handleInput}
        @blur=${this._handleBlur}
      >
    `;
  }

  private _handleInput(e: InputEvent) {
    const target = e.target as HTMLInputElement;
    this.handleValueChange(target.value); // Critical: Call method from FormAssociatedElement
  }

  private _handleBlur() {
    // Example: Simple required validation
    if (this.hasAttribute('required') && !this.value) {
      this.setValidity({ valueMissing: true }, 'This field is required');
    } else {
      this.setValidity({});
    }
  }
}
```

## 5. Testing Standards

**File:** `packages/ui-library/src/components/button/button.test.ts`
```typescript
import { fixture, expect, html } from '@open-wc/testing';
import { Button } from './button.js';
import '. /button.js'; // Define the element

describe('Button', () => {
  it('passes accessibility test', async () => {
    const el = await fixture<Button>(html`<ui-button label="Test"></ui-button>`);
    await expect(el).to.be.accessible();
  });

  it('dispatches "ui-click" event on click', async () => {
    const el = await fixture<Button>(html`<ui-button label="Test"></ui-button>`);
    let clickEventFired = false;
    el.addEventListener('ui-click', () => { clickEventFired = true; });

    el.shadowRoot!.querySelector('button')!.click();
    expect(clickEventFired).to.be.true;
  });

  it('does not dispatch event when disabled', async () => {
    const el = await fixture<Button>(html`<ui-button label="Test" disabled></ui-button>`);
    let clickEventFired = false;
    el.addEventListener('ui-click', () => { clickEventFired = true; });

    el.shadowRoot!.querySelector('button')!.click();
    expect(clickEventFired).to.be.false;
  });
});
```

## 6. Exporting and Building

**File:** `packages/ui-library/src/index.ts` (Barrel Exports)
```typescript
// Foundations
export { UiElement } from './foundations/base-element.js';
export { FormAssociatedElement } from './foundations/form-associated-element.js';
export { tokens, createTheme } from './foundations/tokens.js';

// Components
export { Button } from './components/button/index.js';
export { Input } from './components/input/index.js';
// ... export all other components
```

**File:** `packages/ui-library/vite.config.ts`
```typescript
import { defineConfig } from 'vite';
import { resolve } from 'path';

// https://vitejs.dev/config/
export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      name: 'UiLibrary',
      fileName: 'ui-library',
    },
    rollupOptions: {
      // Externalize deps that shouldn't be bundled
      external: ['lit'],
      output: {
        // Provide global variables to use in UMD build
        globals: {
          lit: 'Lit',
        },
      },
    },
  },
});
```

## 7. Summary of Solved Issues

1.  **Form Submission:** ✅ Solved by the `FormAssociatedElement` base class using the `ElementInternals` API.
2.  **Theming:** ✅ Solved by injecting CSS custom properties via the base class and using a `data-theme` attribute strategy.
3.  **Consistency:** ✅ Enforced by the `UiElement` base class providing standardized props, events, and methods.
4.  **Accessibility (A11y):** ✅ Enforced as a first-class concern in the base class and component templates (aria labels, native elements).
5.  **External Styling:** ✅ Enabled via CSS `parts` (`part="button"`).
6.  **Type Safety:** ✅ Maximized through strict TypeScript usage in all foundations and components.
7.  **Testing:** ✅ Standardized via `@web/test-runner` and `@open-wc/testing` helpers.

By adhering to this guide, we build a robust, future-proof foundation that avoids common pitfalls and ensures a high-quality developer experience across all projects.