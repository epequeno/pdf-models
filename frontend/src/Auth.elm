port module Auth exposing
    ( AuthResponse
    , ConfirmSignUpResponse
    , SignUpResponse
    , TokenRefreshResponse
    , authResponseDecoder
    , clearSession
    , confirmSignUp
    , confirmSignUpResponseDecoder
    , receiveAuthResponse
    , receiveConfirmSignUpResponse
    , receiveRestoredSession
    , receiveSignUpResponse
    , receiveTokenRefreshResponse
    , refreshToken
    , restoreSession
    , signIn
    , signUp
    , signUpResponseDecoder
    , tokenRefreshResponseDecoder
    )

import Json.Decode as Decode exposing (Decoder)
import Json.Decode.Pipeline exposing (required, optional)
import Json.Encode as Encode


-- PORTS


port signInPort : Encode.Value -> Cmd msg


port signUpPort : Encode.Value -> Cmd msg


port confirmSignUpPort : Encode.Value -> Cmd msg


port receiveAuthResponse : (Encode.Value -> msg) -> Sub msg


port receiveSignUpResponse : (Encode.Value -> msg) -> Sub msg


port receiveConfirmSignUpResponse : (Encode.Value -> msg) -> Sub msg


port restoreSessionPort : () -> Cmd msg


port receiveRestoredSession : (Encode.Value -> msg) -> Sub msg


port clearSessionPort : () -> Cmd msg


port refreshTokenPort : String -> Cmd msg


port receiveTokenRefreshResponse : (Encode.Value -> msg) -> Sub msg



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


restoreSession : Cmd msg
restoreSession =
    restoreSessionPort ()


clearSession : Cmd msg
clearSession =
    clearSessionPort ()


refreshToken : String -> Cmd msg
refreshToken refreshTokenValue =
    refreshTokenPort refreshTokenValue



-- TYPES


type alias AuthResponse =
    { success : Bool
    , accessToken : Maybe String
    , idToken : Maybe String
    , refreshToken : Maybe String
    , expiresAt : Maybe Int
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


type alias TokenRefreshResponse =
    { success : Bool
    , accessToken : Maybe String
    , idToken : Maybe String
    , expiresAt : Maybe Int
    , error : Maybe String
    }



-- DECODERS


authResponseDecoder : Decoder AuthResponse
authResponseDecoder =
    Decode.succeed AuthResponse
        |> required "success" Decode.bool
        |> optional "accessToken" (Decode.maybe Decode.string) Nothing
        |> optional "idToken" (Decode.maybe Decode.string) Nothing
        |> optional "refreshToken" (Decode.maybe Decode.string) Nothing
        |> optional "expiresAt" (Decode.maybe Decode.int) Nothing
        |> optional "error" (Decode.maybe Decode.string) Nothing


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


tokenRefreshResponseDecoder : Decoder TokenRefreshResponse
tokenRefreshResponseDecoder =
    Decode.succeed TokenRefreshResponse
        |> required "success" Decode.bool
        |> optional "accessToken" (Decode.maybe Decode.string) Nothing
        |> optional "idToken" (Decode.maybe Decode.string) Nothing
        |> optional "expiresAt" (Decode.maybe Decode.int) Nothing
        |> optional "error" (Decode.maybe Decode.string) Nothing
