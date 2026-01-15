module Components.Input exposing (InputConfig, TextareaConfig, input, textarea)

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (attribute, css, placeholder, rows, type_, value)
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


type alias TextareaConfig msg =
    { label : String
    , value : String
    , onInput : String -> msg
    , placeholder : String
    , hasError : Bool
    , rowCount : Int
    }


input : InputConfig msg -> Html msg
input config =
    div [ css [ marginBottom Styles.spacing.lg ] ]
        [ label
            [ css labelStyles ]
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


textarea : TextareaConfig msg -> Html msg
textarea config =
    div [ css [ marginBottom Styles.spacing.lg ] ]
        [ label
            [ css labelStyles ]
            [ text config.label ]
        , Html.Styled.textarea
            [ value config.value
            , onInput config.onInput
            , placeholder config.placeholder
            , rows config.rowCount
            , css (textareaStyles config.hasError)
            ]
            []
        ]


labelStyles : List Style
labelStyles =
    [ display block
    , marginBottom Styles.spacing.sm
    , Css.fontSize Styles.fontSize.small
    , fontWeight Styles.fontWeights.medium
    , color Styles.colors.textSecondary
    ]


inputStyles : Bool -> List Style
inputStyles hasError =
    let
        borderColorValue =
            if hasError then
                Styles.colors.error

            else
                Styles.colors.border

        focusBorderColor =
            if hasError then
                Styles.colors.error

            else
                Styles.colors.borderFocus
    in
    [ width (pct 100)
    , padding2 Styles.spacing.md Styles.spacing.base
    , backgroundColor Styles.colors.surface
    , border3 (px 1) solid borderColorValue
    , borderRadius Styles.radius.md
    , color Styles.colors.textPrimary
    , fontFamilies Styles.fontStack
    , Css.fontSize Styles.fontSize.body
    , lineHeight Styles.lineHeights.normal
    , outline none
    , Styles.transitions.base
    , hover
        [ borderColor Styles.colors.borderStrong
        ]
    , focus
        [ borderColor focusBorderColor
        , Styles.focusRing
        ]
    , Css.pseudoElement "placeholder"
        [ color Styles.colors.textTertiary
        ]
    ]


textareaStyles : Bool -> List Style
textareaStyles hasError =
    inputStyles hasError
        ++ [ resize vertical
           , minHeight (px 100)
           ]
