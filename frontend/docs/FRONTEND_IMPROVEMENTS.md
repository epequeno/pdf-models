# Frontend Improvement Plan

This document outlines planned improvements to the PDF Models frontend based on the recently stabilized backend infrastructure.

## Backend Context

The backend has been stabilized with the following improvements:
- **Performance**: Pre-downloaded ML models reduced processing time from 10+ minutes to ~30 seconds
- **Reliability**: Marker container font permission issues resolved via monkey-patching
- **Infrastructure**: Parameterized pipeline with dynamic task definition resolution
- **Documentation**: Comprehensive architecture and troubleshooting guides

## Current Frontend State

The frontend currently supports:
- ✅ Authentication with Cognito (User Pool + Identity Pool)
- ✅ File upload to S3 with progress tracking
- ✅ Job submission via API
- ✅ Job listing and status display
- ✅ Timeline component with visual progress indicators
- ✅ Result download functionality
- ✅ Manual refresh for job updates

## Planned Improvements

### Critical Priority - Authentication Persistence

#### 0. Implement LocalStorage Token Persistence and Refresh

**Current Issue**: Users are logged out on every page refresh. Authentication tokens are not persisted, and refresh tokens are not captured or used.

**Impact**: Poor user experience - users must re-authenticate constantly.

**Location**:
- `frontend/dst/interop.js` (JavaScript authentication logic)
- `frontend/src/Auth.elm` (Elm port definitions)
- `frontend/src/Types.elm` (AuthTokens type)
- `frontend/src/Main.elm` (init and update functions)

**Implementation Overview**:

This is a **multi-step implementation** that requires changes across JavaScript interop, Elm types, and application initialization.

---

**Step 1: Update JavaScript Interop to Capture and Store Refresh Token**

Location: `frontend/dst/interop.js:195-260`

```javascript
// Update authenticateWithCognito to capture refresh token
async function authenticateWithCognito(email, password) {
    // Step 1: Authenticate with Cognito User Pool
    const authParams = {
        AuthFlow: 'USER_PASSWORD_AUTH',
        ClientId: AWS_CONFIG.clientId,
        AuthParameters: {
            USERNAME: email,
            PASSWORD: password
        }
    };

    const cognitoResponse = await fetch(
        `https://cognito-idp.${AWS_CONFIG.region}.amazonaws.com/`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-amz-json-1.1',
                'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth'
            },
            body: JSON.stringify(authParams)
        }
    );

    if (!cognitoResponse.ok) {
        const error = await cognitoResponse.json();
        throw new Error(error.message || error.__type || 'Authentication failed');
    }

    const authResult = await cognitoResponse.json();
    const idToken = authResult.AuthenticationResult.IdToken;
    const accessToken = authResult.AuthenticationResult.AccessToken;
    const refreshToken = authResult.AuthenticationResult.RefreshToken;  // ADD THIS
    const expiresIn = authResult.AuthenticationResult.ExpiresIn;  // Seconds until expiration

    // Step 2: Get Identity ID from Identity Pool
    const identityParams = {
        IdentityPoolId: AWS_CONFIG.identityPoolId,
        Logins: {
            [`cognito-idp.${AWS_CONFIG.region}.amazonaws.com/${AWS_CONFIG.userPoolId}`]: idToken
        }
    };

    const identityResponse = await fetch(
        `https://cognito-identity.${AWS_CONFIG.region}.amazonaws.com/`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-amz-json-1.1',
                'X-Amz-Target': 'AWSCognitoIdentityService.GetId'
            },
            body: JSON.stringify(identityParams)
        }
    );

    if (!identityResponse.ok) {
        throw new Error('Failed to get identity ID');
    }

    const identityResult = await identityResponse.json();
    const identityId = identityResult.IdentityId;

    // Calculate expiration timestamp
    const expiresAt = Date.now() + (expiresIn * 1000);

    const tokens = {
        success: true,
        accessToken: accessToken,
        idToken: idToken,
        refreshToken: refreshToken,  // ADD THIS
        identityId: identityId,
        expiresAt: expiresAt  // ADD THIS
    };

    // Store tokens in localStorage
    localStorage.setItem('pdfmodels_auth', JSON.stringify({
        accessToken,
        idToken,
        refreshToken,
        identityId,
        expiresAt
    }));

    return tokens;
}
```

---

**Step 2: Add Refresh Token Function**

Add to `frontend/dst/interop.js`:

```javascript
// Refresh access token using refresh token
async function refreshAuthToken(refreshToken) {
    const refreshParams = {
        AuthFlow: 'REFRESH_TOKEN_AUTH',
        ClientId: AWS_CONFIG.clientId,
        AuthParameters: {
            REFRESH_TOKEN: refreshToken
        }
    };

    const response = await fetch(
        `https://cognito-idp.${AWS_CONFIG.region}.amazonaws.com/`,
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-amz-json-1.1',
                'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth'
            },
            body: JSON.stringify(refreshParams)
        }
    );

    if (!response.ok) {
        const error = await response.json();
        throw new Error(error.message || 'Token refresh failed');
    }

    const result = await response.json();
    const newAccessToken = result.AuthenticationResult.AccessToken;
    const newIdToken = result.AuthenticationResult.IdToken;
    const expiresIn = result.AuthenticationResult.ExpiresIn;

    // Note: Refresh token is NOT returned in refresh response, use existing one
    return {
        accessToken: newAccessToken,
        idToken: newIdToken,
        expiresIn: expiresIn
    };
}

