module Types exposing (..)

import Browser
import Browser.Navigation as Nav
import File exposing (File)
import Http
import Set exposing (Set)
import Time
import Url


-- PDF MODELS


type PdfModel
    = Marker
    | Dolphin
    | Docling
    | DeepSeekOcr
    | MinerU
    | OlmOcr
    | Docext


allPdfModels : List PdfModel
allPdfModels =
    [ Marker, Dolphin, Docling, DeepSeekOcr, MinerU, OlmOcr, Docext ]



-- MODEL CLASSIFICATION


type ModelCategory
    = OcrConversion
    | LayoutAnalysis
    | DocumentUnderstanding


type Capability
    = TableExtraction
    | FormulaMath
    | Handwriting
    | MultiColumn
    | MultiLanguage
    | ImagePreservation
    | StructuredOutput
    | CustomPrompts


type OutputFormat
    = OutputMarkdown
    | OutputJson
    | OutputHtml


type PerformanceTier
    = Fast
    | Balanced
    | HighQuality


type ComputeType
    = CpuCompute
    | GpuCompute


allComputeTypes : List ComputeType
allComputeTypes =
    [ CpuCompute, GpuCompute ]


computeTypeToString : ComputeType -> String
computeTypeToString computeType =
    case computeType of
        CpuCompute ->
            "CPU"

        GpuCompute ->
            "GPU"


computeTypeToIcon : ComputeType -> String
computeTypeToIcon computeType =
    case computeType of
        CpuCompute ->
            "cpu"

        GpuCompute ->
            "zap"


type alias BenchmarkScores =
    { accuracy : Maybe Float
    , speedTier : Maybe String
    , source : Maybe String
    }


allCategories : List ModelCategory
allCategories =
    [ OcrConversion, LayoutAnalysis, DocumentUnderstanding ]


allCapabilities : List Capability
allCapabilities =
    [ TableExtraction, FormulaMath, Handwriting, MultiColumn, MultiLanguage, ImagePreservation, StructuredOutput, CustomPrompts ]


categoryToString : ModelCategory -> String
categoryToString category =
    case category of
        OcrConversion ->
            "OCR & Conversion"

        LayoutAnalysis ->
            "Layout Analysis"

        DocumentUnderstanding ->
            "Document Understanding"


capabilityToString : Capability -> String
capabilityToString capability =
    case capability of
        TableExtraction ->
            "Tables"

        FormulaMath ->
            "Math"

        Handwriting ->
            "Handwriting"

        MultiColumn ->
            "Multi-column"

        MultiLanguage ->
            "Multi-language"

        ImagePreservation ->
            "Images"

        StructuredOutput ->
            "Structured"

        CustomPrompts ->
            "Prompts"


capabilityToIcon : Capability -> String
capabilityToIcon capability =
    case capability of
        TableExtraction ->
            "table"

        FormulaMath ->
            "function"

        Handwriting ->
            "edit"

        MultiColumn ->
            "columns"

        MultiLanguage ->
            "globe"

        ImagePreservation ->
            "image"

        StructuredOutput ->
            "code"

        CustomPrompts ->
            "message"


performanceTierToString : PerformanceTier -> String
performanceTierToString tier =
    case tier of
        Fast ->
            "Fast"

        Balanced ->
            "Balanced"

        HighQuality ->
            "High Quality"


performanceTierToIcon : PerformanceTier -> String
performanceTierToIcon tier =
    case tier of
        Fast ->
            "zap"

        Balanced ->
            "scale"

        HighQuality ->
            "target"


outputFormatToString : OutputFormat -> String
outputFormatToString format =
    case format of
        OutputMarkdown ->
            "Markdown"

        OutputJson ->
            "JSON"

        OutputHtml ->
            "HTML"


defaultPdfModel : PdfModel
defaultPdfModel =
    Marker


pdfModelToString : PdfModel -> String
pdfModelToString pdfModel =
    case pdfModel of
        Marker ->
            "marker"

        Dolphin ->
            "dolphin"

        Docling ->
            "docling"

        DeepSeekOcr ->
            "deepseek-ocr"

        MinerU ->
            "mineru"

        OlmOcr ->
            "olmocr"

        Docext ->
            "docext"


