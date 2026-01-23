# PDF Models Platform - Design Brief

## Application Overview

PDF Models is a web platform that provides access to multiple AI-powered document processing models. Users can upload PDF documents, select from various processing models, submit jobs, and download the processed results. The platform serves as a comparison and evaluation tool for different document OCR and understanding models.

**Target Users**: Developers, data scientists, and organizations evaluating document processing solutions for production use.

## User Roles

### Standard User
- Upload and process documents
- View their own job history
- Create and manage custom model configurations
- Compare model capabilities

### Administrator
- All standard user capabilities
- Review and approve/reject user-submitted custom configurations
- Access admin dashboard for configuration management

## Core Application Screens

### 1. Authentication Screens

#### Sign Up
**Purpose**: New user registration

**Required Elements**:
- Email address input field
- Password input field (with visibility toggle)
- Password confirmation field
- Terms of service acknowledgment
- Submit button
- Link to login page

**Workflow**:
- User enters email and password
- System sends confirmation code to email
- User enters confirmation code to activate account
- Success redirects to login

#### Login
**Purpose**: User authentication

**Required Elements**:
- Email address input field
- Password input field (with visibility toggle)
- "Remember me" option
- Submit button
- Link to sign up page
- Password recovery link

**Workflow**:
- User enters credentials
- System validates and creates session
- Success redirects to upload page

### 2. Upload Screen (Primary Landing Page for Authenticated Users)

**Purpose**: Submit documents for processing

**Required Elements**:
- **Model Selector**: Display currently selected model with ability to change
- **File Upload Area**:
  - Drag-and-drop zone for PDF files
  - Alternative file picker button
  - File type restriction (PDF only)
  - File size limit indicator
- **Selected File Information**:
  - File name
  - File size
  - Preview/thumbnail if possible
  - Remove file button
- **Custom Prompt Input** (conditional - only shown for models that support prompts):
  - Multi-line text area
  - Default prompt suggestion
  - Character count
  - Helper text explaining prompt usage
- **Configuration Selector** (optional):
  - Dropdown or list of saved configurations for the selected model
  - Shows custom settings (CPU, memory, GPU, etc.)
  - Option to use default settings
- **Upload Progress**:
  - Progress bar showing upload percentage
  - Cancel upload button
- **Submit Button**:
  - Disabled until file is uploaded
  - Clear call-to-action text
- **Recent Jobs Quick View**:
  - Last 3-5 submitted jobs
  - Quick status indicators
  - Link to full job history

**Model Selection Interaction**:
- Keyboard shortcut (Cmd/Ctrl+K) to open model selector
- Search/filter models by name, category, capabilities
- Display model key information: name, description, speed, accuracy

**Workflow**:
1. User selects model (default loads on page entry)
2. User drags or selects PDF file
3. (Optional) User enters custom prompt if model supports it
4. (Optional) User selects saved configuration
5. System uploads file to S3 with progress indication
6. User clicks submit
7. System creates job and redirects to job detail or jobs list

### 3. Jobs Dashboard

**Purpose**: View and manage document processing jobs

**Required Elements**:
- **Job List**:
  - Job ID (truncated with copy button)
  - Original filename
  - Model used
  - Status indicator (pending, processing, completed, failed)
  - Submission timestamp
  - Completion timestamp (if applicable)
  - Processing duration
  - Action buttons (download, view details, resubmit)
- **Filtering Controls**:
  - Filter by status
  - Filter by model
  - Date range selector
  - Search by filename or job ID
- **Refresh Controls**:
  - Manual refresh button
  - Last refreshed timestamp
  - Auto-refresh toggle with interval indicator
- **Job Details (Expandable or Modal)**:
  - Full job information
  - Processing substatus (downloading, loading models, converting, uploading)
  - Custom prompt used (if applicable)
  - Configuration used (if applicable)
  - Input file S3 key
  - Output file S3 key
  - Error messages (if failed)
  - Full error stack trace (expandable)
  - Download result button
  - Resubmit with same settings button

**Job Status States**:
- **Pending**: Queued, waiting to start
- **Processing**: Currently being processed (show substatus)
- **Completed**: Successfully processed, result available
- **Failed**: Processing failed with error details

**Workflow**:
- Jobs automatically refresh while processing jobs exist
- User can manually refresh at any time
- User can expand job to see full details
- User can download results for completed jobs
- User can filter and search to find specific jobs

### 4. Models Comparison Screen

**Purpose**: Explore, compare, and understand available models