// Load tokens from localStorage and refresh if needed
async function restoreAuthSession() {
    const stored = localStorage.getItem('pdfmodels_auth');
    if (!stored) {
        return { success: false, error: 'No stored session' };
    }

    try {
        const tokens = JSON.parse(stored);
        const now = Date.now();

        // Check if token is expired or will expire in next 5 minutes
        if (tokens.expiresAt - now < 5 * 60 * 1000) {
            console.log('Token expired or expiring soon, refreshing...');

            // Refresh the token
            const refreshed = await refreshAuthToken(tokens.refreshToken);
            const newExpiresAt = now + (refreshed.expiresIn * 1000);

            // Update stored tokens
            const updatedTokens = {
                accessToken: refreshed.accessToken,
                idToken: refreshed.idToken,
                refreshToken: tokens.refreshToken,  // Keep existing refresh token
                identityId: tokens.identityId,
                expiresAt: newExpiresAt
            };

            localStorage.setItem('pdfmodels_auth', JSON.stringify(updatedTokens));

            return {
                success: true,
                accessToken: refreshed.accessToken,
                idToken: refreshed.idToken,
                refreshToken: tokens.refreshToken,
                identityId: tokens.identityId,
                expiresAt: newExpiresAt
            };
        }

        // Token still valid
        return {
            success: true,
            ...tokens
        };
    } catch (error) {
        console.error('Failed to restore session:', error);
        localStorage.removeItem('pdfmodels_auth');
        return { success: false, error: error.message };
    }
}

// Clear stored tokens on sign out
function clearAuthSession() {
    localStorage.removeItem('pdfmodels_auth');
}
```

---

**Step 3: Add Ports for Session Restoration**

Update `frontend/src/Auth.elm`:

```elm
-- Add new ports for session restoration
port restoreSessionPort : () -> Cmd msg

port receiveRestoredSession : (Encode.Value -> msg) -> Sub msg

port clearSessionPort : () -> Cmd msg


-- Add new command
restoreSession : Cmd msg
restoreSession =
    restoreSessionPort ()

clearSession : Cmd msg
clearSession =
    clearSessionPort ()


-- Update AuthResponse type to include refresh token
type alias AuthResponse =
    { success : Bool
    , accessToken : Maybe String
    , idToken : Maybe String
    , refreshToken : Maybe String  -- ADD THIS
    , identityId : Maybe String
    , expiresAt : Maybe Int  -- ADD THIS (milliseconds timestamp)
    , error : Maybe String
    }


