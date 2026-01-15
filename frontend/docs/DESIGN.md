# Frontend Design Document

## Overview

A premium, executive-ready web application for PDF document processing built with Elm and elm-css. The frontend provides a polished, modern interface for authenticating, uploading PDFs, submitting processing jobs, and retrieving results.

## Design System: "Nexus"

Inspired by Linear and Stripe's design language - sophisticated dark theme with electric cyan accents, professional typography, and attention to micro-interactions.

### Design Principles

**Premium & Professional**
- Stripe/Linear-level polish suitable for executive demos
- Clean, sophisticated dark theme
- Thoughtful spacing and visual hierarchy

**Modern & Innovative**
- Electric cyan accents convey cutting-edge AI technology
- Smooth transitions and animations
- Real-time status feedback for processing jobs

**Developer-Friendly**
- Dashboard-centric design showing job metrics
- Clear status indicators and timelines
- Technical information displayed elegantly

## Visual Design System

### Color Palette

```elm
-- Backgrounds (layered for depth)
background: #0a0a0b      -- Primary background (near black)
surface: #141415         -- Card/panel backgrounds
surfaceRaised: #1c1c1e   -- Modals, dropdowns
overlay: #252528         -- Hover states

-- Text hierarchy
textPrimary: #f4f4f5     -- Primary text (high contrast)
textSecondary: #a1a1aa   -- Secondary/muted text (zinc-400)
textTertiary: #71717a    -- Hints, disabled text (zinc-500)
textInverse: #09090b     -- Text on light/accent surfaces

-- Accent - Electric Cyan
accent: #22d3ee          -- Primary accent (cyan-400)
accentHover: #06b6d4     -- Hover state (cyan-500)
accentPressed: #0891b2   -- Pressed state (cyan-600)
accentMuted: rgba(34, 211, 238, 0.1)   -- Subtle backgrounds
accentSubtle: rgba(34, 211, 238, 0.2)  -- Badges, highlights

-- Semantic colors
success: #4ade80         -- Complete jobs, success states (green-400)
successMuted: rgba(74, 222, 128, 0.15)
warning: #fbbf24         -- Pending states (amber-400)
warningMuted: rgba(251, 191, 36, 0.15)
error: #f87171           -- Failed jobs, errors (red-400)
errorMuted: rgba(248, 113, 113, 0.15)
info: #60a5fa            -- Informational (blue-400)

-- Borders
border: #27272a          -- Default borders (zinc-800)
borderStrong: #3f3f46    -- Emphasized borders (zinc-700)
borderFocus: #22d3ee     -- Focus ring color
```

### Typography

**Primary Font Stack (UI text):**
```
Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif
```

**Code Font Stack (technical values only):**
```
"JetBrains Mono", "Fira Code", "SF Mono", Consolas, "Liberation Mono", monospace
```

**Type Scale:**
- Display: 32px / 600 weight (page titles)
- H1: 24px / 600 weight (section headers)
- H2: 18px / 500 weight (card titles)
- Body: 14px / 400 weight (default text)
- Small: 13px / 400 weight (secondary info)
- Caption: 12px / 500 weight (labels, badges, uppercase)
- Code: 13px / 400 weight (monospace technical values)

**Line Heights:**
- Tight: 1.25 (headings)
- Normal: 1.5 (body text)
- Relaxed: 1.625 (descriptions)

### Spacing System (8px grid)

```
xs:   4px    (micro adjustments)
sm:   8px    (tight spacing)
md:   12px   (compact elements)
base: 16px   (default padding)
lg:   20px   (comfortable spacing)
xl:   24px   (card padding)
xxl:  32px   (section spacing)
xxxl: 40px   (page margins)
huge: 48px   (major sections)
massive: 64px (hero spacing)
```

### Border Radius

```
none: 0px
sm:   4px    (buttons, inputs)
md:   6px    (cards, form elements)
lg:   8px    (modals)
xl:   12px   (feature cards)
full: 9999px (pills, avatars)
```

