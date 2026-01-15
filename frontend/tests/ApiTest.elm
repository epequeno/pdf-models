module ApiTest exposing (suite)

import Api exposing (jobDecoder, jobStatusDecoder, jobsListDecoder, pdfModelDecoder)
import Expect
import Json.Decode as Decode
import Test exposing (..)
import Time
import Types exposing (..)


suite : Test
suite =
    describe "Api module"
        [ jobStatusDecoderTests
        , pdfModelDecoderTests
        , jobDecoderTests
        , jobsListDecoderTests
        ]



-- JOB STATUS DECODER TESTS


jobStatusDecoderTests : Test
jobStatusDecoderTests =
    describe "jobStatusDecoder"
        [ test "decodes 'pending' to Pending" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"pending\""
                    |> Expect.equal (Ok Pending)
        , test "decodes 'processing' to Processing" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"processing\""
                    |> Expect.equal (Ok Processing)
        , test "decodes 'complete' to Complete" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"complete\""
                    |> Expect.equal (Ok Complete)
        , test "decodes 'completed' to Complete (alias)" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"completed\""
                    |> Expect.equal (Ok Complete)
        , test "decodes 'failed' to Failed" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"failed\""
                    |> Expect.equal (Ok Failed)
        , test "is case insensitive (PENDING)" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"PENDING\""
                    |> Expect.equal (Ok Pending)
        , test "is case insensitive (Processing)" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"Processing\""
                    |> Expect.equal (Ok Processing)
        , test "fails for unknown status" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"unknown\""
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "fails for empty string" <|
            \_ ->
                Decode.decodeString jobStatusDecoder "\"\""
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        ]



-- PDF MODEL DECODER TESTS


pdfModelDecoderTests : Test
pdfModelDecoderTests =
    describe "pdfModelDecoder"
        [ test "decodes 'marker' to Marker" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"marker\""
                    |> Expect.equal (Ok Marker)
        , test "decodes 'dolphin' to Dolphin" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"dolphin\""
                    |> Expect.equal (Ok Dolphin)
        , test "decodes 'docling' to Docling" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"docling\""
                    |> Expect.equal (Ok Docling)
        , test "decodes 'deepseek-ocr' to DeepSeekOcr" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"deepseek-ocr\""
                    |> Expect.equal (Ok DeepSeekOcr)
        , test "decodes 'mineru' to MinerU" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"mineru\""
                    |> Expect.equal (Ok MinerU)
        , test "decodes 'olmocr' to OlmOcr" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"olmocr\""
                    |> Expect.equal (Ok OlmOcr)
        , test "decodes 'docext' to Docext" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"docext\""
                    |> Expect.equal (Ok Docext)
        , test "fails for unknown model" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"unknown-model\""
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "fails for uppercase (case sensitive)" <|
            \_ ->
                Decode.decodeString pdfModelDecoder "\"MARKER\""
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        ]



-- JOB DECODER TESTS


