module Api exposing
    ( getJob
    , getJobs
    , jobDecoder
    , jobStatusDecoder
    , jobsListDecoder
    , pdfModelDecoder
    , submitJob
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


submitJob : String -> PdfModel -> String -> Maybe String -> Maybe String -> (Result Http.Error Job -> msg) -> Cmd msg
submitJob accessToken pdfModel s3Key maybePrompt maybeFilename toMsg =
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

        bodyFields =
            baseFields ++ promptField ++ filenameField
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
