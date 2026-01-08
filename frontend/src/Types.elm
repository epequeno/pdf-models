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


allPdfModels : List PdfModel
allPdfModels =
    [ Marker, Dolphin, Docling, DeepSeekOcr ]


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


modelSupportsPrompt : PdfModel -> Bool
modelSupportsPrompt pdfModel =
    case pdfModel of
        Dolphin ->
            True

        DeepSeekOcr ->
            True

        Marker ->
            False

        Docling ->
            False


defaultPromptForModel : PdfModel -> Maybe String
defaultPromptForModel pdfModel =
    case pdfModel of
        Dolphin ->
            Just "Read text in the image."

        DeepSeekOcr ->
            Just "<image>\nConvert the document to markdown."

        Marker ->
            Nothing

        Docling ->
            Nothing


type alias ModelMetadata =
    { description : String
    , producer : String
    , githubUrl : Maybe String
    , docsUrl : Maybe String
    , huggingFaceUrl : Maybe String
    , arxivUrl : Maybe String
    }


modelMetadata : PdfModel -> ModelMetadata
modelMetadata pdfModel =
    case pdfModel of
        Marker ->
            { description = "High-quality PDF to Markdown conversion using deep learning"
            , producer = "VikParuchuri"
            , githubUrl = Just "https://github.com/VikParuchuri/marker"
            , docsUrl = Nothing
            , huggingFaceUrl = Nothing
            , arxivUrl = Nothing
            }

        Dolphin ->
            { description = "Document layout analysis with vision-language model"
            , producer = "ByteDance"
            , githubUrl = Just "https://github.com/bytedance/Dolphin"
            , docsUrl = Nothing
            , huggingFaceUrl = Just "https://huggingface.co/ByteDance/Dolphin"
            , arxivUrl = Just "https://arxiv.org/abs/2505.14059"
            }

        Docling ->
            { description = "AI-powered document understanding and conversion"
            , producer = "IBM"
            , githubUrl = Just "https://github.com/DS4SD/docling"
            , docsUrl = Just "https://docling-project.github.io/docling/"
            , huggingFaceUrl = Just "https://huggingface.co/ds4sd/docling-models"
            , arxivUrl = Just "https://arxiv.org/abs/2408.09869"
            }

        DeepSeekOcr ->
            { description = "Vision-language model for document OCR and understanding"
            , producer = "DeepSeek"
            , githubUrl = Just "https://github.com/deepseek-ai/DeepSeek-VL2"
            , docsUrl = Nothing
            , huggingFaceUrl = Just "https://huggingface.co/deepseek-ai/deepseek-vl2"
            , arxivUrl = Just "https://arxiv.org/abs/2412.10302"
            }



-- ROUTING


type Route
    = Login
    | SignUp
    | Upload PdfModel
    | Jobs
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
    , modelInfoExpanded : Bool
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
    | ToggleModelInfo
    | SubmitJobClicked
    | JobSubmitted (Result Http.Error Job)
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
        , modelInfoExpanded = False
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
    }


isAuthenticated : Model -> Bool
isAuthenticated model =
    case model.auth of
        Authenticated _ ->
            True

        _ ->
            False