stringToPdfModel : String -> Maybe PdfModel
stringToPdfModel str =
    case str of
        "marker" ->
            Just Marker

        "dolphin" ->
            Just Dolphin

        "docling" ->
            Just Docling

        "deepseek-ocr" ->
            Just DeepSeekOcr

        "mineru" ->
            Just MinerU

        "olmocr" ->
            Just OlmOcr

        "docext" ->
            Just Docext

        _ ->
            Nothing


pdfModelToDisplayName : PdfModel -> String
pdfModelToDisplayName pdfModel =
    case pdfModel of
        Marker ->
            "Marker (PDF to Markdown)"

        Dolphin ->
            "Dolphin (Document Layout)"

        Docling ->
            "Docling (Document Understanding)"

        DeepSeekOcr ->
            "DeepSeek OCR"

        MinerU ->
            "MinerU (Document Processing)"

        OlmOcr ->
            "olmocr (VLM OCR)"

        Docext ->
            "docext (Nanonets OCR)"


modelSupportsPrompt : PdfModel -> Bool
modelSupportsPrompt pdfModel =
    case pdfModel of
        Dolphin ->
            True

        DeepSeekOcr ->
            True

        OlmOcr ->
            True

        Docext ->
            True

        Marker ->
            False

        Docling ->
            False

        MinerU ->
            False


defaultPromptForModel : PdfModel -> Maybe String
defaultPromptForModel pdfModel =
    case pdfModel of
        Dolphin ->
            Just "Read text in the image."

        DeepSeekOcr ->
            Just "<image>\nConvert the document to markdown."

        OlmOcr ->
            Just "Convert this document to clean markdown."

        Docext ->
            Just "Extract the text from the above document as if you were reading it naturally."

        Marker ->
            Nothing

        Docling ->
            Nothing

        MinerU ->
            Nothing


type alias ModelMetadata =
    { description : String
    , producer : String
    , githubUrl : Maybe String
    , docsUrl : Maybe String
    , huggingFaceUrl : Maybe String
    , arxivUrl : Maybe String

    -- Classification
    , category : ModelCategory
    , capabilities : List Capability
    , outputFormat : OutputFormat

    -- Infrastructure
    , computeType : ComputeType

    -- Performance
    , performanceTier : PerformanceTier
    , benchmarks : Maybe BenchmarkScores

    -- Use cases
    , bestFor : List String
    }