### Shadows

```
sm:   0 1px 2px rgba(0, 0, 0, 0.3)      -- Subtle depth
md:   0 4px 6px rgba(0, 0, 0, 0.3)      -- Card elevation
lg:   0 8px 16px rgba(0, 0, 0, 0.4)     -- Modal elevation
glow: 0 0 20px rgba(34, 211, 238, 0.15) -- Accent glow
```

### Transitions

All interactive elements use smooth 150ms ease transitions.

## UI Components

### Buttons

**Variants:**
- **Primary**: Solid cyan background, dark text - for main CTAs
- **Secondary**: Outlined with border, fills on hover - for secondary actions
- **Ghost**: No border, subtle hover background - for tertiary actions
- **Danger**: Red outlined - for destructive actions

**Sizes:**
- Small: 28px height, padding 4px 12px
- Medium: 36px height, padding 8px 16px (default)
- Large: 44px height, padding 12px 24px

**States:**
- Hover: Background/border color shift
- Active: Slightly darker
- Focus: Cyan focus ring (2px)
- Disabled: 60% opacity, not-allowed cursor

### Inputs

- Rounded corners (6px radius)
- Subtle border that strengthens on hover
- Cyan focus ring with glow effect
- Placeholder text in zinc-500
- Label above input in caption style (uppercase, medium weight)

### Status Badges

- Pill-shaped (full radius)
- Colored dot + text
- Subtle colored background tint
- Processing badge has animated pulsing dot

**Status Colors:**
- Pending: Amber/yellow
- Processing: Cyan (animated pulse)
- Complete: Green
- Failed: Red

### Cards

- Surface background with subtle border
- 6-8px border radius
- 24px internal padding
- Interactive cards have hover state (raised surface, stronger border)

### Timeline Component

- Vertical layout with connected dots
- Colored indicators per status
- Processing step has glowing animated dot
- Timestamps shown inline
- Detail text in muted code blocks

## Application Structure

### Dashboard (Jobs) View

```
┌────────────────────────────────────────────────────────────┐
│  Dashboard                           [+ New Job] [Sign Out]│
│  Monitor your PDF processing jobs                          │
├────────────────────────────────────────────────────────────┤
│                                                            │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │
│  │ TOTAL    │ │PROCESSING│ │COMPLETED │ │ FAILED   │     │
│  │    12    │ │     2    │ │     8    │ │    2     │     │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │
│                                                            │
│  Recent Jobs                               [Refresh]       │
│                                                            │
│  ┌────────────────────────────────────────────────────┐   │
│  │ ▶ Job abc123   Marker   ● Processing   2m ago      │   │
│  └────────────────────────────────────────────────────┘   │
│  ┌────────────────────────────────────────────────────┐   │
│  │ ▼ Job def456   Marker   ● Complete     5m ago [↓]  │   │
│  │   ─────────────────────────────────────────────    │   │
│  │   user-id/job-def456.pdf                           │   │
│  │                                                     │   │
│  │   ⏱ Processing Timeline                           │   │
│  │   ● Job Submitted         5m ago                   │   │
│  │   │                                                │   │
│  │   ● Processing            Converting document...    │   │
│  │   │                                                │   │
│  │   ● Completed             Ready for download       │   │
│  └────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────┘
```

### Upload View

