# Frontend Design Document

## Overview

A minimal, terminal-style web application for PDF-to-Markdown conversion built with Elm and elm-css. The frontend provides a developer-focused interface for authenticating, uploading PDFs, submitting processing jobs, and retrieving results.

## Design Principles

**Minimal and Functional**
- Focus on core workflows without unnecessary features
- Every UI element serves a clear purpose
- Fast to implement and maintain

**Technical/Terminal Aesthetic**
- Monospace typography throughout
- Dark theme with muted accent colors
- Clean, rectangular UI elements with minimal decoration
- Terminal-style status indicators and feedback

**Transparency**
- Show S3 keys and job IDs to users
- Display raw status information
- Minimal abstraction over backend API

## Visual Design System

### Color Palette

```elm
-- Background and surfaces
background: #1a1a1a      -- Primary background
surface: #252525         -- Card/panel backgrounds
border: #333333          -- Subtle borders and dividers

-- Text
textPrimary: #e0e0e0     -- Primary text
textSecondary: #999999   -- Secondary/muted text
textTertiary: #666666    -- Disabled/placeholder text

-- Accent colors
accentPrimary: #00d9ff   -- Links, primary actions, focus states
accentSuccess: #50fa7b   -- Success states, completed jobs
accentWarning: #f1fa8c   -- Processing/pending states
accentError: #ff5555     -- Errors, failed jobs

-- Interactive states
hover: #2a2a2a           -- Button/row hover background
active: #333333          -- Button active state
focus: #00d9ff           -- Focus ring color
```

### Typography

**Font Stack:**
```
"JetBrains Mono", "Fira Code", "SF Mono", "Consolas", "Liberation Mono", monospace
```

**Type Scale:**
- Heading 1: 24px, weight 600
- Heading 2: 18px, weight 600
- Body: 14px, weight 400
- Small: 12px, weight 400
- Code: 13px, weight 400

**Line Height:** 1.5 for body text, 1.2 for headings

### Spacing System

Base unit: 8px

```
xs:  4px   (0.5 units)
sm:  8px   (1 unit)
md:  16px  (2 units)
lg:  24px  (3 units)
xl:  32px  (4 units)
xxl: 48px  (6 units)
```

### UI Components

**Buttons**
- Rectangular (no border-radius)
- 1px solid border
- Padding: 8px 16px
- Hover: background lightens slightly
- Primary: accent border + text
- Secondary: border text only

**Inputs**
- Rectangular text inputs
- 1px border, accent color on focus
- Padding: 8px 12px
- Background: slightly lighter than page background

**Tables**
- 1px borders between rows
- Hover state on rows
- Monospace throughout
- Compact spacing

**Status Badges**
- Inline text with color coding
- Optional symbol prefix (●)
- No background, just colored text

## Application Structure

### Page Views

The application has three main views, managed by URL routing:

#### 1. Authentication View (`/login`)

**Purpose:** User login via Cognito

**Layout:**
```
┌─────────────────────────────────────┐
│                                     │
│         PDF Models                  │
│                                     │
│     ┌──────────────────────┐       │
│     │ Email                │       │
│     └──────────────────────┘       │
│                                     │
│     ┌──────────────────────┐       │
│     │ Password             │       │
│     └──────────────────────┘       │
│                                     │
│     [    Sign In    ]              │
│                                     │
│     Error message here             │
│                                     │
└─────────────────────────────────────┘
```

**State:**
- Email input value
- Password input value
- Loading state
- Error message (if auth fails)

**Actions:**
- Submit credentials → Cognito authentication
- On success: store tokens, redirect to `/upload`
- On failure: display error

#### 2. Upload View (`/upload` or `/`)

**Purpose:** Upload PDF to S3 and submit processing job

**Layout:**
```
┌─────────────────────────────────────────────────┐
│ PDF Models                      [Jobs] [Logout] │
├─────────────────────────────────────────────────┤
│                                                 │
│  Upload PDF                                     │
│                                                 │
│  ┌─────────────────────────────────────┐       │
│  │                                     │       │
│  │  [Browse Files]                     │       │
│  │                                     │       │
│  │  selected-file.pdf                  │       │
│  │  Uploading... 47%                   │       │
│  │                                     │       │
│  └─────────────────────────────────────┘       │
│                                                 │
│  S3 Key: us-east-1:abc.../job-123.pdf          │
│                                                 │
│  [  Submit Job  ]                              │
│                                                 │
└─────────────────────────────────────────────────┘
```

