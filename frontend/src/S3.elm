port module S3 exposing
    ( UploadRequest
    , UploadResponse
    , receiveUploadProgress
    , receiveUploadResponse
    , uploadFile
    , uploadProgressDecoder
    , uploadResponseDecoder
    )

import File exposing (File)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


-- PORTS


port uploadFilePort : Encode.Value -> Cmd msg


port receiveUploadProgress : (Float -> msg) -> Sub msg


port receiveUploadResponse : (Encode.Value -> msg) -> Sub msg



-- COMMANDS


type alias UploadRequest =
    { file : File
    , identityId : String
    , jobId : String
    }


uploadFile : UploadRequest -> Cmd msg
uploadFile request =
    uploadFilePort
        (Encode.object
            [ ( "identityId", Encode.string request.identityId )
            , ( "jobId", Encode.string request.jobId )
            ]
        )



-- TYPES


type alias UploadResponse =
    { success : Bool
    , s3Key : Maybe String
    , error : Maybe String
    }



-- DECODERS


uploadResponseDecoder : Decoder UploadResponse
uploadResponseDecoder =
    Decode.map3 UploadResponse
        (Decode.field "success" Decode.bool)
        (Decode.maybe (Decode.field "s3Key" Decode.string))
        (Decode.maybe (Decode.field "error" Decode.string))


uploadProgressDecoder : Decoder Float
uploadProgressDecoder =
    Decode.float