```
┌────────────────────────────────────────────────────────────┐
│  PDF Models                         [Dashboard] [Sign Out] │
├────────────────────────────────────────────────────────────┤
│                                                            │
│                      New Job                               │
│           Upload a PDF document for processing             │
│                                                            │
│  ┌────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  │  PROCESSING MODEL                                   │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │ Marker                               ▼      │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  │                                                     │   │
│  │  ▶ About this model                                │   │
│  │                                                     │   │
│  │  DOCUMENT                                          │   │
│  │  ┌─────────────────────────────────────────────┐   │   │
│  │  │                                             │   │   │
│  │  │          📄                                 │   │   │
│  │  │   Click to upload or drag and drop         │   │   │
│  │  │          PDF files only                    │   │   │
│  │  │                                             │   │   │
│  │  └─────────────────────────────────────────────┘   │   │
│  │                                                     │   │
│  └────────────────────────────────────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Login View

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│                         📄                                 │
│                    PDF Models                              │
│            Document processing platform                    │
│                                                            │
│         ┌────────────────────────────────────┐            │
│         │           Sign In                   │            │
│         │                                     │            │
│         │  Email                              │            │
│         │  ┌──────────────────────────────┐  │            │
│         │  │ you@example.com              │  │            │
│         │  └──────────────────────────────┘  │            │
│         │                                     │            │
│         │  Password                           │            │
│         │  ┌──────────────────────────────┐  │            │
│         │  │ ••••••••••••                 │  │            │
│         │  └──────────────────────────────┘  │            │
│         │                                     │            │
│         │  ┌──────────────────────────────┐  │            │
│         │  │         Sign In              │  │            │
│         │  └──────────────────────────────┘  │            │
│         │                                     │            │
│         │  Don't have an account? Sign up    │            │
│         └────────────────────────────────────┘            │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

## File Structure

```
frontend/
├── elm.json
├── build.sh                   -- Build script
├── interop.js                 -- AWS Cognito/S3 JavaScript interop
├── src/
│   ├── Main.elm              -- Application entry point, routing
│   ├── Api.elm               -- HTTP API calls
│   ├── Auth.elm              -- Cognito authentication ports
│   ├── S3.elm                -- S3 upload handling
│   ├── Types.elm             -- Shared types (Model, Msg, etc.)
│   ├── Styles.elm            -- Design system tokens and utilities
│   ├── Views/
│   │   ├── Login.elm         -- Login page
│   │   ├── SignUp.elm        -- Sign up + confirmation page
│   │   ├── Upload.elm        -- File upload page
│   │   └── Jobs.elm          -- Dashboard/jobs list
│   └── Components/
│       ├── Button.elm        -- Primary/Secondary/Ghost/Danger variants
│       ├── Input.elm         -- Text input and textarea
│       ├── StatusBadge.elm   -- Job status pills with animation
│       └── Timeline.elm      -- Processing timeline
├── dst/                       -- Built output
│   ├── index.html
│   ├── main.js
│   └── interop.js
└── docs/
    ├── DESIGN.md             -- This document
    └── DEPLOYMENT.md         -- Deployment instructions
```

## Configuration

**API Endpoint:** `https://api.epequeno.app`

**Cognito Details:**
- User Pool ID: `us-east-1_wslqPOxQd`
- Client ID: `4tmf8s58738hrbrp4ff2utqg5`
- Identity Pool ID: `us-east-1:1fd26b6e-8a1c-4dd7-940d-60ec7884f384`

**Test Users:**

*UI Testing (for agent-browser):*
- Email: `ui-test@pdf-models.local`
- Password: `UiTest123!`

*Integration Testing:*
- Email: `integration-test@pdf-models.local`
- Password: `TestPass123!`

## Development

**Local Development:**
```bash
cd frontend
./build.sh
cd dst && python3 -m http.server 8000
```

**Building for Production:**
```bash
./build.sh
```

The build outputs to `dst/` which is deployed to S3/CloudFront.

## Browser Support

- Modern evergreen browsers (Chrome, Firefox, Safari, Edge)
- ES6+ JavaScript output from Elm
- No IE11 support needed

## Accessibility

- Semantic HTML from Elm's Html module
- Keyboard navigation for all interactive elements
- Focus rings on inputs and buttons
- Color contrast meeting WCAG AA standards
- Status announcements for screen readers

---

*Last updated: January 2026*
*Design system version: Nexus 1.0*