**State:**
- Selected file
- Upload progress (0-100)
- S3 key (after upload complete)
- Submit status
- Identity ID (from Identity Pool)

**Actions:**
1. Select file from local system
2. Get Identity Pool credentials
3. Upload to S3: `s3://bucket/{identityId}/{jobId}.pdf`
4. Display S3 key to user
5. Submit job to API with S3 key
6. Redirect to `/jobs` on success

#### 3. Jobs List View (`/jobs`)

**Purpose:** View all submitted jobs and their status

**Layout:**
```
┌───────────────────────────────────────────────────────────────┐
│ PDF Models              [Upload] [Refresh] [Logout]           │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  Your Jobs                                                    │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Job ID        │ Submitted    │ Status     │ Actions    │ │
│  ├─────────────────────────────────────────────────────────┤ │
│  │ job-abc123    │ 2 min ago    │ ● complete │ [Download] │ │
│  │ job-def456    │ 5 min ago    │ ● process  │ —          │ │
│  │ job-ghi789    │ 1 hour ago   │ ● failed   │ [Retry]    │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  Auto-refresh: 10s                                            │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**State:**
- List of jobs (fetched from API)
- Polling interval (active when any job is processing)
- Last refresh timestamp

**Actions:**
- Fetch jobs on mount
- Poll every 10s when jobs are in "processing" state
- Download button → fetch result from S3
- Manual refresh button
- Navigate to Upload view

**Job Status Values:**
```elm
type JobStatus
    = Pending      -- Submitted but not started
    | Processing   -- Currently being processed
    | Complete     -- Done, results available
    | Failed       -- Processing failed
```

### Routing

Using `elm/browser` and `Browser.application`:

```elm
type Route
    = Login
    | Upload
    | Jobs
    | NotFound

-- URL structure:
-- /login
-- /upload (or /)
-- /jobs
```

## Component Architecture

### Reusable Components

#### Button
```elm
-- Button.elm
type ButtonStyle = Primary | Secondary

button : ButtonStyle -> String -> msg -> Html msg
```

**Styles:**
- Primary: accent border and text, hover background
- Secondary: border only, accent text

#### Input
```elm
-- Input.elm
type alias InputConfig msg =
    { label : String
    , value : String
    , onInput : String -> msg
    , inputType : String  -- "text", "password", "email"
    , placeholder : String
    }

input : InputConfig msg -> Html msg
```

**Features:**
- Label above input
- Focus state with accent border
- Error state (red border)

#### Table
```elm
-- Table.elm
type alias Column data =
    { header : String
    , view : data -> Html msg
    }

table : List (Column data) -> List data -> Html msg
```

**Features:**
- Generic table component
- Hover states on rows
- Consistent spacing and borders

#### StatusBadge
```elm
-- StatusBadge.elm
type Status = Pending | Processing | Complete | Failed

statusBadge : Status -> Html msg
```

**Rendering:**
- Pending: yellow dot + "pending"
- Processing: yellow dot + "processing"
- Complete: green dot + "complete"
- Failed: red dot + "failed"

#### FileUploader
```elm
-- FileUploader.elm
type alias UploaderState =
    { selectedFile : Maybe File
    , progress : Maybe Float  -- 0.0 to 1.0
    , s3Key : Maybe String
    }

fileUploader : UploaderState -> (File -> msg) -> Html msg
```

**Features:**
- File input
- Display selected filename
- Progress bar during upload
- Display S3 key after upload

## Data Flow and State Management

### Model Structure

```elm
type alias Model =
    { route : Route
    , auth : AuthState
    , upload : UploadState
    , jobs : JobsState
    }

type AuthState
    = NotAuthenticated
    | Authenticating
    | Authenticated AuthTokens

type alias AuthTokens =
    { accessToken : String
    , idToken : String
    , identityId : String
    }

type alias UploadState =
    { selectedFile : Maybe File
    , uploadProgress : Maybe Float
    , s3Key : Maybe String
    , submitStatus : RemoteData
    }

type alias JobsState =
    { jobs : List Job
    , loading : Bool
    , error : Maybe String
    , lastRefresh : Maybe Time.Posix
    }

