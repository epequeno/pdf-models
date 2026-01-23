port module S3 exposing
    ( UploadRequest
    , UploadResponse
    , receiveUploadProgress
    , receiveUploadResponse
    , uploadFile
    , uploadResponseDecoder
    )

import File exposing (File)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import Types exposing (PdfModel, pdfModelToString)



-- PORTS


port uploadFilePort : Encode.Value -> Cmd msg


port receiveUploadProgress : (Float -> msg) -> Sub msg


port receiveUploadResponse : (Encode.Value -> msg) -> Sub msg



-- COMMANDS


type alias UploadRequest =
    { file : File
    , accessToken : String
    , pdfModel : PdfModel
    }


uploadFile : UploadRequest -> Cmd msg
uploadFile request =
    uploadFilePort
        (Encode.object
            [ ( "accessToken", Encode.string request.accessToken )
            , ( "model", Encode.string (pdfModelToString request.pdfModel) )
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
