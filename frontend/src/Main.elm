module Main exposing (main)

import Browser
import Browser.Navigation as Nav
import Css.Global
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (..)
import Api
import Auth
import File
import Http
import Json.Decode as Decode
import S3
import Set
import Styles
import Task
import Time
import Types exposing (..)
import Url
import Url.Parser as Parser exposing ((</>), Parser)
import Views.Jobs
import Views.Login
import Views.SignUp
import Views.Upload


main : Program Flags Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }



-- INIT


init : Flags -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init _ url key =
    let
        route =
            parseUrl url

        model =
            Types.initModel key route
    in
    -- Attempt to restore authentication session from localStorage and get current time
    ( model, Cmd.batch [ Auth.restoreSession, Task.perform CurrentTimeReceived Time.now ] )



-- URL PARSING


routeParser : Parser (Route -> a) a
routeParser =
    Parser.oneOf
        [ Parser.map (Upload defaultPdfModel) Parser.top
        , Parser.map Login (Parser.s "login")
        , Parser.map SignUp (Parser.s "signup")
        , Parser.map parseModelRoute (Parser.s "upload" </> Parser.string)
        , Parser.map (Upload defaultPdfModel) (Parser.s "upload")
        , Parser.map Jobs (Parser.s "jobs")
        ]


parseModelRoute : String -> Route
parseModelRoute modelStr =
    case stringToPdfModel modelStr of
        Just pdfModel ->
            Upload pdfModel

        Nothing ->
            NotFound


parseUrl : Url.Url -> Route
parseUrl url =
    Parser.parse routeParser url
        |> Maybe.withDefault NotFound