jobDecoderTests : Test
jobDecoderTests =
    describe "jobDecoder"
        [ test "decodes minimal valid job" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "job_id": "test-123",
                            "model": "marker",
                            "created_at": "2024-01-15T10:30:00Z",
                            "status": "pending",
                            "s3_input_key": "user/test.pdf"
                        }
                        """
                in
                case Decode.decodeString jobDecoder json of
                    Ok job ->
                        Expect.all
                            [ \j -> Expect.equal "test-123" j.id
                            , \j -> Expect.equal Marker j.pdfModel
                            , \j -> Expect.equal Pending j.status
                            , \j -> Expect.equal "user/test.pdf" j.s3InputKey
                            , \j -> Expect.equal Nothing j.s3OutputKey
                            , \j -> Expect.equal Nothing j.completedAt
                            , \j -> Expect.equal Nothing j.error
                            , \j -> Expect.equal Nothing j.downloadUrl
                            , \j -> Expect.equal Nothing j.prompt
                            ]
                            job

                    Err err ->
                        Expect.fail (Decode.errorToString err)
        , test "decodes complete job with all optional fields" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "job_id": "job-456",
                            "model": "dolphin",
                            "created_at": "2024-01-15T10:30:00Z",
                            "status": "complete",
                            "s3_input_key": "user/input.pdf",
                            "s3_result_key": "user/output.md",
                            "completed_at": "2024-01-15T10:35:00Z",
                            "download_url": "https://example.com/download",
                            "prompt": "Extract tables"
                        }
                        """
                in
                case Decode.decodeString jobDecoder json of
                    Ok job ->
                        Expect.all
                            [ \j -> Expect.equal "job-456" j.id
                            , \j -> Expect.equal Dolphin j.pdfModel
                            , \j -> Expect.equal Complete j.status
                            , \j -> Expect.equal (Just "user/output.md") j.s3OutputKey
                            , \j -> Expect.notEqual Nothing j.completedAt
                            , \j -> Expect.equal (Just "https://example.com/download") j.downloadUrl
                            , \j -> Expect.equal (Just "Extract tables") j.prompt
                            ]
                            job

                    Err err ->
                        Expect.fail (Decode.errorToString err)
        , test "decodes failed job with error" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "job_id": "job-err",
                            "model": "docling",
                            "created_at": "2024-01-15T10:30:00Z",
                            "status": "failed",
                            "s3_input_key": "user/bad.pdf",
                            "error": "Processing failed: invalid PDF"
                        }
                        """
                in
                case Decode.decodeString jobDecoder json of
                    Ok job ->
                        Expect.all
                            [ \j -> Expect.equal Failed j.status
                            , \j -> Expect.equal (Just "Processing failed: invalid PDF") j.error
                            ]
                            job

                    Err err ->
                        Expect.fail (Decode.errorToString err)
        , test "fails when job_id is missing" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "model": "marker",
                            "created_at": "2024-01-15T10:30:00Z",
                            "status": "pending",
                            "s3_input_key": "user/test.pdf"
                        }
                        """
                in
                Decode.decodeString jobDecoder json
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "fails when model is missing" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "job_id": "test-123",
                            "created_at": "2024-01-15T10:30:00Z",
                            "status": "pending",
                            "s3_input_key": "user/test.pdf"
                        }
                        """
                in
                Decode.decodeString jobDecoder json
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "fails when status is missing" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "job_id": "test-123",
                            "model": "marker",
                            "created_at": "2024-01-15T10:30:00Z",
                            "s3_input_key": "user/test.pdf"
                        }
                        """
                in
                Decode.decodeString jobDecoder json
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        ]



-- JOBS LIST DECODER TESTS


jobsListDecoderTests : Test
jobsListDecoderTests =
    describe "jobsListDecoder"
        [ test "decodes empty jobs list" <|
            \_ ->
                let
                    json =
                        """{"jobs": []}"""
                in
                Decode.decodeString jobsListDecoder json
                    |> Result.map List.length
                    |> Expect.equal (Ok 0)
        , test "decodes list with multiple jobs" <|
            \_ ->
                let
                    json =
                        """
                        {
                            "jobs": [
                                {
                                    "job_id": "job-1",
                                    "model": "marker",
                                    "created_at": "2024-01-15T10:30:00Z",
                                    "status": "complete",
                                    "s3_input_key": "user/file1.pdf"
                                },
                                {
                                    "job_id": "job-2",
                                    "model": "dolphin",
                                    "created_at": "2024-01-15T11:00:00Z",
                                    "status": "processing",
                                    "s3_input_key": "user/file2.pdf"
                                }
                            ]
                        }
                        """
                in
                case Decode.decodeString jobsListDecoder json of
                    Ok jobs ->
                        Expect.all
                            [ \js -> Expect.equal 2 (List.length js)
                            , \js ->
                                js
                                    |> List.map .id
                                    |> Expect.equal [ "job-1", "job-2" ]
                            , \js ->
                                js
                                    |> List.map .status
                                    |> Expect.equal [ Complete, Processing ]
                            ]
                            jobs

                    Err err ->
                        Expect.fail (Decode.errorToString err)
        , test "fails when jobs field is missing" <|
            \_ ->
                let
                    json =
                        """{"data": []}"""
                in
                Decode.decodeString jobsListDecoder json
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        , test "fails when jobs is not an array" <|
            \_ ->
                let
                    json =
                        """{"jobs": "not-an-array"}"""
                in
                Decode.decodeString jobsListDecoder json
                    |> Result.toMaybe
                    |> Expect.equal Nothing
        ]