type alias Job =
    { id : String
    , submittedAt : Time.Posix
    , status : JobStatus
    , s3InputKey : String
    , s3OutputKey : Maybe String
    }
```

### Message Types

```elm
type Msg
    -- Routing
    = UrlChanged Url
    | LinkClicked Browser.UrlRequest

    -- Auth
    | EmailChanged String
    | PasswordChanged String
    | SignInClicked
    | SignInCompleted (Result Http.Error AuthTokens)
    | SignOutClicked

    -- Upload
    | FileSelected File
    | UploadToS3
    | UploadProgress Float
    | UploadCompleted (Result Http.Error String)  -- S3 key
    | SubmitJobClicked
    | JobSubmitted (Result Http.Error Job)

    -- Jobs
    | FetchJobs
    | JobsFetched (Result Http.Error (List Job))
    | RefreshClicked
    | DownloadResult String  -- job ID
    | PollTick Time.Posix
```

### Side Effects (Commands)

**Authentication:**
```elm
-- Use Cognito InitiateAuth API
signIn : String -> String -> Cmd Msg

-- Get Identity Pool credentials
getIdentityCredentials : String -> Cmd Msg  -- ID token
```

**S3 Upload:**
```elm
-- Upload file using Identity Pool credentials
uploadToS3 : File -> AuthTokens -> Cmd Msg
```

**API Calls:**
```elm
-- All API calls include Authorization header with access token

submitJob : String -> String -> Cmd Msg
-- POST /v1/models/marker/jobs
-- Body: {"s3_input_key": "...", "start_processing": true}

fetchJobs : String -> Cmd Msg
-- GET /v1/models/marker/jobs

getJobStatus : String -> String -> Cmd Msg
-- GET /v1/models/marker/jobs/{jobId}

downloadResult : String -> String -> Cmd Msg
-- GET presigned S3 URL for output
```

### Subscriptions

```elm
subscriptions : Model -> Sub Msg
subscriptions model =
    case model.jobs.jobs of
        [] ->
            Sub.none

        jobs ->
            if List.any (\j -> j.status == Processing) jobs then
                Time.every (10 * 1000) PollTick  -- Poll every 10s
            else
                Sub.none
```

## API Integration

### Endpoints

Base URL: `https://eykwwhrt16.execute-api.us-east-1.amazonaws.com`

**Submit Job:**
```
POST /v1/models/marker/jobs
Authorization: Bearer {accessToken}
Content-Type: application/json

{
  "s3_input_key": "{identityId}/{jobId}.pdf",
  "start_processing": true
}

Response 201:
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending",
  "s3_input_key": "...",
  "submitted_at": "2025-01-02T12:00:00Z"
}
```

**List Jobs:**
```
GET /v1/models/marker/jobs
Authorization: Bearer {accessToken}

Response 200:
{
  "jobs": [
    {
      "job_id": "...",
      "status": "complete",
      "s3_input_key": "...",
      "s3_output_key": "...",
      "submitted_at": "...",
      "completed_at": "..."
    }
  ]
}
```

**Get Job Status:**
```
GET /v1/models/marker/jobs/{jobId}
Authorization: Bearer {accessToken}

Response 200:
{
  "job_id": "...",
  "status": "processing",
  "s3_input_key": "...",
  "submitted_at": "..."
}
```

### Authentication Flow

1. User submits email/password
2. Call Cognito `InitiateAuth` with `USER_PASSWORD_AUTH` flow
3. Receive `AccessToken`, `IdToken`, `RefreshToken`
4. Exchange `IdToken` for Identity Pool credentials:
   - Call `GetId` with ID token
   - Call `GetCredentialsForIdentity`
   - Receive temporary AWS credentials and `identityId`
5. Store tokens in model
6. Use `AccessToken` for API calls, Identity Pool credentials for S3

### Error Handling

**HTTP Errors:**
- 401: Redirect to login, clear auth state
- 403: Show "Access denied" message
- 404: Show "Not found" message
- 5xx: Show "Server error, please try again"

**Network Errors:**
- Show "Network error, check connection"
- Provide retry button

**Validation Errors:**
- Show inline validation messages
- Prevent form submission

## File Structure

