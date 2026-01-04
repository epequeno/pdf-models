module Types exposing (..)

import Browser
import Browser.Navigation as Nav
import File exposing (File)
import Http
import Time
import Url


-- ROUTING


type Route
    = Login
    | SignUp
    | Upload
    | Jobs
    | NotFound


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
    , completedAt : Maybe Time.Posix
    , error : Maybe String
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
    | FileSelected File
    | UploadToS3
    | UploadProgress Float
    | UploadResponseReceived String
    | UploadCompleted (Result Http.Error String)
    | SubmitJobClicked
    | JobSubmitted (Result Http.Error Job)
      -- Jobs
    | FetchJobs
    | JobsFetched (Result Http.Error (List Job))
    | RefreshClicked
    | DownloadResult String
    | PollTick Time.Posix



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
        }
    , jobs =
        { jobs = []
        , loading = False
        , error = Nothing
        , lastRefresh = Nothing
        }
    }


isAuthenticated : Model -> Bool
isAuthenticated model =
    case model.auth of
        Authenticated _ ->
            True

        _ ->
            False