modelMetadata : PdfModel -> ModelMetadata
modelMetadata pdfModel =
    case pdfModel of
        Marker ->
            { description = "High-quality PDF to Markdown conversion using deep learning. Excels at preserving document structure, tables, and formatting with fast processing times."
            , producer = "VikParuchuri"
            , githubUrl = Just "https://github.com/VikParuchuri/marker"
            , docsUrl = Nothing
            , huggingFaceUrl = Nothing
            , arxivUrl = Nothing
            , category = OcrConversion
            , capabilities = [ TableExtraction, MultiColumn, ImagePreservation, MultiLanguage ]
            , outputFormat = OutputMarkdown
            , computeType = CpuCompute
            , performanceTier = Fast
            , benchmarks = Just { accuracy = Just 92.3, speedTier = Just "~2s/page", source = Just "Internal benchmark" }
            , bestFor = [ "Technical documentation", "Reports with tables", "Multi-column layouts" ]
            }

        Dolphin ->
            { description = "State-of-the-art document layout analysis using vision-language models. Specializes in understanding complex document structures and extracting structured data."
            , producer = "ByteDance"
            , githubUrl = Just "https://github.com/bytedance/Dolphin"
            , docsUrl = Nothing
            , huggingFaceUrl = Just "https://huggingface.co/ByteDance/Dolphin"
            , arxivUrl = Just "https://arxiv.org/abs/2505.14059"
            , category = LayoutAnalysis
            , capabilities = [ TableExtraction, FormulaMath, StructuredOutput, CustomPrompts ]
            , outputFormat = OutputMarkdown
            , computeType = GpuCompute
            , performanceTier = Balanced
            , benchmarks = Just { accuracy = Just 94.1, speedTier = Just "~5s/page", source = Just "IDP Leaderboard" }
            , bestFor = [ "Scientific papers", "Financial documents", "Forms and invoices" ]
            }

        Docling ->
            { description = "Enterprise-grade document understanding from IBM Research. Combines multiple AI models for comprehensive document analysis and conversion."
            , producer = "IBM"
            , githubUrl = Just "https://github.com/DS4SD/docling"
            , docsUrl = Just "https://docling-project.github.io/docling/"
            , huggingFaceUrl = Just "https://huggingface.co/ds4sd/docling-models"
            , arxivUrl = Just "https://arxiv.org/abs/2408.09869"
            , category = DocumentUnderstanding
            , capabilities = [ TableExtraction, FormulaMath, StructuredOutput, MultiLanguage ]
            , outputFormat = OutputMarkdown
            , computeType = CpuCompute
            , performanceTier = HighQuality
            , benchmarks = Just { accuracy = Just 95.8, speedTier = Just "~8s/page", source = Just "IDP Leaderboard" }
            , bestFor = [ "Enterprise documents", "Complex layouts", "Regulatory filings" ]
            }

        DeepSeekOcr ->
            { description = "Advanced vision-language model optimized for document OCR. Excels at handwriting recognition and multilingual text extraction with customizable prompts."
            , producer = "DeepSeek"
            , githubUrl = Just "https://github.com/deepseek-ai/DeepSeek-VL2"
            , docsUrl = Nothing
            , huggingFaceUrl = Just "https://huggingface.co/deepseek-ai/deepseek-vl2"
            , arxivUrl = Just "https://arxiv.org/abs/2412.10302"
            , category = OcrConversion
            , capabilities = [ Handwriting, MultiLanguage, CustomPrompts, ImagePreservation ]
            , outputFormat = OutputMarkdown
            , computeType = GpuCompute
            , performanceTier = Balanced
            , benchmarks = Just { accuracy = Just 91.5, speedTier = Just "~4s/page", source = Just "Internal benchmark" }
            , bestFor = [ "Handwritten documents", "Multilingual content", "Custom extraction tasks" ]
            }

        MinerU ->
            { description = "High-quality PDF processing from OpenDataLab. Uses layout detection, table extraction, and formula recognition to convert documents to both Markdown and structured JSON."
            , producer = "OpenDataLab"
            , githubUrl = Just "https://github.com/opendatalab/MinerU"
            , docsUrl = Just "https://mineru.readthedocs.io/"
            , huggingFaceUrl = Nothing
            , arxivUrl = Nothing
            , category = DocumentUnderstanding
            , capabilities = [ TableExtraction, FormulaMath, StructuredOutput, MultiLanguage ]
            , outputFormat = OutputMarkdown
            , computeType = CpuCompute
            , performanceTier = Balanced
            , benchmarks = Just { accuracy = Just 93.2, speedTier = Just "~6s/page", source = Just "Internal benchmark" }
            , bestFor = [ "Academic papers", "Technical documentation", "Structured data extraction" ]
            }

        OlmOcr ->
            { description = "Allen AI's 7B parameter vision-language model for document OCR. Uses vLLM for fast inference and excels at converting complex documents to clean Markdown."
            , producer = "Allen AI"
            , githubUrl = Just "https://github.com/allenai/olmocr"
            , docsUrl = Nothing
            , huggingFaceUrl = Just "https://huggingface.co/allenai/olmOCR-7B-0225-preview"
            , arxivUrl = Nothing
            , category = OcrConversion
            , capabilities = [ TableExtraction, MultiColumn, MultiLanguage, CustomPrompts ]
            , outputFormat = OutputMarkdown
            , computeType = GpuCompute
            , performanceTier = HighQuality
            , benchmarks = Just { accuracy = Just 94.5, speedTier = Just "~3s/page", source = Just "Internal benchmark" }
            , bestFor = [ "Complex documents", "Research papers", "High-accuracy OCR" ]
            }

        Docext ->
            { description = "Nanonets-OCR-s is a 3B parameter VLM based on Qwen2.5-VL. Provides semantic document understanding with table HTML output and LaTeX math support."
            , producer = "Nanonets"
            , githubUrl = Nothing
            , docsUrl = Nothing
            , huggingFaceUrl = Just "https://huggingface.co/nanonets/Nanonets-OCR-s"
            , arxivUrl = Nothing
            , category = OcrConversion
            , capabilities = [ TableExtraction, FormulaMath, Handwriting, CustomPrompts, ImagePreservation ]
            , outputFormat = OutputMarkdown
            , computeType = GpuCompute
            , performanceTier = Balanced
            , benchmarks = Just { accuracy = Just 92.8, speedTier = Just "~4s/page", source = Just "Internal benchmark" }
            , bestFor = [ "Forms and invoices", "Handwritten notes", "Document digitization" ]
            }