-- Update decoder
authResponseDecoder : Decoder AuthResponse
authResponseDecoder =
    Decode.map7 AuthResponse
        (Decode.field "success" Decode.bool)
        (Decode.maybe (Decode.field "accessToken" Decode.string))
        (Decode.maybe (Decode.field "idToken" Decode.string))
        (Decode.maybe (Decode.field "refreshToken" Decode.string))  -- ADD THIS
        (Decode.maybe (Decode.field "identityId" Decode.string))
        (Decode.maybe (Decode.field "expiresAt" Decode.int))  -- ADD THIS
        (Decode.maybe (Decode.field "error" Decode.string))
```

---

**Step 4: Update Elm Types to Store Refresh Token**

Update `frontend/src/Types.elm:47-51`:

```elm
type alias AuthTokens =
    { accessToken : String
    , idToken : String
    , refreshToken : String  -- ADD THIS
    , identityId : String
    , expiresAt : Int  -- ADD THIS (milliseconds since epoch)
    }
```

---

**Step 5: Update Main.elm to Restore Session on Init**

Update `frontend/src/Main.elm:41-50`:

```elm
init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        route =
            parseUrl url

        model =
            Types.initModel key route
    in
    -- Attempt to restore authentication session from localStorage
    ( model, Auth.restoreSession )
```

Add new message type in `frontend/src/Types.elm:109-145`:

```elm
type Msg
    = UrlChanged Url.Url
    | LinkClicked Browser.UrlRequest
    | SessionRestored (Result String AuthTokens)  -- ADD THIS
    -- Auth - Login
    | EmailChanged String
    ...
```

---

**Step 6: Handle Session Restoration in Update**

Add to `frontend/src/Main.elm` update function:

```elm
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SessionRestored result ->
            case result of
                Ok tokens ->
                    ( { model | auth = Authenticated tokens }
                    , Cmd.none
                    )

                Err _ ->
                    -- No stored session or restoration failed
                    ( model, Cmd.none )

        AuthResponseReceived jsonString ->
            case Decode.decodeString Auth.authResponseDecoder jsonString of
                Ok response ->
                    if response.success then
                        case ( response.accessToken, response.idToken, response.refreshToken, response.identityId, response.expiresAt ) of
                            ( Just accessToken, Just idToken, Just refreshToken, Just identityId, Just expiresAt ) ->
                                let
                                    tokens =
                                        { accessToken = accessToken
                                        , idToken = idToken
                                        , refreshToken = refreshToken  -- ADD THIS
                                        , identityId = identityId
                                        , expiresAt = expiresAt  -- ADD THIS
                                        }
                                in
                                ( { model | auth = Authenticated tokens }
                                , Nav.pushUrl model.key "/upload"
                                )
                            -- Handle case where refresh token or expiresAt is missing
                            ...

        SignOutClicked ->
            ( { model | auth = NotAuthenticated }
            , Cmd.batch
                [ Auth.clearSession
                , Nav.pushUrl model.key "/login"
                ]
            )
```

---

**Step 7: Add Subscription for Restored Session**

Update `frontend/src/Main.elm:618-680`:

```elm
subscriptions : Model -> Sub Msg
subscriptions model =
    let
        -- Add subscription for restored session
        restoredSessionSub =
            Auth.receiveRestoredSession
                (\value ->
                    case Decode.decodeValue Auth.authResponseDecoder value of
                        Ok response ->
                            if response.success then
                                case ( response.accessToken, response.idToken, response.refreshToken, response.identityId, response.expiresAt ) of
                                    ( Just accessToken, Just idToken, Just refreshToken, Just identityId, Just expiresAt ) ->
                                        SessionRestored (Ok
                                            { accessToken = accessToken
                                            , idToken = idToken
                                            , refreshToken = refreshToken
                                            , identityId = identityId
                                            , expiresAt = expiresAt
                                            })

                                    _ ->
                                        SessionRestored (Err "Invalid session data")
                            else
                                SessionRestored (Err (Maybe.withDefault "Session restore failed" response.error))

                        Err _ ->
                            SessionRestored (Err "Failed to decode session")
                )

        authSub =
            Auth.receiveAuthResponse
                (\value ->
                    case Decode.decodeValue Decode.string value of
                        Ok jsonString ->
                            AuthResponseReceived jsonString

                        Err _ ->
                            AuthResponseReceived "{}"
                )

        -- ... other subscriptions
    in
    Sub.batch [ restoredSessionSub, authSub, signUpSub, confirmSignUpSub, uploadProgressSub, uploadResponseSub, pollSub ]
