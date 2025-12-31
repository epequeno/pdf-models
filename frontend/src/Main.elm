module Main exposing (main)

import Browser
import Browser.Navigation
import Element exposing (layout, text)
import Url exposing (Url)


type alias Model =
    { count : Int, key : Browser.Navigation.Key }


initialModel _ _ key =
    ( { count = 0, key = key }, Cmd.none )


type Msg
    = UrlChange Url.Url
    | UrlRequest Browser.UrlRequest
    | Increment
    | Decrement


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlChange url ->
            ( model, Cmd.none )

        UrlRequest request ->
            case request of
                Browser.Internal url ->
                    ( model
                    , Browser.Navigation.pushUrl model.key (Url.toString url)
                    )

                Browser.External url ->
                    ( model
                    , Browser.Navigation.load url
                    )

        Increment ->
            ( { model | count = model.count + 1 }, Cmd.none )

        Decrement ->
            ( { model | count = model.count - 1 }, Cmd.none )


view : Model -> Browser.Document Msg
view model =
    { title = ""
    , body =
        [ layout [] (text "hello world")
        ]
    }


main : Program () Model Msg
main =
    Browser.application
        { init = initialModel
        , view = view
        , update = update
        , onUrlChange = UrlChange
        , onUrlRequest = UrlRequest
        , subscriptions = \_ -> Sub.none
        }