**Required Elements**:
- **Model Grid/List**:
  - Model name and display name
  - Model producer/organization
  - Short description
  - Category badge (OCR & Conversion, Layout Analysis, Document Understanding)
  - Capability tags (Tables, Math, Handwriting, Multi-column, Multi-language, Images, Structured output, Custom prompts)
  - Compute type indicator (CPU or GPU)
  - Performance tier (Fast, Balanced, High Quality)
  - Benchmark scores (accuracy percentage, speed in pages/sec or sec/page)
  - "Try it" button (navigates to upload with model selected)
- **Search and Filter**:
  - Text search across model names, descriptions, producers
  - Filter by category (multi-select)
  - Filter by capabilities (multi-select)
  - Filter by compute type
  - Active filter indicators
  - Clear filters button
- **Model Details (Expandable Cards or Modal)**:
  - Full description
  - Producer information
  - Links to documentation, GitHub, Hugging Face, arXiv paper
  - Complete capability list
  - Output formats supported
  - Benchmark details with source
  - Best use cases
  - Default prompt (if supports prompts)
  - Example results or sample output
- **Model Comparison Mode**:
  - Select 2-4 models to compare side-by-side
  - Comparison table showing all attributes
  - Clear comparison button

**Interaction**:
- Keyboard shortcut to open quick model palette from any page
- Search-as-you-type filtering
- Click model card to expand details
- Checkbox or toggle to add to comparison
- Sticky filter bar on scroll

### 5. Configurations Screen

**Purpose**: Create, manage, and share custom model configurations

**Required Elements**:
- **Configuration List**:
  - Configuration name
  - Description
  - Model type
  - Visibility (Private or Public)
  - Approval status (Pending, Approved, Rejected)
  - Usage count
  - Created date
  - Last updated date
  - Actions (edit, delete, fork, use)
- **Search and Filter**:
  - Text search by name or description
  - Filter by model
  - Filter by visibility
  - Filter by approval status
- **Create/Edit Configuration Form**:
  - Configuration name (required)
  - Description (optional, multi-line)
  - Model selector (required)
  - Visibility toggle (Private/Public)
  - **Inference Parameters**:
    - Custom prompt (if model supports)
    - Output format preference
    - Custom environment variables (key-value pairs, add/remove)
  - **Infrastructure Parameters**:
    - CPU units (integer input)
    - Memory in MiB (integer input)
    - GPU count (integer input)
    - Timeout in minutes (integer input)
    - Ephemeral storage in GiB (integer input)
    - EBS volume size in GB (integer input)
    - Spot instances enabled (checkbox)
  - Save button
  - Cancel button
  - Validation error messages
- **Configuration Details View**:
  - All configuration parameters
  - Fork button (create copy for editing)
  - Use button (select for next upload)
  - Delete button (with confirmation)
  - Approval status and history
  - Rejection reason (if applicable)

**Workflow - Creating Configuration**:
1. User clicks "Create Configuration"
2. Selects model
3. Enters name and description
4. Configures inference and infrastructure parameters
5. Sets visibility (Private or Public)
6. Saves configuration
7. If Public, configuration enters "Pending Approval" state
8. If Private, configuration is immediately available for use

**Workflow - Using Configuration**:
1. User selects configuration from list
2. Clicks "Use" button
3. Redirected to Upload page with configuration pre-selected
4. Can upload and submit job with custom settings

### 6. Admin Configurations Screen

**Purpose**: Review and approve user-submitted public configurations

**Accessible to**: Administrators only

**Required Elements**:
- **Pending Configurations Queue**:
  - Configuration name
  - Submitting user
  - Model type
  - Submission date
  - Quick preview of settings
  - Review actions (approve, reject, view details)
- **Configuration Review Detail**:
  - All configuration parameters
  - Submitting user information
  - Submission timestamp
  - Risk assessment indicators (unusual resource requests)
  - Approve button with confirmation
  - Reject button with reason text field
  - Security/resource validation warnings
- **Approved Configurations List**:
  - Same as pending, with approval date and approver
  - Revoke button (moves back to rejected state)

**Workflow**:
1. Admin views pending configurations
2. Clicks to review configuration details
3. Evaluates resource requests and parameters
4. Either approves (makes available to all users) or rejects with reason
5. User is notified of approval/rejection

## Cross-Screen Features

### Global Navigation
**Required**:
- Logo/brand
- Navigation menu with clear labels
- Active page indicator
- User account menu:
  - Display user email
  - Settings link
  - Logout button
- Admin menu item (visible only to admins)

### Model Palette (Global Quick Access)
**Activation**: Keyboard shortcut (Cmd/Ctrl+K) from any authenticated page