```

---

**Step 8: Wire Up JavaScript Ports**

Update `frontend/dst/interop.js` AwsInterop.setup function:

```javascript
window.AwsInterop = {
    setup: function(ports) {
        console.log('AWS Interop ready');

        // Handle session restoration requests
        if (ports.restoreSessionPort) {
            ports.restoreSessionPort.subscribe(async function() {
                try {
                    const result = await restoreAuthSession();
                    if (ports.receiveRestoredSession) {
                        ports.receiveRestoredSession.send(JSON.stringify(result));
                    }
                } catch (error) {
                    console.error('Session restoration error:', error);
                    if (ports.receiveRestoredSession) {
                        ports.receiveRestoredSession.send(JSON.stringify({
                            success: false,
                            error: error.message
                        }));
                    }
                }
            });
        }

        // Handle clear session requests
        if (ports.clearSessionPort) {
            ports.clearSessionPort.subscribe(function() {
                clearAuthSession();
            });
        }

        // ... existing signInPort, signUpPort, etc.
    }
};
```

---

**Step 9: Proactive Token Refresh**

Add background token refresh to ensure tokens never expire during active use:

In `frontend/src/Main.elm` subscriptions:

```elm
subscriptions : Model -> Sub Msg
subscriptions model =
    let
        -- Add token refresh check every 4 minutes
        tokenRefreshSub =
            case model.auth of
                Authenticated tokens ->
                    -- Check every 4 minutes if we need to refresh
                    Time.every (4 * 60 * 1000) (\_ -> CheckTokenExpiration)

                _ ->
                    Sub.none

        -- ... other subscriptions
    in
    Sub.batch [ tokenRefreshSub, restoredSessionSub, authSub, ... ]
```

Add new message:

```elm
type Msg
    = ...
    | CheckTokenExpiration
    | TokenRefreshed (Result String AuthTokens)
```

Add handler:

```elm
CheckTokenExpiration ->
    case model.auth of
        Authenticated tokens ->
            let
                now = Time.posixToMillis model.currentTime
                timeUntilExpiry = tokens.expiresAt - now
                fiveMinutes = 5 * 60 * 1000
            in
            if timeUntilExpiry < fiveMinutes then
                -- Trigger refresh via JavaScript
                ( model, Auth.refreshTokenCmd tokens.refreshToken )
            else
                ( model, Cmd.none )

        _ ->
            ( model, Cmd.none )
```

---

**Security Considerations**:

1. **localStorage vs sessionStorage**: Using localStorage means tokens persist across browser sessions. For better security, consider:
   - Using sessionStorage (clears on browser close)
   - Encrypting tokens before storage
   - Adding a "Remember me" checkbox to let users choose

2. **XSS Protection**: Ensure proper Content Security Policy headers are set

3. **Refresh Token Rotation**: Cognito doesn't rotate refresh tokens by default, but you can enable it in User Pool settings

4. **Token Expiration**: Access tokens expire after 1 hour by default, refresh tokens after 30 days

---

**Testing Checklist**:
- [ ] User stays logged in after page refresh
- [ ] Tokens automatically refresh when approaching expiration
- [ ] Sign out properly clears localStorage
- [ ] Expired refresh token redirects to login
- [ ] Multiple tabs share authentication state
- [ ] Manual localStorage deletion handled gracefully

---

**Estimated Effort**: 6-8 hours (complex, touches many files)

**Priority**: **CRITICAL** - Should be implemented before other improvements. Poor authentication UX is a major blocker.

---

### High Priority

#### 1. Fix Timestamp Formatting

**Current Issue**: Timeline component shows "Just now" for all timestamps instead of actual dates.

**Location**: `frontend/src/Components/Timeline.elm:237-243`

**Implementation**:
```elm
-- Replace placeholder formatTimestamp function
formatTimestamp : Maybe Time.Posix -> String
formatTimestamp maybeTime =
    case maybeTime of
        Just time ->
            -- Use elm/time or third-party package for proper ISO 8601 formatting
            -- Consider: justinmimbs/time-extra or ryangatchalian912/elm-datetime
            formatDateTime time
        Nothing ->
            ""