```
frontend/
├── elm.json
├── src/
│   ├── Main.elm              -- Application entry point, routing
│   ├── Api.elm               -- HTTP API calls
│   ├── Auth.elm              -- Cognito authentication logic
│   ├── Types.elm             -- Shared types (Model, Msg, etc.)
│   ├── Styles.elm            -- Global elm-css styles and theme
│   ├── Views/
│   │   ├── Login.elm         -- Login page view
│   │   ├── Upload.elm        -- Upload page view
│   │   └── Jobs.elm          -- Jobs list view
│   └── Components/
│       ├── Button.elm
│       ├── Input.elm
│       ├── Table.elm
│       ├── StatusBadge.elm
│       └── FileUploader.elm
├── public/
│   ├── index.html            -- HTML shell
│   └── styles.css            -- Minimal reset/base styles
└── DESIGN.md                 -- This document
```

## Development Workflow

**Local Development:**
```bash
cd frontend
elm reactor  # or elm-live for hot reload
```

**Building for Production:**
```bash
elm make src/Main.elm --optimize --output=public/main.js
```

**Recommended Tools:**
- `elm-format` for code formatting
- `elm-analyse` for code quality
- `elm-test` for testing (add later)

## Implementation Phases

### Phase 1: Foundation (1-2 hours)
- Set up routing with `Browser.application`
- Create global styles and theme with elm-css
- Build core components: Button, Input, Table

### Phase 2: Authentication (1-2 hours)
- Implement Login view
- Cognito authentication flow
- Token storage in model
- Protected route logic

### Phase 3: Upload Flow (2-3 hours)
- FileUploader component
- S3 upload with Identity Pool credentials
- Upload progress tracking
- Job submission

### Phase 4: Jobs List (1-2 hours)
- Jobs list view and table
- Status polling subscription
- Download functionality
- Error states

### Phase 5: Polish (1 hour)
- Loading states
- Error messages
- Responsive layout (if needed)
- Testing on real backend

## Future Enhancements (Post-MVP)

**Features:**
- Dark/light theme toggle
- Drag-and-drop file upload
- Job result preview (markdown rendering)
- Batch upload
- Search/filter jobs
- LocalStorage for token persistence
- Remember me checkbox
- Password reset flow
- Usage statistics dashboard

**Technical:**
- elm-test suite
- CI/CD integration
- Performance optimization
- Accessibility improvements (ARIA labels, keyboard nav)
- PWA support

## Configuration

**API Endpoints:** Currently hardcoded, could be moved to:
```elm
-- Config.elm
type alias Config =
    { apiBaseUrl : String
    , cognitoUserPoolId : String
    , cognitoClientId : String
    , identityPoolId : String
    , s3Bucket : String
    }
```

**Environment-specific config:**
- Development: localhost API proxy
- Production: deployed API Gateway URL

## Security Considerations

- Never log or display sensitive tokens
- Use HTTPS for all API calls
- Validate file types before upload (PDF only)
- Implement file size limits (frontend + backend)
- Clear tokens on logout
- Handle token expiration (refresh or re-login)
- Sanitize user input
- Use Content Security Policy headers

## Browser Support

**Target:**
- Modern evergreen browsers (Chrome, Firefox, Safari, Edge)
- ES6+ JavaScript output from Elm
- No IE11 support needed

**Required Browser APIs:**
- File API (for file upload)
- Fetch API (via elm/http)
- LocalStorage (future enhancement)

## Accessibility

**MVP Standards:**
- Semantic HTML from Elm's Html module
- Keyboard navigation for all interactive elements
- Focus states on inputs and buttons
- Alt text for any icons/images
- Color contrast meeting WCAG AA standards

**Future:**
- ARIA labels and roles
- Screen reader testing
- Keyboard shortcuts
- Focus management on route changes

---

## Quick Reference

**Current Backend Status:**
- ✅ Authentication: Cognito User Pool + Identity Pool
- ✅ API: HTTP API Gateway with JWT authorizer
- ✅ Storage: S3 with Identity Pool access
- ✅ Processing: Step Functions + ECS Fargate
- ✅ Integration tests passing

**API Endpoint:**
`https://eykwwhrt16.execute-api.us-east-1.amazonaws.com`

**Cognito Details:**
- User Pool ID: `us-east-1_wslqPOxQd`
- Client ID: `4tmf8s58738hrbrp4ff2utqg5`
- Identity Pool ID: `us-east-1:1fd26b6e-8a1c-4dd7-940d-60ec7884f384`

**Test User:**
- Email: `integration-test@pdf-models.local`
- Password: `TestPass123!`
