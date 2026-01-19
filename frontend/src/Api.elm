module Api exposing
    ( approveConfig
    , createConfig
    , deleteConfig
    , discoverConfigs
    , forkConfig
    , getConfig
    , getConfigs
    , getJob
    , getJobs
    , getPendingConfigs
    , jobDecoder
    , jobStatusDecoder
    , jobsListDecoder
    , pdfModelDecoder
    , rejectConfig
    , revokeConfig
    , submitJob
    , updateConfig
    )

import Http
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (optional, required)
import Json.Encode as Encode
import Time
import Types exposing (..)


-- CONFIGURATION


apiBaseUrl : String
apiBaseUrl =
    "https://api.epequeno.app"



-- SUBMIT JOB


submitJob : String -> PdfModel -> String -> Maybe String -> Maybe String -> Maybe String -> (Result Http.Error Job -> msg) -> Cmd msg
submitJob accessToken pdfModel s3Key maybePrompt maybeFilename maybeConfigId toMsg =
    let
        baseFields =
            [ ( "s3_input_key", Encode.string s3Key )
            , ( "start_processing", Encode.bool True )
            ]

        promptField =
            case maybePrompt of
                Just prompt ->
                    if String.isEmpty (String.trim prompt) then
                        []

                    else
                        [ ( "prompt", Encode.string (String.trim prompt) ) ]

                Nothing ->
                    []

        filenameField =
            case maybeFilename of
                Just filename ->
                    [ ( "original_filename", Encode.string filename ) ]

                Nothing ->
                    []

        configIdField =
            case maybeConfigId of
                Just configId ->
                    [ ( "config_id", Encode.string configId ) ]

                Nothing ->
                    []

        bodyFields =
            baseFields ++ promptField ++ filenameField ++ configIdField
    in
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/jobs"
        , body = Http.jsonBody (Encode.object bodyFields)
        , expect = Http.expectJson toMsg jobDecoder
        , timeout = Nothing
        , tracker = Nothing
        }



-- GET SINGLE JOB (with download URL)


getJob : String -> PdfModel -> String -> (Result Http.Error Job -> msg) -> Cmd msg
getJob accessToken pdfModel jobId toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/jobs/" ++ jobId
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg jobWithDownloadDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


-- GET JOBS


getJobs : String -> PdfModel -> (Result Http.Error (List Job) -> msg) -> Cmd msg
getJobs accessToken pdfModel toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/jobs"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg jobsListDecoder
        , timeout = Nothing
        , tracker = Nothing
        }



-- DECODERS


jobWithDownloadDecoder : Decoder Job
jobWithDownloadDecoder =
    Decode.succeed Job
        |> required "job_id" Decode.string
        |> required "model" pdfModelDecoder
        |> required "created_at" iso8601Decoder
        |> required "status" jobStatusDecoder
        |> optional "substatus" (Decode.maybe Decode.string) Nothing
        |> required "s3_input_key" Decode.string
        |> optional "s3_result_key" (Decode.maybe Decode.string) Nothing
        |> optional "completed_at" (Decode.maybe iso8601Decoder) Nothing
        |> optional "error" (Decode.maybe Decode.string) Nothing
        |> optional "download_url" (Decode.maybe Decode.string) Nothing
        |> optional "prompt" (Decode.maybe Decode.string) Nothing
        |> optional "original_filename" (Decode.maybe Decode.string) Nothing


jobDecoder : Decoder Job
jobDecoder =
    Decode.succeed Job
        |> required "job_id" Decode.string
        |> required "model" pdfModelDecoder
        |> required "created_at" iso8601Decoder
        |> required "status" jobStatusDecoder
        |> optional "substatus" (Decode.maybe Decode.string) Nothing
        |> required "s3_input_key" Decode.string
        |> optional "s3_result_key" (Decode.maybe Decode.string) Nothing
        |> optional "completed_at" (Decode.maybe iso8601Decoder) Nothing
        |> optional "error" (Decode.maybe Decode.string) Nothing
        |> optional "download_url" (Decode.maybe Decode.string) Nothing
        |> optional "prompt" (Decode.maybe Decode.string) Nothing
        |> optional "original_filename" (Decode.maybe Decode.string) Nothing


jobsListDecoder : Decoder (List Job)
jobsListDecoder =
    Decode.field "jobs" (Decode.list jobDecoder)


jobStatusDecoder : Decoder JobStatus
jobStatusDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case String.toLower str of
                    "pending" ->
                        Decode.succeed Pending

                    "processing" ->
                        Decode.succeed Processing

                    "complete" ->
                        Decode.succeed Complete

                    "completed" ->
                        Decode.succeed Complete

                    "failed" ->
                        Decode.succeed Failed

                    _ ->
                        Decode.fail ("Unknown status: " ++ str)
            )


pdfModelDecoder : Decoder PdfModel
pdfModelDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case stringToPdfModel str of
                    Just pdfModel ->
                        Decode.succeed pdfModel

                    Nothing ->
                        Decode.fail ("Unknown model: " ++ str)
            )