```

**Considerations**:
- Install Elm package for date formatting (e.g., `justinmimbs/time-extra`)
- Format as human-readable: "Jan 4, 2026 3:45 PM" or relative: "2 minutes ago"
- Consider timezone handling (display in user's local time)

**Estimated Effort**: 1-2 hours

---

#### 2. Implement Auto-Polling for Active Jobs

**Current Issue**: Users must manually click "Refresh" to see job status updates.

**Location**: `frontend/src/Main.elm` (subscriptions), `frontend/src/Types.elm:144` (PollTick already defined)

**Implementation**:
```elm
-- In Main.elm subscriptions
subscriptions : Model -> Sub Msg
subscriptions model =
    case model.route of
        Jobs ->
            if hasActiveJobs model.jobs then
                Time.every (5 * 1000) PollTick  -- Poll every 5 seconds
            else
                Sub.none
        _ ->
            Sub.none

-- Helper function
hasActiveJobs : JobsState -> Bool
hasActiveJobs jobsState =
    List.any (\job -> job.status == Pending || job.status == Processing) jobsState.jobs

-- In update function
PollTick _ ->
    case model.auth of
        Authenticated tokens ->
            ( { model | jobs = { jobs | loading = True } }
            , Api.getJobs tokens.accessToken JobsFetched
            )
        _ ->
            ( model, Cmd.none )
