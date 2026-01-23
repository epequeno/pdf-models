module Components.Input exposing
    ( InputConfig
    , TextareaConfig
    , PasswordConfig
    , input
    , password
    , textarea
    )

{-| Input components matching Pencil design specifications

All inputs use:

  - Font: Manrope
  - Label font size: 12px, weight: 500
  - Input font size: 14px
  - Border: $--border

-}

import Components.Icon as Icon
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (attribute, css, placeholder, rows, type_, value)
import Html.Styled.Events exposing (on, onInput)
import Json.Decode as Decode
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


type alias PasswordConfig msg =
    { label : String
    , value : String
    , onInput : String -> msg
    , placeholder : String
    , hasError : Bool
    , autocomplete : String
    , showPassword : Bool
    , togglePassword : msg
    }


type alias TextareaConfig msg =
    { label : String
    , value : String
    , onInput : String -> msg
    , placeholder : String
    , hasError : Bool
    }


{-| Text input matching Pencil design (k8keV)

  - Label + field
  - height=44px
  - padding=[0,16]
  - border=$--border

-}
input : InputConfig msg -> Html msg
input config =
    div [ css [ property "gap" "8px", display block ] ]
        [ label
            [ css labelStyles ]
            [ text config.label ]
        , Html.Styled.input
            [ type_ config.inputType
            , value config.value
            , onInput config.onInput
            , placeholder config.placeholder
            , attribute "autocomplete" config.autocomplete
            , css (inputFieldStyles config.hasError)
            ]
            []
        ]


{-| Password input with toggle visibility (aDrre)

  - Like text input but with eye icon toggle
  - padding=[0,16]

-}
password : PasswordConfig msg -> Html msg
password config =
    div [ css [ property "gap" "8px", display block ] ]
        [ label
            [ css labelStyles ]
            [ text config.label ]
        , div
            [ css
                [ position relative
                , displayFlex
                , alignItems center
                ]
            ]
            [ Html.Styled.input
                [ type_
                    (if config.showPassword then
                        "text"

                     else
                        "password"
                    )
                , value config.value
                , onInput config.onInput
                , placeholder config.placeholder
                , attribute "autocomplete" config.autocomplete
                , css (inputFieldStyles config.hasError ++ [ paddingRight (px 48) ])
                ]
                []
            , button
                [ type_ "button"
                , on "click" (Decode.succeed config.togglePassword)
                , css
                    [ position absolute
                    , Css.right (px 16)
                    , backgroundColor transparent
                    , border zero
                    , cursor pointer
                    , padding zero
                    , displayFlex
                    , alignItems center
                    , hover
                        [ opacity (num 0.7)
                        ]
                    ]
                ]
                [ Icon.icon Icon.Eye Icon.Medium Styles.colors.foregroundSubtle ]
            ]
        ]


{-| Textarea input matching Pencil design (4VEEF)

  - Label + textarea
  - height=100px
  - padding=16 (all sides)

-}
textarea : TextareaConfig msg -> Html msg
textarea config =
    div [ css [ property "gap" "8px", display block ] ]
        [ label
            [ css labelStyles ]
            [ text config.label ]
        , Html.Styled.textarea
            [ value config.value
            , onInput config.onInput
            , placeholder config.placeholder
            , css (textareaFieldStyles config.hasError)
            ]
            []
        ]


{-| Label styles - fontSize=12, fontWeight=500, color=$--foreground-muted
-}
labelStyles : List Style
labelStyles =
    [ display block
    , marginBottom (px 0)
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 12)
    , fontWeight (int 500)
    , color Styles.colors.foregroundMuted
    ]


{-| Input field styles - height=44px, padding=[0,16], fontSize=14
-}
inputFieldStyles : Bool -> List Style
inputFieldStyles hasError =
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
    , Css.height (px 44)
    , padding2 zero (px 16)
    , backgroundColor transparent
    , border3 (px 1) solid borderColorValue
    , borderRadius zero
    , color Styles.colors.foreground
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 400)
    , lineHeight (num 1.5)
    , outline none
    , Styles.transitions.base
    , hover
        [ borderColor Styles.colors.borderEmphasis
        ]
    , focus
        [ borderColor focusBorderColor
        , Styles.focusRing
        ]
    , Css.pseudoElement "placeholder"
        [ color Styles.colors.foregroundSubtle
        ]
    ]


{-| Textarea field styles - height=100px, padding=16
-}
textareaFieldStyles : Bool -> List Style
textareaFieldStyles hasError =
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
    , Css.height (px 100)
    , padding (px 16)
    , backgroundColor transparent
    , border3 (px 1) solid borderColorValue
    , borderRadius zero
    , color Styles.colors.foreground
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 14)
    , fontWeight (int 400)
    , lineHeight (num 1.5)
    , outline none
    , resize vertical
    , Styles.transitions.base
    , hover
        [ borderColor Styles.colors.borderEmphasis
        ]
    , focus
        [ borderColor focusBorderColor
        , Styles.focusRing
        ]
    , Css.pseudoElement "placeholder"
        [ color Styles.colors.foregroundSubtle
        ]
    ]