**Required Elements**:
- Modal overlay
- Search input (auto-focused)
- Filtered model list based on search
- Model quick info (name, category, speed tier)
- Arrow key navigation
- Enter to select model
- Escape to close
- Click outside to close

**Behavior**:
- Opens from any page
- Allows quick model selection
- Selecting model navigates to Upload page with that model

### Notifications/Feedback
**Required States**:
- Success messages (job submitted, configuration saved, etc.)
- Error messages (upload failed, invalid input, API errors)
- Warning messages (large file, long processing time expected)
- Info messages (job completed, authentication expiring)

**Behavior**:
- Non-blocking notifications
- Auto-dismiss after timeout (except errors)
- Manual dismiss option
- Stack multiple notifications

## Data Display Requirements

### Job Data
- Job ID (UUID format, truncated display with full copy)
- Model name (human-readable)
- Original filename
- File size
- Status (enumeration with clear labels)
- Substatus (processing phase)
- Created timestamp (relative time + absolute)
- Completed timestamp (relative time + absolute)
- Duration (calculated, formatted)
- Custom prompt (if used)
- Error message (if failed)
- S3 keys (truncated with copy)

### Model Data
- Model identifier (internal name)
- Display name (user-friendly)
- Producer/organization name
- Description (150-300 words)
- Category badge
- Capabilities (icon + label)
- Compute type (CPU/GPU with icon)
- Performance tier
- Benchmark accuracy (percentage with source)
- Speed benchmark (pages/sec or sec/page)
- Supports custom prompts (boolean)
- Output formats (Markdown, JSON, HTML)
- External links (GitHub, documentation, Hugging Face, arXiv)

### Configuration Data
- Configuration ID (UUID)
- Name (user-provided)
- Description (optional)
- Model name
- Visibility (Private/Public)
- Approval status (Pending/Approved/Rejected)
- Created timestamp
- Updated timestamp
- Usage count (how many jobs used this config)
- Creator user ID
- Inference parameters (prompt, output format, env vars)
- Infrastructure parameters (CPU, memory, GPU, timeout, storage)
- Rejection reason (if rejected)

### User Data
- Email address
- Account creation date
- User role (standard/admin)
- Authentication state
- Token expiration

## Interaction Patterns

### File Upload
- Drag-and-drop support
- Click to browse file system
- Visual feedback for valid/invalid file types
- Progress indication during upload
- Ability to cancel upload
- Success confirmation

### Form Validation
- Real-time validation on blur
- Clear error messages next to fields
- Submit button disabled until valid
- Success feedback on save
- Unsaved changes warning on navigation

### Loading States
- Skeleton screens for initial data load
- Loading spinners for actions (submit, save, delete)
- Disabled states during processing
- Progress indication where applicable

### Error Handling
- Clear error messages in plain language
- Actionable error states (retry buttons)
- Error details available (expandable technical info)
- Fallback UI for failed data loads

### Data Refresh
- Manual refresh buttons
- Auto-refresh for active jobs (5-15 second intervals)
- Refresh timestamp indication
- Visual indication when refresh is in progress
- Optimistic updates where appropriate

### Responsive Behaviors
- Mobile-friendly navigation (hamburger menu)
- Touch-friendly targets and gestures
- Adaptive layouts for small screens
- Table to card layout transformation on mobile
- Swipe gestures for mobile actions

## Functional Requirements

### Performance
- Initial page load under 3 seconds
- File upload progress feedback within 500ms
- API response handling with appropriate loading states
- Pagination or infinite scroll for long job lists (>20 items)
- Debounced search inputs

### Accessibility
- Keyboard navigation for all interactive elements
- Focus indicators visible
- Screen reader support for all content
- Color contrast meeting WCAG AA standards
- Alt text for meaningful images/icons
- Form labels properly associated
- Error messages announced to screen readers

### Browser Support
- Modern browsers (Chrome, Firefox, Safari, Edge)
- Progressive enhancement approach
- Graceful degradation for older browsers

### Security
- Automatic token refresh before expiration
- Session timeout after inactivity
- Secure handling of credentials (no storage in localStorage beyond refresh token)
- CSRF protection for state-changing operations
- Input sanitization and validation

## User Flows

### First-Time User Flow
1. Lands on login page (unauthenticated)
2. Clicks "Sign Up"
3. Enters email and password
4. Receives confirmation code via email
5. Enters confirmation code
6. Account activated
7. Redirects to login
8. Logs in
9. Lands on Upload page
10. Explores models (opens model palette or navigates to Models page)
11. Selects model and uploads first document
12. Navigates to Jobs to see processing status
13. Downloads result when complete