```

**Considerations**:
- Only poll when on Jobs page
- Stop polling when all jobs are complete/failed
- Show visual indicator when polling is active
- Consider exponential backoff if job takes longer than expected
- Stop polling if user navigates away

**Estimated Effort**: 2-3 hours

---

#### 3. Display Processing Time

**Enhancement**: Show users how long their jobs took to process.

**Location**: `frontend/src/Views/Jobs.elm` (job card) and `frontend/src/Components/Timeline.elm`

**Implementation**:
```elm
-- Calculate duration
calculateDuration : Time.Posix -> Maybe Time.Posix -> Maybe String
calculateDuration submittedAt completedAt =
    case completedAt of
        Just completed ->
            let
                durationMs = Time.posixToMillis completed - Time.posixToMillis submittedAt
                durationSeconds = durationMs // 1000
            in
            if durationSeconds < 60 then
                Just (String.fromInt durationSeconds ++ " seconds")
            else
                Just (String.fromInt (durationSeconds // 60) ++ " minutes")
        Nothing ->
            Nothing

-- Display in job card
case job.status of
    Complete ->
        case calculateDuration job.submittedAt job.completedAt of
            Just duration ->
                div [ css [ ... ] ]
                    [ text ("Completed in " ++ duration) ]
            Nothing ->
                text ""
```

**Considerations**:
- Show in timeline completion event
- Highlight fast processing times (< 60 seconds)
- Format nicely: "Completed in 32 seconds"

**Estimated Effort**: 1-2 hours

---

### Medium Priority

#### 4. Improve Error Handling

**Enhancement**: Provide better user-facing error messages for common failures.

**Locations**:
- `frontend/src/Views/Upload.elm` (upload errors)
- `frontend/src/Views/Jobs.elm` (API errors)
- `frontend/src/Main.elm` (authentication errors)

**Implementation**:
```elm
-- Create error message mapper
userFriendlyError : Http.Error -> String
userFriendlyError error =
    case error of
        Http.BadStatus 401 ->
            "Your session has expired. Please sign in again."

        Http.BadStatus 403 ->
            "You don't have permission to access this resource."

        Http.BadStatus 404 ->
            "Resource not found. The job may have been deleted."

        Http.Timeout ->
            "Request timed out. Please check your connection and try again."

        Http.NetworkError ->
            "Network error. Please check your internet connection."

        _ ->
            "An unexpected error occurred. Please try again."
```

**Common Error Scenarios**:
- S3 upload failures (permissions, network)
- JWT token expiration (need to refresh or re-authenticate)
- API timeouts
- Invalid file format
- Job not found (lifecycle policy deleted it)

**Considerations**:
- Add error boundaries for graceful degradation
- Provide actionable guidance (e.g., "Sign in again")
- Consider retry mechanisms for transient errors
- Log errors for debugging (console)

**Estimated Effort**: 3-4 hours

---

#### 5. File Validation Before Upload

**Enhancement**: Validate files on the client side before attempting upload.

**Location**: `frontend/src/Views/Upload.elm`

**Implementation**:
```elm
-- Validate file on selection
FileSelected file ->
    let
        fileName = File.name file
        fileSize = File.size file
        mimeType = File.mime file

        validation = validateFile fileName fileSize mimeType
    in
    case validation of
        Ok _ ->
            ( { model | upload = { upload | selectedFile = Just file, error = Nothing } }
            , Cmd.none
            )

        Err errorMsg ->
            ( { model | upload = { upload | selectedFile = Nothing, error = Just errorMsg } }
            , Cmd.none
            )

validateFile : String -> Int -> String -> Result String ()
validateFile fileName fileSize mimeType =
    if not (String.endsWith ".pdf" (String.toLower fileName)) then
        Err "Only PDF files are supported"
    else if fileSize > 50 * 1024 * 1024 then  -- 50MB limit
        Err "File size must be less than 50MB"
    else if fileSize == 0 then
        Err "File is empty"
    else
        Ok ()
```

**Validations**:
- File type must be PDF (check extension and MIME type)
- File size within limits (warn if >10MB, reject if >50MB)
- File is not empty
- Filename is valid (no special characters that break S3)

**UI Enhancements**:
- Show file details after selection (name, size, type)
- Display file size in human-readable format
- Visual warning for large files (slower upload)

**Estimated Effort**: 2-3 hours

---

#### 6. Token Refresh Handling

**Enhancement**: Automatically refresh expired tokens instead of forcing re-authentication.

**Location**: `frontend/src/Auth.elm`, `frontend/src/Main.elm`

**Implementation**:
```elm
-- Detect token expiration and refresh
type alias AuthTokens =
    { accessToken : String
    , idToken : String
    , identityId : String
    , refreshToken : String  -- ADD THIS
    , expiresAt : Time.Posix  -- ADD THIS
    }

-- Check if token needs refresh before API calls
needsRefresh : AuthTokens -> Time.Posix -> Bool
needsRefresh tokens currentTime =
    let
        expiresInMs = Time.posixToMillis tokens.expiresAt - Time.posixToMillis currentTime
        fiveMinutesMs = 5 * 60 * 1000
    in
    expiresInMs < fiveMinutesMs

-- Add refresh command
refreshToken : String -> (Result Http.Error AuthTokens -> msg) -> Cmd msg
refreshToken refreshToken toMsg =
    -- Call Cognito refresh token endpoint
    -- Implementation depends on AWS Amplify integration
```

**Considerations**:
- Store refresh token securely (consider encryption)
- Refresh proactively (5 minutes before expiration)
- Handle refresh failures gracefully
- Clear tokens and redirect to login if refresh fails

**Estimated Effort**: 4-5 hours (requires AWS Amplify integration)

---

### Low Priority

#### 7. Markdown Preview Modal

**Enhancement**: Allow users to preview converted markdown before downloading.

**Location**: New component `frontend/src/Components/MarkdownPreview.elm`

**Implementation**:
```elm
-- Add preview mode to model
type alias JobsState =
    { jobs : List Job
    , loading : Bool
    , error : Maybe String
    , lastRefresh : Maybe Time.Posix
    , previewingJob : Maybe String  -- Job ID being previewed
    , previewContent : Maybe String
    }

-- Messages
type Msg
    = ...
    | PreviewResult String  -- Job ID
    | PreviewLoaded (Result Http.Error String)
    | ClosePreview
    | CopyToClipboard

-- Download result from S3 and display in modal
previewResult : String -> AuthTokens -> Cmd Msg
previewResult jobId tokens =
    -- Fetch markdown content from S3
    -- Display in modal with rendered preview
```

**Features**:
- Modal overlay with markdown content
- Syntax highlighted code blocks
- Copy to clipboard button
- Download button
- Close/ESC to dismiss

**Considerations**:
- Need markdown rendering library (`pablohirafuji/elm-markdown`)
- Handle large files (pagination or scroll)
- Consider security (sanitize markdown)

**Estimated Effort**: 4-6 hours

---

#### 8. Job Filtering and Sorting

**Enhancement**: Help users find jobs more easily.

**Location**: `frontend/src/Views/Jobs.elm`

**Implementation**:
```elm
-- Add filter state to model
type alias JobsState =
    { jobs : List Job
    , filteredJobs : List Job  -- ADD THIS
    , filter : JobFilter  -- ADD THIS
    , sortBy : SortOption  -- ADD THIS
    , ...
    }

type JobFilter
    = AllJobs
    | OnlyPending
    | OnlyProcessing
    | OnlyComplete
    | OnlyFailed

type SortOption
    = NewestFirst
    | OldestFirst
    | StatusAsc
    | StatusDesc

-- Filter and sort functions
filterJobs : JobFilter -> List Job -> List Job
filterJobs filter jobs =
    case filter of
        AllJobs -> jobs
        OnlyPending -> List.filter (\j -> j.status == Pending) jobs
        ...

sortJobs : SortOption -> List Job -> List Job
sortJobs option jobs =
    case option of
        NewestFirst -> List.sortBy (.submittedAt >> Time.posixToMillis >> negate) jobs
        ...
```

**UI Components**:
- Filter pills/tabs (All, Pending, Processing, Complete, Failed)
- Sort dropdown (Newest first, Oldest first)
- Search input (filter by filename)
- Show count: "Showing 5 of 12 jobs"

**Estimated Effort**: 3-4 hours

---

#### 9. Success Notifications

**Enhancement**: Provide feedback after successful operations.

**Location**: New component `frontend/src/Components/Toast.elm`

**Implementation**:
```elm
-- Add toast state to model
type alias Model =
    { ...
    , toast : Maybe Toast
    }

type alias Toast =
    { message : String
    , type_ : ToastType
    , expiresAt : Time.Posix
    }

type ToastType
    = Success
    | Error
    | Info
    | Warning

-- Show toast after job submission
JobSubmitted (Ok job) ->
    ( { model
        | upload = resetUpload
        , toast = Just (Toast "Job submitted successfully!" Success (addSeconds 5 now))
      }
    , Cmd.batch
        [ Nav.pushUrl model.key "/jobs"
        , Api.getJobs tokens.accessToken JobsFetched
        ]
    )
```

**Features**:
- Auto-dismiss after 5 seconds
- Dismiss on click
- Queue multiple toasts
- Animate in/out
- Positioned at top-right of screen

**Estimated Effort**: 3-4 hours

---

#### 10. Empty State Improvements

**Enhancement**: Better guidance when no jobs exist.

**Location**: `frontend/src/Views/Jobs.elm:104-114`

**Current State**: Shows basic "No jobs yet" message.

**Enhancement**:
```elm
-- Empty state with call-to-action
div [ css [ ... emptyStateStyles ] ]
    [ div [ css [ ... iconStyles ] ]
        [ text "📄" ]  -- Or use SVG icon
    , h3 [ css [ ... ] ]
        [ text "No jobs yet" ]
    , p [ css [ ... ] ]
        [ text "Upload a PDF document to convert it to Markdown format" ]
    , a [ href "/upload", css [ ... buttonStyles ] ]
        [ text "Upload Your First PDF" ]
    , div [ css [ ... helpTextStyles ] ]
        [ text "Processing typically takes 30-60 seconds"
        , text "Supported formats: PDF"
        , text "Maximum file size: 50MB"
        ]
    ]
```

**Estimated Effort**: 1-2 hours

---

## Implementation Strategy

### Phase 1: Quick Wins (1-2 days)
1. Fix timestamp formatting
2. Implement auto-polling
3. Display processing time
4. Improve empty states

**Goal**: Significantly improve UX with minimal effort.

---

### Phase 2: Robustness (2-3 days)
1. File validation
2. Better error handling
3. Token refresh mechanism

**Goal**: Make the app more reliable and user-friendly.

---

### Phase 3: Polish (3-5 days)
1. Markdown preview modal
2. Job filtering and sorting
3. Success notifications
4. UI refinements

**Goal**: Professional, feature-rich application.

---

## Technical Considerations

### Dependencies to Add
- Date/time formatting: `justinmimbs/time-extra` or `ryangatchalian912/elm-datetime`
- Markdown rendering: `pablohirafuji/elm-markdown`
- Clipboard access: Port to JavaScript

### API Compatibility
Current API implementation is compatible with all planned features. No backend changes required.

### Browser Compatibility
- Test file upload on Safari (known issues with File API)
- Test auto-polling doesn't cause excessive battery drain
- Ensure markdown preview handles large files

### Performance
- Auto-polling: Only when needed, stop when complete
- File validation: Client-side only, very fast
- Markdown preview: May need optimization for large files

### Accessibility
- Keyboard navigation for filters/modals
- Screen reader announcements for status updates
- High contrast mode support
- Focus management in modals

---

## Testing Checklist

### Manual Testing
- [ ] Upload various PDF file sizes (1KB, 10MB, 50MB)
- [ ] Test with invalid file types
- [ ] Verify auto-polling starts and stops correctly
- [ ] Test token expiration handling
- [ ] Check timeline timestamps display correctly
- [ ] Verify error messages are user-friendly
- [ ] Test on mobile devices (responsive design)

### Edge Cases
- [ ] Very long filenames
- [ ] Special characters in filenames
- [ ] Network disconnection during upload
- [ ] Multiple tabs open simultaneously
- [ ] Browser refresh during job processing
- [ ] S3 lifecycle deletion (7-day limit)

---

## Notes

### API Response Format
Jobs returned from API (`GET /v1/models/marker/jobs`):
```json
{
  "jobs": [
    {
      "job_id": "uuid",
      "created_at": "2026-01-04T12:00:00Z",
      "status": "completed",
      "s3_input_key": "identity-id/job-id.pdf",
      "s3_result_key": "identity-id/job-id-result.md",
      "completed_at": "2026-01-04T12:00:35Z",
      "error": null
    }
  ]
}
```

### Current Limitations
- No pagination for job list (fine for MVP, consider if users have 100+ jobs)
- No job cancellation (jobs run to completion)
- No batch processing (one PDF at a time)
- No result caching (re-upload same file creates new job)

### Future Enhancements (Out of Scope)
- Real-time updates via WebSocket (instead of polling)
- Batch upload (multiple PDFs)
- Job management (delete, cancel, retry)
- Result comparison (diff between conversions)
- User preferences (theme, default settings)
- API key management for programmatic access
- Usage analytics dashboard

---

## References

- Backend Architecture: `backend/docs/architecture.md`
- Backend Troubleshooting: `backend/docs/TROUBLESHOOTING.md`
- Current API Implementation: `frontend/src/Api.elm`
- Type Definitions: `frontend/src/Types.elm`
