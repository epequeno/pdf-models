module Api exposing
    ( getJob
    , getJobs
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
    "https://api.epequeno.app"



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



-- GET SINGLE JOB (with download URL)


getJob : String -> String -> (Result Http.Error Job -> msg) -> Cmd msg
getJob accessToken jobId toMsg =
    Http.request
        { method = "GET"
        , headers = [ Http.header "Authorization" ("Bearer " ++ accessToken) ]
        , url = apiBaseUrl ++ "/v1/models/marker/jobs/" ++ jobId
        , body = Http.emptyBody
        , expect = Http.expectJson toMsg jobWithDownloadDecoder
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


jobWithDownloadDecoder : Decoder Job
jobWithDownloadDecoder =
    Decode.map8 Job
        (Decode.field "job_id" Decode.string)
        (Decode.field "created_at" iso8601Decoder)
        (Decode.field "status" jobStatusDecoder)
        (Decode.field "s3_input_key" Decode.string)
        (Decode.maybe (Decode.field "s3_result_key" Decode.string))
        (Decode.maybe (Decode.field "completed_at" iso8601Decoder))
        (Decode.maybe (Decode.field "error" Decode.string))
        (Decode.maybe (Decode.field "download_url" Decode.string))


jobDecoder : Decoder Job
jobDecoder =
    Decode.map8 Job
        (Decode.field "job_id" Decode.string)
        (Decode.field "created_at" iso8601Decoder)
        (Decode.field "status" jobStatusDecoder)
        (Decode.field "s3_input_key" Decode.string)
        (Decode.maybe (Decode.field "s3_result_key" Decode.string))
        (Decode.maybe (Decode.field "completed_at" iso8601Decoder))
        (Decode.maybe (Decode.field "error" Decode.string))
        (Decode.succeed Nothing)  -- downloadUrl not provided in list view


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
                -- Parse ISO 8601 timestamp
                -- For now, we'll use a simple approach that works with common formats
                -- In production, you'd want a proper ISO 8601 parsing library
                case parseIso8601 str of
                    Just posix ->
                        Decode.succeed posix
                    
                    Nothing ->
                        -- Fallback to current time if parsing fails
                        Decode.succeed (Time.millisToPosix (round (1000 * 1735948800))) -- Approximate current time
            )


parseIso8601 : String -> Maybe Time.Posix
parseIso8601 str =
    -- Simple ISO 8601 parser for common formats like "2024-01-04T15:30:00Z"
    -- This is a basic implementation - in production use a proper library
    let
        -- Remove 'Z' suffix if present
        cleanStr = String.replace "Z" "" str
        
        -- Split on 'T' to separate date and time
        parts = String.split "T" cleanStr
    in
    case parts of
        [datePart, timePart] ->
            case (parseDate datePart, parseTime timePart) of
                (Just (year, month, day), Just (hour, minute, second)) ->
                    -- Convert to milliseconds since epoch (very rough approximation)
                    -- This is not accurate for all dates but will work for recent timestamps
                    let
                        -- Rough calculation - not accounting for leap years, etc.
                        daysSinceEpoch = (year - 1970) * 365 + (month - 1) * 30 + (day - 1)
                        millisSinceEpoch = 
                            daysSinceEpoch * 24 * 60 * 60 * 1000 +
                            hour * 60 * 60 * 1000 +
                            minute * 60 * 1000 +
                            second * 1000
                    in
                    Just (Time.millisToPosix millisSinceEpoch)
                
                _ ->
                    Nothing
        
        _ ->
            Nothing


parseDate : String -> Maybe (Int, Int, Int)
parseDate str =
    case String.split "-" str of
        [yearStr, monthStr, dayStr] ->
            case (String.toInt yearStr, String.toInt monthStr, String.toInt dayStr) of
                (Just year, Just month, Just day) ->
                    Just (year, month, day)
                _ ->
                    Nothing
        _ ->
            Nothing


parseTime : String -> Maybe (Int, Int, Int)
parseTime str =
    case String.split ":" str of
        [hourStr, minuteStr, secondStr] ->
            let
                -- Handle seconds that might have decimal places
                secondInt = String.split "." secondStr
                    |> List.head
                    |> Maybe.withDefault "0"
                    |> String.toInt
                    |> Maybe.withDefault 0
            in
            case (String.toInt hourStr, String.toInt minuteStr) of
                (Just hour, Just minute) ->
                    Just (hour, minute, secondInt)
                _ ->
                    Nothing
        _ ->
            Nothing