iso8601Decoder : Decoder Time.Posix
iso8601Decoder =
    Iso8601.decoder



-- CONFIGURATION API


createConfig : String -> PdfModel -> Types.CreateConfigRequest -> (Result Http.Error Types.Configuration -> msg) -> Cmd msg
createConfig accessToken pdfModel request toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/configs"
        , body = Http.jsonBody (encodeCreateConfigRequest request)
        , expect = Http.expectJson toMsg configurationDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


getConfigs : String -> PdfModel -> (Result Http.Error (List Types.Configuration) -> msg) -> Cmd msg
getConfigs accessToken pdfModel toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/configs"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg configurationsListDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


getConfig : String -> PdfModel -> String -> (Result Http.Error Types.Configuration -> msg) -> Cmd msg
getConfig accessToken pdfModel configId toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/configs/" ++ configId
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg configurationDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


updateConfig : String -> PdfModel -> String -> Types.UpdateConfigRequest -> (Result Http.Error Types.Configuration -> msg) -> Cmd msg
updateConfig accessToken pdfModel configId request toMsg =
    Http.request
        { method = "PUT"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/configs/" ++ configId
        , body = Http.jsonBody (encodeUpdateConfigRequest request)
        , expect = Http.expectJson toMsg configurationDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


deleteConfig : String -> PdfModel -> String -> (Result Http.Error () -> msg) -> Cmd msg
deleteConfig accessToken pdfModel configId toMsg =
    Http.request
        { method = "DELETE"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/configs/" ++ configId
        , body = Http.emptyBody
        , expect = Http.expectWhatever toMsg
        , timeout = Nothing
        , tracker = Nothing
        }


forkConfig : String -> PdfModel -> String -> (Result Http.Error Types.Configuration -> msg) -> Cmd msg
forkConfig accessToken pdfModel configId toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/" ++ pdfModelToString pdfModel ++ "/configs/" ++ configId ++ "/fork"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg configurationDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


discoverConfigs : String -> Maybe PdfModel -> (Result Http.Error (List Types.Configuration) -> msg) -> Cmd msg
discoverConfigs accessToken maybeModel toMsg =
    let
        queryParams =
            case maybeModel of
                Just model ->
                    "?model=" ++ pdfModelToString model

                Nothing ->
                    ""
    in
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/configs/discover" ++ queryParams
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg configurationsListDecoder
        , timeout = Nothing
        , tracker = Nothing
        }



-- CONFIGURATION ENCODERS


encodeCreateConfigRequest : Types.CreateConfigRequest -> Encode.Value
encodeCreateConfigRequest request =
    let
        requiredFields =
            [ ( "name", Encode.string request.name ) ]

        optionalFields =
            List.filterMap identity
                [ Maybe.map (\d -> ( "description", Encode.string d )) request.description
                , Maybe.map (\p -> ( "inference_params", encodeInferenceParams p )) request.inferenceParams
                , Maybe.map (\p -> ( "infra_params", encodeInfraParams p )) request.infraParams
                , Maybe.map (\v -> ( "visibility", Encode.string (Types.visibilityToString v) )) request.visibility
                ]
    in
    Encode.object (requiredFields ++ optionalFields)


encodeUpdateConfigRequest : Types.UpdateConfigRequest -> Encode.Value
encodeUpdateConfigRequest request =
    let
        optionalFields =
            List.filterMap identity
                [ Maybe.map (\n -> ( "name", Encode.string n )) request.name
                , Maybe.map (\d -> ( "description", Encode.string d )) request.description
                , Maybe.map (\p -> ( "inference_params", encodeInferenceParams p )) request.inferenceParams
                , Maybe.map (\p -> ( "infra_params", encodeInfraParams p )) request.infraParams
                , Maybe.map (\v -> ( "visibility", Encode.string (Types.visibilityToString v) )) request.visibility
                ]
    in
    Encode.object optionalFields


encodeInferenceParams : Types.InferenceParams -> Encode.Value
encodeInferenceParams params =
    let
        optionalFields =
            List.filterMap identity
                [ Maybe.map (\p -> ( "prompt", Encode.string p )) params.prompt
                , Maybe.map (\f -> ( "output_format", Encode.string f )) params.outputFormat
                ]

        envVarsField =
            if List.isEmpty params.customEnvVars then
                []

            else
                [ ( "custom_env_vars", Encode.object (List.map (\( k, v ) -> ( k, Encode.string v )) params.customEnvVars) ) ]
    in
    Encode.object (optionalFields ++ envVarsField)


