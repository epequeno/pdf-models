module Components.Button exposing (ButtonStyle(..), button)

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, type_)
import Html.Styled.Events exposing (onClick)
import Styles


type ButtonStyle
    = Primary
    | Secondary


button : ButtonStyle -> String -> msg -> Html msg
button btnStyle label msg =
    Html.Styled.button
        [ css (buttonStyles btnStyle)
        , onClick msg
        , type_ "button"
        ]
        [ text label ]


buttonStyles : ButtonStyle -> List Style
buttonStyles btnStyle =
    let
        baseStyles =
            [ padding2 Styles.spacing.sm Styles.spacing.md
            , border3 (px 1) solid Styles.colors.border
            , backgroundColor transparent
            , color Styles.colors.textPrimary
            , fontFamilies Styles.fontStack
            , Css.fontSize Styles.fontSize.body
            , cursor pointer
            , hover
                [ backgroundColor Styles.colors.hover
                ]
            , active
                [ backgroundColor Styles.colors.active
                ]
            ]

        styleVariant =
            case btnStyle of
                Primary ->
                    [ borderColor Styles.colors.accentPrimary
                    , color Styles.colors.accentPrimary
                    ]

                Secondary ->
                    [ borderColor Styles.colors.border
                    , color Styles.colors.textSecondary
                    ]
    in
    baseStyles ++ styleVariant
