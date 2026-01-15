module Components.Button exposing (ButtonSize(..), ButtonStyle(..), button, buttonDisabled, iconButton)

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, type_)
import Html.Styled.Events exposing (onClick)
import Styles


type ButtonStyle
    = Primary
    | Secondary
    | Ghost
    | Danger


type ButtonSize
    = Small
    | Medium
    | Large


button : ButtonStyle -> String -> msg -> Html msg
button btnStyle label msg =
    buttonWithSize btnStyle Medium label msg


buttonWithSize : ButtonStyle -> ButtonSize -> String -> msg -> Html msg
buttonWithSize btnStyle size label msg =
    Html.Styled.button
        [ css (buttonStyles btnStyle size False)
        , onClick msg
        , type_ "button"
        ]
        [ text label ]


buttonDisabled : ButtonStyle -> String -> Html msg
buttonDisabled btnStyle label =
    Html.Styled.button
        [ css (buttonStyles btnStyle Medium True)
        , Attr.disabled True
        , type_ "button"
        ]
        [ text label ]


iconButton : ButtonStyle -> String -> String -> msg -> Html msg
iconButton btnStyle icon label msg =
    Html.Styled.button
        [ css (buttonStyles btnStyle Medium False ++ [ displayFlex, alignItems center, Styles.gap Styles.spacing.sm ])
        , onClick msg
        , type_ "button"
        ]
        [ span [ css [ Css.fontSize (px 16) ] ] [ text icon ]
        , text label
        ]


buttonStyles : ButtonStyle -> ButtonSize -> Bool -> List Style
buttonStyles btnStyle size isDisabled =
    let
        baseStyles =
            [ border3 (px 1) solid transparent
            , borderRadius Styles.radius.md
            , fontFamilies Styles.fontStack
            , fontWeight Styles.fontWeights.medium
            , cursor pointer
            , Styles.transitions.base
            , displayFlex
            , alignItems center
            , justifyContent center
            , Styles.gap Styles.spacing.sm
            , focus
                [ Styles.focusRing
                ]
            ]

        sizeStyles =
            case size of
                Small ->
                    [ padding2 Styles.spacing.xs Styles.spacing.md
                    , Css.fontSize Styles.fontSize.small
                    , minHeight (px 28)
                    ]

                Medium ->
                    [ padding2 Styles.spacing.sm Styles.spacing.base
                    , Css.fontSize Styles.fontSize.body
                    , minHeight (px 36)
                    ]

                Large ->
                    [ padding2 Styles.spacing.md Styles.spacing.xl
                    , Css.fontSize Styles.fontSize.body
                    , minHeight (px 44)
                    ]

        styleVariant =
            if isDisabled then
                [ backgroundColor Styles.colors.surface
                , borderColor Styles.colors.border
                , color Styles.colors.textTertiary
                , cursor notAllowed
                , opacity (num 0.6)
                ]

            else
                case btnStyle of
                    Primary ->
                        [ backgroundColor Styles.colors.accent
                        , borderColor Styles.colors.accent
                        , color Styles.colors.textInverse
                        , hover
                            [ backgroundColor Styles.colors.accentHover
                            , borderColor Styles.colors.accentHover
                            ]
                        , active
                            [ backgroundColor Styles.colors.accentPressed
                            , borderColor Styles.colors.accentPressed
                            ]
                        ]

                    Secondary ->
                        [ backgroundColor transparent
                        , borderColor Styles.colors.border
                        , color Styles.colors.textPrimary
                        , hover
                            [ backgroundColor Styles.colors.overlay
                            , borderColor Styles.colors.borderStrong
                            ]
                        , active
                            [ backgroundColor Styles.colors.active
                            ]
                        ]

                    Ghost ->
                        [ backgroundColor transparent
                        , borderColor transparent
                        , color Styles.colors.textSecondary
                        , hover
                            [ backgroundColor Styles.colors.overlay
                            , color Styles.colors.textPrimary
                            ]
                        , active
                            [ backgroundColor Styles.colors.active
                            ]
                        ]

                    Danger ->
                        [ backgroundColor transparent
                        , borderColor Styles.colors.error
                        , color Styles.colors.error
                        , hover
                            [ backgroundColor Styles.colors.errorMuted
                            ]
                        , active
                            [ backgroundColor Styles.colors.errorMuted
                            , opacity (num 0.8)
                            ]
                        ]
    in
    baseStyles ++ sizeStyles ++ styleVariant