encodeInfraParams : Types.InfraParams -> Encode.Value
encodeInfraParams params =
    let
        optionalFields =
            List.filterMap identity
                [ Maybe.map (\c -> ( "cpu", Encode.int c )) params.cpu
                , Maybe.map (\m -> ( "memory_mib", Encode.int m )) params.memoryMib
                , Maybe.map (\g -> ( "gpu_count", Encode.int g )) params.gpuCount
                , Maybe.map (\t -> ( "timeout_minutes", Encode.int t )) params.timeoutMinutes
                , Maybe.map (\e -> ( "ephemeral_storage_gib", Encode.int e )) params.ephemeralStorageGib
                , Maybe.map (\e -> ( "ebs_volume_size_gb", Encode.int e )) params.ebsVolumeSizeGb
                , Maybe.map (\s -> ( "spot_enabled", Encode.bool s )) params.spotEnabled
                ]
    in
    Encode.object optionalFields



-- CONFIGURATION DECODERS


configurationDecoder : Decoder Types.Configuration
configurationDecoder =
    Decode.succeed Types.Configuration
        |> required "config_id" Decode.string
        |> required "user_id" Decode.string
        |> required "model" pdfModelDecoder
        |> required "name" Decode.string
        |> optional "description" (Decode.maybe Decode.string) Nothing
        |> required "created_at" iso8601Decoder
        |> required "updated_at" iso8601Decoder
        |> optional "inference_params" inferenceParamsDecoder Types.emptyInferenceParams
        |> optional "infra_params" infraParamsDecoder Types.emptyInfraParams
        |> required "approval_status" approvalStatusDecoder
        |> optional "approved_by" (Decode.maybe Decode.string) Nothing
        |> optional "approved_at" (Decode.maybe iso8601Decoder) Nothing
        |> optional "rejection_reason" (Decode.maybe Decode.string) Nothing
        |> optional "task_definition_arn" (Decode.maybe Decode.string) Nothing
        |> optional "task_definition_status" (Decode.maybe Decode.string) Nothing
        |> optional "visibility" visibilityDecoder Types.Private
        |> optional "usage_count" Decode.int 0
        |> optional "forked_from" (Decode.maybe Decode.string) Nothing


configurationsListDecoder : Decoder (List Types.Configuration)
configurationsListDecoder =
    Decode.field "configs" (Decode.list configurationDecoder)


approvalStatusDecoder : Decoder Types.ApprovalStatus
approvalStatusDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case Types.stringToApprovalStatus str of
                    Just status ->
                        Decode.succeed status

                    Nothing ->
                        Decode.fail ("Unknown approval status: " ++ str)
            )


visibilityDecoder : Decoder Types.Visibility
visibilityDecoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                case Types.stringToVisibility str of
                    Just visibility ->
                        Decode.succeed visibility

                    Nothing ->
                        Decode.fail ("Unknown visibility: " ++ str)
            )


inferenceParamsDecoder : Decoder Types.InferenceParams
inferenceParamsDecoder =
    Decode.succeed Types.InferenceParams
        |> optional "prompt" (Decode.maybe Decode.string) Nothing
        |> optional "output_format" (Decode.maybe Decode.string) Nothing
        |> optional "custom_env_vars" customEnvVarsDecoder []


customEnvVarsDecoder : Decoder (List ( String, String ))
customEnvVarsDecoder =
    Decode.keyValuePairs Decode.string


infraParamsDecoder : Decoder Types.InfraParams
infraParamsDecoder =
    Decode.succeed Types.InfraParams
        |> optional "cpu" (Decode.maybe Decode.int) Nothing
        |> optional "memory_mib" (Decode.maybe Decode.int) Nothing
        |> optional "gpu_count" (Decode.maybe Decode.int) Nothing
        |> optional "timeout_minutes" (Decode.maybe Decode.int) Nothing
        |> optional "ephemeral_storage_gib" (Decode.maybe Decode.int) Nothing
        |> optional "ebs_volume_size_gb" (Decode.maybe Decode.int) Nothing
        |> optional "spot_enabled" (Decode.maybe Decode.bool) Nothing



-- ADMIN API


getPendingConfigs : String -> (Result Http.Error (List Types.Configuration) -> msg) -> Cmd msg
getPendingConfigs accessToken toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/admin/configs/pending"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg configurationsListDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


approveConfig : String -> String -> (Result Http.Error Types.Configuration -> msg) -> Cmd msg
approveConfig accessToken configId toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/admin/configs/" ++ configId ++ "/approve"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg configurationDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


rejectConfig : String -> String -> String -> (Result Http.Error Types.Configuration -> msg) -> Cmd msg
rejectConfig accessToken configId reason toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/admin/configs/" ++ configId ++ "/reject"
        , body = Http.jsonBody (Encode.object [ ( "reason", Encode.string reason ) ])
        , expect = Http.expectJson toMsg configurationDecoder
        , timeout = Nothing
        , tracker = Nothing
        }


revokeConfig : String -> String -> (Result Http.Error Types.Configuration -> msg) -> Cmd msg
revokeConfig accessToken configId toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/admin/configs/" ++ configId ++ "/revoke"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg configurationDecoder
        , timeout = Nothing
        , tracker = Nothing
        }
