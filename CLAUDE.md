# Capital Flow Cityscape — Design System

Developer reference for the visual design system used in this project.

---

## Color Palette

### Theme Colors (CSS Custom Properties)

| Token                    | Dark Mode                    | Light Mode                   |
|--------------------------|------------------------------|------------------------------|
| `--color-primary`        | `#10B981` (Emerald)          | `#059669` (Emerald)          |
| `--color-primary-dark`   | `#059669`                    | `#047857`                    |
| `--color-primary-light`  | `#34D399`                    | `#A7F3D0`                    |
| `--color-accent`         | `#F59E0B` (Amber)            | `#D97706` (Amber)            |
| `--color-accent-dark`    | `#D97706`                    | `#B45309`                    |
| `--color-accent-light`   | `#FCD34D`                    | `#FDE68A`                    |
| `--color-bg`             | `#0F172A` (Slate-900)        | `#F1F5F9` (Slate-100)        |
| `--color-bg-deep`        | `#020617`                    | `#E2E8F0`                    |
| `--color-surface`        | `rgba(15,23,42,0.92)`        | `rgba(255,255,255,0.95)`     |
| `--color-surface-hover`  | `rgba(30,41,59,0.92)`        | `rgba(241,245,249,0.95)`     |
| `--color-border`         | `rgba(255,255,255,0.12)`     | `rgba(0,0,0,0.12)`           |
| `--color-text`           | `#F8FAFC`                    | `#0F172A`                    |
| `--color-text-secondary` | `#94A3B8`                    | `#475569`                    |
| `--color-text-muted`     | `#64748B`                    | `#94A3B8`                    |
| `--color-heading-accent` | `#5EEAD4` (Teal)             | `#059669` (Emerald)          |
| `--color-label`          | `#7DD3FC` (Sky)              | `#0D9488` (Teal)             |
| `--color-link`           | `#5EEAD4`                    | `#059669`                    |
| `--color-success`        | `#22C55E`                    | `#16A34A`                    |
| `--color-error`          | `#EF4444`                    | `#DC2626`                    |
| `--color-warning`        | `#F59E0B`                    | `#D97706`                    |
| `--color-slider-thumb`   | `#10B981`                    | `#059669`                    |
| `--color-dropdown-hover` | `rgba(16,185,129,0.3)`       | `rgba(5,150,105,0.15)`       |

### District Colors

Fixed colors, same in both themes.

| District           | Hex       |
|--------------------|-----------|
| Stocks             | `#F43F5E` |
| ETFs               | `#3B82F6` |
| Options            | `#EC4899` |
| Futures            | `#06B6D4` |
| Bonds              | `#F59E0B` |
| Mutual Funds       | `#10B981` |

---

## Typography

### Fonts

| Token          | Font Stack                                      | Use              |
|----------------|-------------------------------------------------|------------------|
| `--font-ui`    | `'Inter', system-ui, -apple-system, sans-serif` | All UI text      |
| `--font-mono`  | `'JetBrains Mono', 'Fira Code', monospace`      | Data, timestamps |

Loaded via Google Fonts:
- **Inter:** weights 300, 400, 500, 600, 700
- **JetBrains Mono:** weights 400, 500, 600, 700

### Sizes

| Element             | Size   | Weight | Additional                              |
|---------------------|--------|--------|-----------------------------------------|
| Panel headings      | 13-14px | —     | Uppercase, `letter-spacing: 1.5px`      |
| Body / stat rows    | 14px   | —      | —                                       |
| Labels              | 12px   | —      | Uppercase, `letter-spacing: 1px`        |
| Tooltips            | 12px   | —      | Tooltip headings 14px                   |
| Muted hints         | 11px   | —      | `color: var(--color-text-muted)`        |
| Title bar heading   | 16px   | 600    | `letter-spacing: 1px`                   |
| Stat values         | 14px   | 600    | `color: #fff`                           |
| Timeline date       | 12px   | —      | `font-family: var(--font-mono)`         |

---

## Component Classes

### Pill Buttons

Base class `.pill` — pill-shaped buttons with rounded corners.

```css
.pill            /* Base: 6px 16px padding, 13px font, border-radius: 999px */
.pill--primary   /* Emerald fill, white text */
.pill--secondary /* Translucent gray fill, white text */
.pill--disabled  /* Muted fill, muted text, no pointer events */
.pill--sm        /* Compact: 4px 12px padding, 11px font */
```

### District Navigation

```css
.district-nav        /* Container — shows .nb-dropdown on hover */
.nb-dropdown         /* Flyout menu: positioned left of parent */
.nb-dropdown-item    /* Menu item: 11px, left-aligned, hover highlight */
```

### Layout Panels

All panels share: `var(--color-surface)` background, `var(--color-border)` border, `border-radius: 10px`, `backdrop-filter: blur(12px)`.

| Panel               | Position             | Key contents             |
|----------------------|----------------------|--------------------------|
| `#legend`            | Top-left fixed       | District swatches, visual encoding key |
| `#stats`             | Top-right fixed      | Aggregate stats          |
| `#toolbar`           | Top-center fixed     | Date period, filters     |
| `#timelapse-controls`| Below toolbar        | Play/pause, scrubber, speed |
| `#tooltip`           | Follows cursor       | Building hover details   |
| `#flow-tooltip`      | Follows cursor       | Flow arc hover details   |
| `#title-bar`         | Bottom-center fixed  | Project title            |
| `#controls-hint`     | Right side fixed     | Mouse control hints      |
| `#filter-panel`      | Below toolbar        | Filter inputs (toggled)  |

---

## Theme System

### How It Works

1. CSS custom properties are defined on `:root` (defaults to dark) and overridden on `[data-theme="light"]`.
2. The `#theme-toggle` button calls `toggleTheme()`, which toggles `data-theme` on `<html>`.
3. User preference is saved to `localStorage` under the key `cfcTheme` (values: `"dark"` or `"light"`).
4. On page load, the saved theme is restored from `localStorage` before first paint.

### Adding New Theme-Aware Styles

Use custom properties, never hardcode colors:

```css
/* Do this */
color: var(--color-text);
background: var(--color-surface);

/* Not this */
color: #F8FAFC;
background: rgba(15, 23, 42, 0.92);
```

### Theme Toggle Button

Fixed position, top-right (offset to avoid overlapping `#stats` panel). Shows moon icon in dark mode, sun icon in light mode.
