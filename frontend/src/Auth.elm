port module Auth exposing
    ( AuthResponse
    , ConfirmSignUpResponse
    , SignUpResponse
    , authResponseDecoder
    , confirmSignUp
    , confirmSignUpResponseDecoder
    , receiveAuthResponse
    , receiveConfirmSignUpResponse
    , receiveSignUpResponse
    , signIn
    , signUp
    , signUpResponseDecoder
    )

import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


-- PORTS


port signInPort : Encode.Value -> Cmd msg


port signUpPort : Encode.Value -> Cmd msg


port confirmSignUpPort : Encode.Value -> Cmd msg


port receiveAuthResponse : (Encode.Value -> msg) -> Sub msg


port receiveSignUpResponse : (Encode.Value -> msg) -> Sub msg


port receiveConfirmSignUpResponse : (Encode.Value -> msg) -> Sub msg



-- COMMANDS


signIn : String -> String -> Cmd msg
signIn email password =
    signInPort
        (Encode.object
            [ ( "email", Encode.string email )
            , ( "password", Encode.string password )
            ]
        )


signUp : String -> String -> Cmd msg
signUp email password =
    signUpPort
        (Encode.object
            [ ( "email", Encode.string email )
            , ( "password", Encode.string password )
            ]
        )


confirmSignUp : String -> String -> Cmd msg
confirmSignUp email code =
    confirmSignUpPort
        (Encode.object
            [ ( "email", Encode.string email )
            , ( "code", Encode.string code )
            ]
        )



-- TYPES


type alias AuthResponse =
    { success : Bool
    , accessToken : Maybe String
    , idToken : Maybe String
    , identityId : Maybe String
    , error : Maybe String
    }


type alias SignUpResponse =
    { success : Bool
    , userConfirmed : Bool
    , error : Maybe String
    }


type alias ConfirmSignUpResponse =
    { success : Bool
    , error : Maybe String
    }



-- DECODERS


authResponseDecoder : Decoder AuthResponse
authResponseDecoder =
    Decode.map5 AuthResponse
        (Decode.field "success" Decode.bool)
        (Decode.maybe (Decode.field "accessToken" Decode.string))
        (Decode.maybe (Decode.field "idToken" Decode.string))
        (Decode.maybe (Decode.field "identityId" Decode.string))
        (Decode.maybe (Decode.field "error" Decode.string))


signUpResponseDecoder : Decoder SignUpResponse
signUpResponseDecoder =
    Decode.map3 SignUpResponse
        (Decode.field "success" Decode.bool)
        (Decode.field "userConfirmed" Decode.bool |> Decode.maybe |> Decode.map (Maybe.withDefault False))
        (Decode.maybe (Decode.field "error" Decode.string))


confirmSignUpResponseDecoder : Decoder ConfirmSignUpResponse
confirmSignUpResponseDecoder =
    Decode.map2 ConfirmSignUpResponse
        (Decode.field "success" Decode.bool)
        (Decode.maybe (Decode.field "error" Decode.string))
