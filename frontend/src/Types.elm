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
    }


isAuthenticated : Model -> Bool
isAuthenticated model =
    case model.auth of
        Authenticated _ ->
            True

        _ ->
            False