-- UPDATE


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SessionRestored jsonString ->
            case Decode.decodeString Auth.authResponseDecoder jsonString of
                Ok response ->
                    if response.success then
                        case response.accessToken of
                            Just accessToken ->
                                case response.idToken of
                                    Just idToken ->
                                        case response.refreshToken of
                                            Just refreshToken ->
                                                case response.expiresAt of
                                                    Just expiresAt ->
                                                        ( { model
                                                            | auth =
                                                                Authenticated
                                                                    { accessToken = accessToken
                                                                    , idToken = idToken
                                                                    , refreshToken = refreshToken
                                                                    , expiresAt = expiresAt
                                                                    }
                                                          }
                                                        , Cmd.none
                                                        )

                                                    Nothing ->
                                                        ( model, Cmd.none )

                                            Nothing ->
                                                ( model, Cmd.none )

                                    Nothing ->
                                        ( model, Cmd.none )

                            Nothing ->
                                ( model, Cmd.none )

                    else
                        ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        UrlChanged url ->
            let
                newRoute =
                    parseUrl url

                cmd =
                    case newRoute of
                        Jobs ->
                            if Types.isAuthenticated model then
                                Api.getJobs
                                    (case model.auth of
                                        Authenticated tokens ->
                                            tokens.accessToken

                                        _ ->
                                            ""
                                    )
                                    defaultPdfModel
                                    JobsFetched

                            else
                                Cmd.none

                        _ ->
                            Cmd.none

                -- Set default prompt when navigating to upload page
                newUpload =
                    case newRoute of
                        Upload pdfModel ->
                            let
                                oldUpload =
                                    model.upload

                                newPrompt =
                                    case defaultPromptForModel pdfModel of
                                        Just defaultPrompt ->
                                            defaultPrompt

                                        Nothing ->
                                            ""
                            in
                            { oldUpload | prompt = newPrompt }

                        _ ->
                            model.upload
            in
            ( { model | route = newRoute, upload = newUpload }, cmd )

        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        EmailChanged email ->
            let
                oldForm =
                    model.loginForm

                newForm =
                    { oldForm | email = email }
            in
            ( { model | loginForm = newForm }, Cmd.none )

        PasswordChanged password ->
            let
                oldForm =
                    model.loginForm

                newForm =
                    { oldForm | password = password }
            in
            ( { model | loginForm = newForm }, Cmd.none )

        SignInClicked ->
            ( { model | auth = Authenticating }
            , Auth.signIn model.loginForm.email model.loginForm.password
            )

        AuthResponseReceived jsonString ->
            case Decode.decodeString Auth.authResponseDecoder jsonString of
                Ok response ->
                    if response.success then
                        case response.accessToken of
                            Just accessToken ->
                                case response.idToken of
                                    Just idToken ->
                                        case response.refreshToken of
                                            Just refreshToken ->
                                                case response.expiresAt of
                                                    Just expiresAt ->
                                                        let
                                                            tokens =
                                                                { accessToken = accessToken
                                                                , idToken = idToken
                                                                , refreshToken = refreshToken
                                                                , expiresAt = expiresAt
                                                                }
                                                        in
                                                        ( { model | auth = Authenticated tokens }
                                                        , Nav.pushUrl model.key (routeToPath (Upload defaultPdfModel))
                                                        )

                                                    Nothing ->
                                                        let
                                                            oldForm =
                                                                model.loginForm

                                                            newForm =
                                                                { oldForm | error = Just "Invalid authentication response" }
                                                        in
                                                        ( { model
                                                            | auth = NotAuthenticated
                                                            , loginForm = newForm
                                                          }
                                                        , Cmd.none
                                                        )

                                            Nothing ->
                                                let
                                                    oldForm =
                                                        model.loginForm

                                                    newForm =
                                                        { oldForm | error = Just "Invalid authentication response" }
                                                in
                                                ( { model
                                                    | auth = NotAuthenticated
                                                    , loginForm = newForm
                                                  }
                                                , Cmd.none
                                                )

                                    Nothing ->
                                        let
                                            oldForm =
                                                model.loginForm

                                            newForm =
                                                { oldForm | error = Just "Invalid authentication response" }
                                        in
                                        ( { model
                                            | auth = NotAuthenticated
                                            , loginForm = newForm
                                          }
                                        , Cmd.none
                                        )

                            Nothing ->
                                let
                                    oldForm =
                                        model.loginForm

                                    newForm =
                                        { oldForm | error = Just "Invalid authentication response" }
                                in
                                ( { model
                                    | auth = NotAuthenticated
                                    , loginForm = newForm
                                  }
                                , Cmd.none
                                )

                    else
                        let
                            oldForm =
                                model.loginForm

                            errorMsg =
                                Maybe.withDefault "Authentication failed" response.error

                            newForm =
                                { oldForm | error = Just errorMsg }
                        in
                        ( { model
                            | auth = NotAuthenticated
                            , loginForm = newForm
                          }
                        , Cmd.none
                        )

                Err _ ->
                    let
                        oldForm =
                            model.loginForm

                        newForm =
                            { oldForm | error = Just "Failed to parse authentication response" }
                    in
                    ( { model
                        | auth = NotAuthenticated
                        , loginForm = newForm
                      }
                    , Cmd.none
                    )

        SignInCompleted result ->
            -- This is kept for compatibility but auth now goes through AuthResponseReceived
            ( model, Cmd.none )

        SignOutClicked ->
            ( { model | auth = NotAuthenticated }
            , Cmd.batch
                [ Auth.clearSession
                , Nav.pushUrl model.key (routeToPath Login)
                ]
            )

        SignUpEmailChanged email ->
            let
                oldForm =
                    model.signUpForm

                newForm =
                    { oldForm | email = email }
            in
            ( { model | signUpForm = newForm }, Cmd.none )

        SignUpPasswordChanged password ->
            let
                oldForm =
                    model.signUpForm

                newForm =
                    { oldForm | password = password }
            in
            ( { model | signUpForm = newForm }, Cmd.none )

        SignUpConfirmPasswordChanged confirmPassword ->
            let
                oldForm =
                    model.signUpForm

                newForm =
                    { oldForm | confirmPassword = confirmPassword }
            in
            ( { model | signUpForm = newForm }, Cmd.none )

        SignUpClicked ->
            if model.signUpForm.password /= model.signUpForm.confirmPassword then
                let
                    oldForm =
                        model.signUpForm

                    newForm =
                        { oldForm | error = Just "Passwords do not match" }
                in
                ( { model | signUpForm = newForm }, Cmd.none )

            else if String.length model.signUpForm.password < 8 then
                let
                    oldForm =
                        model.signUpForm

                    newForm =
                        { oldForm | error = Just "Password must be at least 8 characters" }
                in
                ( { model | signUpForm = newForm }, Cmd.none )

            else
                ( { model | auth = Authenticating }
                , Auth.signUp model.signUpForm.email model.signUpForm.password
                )

        SignUpResponseReceived jsonString ->
            case Decode.decodeString Auth.signUpResponseDecoder jsonString of
                Ok response ->
                    if response.success then
                        let
                            oldForm =
                                model.signUpForm

                            newForm =
                                if response.userConfirmed then
                                    -- User already confirmed, go straight to success
                                    { oldForm
                                        | success = True
                                        , needsConfirmation = False
                                        , error = Nothing
                                    }

                                else
                                    -- User needs to confirm email
                                    { oldForm
                                        | needsConfirmation = True
                                        , error = Nothing
                                    }
                        in
                        ( { model
                            | auth = NotAuthenticated
                            , signUpForm = newForm
                          }
                        , Cmd.none
                        )

                    else
                        let
                            oldForm =
                                model.signUpForm

                            errorMsg =
                                Maybe.withDefault "Sign up failed" response.error

                            newForm =
                                { oldForm | error = Just errorMsg }
                        in
                        ( { model
                            | auth = NotAuthenticated
                            , signUpForm = newForm
                          }
                        , Cmd.none
                        )

                Err _ ->
                    let
                        oldForm =
                            model.signUpForm

                        newForm =
                            { oldForm | error = Just "Failed to parse sign up response" }
                    in
                    ( { model
                        | auth = NotAuthenticated
                        , signUpForm = newForm
                      }
                    , Cmd.none
                    )

        ConfirmationCodeChanged code ->
            let
                oldForm =
                    model.signUpForm

                newForm =
                    { oldForm | confirmationCode = code }
            in
            ( { model | signUpForm = newForm }, Cmd.none )

        ConfirmSignUpClicked ->
            let
                oldForm =
                    model.signUpForm

                newForm =
                    { oldForm | confirming = True, error = Nothing }
            in
            ( { model | signUpForm = newForm }
            , Auth.confirmSignUp model.signUpForm.email model.signUpForm.confirmationCode
            )

        ConfirmSignUpResponseReceived jsonString ->
            case Decode.decodeString Auth.confirmSignUpResponseDecoder jsonString of
                Ok response ->
                    if response.success then
                        let
                            oldForm =
                                model.signUpForm

                            newForm =
                                { oldForm
                                    | success = True
                                    , needsConfirmation = False
                                    , confirming = False
                                    , error = Nothing
                                }
                        in
                        ( { model | signUpForm = newForm }, Cmd.none )

                    else
                        let
                            oldForm =
                                model.signUpForm

                            errorMsg =
                                Maybe.withDefault "Confirmation failed" response.error

                            newForm =
                                { oldForm
                                    | confirming = False
                                    , error = Just errorMsg
                                }
                        in
                        ( { model | signUpForm = newForm }, Cmd.none )

                Err _ ->
                    let
                        oldForm =
                            model.signUpForm

                        newForm =
                            { oldForm
                                | confirming = False
                                , error = Just "Failed to parse confirmation response"
                            }
                    in
                    ( { model | signUpForm = newForm }, Cmd.none )

        ModelSelected newPdfModel ->
            let
                oldUpload =
                    model.upload

                newPrompt =
                    case defaultPromptForModel newPdfModel of
                        Just defaultPrompt ->
                            defaultPrompt

                        Nothing ->
                            ""

                newUpload =
                    { oldUpload | prompt = newPrompt }
            in
            ( { model | upload = newUpload }
            , Nav.pushUrl model.key (routeToPath (Upload newPdfModel))
            )

        FileSelected file ->
            -- Automatically upload to S3 when file is selected
            case model.auth of
                Authenticated tokens ->
                    let
                        oldUpload =
                            model.upload

                        newUpload =
                            { oldUpload
                                | selectedFile = Just file
                                , uploadProgress = Nothing
                                , s3Key = Nothing
                                , error = Nothing
                            }

                        request =
                            { file = file
                            , accessToken = tokens.accessToken
                            , pdfModel = getModelFromRoute model.route
                            }
                    in
                    ( { model | upload = newUpload }, S3.uploadFile request )

                _ ->
                    let
                        oldUpload =
                            model.upload

                        newUpload =
                            { oldUpload
                                | selectedFile = Just file
                                , uploadProgress = Nothing
                                , s3Key = Nothing
                                , error = Nothing
                            }
                    in
                    ( { model | upload = newUpload }, Cmd.none )

        UploadToS3 ->
            case ( model.upload.selectedFile, model.auth ) of
                ( Just file, Authenticated tokens ) ->
                    let
                        request =
                            { file = file
                            , accessToken = tokens.accessToken
                            , pdfModel = getModelFromRoute model.route
                            }
                    in
                    ( model, S3.uploadFile request )

                _ ->
                    ( model, Cmd.none )

        UploadProgress progress ->
            let
                oldUpload =
                    model.upload

                newUpload =
                    { oldUpload | uploadProgress = Just progress }
            in
            ( { model | upload = newUpload }, Cmd.none )

        PromptChanged newPrompt ->
            let
                oldUpload =
                    model.upload

                newUpload =
                    { oldUpload | prompt = newPrompt }
            in
            ( { model | upload = newUpload }, Cmd.none )

        UploadResponseReceived jsonString ->
            case Decode.decodeString S3.uploadResponseDecoder jsonString of
                Ok response ->
                    if response.success then
                        case response.s3Key of
                            Just s3Key ->
                                -- Automatically submit job after successful S3 upload
                                case model.auth of
                                    Authenticated tokens ->
                                        let
                                            oldUpload =
                                                model.upload

                                            newUpload =
                                                { oldUpload
                                                    | s3Key = Just s3Key
                                                    , uploadProgress = Nothing
                                                    , submitting = True
                                                }

                                            pdfModel =
                                                getModelFromRoute model.route

                                            maybePrompt =
                                                if modelSupportsPrompt pdfModel && not (String.isEmpty (String.trim model.upload.prompt)) then
                                                    Just model.upload.prompt

                                                else
                                                    Nothing
                                        in
                                        ( { model | upload = newUpload }
                                        , Api.submitJob tokens.accessToken pdfModel s3Key maybePrompt JobSubmitted
                                        )

                                    _ ->
                                        let
                                            oldUpload =
                                                model.upload

                                            newUpload =
                                                { oldUpload
                                                    | s3Key = Just s3Key
                                                    , uploadProgress = Nothing
                                                }
                                        in
                                        ( { model | upload = newUpload }, Cmd.none )

                            Nothing ->
                                let
                                    oldUpload =
                                        model.upload

                                    newUpload =
                                        { oldUpload | error = Just "No S3 key in response" }
                                in
                                ( { model | upload = newUpload }, Cmd.none )

                    else
                        let
                            oldUpload =
                                model.upload

                            errorMsg =
                                Maybe.withDefault "Upload failed" response.error

                            newUpload =
                                { oldUpload
                                    | error = Just errorMsg
                                    , uploadProgress = Nothing
                                }
                        in
                        ( { model | upload = newUpload }, Cmd.none )

                Err _ ->
                    let
                        oldUpload =
                            model.upload

                        newUpload =
                            { oldUpload | error = Just "Failed to parse upload response" }
                    in
                    ( { model | upload = newUpload }, Cmd.none )

        UploadCompleted result ->
            -- Kept for compatibility
            ( model, Cmd.none )

        SubmitJobClicked ->
            case ( model.upload.s3Key, model.auth ) of
                ( Just s3Key, Authenticated tokens ) ->
                    let
                        oldUpload =
                            model.upload

                        newUpload =
                            { oldUpload | submitting = True }

                        pdfModel =
                            getModelFromRoute model.route

                        maybePrompt =
                            if modelSupportsPrompt pdfModel && not (String.isEmpty (String.trim model.upload.prompt)) then
                                Just model.upload.prompt

                            else
                                Nothing
                    in
                    ( { model | upload = newUpload }
                    , Api.submitJob tokens.accessToken pdfModel s3Key maybePrompt JobSubmitted
                    )

                _ ->
                    ( model, Cmd.none )

        JobSubmitted result ->
            case result of
                Ok job ->
                    let
                        oldUpload =
                            model.upload

                        newUpload =
                            { oldUpload
                                | submitting = False
                                , selectedFile = Nothing
                                , s3Key = Nothing
                                , uploadProgress = Nothing
                                , error = Nothing
                                , prompt = ""
                            }
                    in
                    ( { model | upload = newUpload }
                    , Nav.pushUrl model.key (routeToPath Jobs)
                    )

                Err error ->
                    let
                        oldUpload =
                            model.upload

                        newUpload =
                            { oldUpload
                                | submitting = False
                                , error = Just (httpErrorToString error)
                            }
                    in
                    ( { model | upload = newUpload }, Cmd.none )

        FetchJobs ->
            case model.auth of
                Authenticated tokens ->
                    let
                        oldJobs =
                            model.jobs

                        newJobs =
                            { oldJobs | loading = True }
                    in
                    ( { model | jobs = newJobs }
                    , Api.getJobs tokens.accessToken defaultPdfModel JobsFetched
                    )

                _ ->
                    ( model, Cmd.none )

        JobsFetched result ->
            case result of
                Ok jobs ->
                    let
                        oldJobs =
                            model.jobs

                        -- Check if any job transitioned from Processing to Complete/Failed
                        processingCompleted =
                            List.any
                                (\newJob ->
                                    case List.filter (\old -> old.id == newJob.id) oldJobs.jobs of
                                        [ oldJob ] ->
                                            oldJob.status == Processing && newJob.status /= Processing

                                        _ ->
                                            False
                                )
                                jobs

                        -- Reset polling state if job completed
                        newPollingState =
                            if processingCompleted then
                                Types.initPollingState

                            else
                                model.pollingState

                        -- Auto-expand most recent job on first load
                        newExpandedIds =
                            if List.isEmpty oldJobs.jobs then
                                case List.head jobs of
                                    Just mostRecent ->
                                        Set.singleton mostRecent.id

                                    Nothing ->
                                        Set.empty

                            else
                                oldJobs.expandedJobIds

                        newJobs =
                            { oldJobs
                                | jobs = jobs
                                , loading = False
                                , error = Nothing
                                , lastRefresh = Nothing
                                , expandedJobIds = newExpandedIds
                            }
                    in
                    ( { model | jobs = newJobs, pollingState = newPollingState }, Cmd.none )

                Err error ->
                    if is401Error error then
                        -- Token expired, trigger refresh
                        case model.auth of
                            Authenticated tokens ->
                                ( { model | pendingRetry = Just RetryFetchJobs }
                                , Auth.refreshToken tokens.refreshToken
                                )

                            _ ->
                                ( model, Nav.pushUrl model.key (routeToPath Login) )

                    else
                        let
                            oldJobs =
                                model.jobs

                            newJobs =
                                { oldJobs
                                    | loading = False
                                    , error = Just (httpErrorToString error)
                                }
                        in
                        ( { model | jobs = newJobs }, Cmd.none )

        RefreshClicked ->
            update FetchJobs model

        DownloadResult jobId ->
            -- Fetch the job with download URL, then trigger download
            case model.auth of
                Authenticated tokens ->
                    let
                        jobPdfModel =
                            findJobPdfModel jobId model.jobs.jobs
                    in
                    ( model, Api.getJob tokens.accessToken jobPdfModel jobId JobWithDownloadFetched )

                _ ->
                    ( model, Cmd.none )

        JobWithDownloadFetched result ->
            case result of
                Ok job ->
                    case job.downloadUrl of
                        Just url ->
                            -- Clear any previous error and trigger download
                            let
                                oldJobs =
                                    model.jobs

                                newJobs =
                                    { oldJobs | downloadError = Nothing }
                            in
                            ( { model | jobs = newJobs }, Nav.load url )

                        Nothing ->
                            -- No download URL available
                            let
                                oldJobs =
                                    model.jobs

                                newJobs =
                                    { oldJobs
                                        | downloadError =
                                            Just
                                                { jobId = job.id
                                                , message = "Download not available. The result may still be processing."
                                                }
                                    }
                            in
                            ( { model | jobs = newJobs }, Cmd.none )

                Err error ->
                    let
                        oldJobs =
                            model.jobs

                        newJobs =
                            { oldJobs
                                | downloadError =
                                    Just
                                        { jobId = ""
                                        , message = "Failed to fetch download: " ++ httpErrorToString error
                                        }
                            }
                    in
                    ( { model | jobs = newJobs }, Cmd.none )

        ClearDownloadError ->
            let
                oldJobs =
                    model.jobs

                newJobs =
                    { oldJobs | downloadError = Nothing }
            in
            ( { model | jobs = newJobs }, Cmd.none )

        ToggleJobExpanded jobId ->
            let
                oldJobs =
                    model.jobs

                newExpandedIds =
                    if Set.member jobId oldJobs.expandedJobIds then
                        Set.remove jobId oldJobs.expandedJobIds

                    else
                        Set.insert jobId oldJobs.expandedJobIds

                newJobs =
                    { oldJobs | expandedJobIds = newExpandedIds }
            in
            ( { model | jobs = newJobs }, Cmd.none )

        TokenRefreshReceived jsonString ->
            case Decode.decodeString Auth.tokenRefreshResponseDecoder jsonString of
                Ok response ->
                    if response.success then
                        case ( response.accessToken, response.idToken, response.expiresAt ) of
                            ( Just accessToken, Just idToken, Just expiresAt ) ->
                                let
                                    newAuth =
                                        case model.auth of
                                            Authenticated tokens ->
                                                Authenticated
                                                    { tokens
                                                        | accessToken = accessToken
                                                        , idToken = idToken
                                                        , expiresAt = expiresAt
                                                    }

                                            _ ->
                                                model.auth

                                    retryCmd =
                                        case model.pendingRetry of
                                            Just RetryFetchJobs ->
                                                Api.getJobs accessToken defaultPdfModel JobsFetched

                                            Just (RetryFetchJob retryPdfModel jobId) ->
                                                Api.getJob accessToken retryPdfModel jobId JobWithDownloadFetched

                                            Just (RetrySubmitJob retryPdfModel s3Key) ->
                                                let
                                                    maybePrompt =
                                                        if modelSupportsPrompt retryPdfModel && not (String.isEmpty (String.trim model.upload.prompt)) then
                                                            Just model.upload.prompt

                                                        else
                                                            Nothing
                                                in
                                                Api.submitJob accessToken retryPdfModel s3Key maybePrompt JobSubmitted

                                            Nothing ->
                                                Cmd.none
                                in
                                ( { model
                                    | auth = newAuth
                                    , pendingRetry = Nothing
                                  }
                                , retryCmd
                                )

                            _ ->
                                -- Incomplete response, redirect to login
                                ( { model | auth = NotAuthenticated, pendingRetry = Nothing }
                                , Cmd.batch [ Auth.clearSession, Nav.pushUrl model.key (routeToPath Login) ]
                                )

                    else
                        -- Refresh failed, redirect to login
                        ( { model | auth = NotAuthenticated, pendingRetry = Nothing }
                        , Cmd.batch [ Auth.clearSession, Nav.pushUrl model.key (routeToPath Login) ]
                        )

                Err _ ->
                    ( { model | auth = NotAuthenticated, pendingRetry = Nothing }
                    , Cmd.batch [ Auth.clearSession, Nav.pushUrl model.key (routeToPath Login) ]
                    )

        PollTick time ->
            -- Poll for job updates if any jobs are processing and update current time
            let
                oldPolling =
                    model.pollingState

                newPolling =
                    { oldPolling | consecutivePolls = oldPolling.consecutivePolls + 1 }

                updatedModel =
                    { model | currentTime = time, pollingState = newPolling }
            in
            update FetchJobs updatedModel

        CurrentTimeReceived time ->
            ( { model | currentTime = time }, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        restoredSessionSub =
            Auth.receiveRestoredSession
                (\value ->
                    case Decode.decodeValue Decode.string value of
                        Ok jsonString ->
                            SessionRestored jsonString

                        Err _ ->
                            SessionRestored "{}"
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

        signUpSub =
            Auth.receiveSignUpResponse
                (\value ->
                    case Decode.decodeValue Decode.string value of
                        Ok jsonString ->
                            SignUpResponseReceived jsonString

                        Err _ ->
                            SignUpResponseReceived "{}"
                )

        confirmSignUpSub =
            Auth.receiveConfirmSignUpResponse
                (\value ->
                    case Decode.decodeValue Decode.string value of
                        Ok jsonString ->
                            ConfirmSignUpResponseReceived jsonString

                        Err _ ->
                            ConfirmSignUpResponseReceived "{}"
                )

        uploadProgressSub =
            S3.receiveUploadProgress UploadProgress

        uploadResponseSub =
            S3.receiveUploadResponse
                (\value ->
                    case Decode.decodeValue Decode.string value of
                        Ok jsonString ->
                            UploadResponseReceived jsonString

                        Err _ ->
                            UploadResponseReceived "{}"
                )

        pollSub =
            case model.jobs.jobs of
                [] ->
                    Sub.none

                jobs ->
                    if List.any (\j -> j.status == Processing) jobs then
                        if model.pollingState.consecutivePolls < model.pollingState.maxPolls then
                            Time.every (calculatePollingInterval model.pollingState) PollTick

                        else
                            Sub.none
                            -- Stop polling after max attempts

                    else
                        Sub.none

        -- Update current time every 30 seconds to keep relative timestamps fresh
        timeUpdateSub =
            if model.route == Jobs then
                Time.every (30 * 1000) CurrentTimeReceived
            else
                Sub.none

        tokenRefreshSub =
            Auth.receiveTokenRefreshResponse
                (\value ->
                    case Decode.decodeValue Decode.string value of
                        Ok jsonString ->
                            TokenRefreshReceived jsonString

                        Err _ ->
                            TokenRefreshReceived "{}"
                )
    in
    Sub.batch [ restoredSessionSub, authSub, signUpSub, confirmSignUpSub, uploadProgressSub, uploadResponseSub, pollSub, timeUpdateSub, tokenRefreshSub ]



-- VIEW


view : Model -> Browser.Document Msg
view model =
    { title = "PDF Models"
    , body =
        [ toUnstyled <|
            div []
                [ Css.Global.global Styles.globalStyles
                , viewContent model
                ]
        ]
    }


viewContent : Model -> Html Msg
viewContent model =
    case model.route of
        Login ->
            viewLoginPlaceholder model

        SignUp ->
            Views.SignUp.view model

        Upload pdfModel ->
            if Types.isAuthenticated model then
                viewUploadPlaceholder pdfModel model

            else
                viewLoginPlaceholder model

        Jobs ->
            if Types.isAuthenticated model then
                viewJobsPlaceholder model

            else
                viewLoginPlaceholder model

        NotFound ->
            div [] [ text "404 - Not Found" ]


viewLoginPlaceholder : Model -> Html Msg
viewLoginPlaceholder model =
    Views.Login.view model


viewUploadPlaceholder : PdfModel -> Model -> Html Msg
viewUploadPlaceholder pdfModel model =
    Views.Upload.view pdfModel model


viewJobsPlaceholder : Model -> Html Msg
viewJobsPlaceholder model =
    Views.Jobs.view model



-- HELPERS


getModelFromRoute : Route -> PdfModel
getModelFromRoute route =
    case route of
        Upload pdfModel ->
            pdfModel

        _ ->
            defaultPdfModel


findJobPdfModel : String -> List Job -> PdfModel
findJobPdfModel jobId jobs =
    jobs
        |> List.filter (\job -> job.id == jobId)
        |> List.head
        |> Maybe.map .pdfModel
        |> Maybe.withDefault defaultPdfModel


is401Error : Http.Error -> Bool
is401Error error =
    case error of
        Http.BadStatus 401 ->
            True

        _ ->
            False


calculatePollingInterval : PollingState -> Float
calculatePollingInterval state =
    let
        -- Exponential backoff: base * 1.5^n, capped at max
        multiplier =
            1.5 ^ toFloat state.consecutivePolls

        calculated =
            state.baseIntervalMs * multiplier
    in
    Basics.min calculated state.maxIntervalMs


generateJobId : () -> String
generateJobId _ =
    -- Simple UUID-like generator for job IDs
    -- In production, use a proper UUID library or let backend generate
    "job-" ++ String.fromInt (Time.posixToMillis (Time.millisToPosix 0))


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl url ->
            "Invalid URL: " ++ url

        Http.Timeout ->
            "Request timed out"

        Http.NetworkError ->
            "Network error - check your connection"

        Http.BadStatus code ->
            "Server error: " ++ String.fromInt code

        Http.BadBody message ->
            "Invalid response: " ++ message
