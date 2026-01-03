module Components.Input exposing (InputConfig, input)

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (attribute, css, placeholder, type_, value)
import Html.Styled.Events exposing (onInput)
import Styles


type alias InputConfig msg =
    { label : String
    , value : String
    , onInput : String -> msg
    , inputType : String
    , placeholder : String
    , hasError : Bool
    , autocomplete : String
    }


input : InputConfig msg -> Html msg
input config =
    div [ css [ marginBottom Styles.spacing.md ] ]
        [ label
            [ css
                [ display block
                , marginBottom Styles.spacing.xs
                , Css.fontSize Styles.fontSize.small
                , color Styles.colors.textSecondary
                ]
            ]
            [ text config.label ]
        , Html.Styled.input
            [ type_ config.inputType
            , value config.value
            , onInput config.onInput
            , placeholder config.placeholder
            , attribute "autocomplete" config.autocomplete
            , css (inputStyles config.hasError)
            ]
            []
        ]


inputStyles : Bool -> List Style
inputStyles hasError =
    let
        borderColorValue =
            if hasError then
                Styles.colors.accentError

            else
                Styles.colors.border

        focusBorderColor =
            if hasError then
                Styles.colors.accentError

            else
                Styles.colors.focus
    in
    [ width (pct 100)
    , padding2 Styles.spacing.sm (px 12)
    , backgroundColor Styles.colors.surface
    , border3 (px 1) solid borderColorValue
    , color Styles.colors.textPrimary
    , fontFamilies Styles.fontStack
    , Css.fontSize Styles.fontSize.body
    , outline none
    , focus
        [ borderColor focusBorderColor
        ]
    , Css.pseudoElement "placeholder"
        [ color Styles.colors.textTertiary
        ]
    ]