-- ROUTING


type Route
    = Login
    | SignUp
    | Upload PdfModel
    | Jobs
    | Models
    | NotFound


routeToPath : Route -> String
routeToPath route =
    case route of
        Login ->
            "/login"

        SignUp ->
            "/signup"

        Upload pdfModel ->
            "/upload/" ++ pdfModelToString pdfModel

        Jobs ->
            "/jobs"

        Models ->
            "/models"

        NotFound ->
            "/"


type alias Flags =
    {}



-- MODEL


type alias Model =
    { key : Nav.Key
    , route : Route
    , auth : AuthState
    , loginForm : LoginForm
    , signUpForm : SignUpForm
    , upload : UploadState
    , jobs : JobsState
    , currentTime : Time.Posix
    , pendingRetry : Maybe ApiRetryContext
    , pollingState : PollingState

    -- Model selection (shared between Upload and Models pages)
    , modelPaletteOpen : Bool
    , modelSearchQuery : String
    , modelFilters : ModelFilters
    , hoveredModel : Maybe PdfModel
    , expandedModelCard : Maybe PdfModel
    , comparisonModels : List PdfModel
    }


type alias ModelFilters =
    { categories : List ModelCategory
    , capabilities : List Capability
    , computeTypes : List ComputeType
    }


type AuthState
    = NotAuthenticated
    | Authenticating
    | Authenticated AuthTokens


type alias AuthTokens =
    { accessToken : String
    , idToken : String
    , refreshToken : String
    , expiresAt : Int
    }


type alias LoginForm =
    { email : String
    , password : String
    , error : Maybe String
    }


type alias SignUpForm =
    { email : String
    , password : String
    , confirmPassword : String
    , confirmationCode : String
    , error : Maybe String
    , success : Bool
    , needsConfirmation : Bool
    , confirming : Bool
    }


type alias UploadState =
    { selectedFile : Maybe File
    , uploadProgress : Maybe Float
    , s3Key : Maybe String
    , submitting : Bool
    , error : Maybe String
    , prompt : String
    }


type alias JobsState =
    { jobs : List Job
    , loading : Bool
    , error : Maybe String
    , lastRefresh : Maybe Time.Posix
    , downloadError : Maybe DownloadError
    , expandedJobIds : Set String
    }


type alias DownloadError =
    { jobId : String
    , message : String
    }


type ApiRetryContext
    = RetryFetchJobs
    | RetryFetchJob PdfModel String -- model, jobId
    | RetrySubmitJob PdfModel String -- model, s3Key


type alias PollingState =
    { consecutivePolls : Int
    , maxPolls : Int
    , baseIntervalMs : Float
    , maxIntervalMs : Float
    }


initPollingState : PollingState
initPollingState =
    { consecutivePolls = 0
    , maxPolls = 60
    , baseIntervalMs = 5000
    , maxIntervalMs = 60000
    }


type alias Job =
    { id : String
    , pdfModel : PdfModel
    , submittedAt : Time.Posix
    , status : JobStatus
    , substatus : Maybe String
    , s3InputKey : String
    , s3OutputKey : Maybe String
    , completedAt : Maybe Time.Posix
    , error : Maybe String
    , downloadUrl : Maybe String
    , prompt : Maybe String
    }


type JobStatus
    = Pending
    | Processing
    | Complete
    | Failed



-- MESSAGES


type Msg
    = UrlChanged Url.Url
    | LinkClicked Browser.UrlRequest
    | SessionRestored String
      -- Auth - Login
    | EmailChanged String
    | PasswordChanged String
    | SignInClicked
    | AuthResponseReceived String
    | SignInCompleted (Result Http.Error AuthTokens)
    | SignOutClicked
      -- Auth - Sign Up
    | SignUpEmailChanged String
    | SignUpPasswordChanged String
    | SignUpConfirmPasswordChanged String
    | SignUpClicked
    | SignUpResponseReceived String
    | ConfirmationCodeChanged String
    | ConfirmSignUpClicked
    | ConfirmSignUpResponseReceived String
      -- Upload
    | ModelSelected PdfModel
    | FileSelected File
    | UploadToS3
    | UploadProgress Float
    | UploadResponseReceived String
    | UploadCompleted (Result Http.Error String)
    | PromptChanged String
    | SubmitJobClicked
    | JobSubmitted (Result Http.Error Job)
      -- Model Selection & Discovery
    | OpenModelPalette
    | CloseModelPalette
    | ModelSearchChanged String
    | ModelHovered (Maybe PdfModel)
    | ToggleModelCardExpanded PdfModel
    | ToggleCategoryFilter ModelCategory
    | ToggleCapabilityFilter Capability
    | ToggleComputeTypeFilter ComputeType
    | ClearModelFilters
    | ToggleModelComparison PdfModel
    | ClearComparison
    | KeyboardShortcut String
      -- Jobs
    | FetchJobs
    | JobsFetched (Result Http.Error (List Job))
    | RefreshClicked
    | DownloadResult String
    | JobWithDownloadFetched (Result Http.Error Job)
    | PollTick Time.Posix
    | CurrentTimeReceived Time.Posix
    | ClearDownloadError
    | ToggleJobExpanded String
    | TokenRefreshReceived String



