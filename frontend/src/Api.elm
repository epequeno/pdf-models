module Api exposing
    ( getJobs
    , submitJob
    )

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Time
import Types exposing (..)


-- CONFIGURATION


apiBaseUrl : String
apiBaseUrl =
    "https://eykwwhrt16.execute-api.us-east-1.amazonaws.com"



-- SUBMIT JOB


submitJob : String -> String -> (Result Http.Error Job -> msg) -> Cmd msg
submitJob accessToken s3Key toMsg =
    Http.request
        { method = "POST"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/marker/jobs"
        , body =
            Http.jsonBody
                (Encode.object
                    [ ( "s3_input_key", Encode.string s3Key )
                    , ( "start_processing", Encode.bool True )
                    ]
                )
        , expect = Http.expectJson toMsg jobDecoder
        , timeout = Nothing
        , tracker = Nothing
        }



-- GET JOBS


getJobs : String -> (Result Http.Error (List Job) -> msg) -> Cmd msg
getJobs accessToken toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/marker/jobs"
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg jobsListDecoder
        , timeout = Nothing
        , tracker = Nothing
        }



-- DECODERS


jobDecoder : Decoder Job
jobDecoder =
    Decode.map7 Job
        (Decode.field "job_id" Decode.string)
        (Decode.field "created_at" iso8601Decoder)
        (Decode.field "status" jobStatusDecoder)
        (Decode.field "s3_input_key" Decode.string)
        (Decode.maybe (Decode.field "s3_result_key" Decode.string))
        (Decode.maybe (Decode.field "completed_at" iso8601Decoder))
        (Decode.maybe (Decode.field "error" Decode.string))


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


iso8601Decoder : Decoder Time.Posix
iso8601Decoder =
    Decode.string
        |> Decode.andThen
            (\str ->
                -- Simple ISO 8601 parsing - just return epoch for now
                -- In production, use a proper date parsing library
                Decode.succeed (Time.millisToPosix 0)
            )