### Regular User Flow - Processing a Document
1. Lands on Upload page (already authenticated)
2. Selects desired model (or keeps default)
3. Uploads PDF file
4. (Optional) Enters custom prompt
5. (Optional) Selects saved configuration
6. Clicks submit
7. Job created, redirected to Jobs page
8. Monitors job progress (auto-refreshing)
9. Downloads result when complete

### Power User Flow - Creating Custom Configuration
1. Navigates to Configurations page
2. Clicks "Create Configuration"
3. Names configuration (e.g., "High-Memory Docling")
4. Selects model
5. Adjusts infrastructure parameters (e.g., 32GB RAM)
6. (Optional) Sets custom prompt
7. Sets visibility to Private
8. Saves configuration
9. Returns to Upload page
10. Selects custom configuration from dropdown
11. Uploads and processes document with custom settings

### Admin Flow - Approving Configuration
1. Receives notification of pending configuration
2. Navigates to Admin Configurations page
3. Reviews pending configuration details
4. Evaluates resource requests
5. Approves or rejects with reason
6. User is notified of decision

### Model Comparison Flow
1. Navigates to Models page
2. Enables comparison mode
3. Selects 2-3 models to compare
4. Views side-by-side comparison table
5. Identifies best model for use case
6. Clicks "Try it" on selected model
7. Redirected to Upload page with model selected

## States and Edge Cases

### Authentication States
- Not authenticated (show login/signup only)
- Authenticated (show full app)
- Token expired (prompt re-login)
- Session restored (from refresh token)

### Job States and Transitions
- Created → Pending (queued)
- Pending → Processing (started)
- Processing → Completed (success)
- Processing → Failed (error)
- (No state can transition to Pending once started)

### Upload States
- No file selected
- File selected (show details)
- Uploading (show progress)
- Upload complete (enable submit)
- Upload failed (show error, allow retry)

### Configuration States
- Draft (being edited)
- Private (saved, user-only)
- Pending Approval (public, awaiting review)
- Approved (public, available to all)
- Rejected (public request denied)

### Network States
- Online (normal operation)
- Offline (show offline indicator, queue actions if possible)
- Slow connection (show warnings, adjust timeouts)
- API error (show error with retry)

### Empty States
- No jobs yet (encourage first upload)
- No results found (adjust filters or search)
- No configurations yet (encourage creation)
- No pending approvals (all clear for admin)

## Content and Copy Requirements

### Tone
- Professional but approachable
- Technical accuracy without jargon overload
- Helpful error messages with suggested actions
- Encouraging empty states

### Key Messages
- Clear value proposition on login/signup
- Model descriptions focus on use cases
- Configuration explanations emphasize customization benefits
- Error messages explain what happened and how to fix

### Labels and Terminology
- "Jobs" not "Tasks" or "Requests"
- "Model" not "Algorithm" or "Service"
- "Configuration" not "Template" or "Preset"
- "Upload" not "Submit" or "Add" (until after file is selected)
- "Process" not "Convert" or "Transform"
- "Result" not "Output" or "File"

## Technical Constraints

### File Handling
- PDF files only
- Maximum file size limit (to be determined by backend)
- Direct upload to S3 (not through API)
- Pre-signed URLs for secure upload/download

### API Integration
- RESTful API with JWT authentication
- Polling for job status (no WebSocket required initially)
- Retry logic for failed requests
- Rate limiting awareness

### Data Refresh
- Jobs list auto-refreshes while processing jobs exist
- Configurable refresh intervals
- Manual refresh always available
- Refresh only affected data, not full page

### Real-time Requirements
- Near real-time job status (15-30 second polling)
- Upload progress updates (real-time)
- No hard real-time requirements (notifications can be delayed)

## Success Metrics

### User Engagement
- Successful job completions
- Return user rate
- Models tried per user
- Custom configurations created

### Usability
- Time from login to first job submission
- Error rate (failed uploads, form validation errors)
- Support ticket volume for UI issues
- Task completion rates

### Performance
- Page load times
- Upload success rate
- API response times
- Time to interactive

## Out of Scope (Future Considerations)

These features are not required for the initial design but may be considered later:
- Batch uploads (multiple PDFs at once)
- Job scheduling
- Webhooks for job completion notifications
- Result export to external systems
- Collaboration features (sharing jobs/configs between users)
- Usage analytics dashboard
- Cost estimation before job submission
- Model versioning and rollback
- A/B testing different models on same document
- Annotation or editing of results within the app