-- HELPERS


initModel : Nav.Key -> Route -> Model
initModel key route =
    { key = key
    , route = route
    , auth = NotAuthenticated
    , loginForm =
        { email = ""
        , password = ""
        , error = Nothing
        }
    , signUpForm =
        { email = ""
        , password = ""
        , confirmPassword = ""
        , confirmationCode = ""
        , error = Nothing
        , success = False
        , needsConfirmation = False
        , confirming = False
        }
    , upload =
        { selectedFile = Nothing
        , uploadProgress = Nothing
        , s3Key = Nothing
        , submitting = False
        , error = Nothing
        , prompt = ""
        }
    , jobs =
        { jobs = []
        , loading = False
        , error = Nothing
        , lastRefresh = Nothing
        , downloadError = Nothing
        , expandedJobIds = Set.empty
        }
    , currentTime = Time.millisToPosix 0
    , pendingRetry = Nothing
    , pollingState = initPollingState

    -- Model selection state
    , modelPaletteOpen = False
    , modelSearchQuery = ""
    , modelFilters = { categories = [], capabilities = [], computeTypes = [] }
    , hoveredModel = Nothing
    , expandedModelCard = Nothing
    , comparisonModels = []
    }


isAuthenticated : Model -> Bool
isAuthenticated model =
    case model.auth of
        Authenticated _ ->
            True

        _ ->
            False


-- Model filtering helpers


filterModels : ModelFilters -> String -> List PdfModel -> List PdfModel
filterModels filters searchQuery models =
    models
        |> filterByCategory filters.categories
        |> filterByCapabilities filters.capabilities
        |> filterByComputeType filters.computeTypes
        |> filterBySearch searchQuery


filterByCategory : List ModelCategory -> List PdfModel -> List PdfModel
filterByCategory categories models =
    if List.isEmpty categories then
        models

    else
        List.filter
            (\model ->
                let
                    metadata =
                        modelMetadata model
                in
                List.member metadata.category categories
            )
            models


filterByCapabilities : List Capability -> List PdfModel -> List PdfModel
filterByCapabilities capabilities models =
    if List.isEmpty capabilities then
        models

    else
        List.filter
            (\model ->
                let
                    metadata =
                        modelMetadata model
                in
                List.any (\cap -> List.member cap metadata.capabilities) capabilities
            )
            models


filterByComputeType : List ComputeType -> List PdfModel -> List PdfModel
filterByComputeType computeTypes models =
    if List.isEmpty computeTypes then
        models

    else
        List.filter
            (\model ->
                let
                    metadata =
                        modelMetadata model
                in
                List.member metadata.computeType computeTypes
            )
            models


filterBySearch : String -> List PdfModel -> List PdfModel
filterBySearch query models =
    if String.isEmpty (String.trim query) then
        models

    else
        let
            lowerQuery =
                String.toLower query
        in
        List.filter
            (\model ->
                let
                    metadata =
                        modelMetadata model

                    searchableText =
                        String.toLower
                            (pdfModelToDisplayName model
                                ++ " "
                                ++ metadata.producer
                                ++ " "
                                ++ metadata.description
                                ++ " "
                                ++ categoryToString metadata.category
                            )
                in
                String.contains lowerQuery searchableText
            )
            models


hasActiveFilters : ModelFilters -> Bool
hasActiveFilters filters =
    not (List.isEmpty filters.categories && List.isEmpty filters.capabilities && List.isEmpty filters.computeTypes)
