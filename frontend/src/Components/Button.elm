module Components.Button exposing
    ( ButtonStyle(..)
    , button
    , buttonDisabled
    , buttonWithIcon
    , iconButton
    )

{-| Button component matching Pencil design specifications

All buttons use:

  - Font: Manrope
  - Font size: 13px
  - Font weight: 500
  - Gap: 8px (between icon and text)

-}

import Components.Icon as Icon
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
    | IconOnly


{-| Basic button with text only
-}
button : ButtonStyle -> String -> msg -> Html msg
button btnStyle label msg =
    Html.Styled.button
        [ css (buttonStyles btnStyle False)
        , onClick msg
        , type_ "button"
        ]
        [ text label ]


{-| Button with icon and text
-}
buttonWithIcon : ButtonStyle -> Icon.Icon -> String -> msg -> Html msg
buttonWithIcon btnStyle icon label msg =
    Html.Styled.button
        [ css (buttonStyles btnStyle False)
        , onClick msg
        , type_ "button"
        ]
        [ Icon.icon icon Icon.Small (iconColor btnStyle)
        , text label
        ]


{-| Icon-only button (no text)
-}
iconButton : Icon.Icon -> msg -> Html msg
iconButton icon msg =
    Html.Styled.button
        [ css (buttonStyles IconOnly False)
        , onClick msg
        , type_ "button"
        ]
        [ Icon.icon icon Icon.Small Styles.colors.foregroundSubtle ]


{-| Disabled button
-}
buttonDisabled : ButtonStyle -> String -> Html msg
buttonDisabled btnStyle label =
    Html.Styled.button
        [ css (buttonStyles btnStyle True)
        , Attr.disabled True
        , type_ "button"
        ]
        [ text label ]


{-| Get icon color based on button style
-}
iconColor : ButtonStyle -> Color
iconColor btnStyle =
    case btnStyle of
        Primary ->
            Styles.colors.primaryForeground

        Secondary ->
            Styles.colors.foregroundSubtle

        Ghost ->
            Styles.colors.foregroundSubtle

        Danger ->
            Css.hex "FFFFFF"

        IconOnly ->
            Styles.colors.foregroundSubtle


{-| Button styles matching Pencil design exactly
-}
buttonStyles : ButtonStyle -> Bool -> List Style
buttonStyles btnStyle isDisabled =
    let
        baseStyles =
            [ fontFamilies Styles.fontStack
            , Css.fontSize (px 13)
            , fontWeight (int 500)
            , cursor pointer
            , Styles.transitions.base
            , displayFlex
            , alignItems center
            , justifyContent center
            , property "gap" "8px"
            , border zero
            , outline zero
            , focus
                [ Styles.focusRing
                ]
            ]

        styleVariant =
            if isDisabled then
                [ backgroundColor Styles.colors.border
                , color Styles.colors.foregroundSubtle
                , cursor notAllowed
                , opacity (num 0.5)
                , padding2 (px 12) (px 24)
                ]

            else
                case btnStyle of
                    Primary ->
                        -- fill=$--primary, text=$--primary-foreground, padding=[12,24]
                        [ backgroundColor Styles.colors.primary
                        , color Styles.colors.primaryForeground
                        , padding2 (px 12) (px 24)
                        , hover
                            [ backgroundColor Styles.colors.accentHover
                            ]
                        , active
                            [ backgroundColor Styles.colors.accentPressed
                            , transform (scale 0.98)
                            ]
                        ]

                    Secondary ->
                        -- border=$--border-button, padding=[12,20]
                        [ backgroundColor transparent
                        , color Styles.colors.foreground
                        , padding2 (px 12) (px 20)
                        , border3 (px 1) solid Styles.colors.borderButton
                        , hover
                            [ backgroundColor Styles.colors.overlay
                            , borderColor Styles.colors.borderEmphasis
                            ]
                        , active
                            [ transform (scale 0.98)
                            ]
                        ]

                    Ghost ->
                        -- no fill/border, padding=[12,20]
                        [ backgroundColor transparent
                        , color Styles.colors.foreground
                        , padding2 (px 12) (px 20)
                        , hover
                            [ backgroundColor Styles.colors.overlay
                            ]
                        , active
                            [ transform (scale 0.98)
                            ]
                        ]

                    Danger ->
                        -- fill=$--error, text=#FFFFFF, padding=[12,24]
                        [ backgroundColor Styles.colors.error
                        , color (hex "FFFFFF")
                        , padding2 (px 12) (px 24)
                        , hover
                            [ backgroundColor (hex "DC2626")
                            ]
                        , active
                            [ backgroundColor (hex "B91C1C")
                            , transform (scale 0.98)
                            ]
                        ]

                    IconOnly ->
                        -- border=$--border-button, padding=[10,14], icon only
                        [ backgroundColor transparent
                        , color Styles.colors.foregroundSubtle
                        , padding2 (px 10) (px 14)
                        , border3 (px 1) solid Styles.colors.borderButton
                        , hover
                            [ backgroundColor Styles.colors.overlay
                            , borderColor Styles.colors.borderEmphasis
                            , color Styles.colors.foreground
                            ]
                        , active
                            [ transform (scale 0.98)
                            ]
                        ]
    in
    baseStyles ++ styleVariant
