module Components.Badge exposing
    ( BadgeStyle(..)
    , badge
    )

{-| Badge component matching Pencil design specifications

All badges use:

  - Font: Manrope
  - Font size: 10px
  - Font weight: 500
  - Padding: [4, 10]px
  - Centered alignment

-}

import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles


type BadgeStyle
    = Success
    | Info
    | Warning
    | Error
    | Default


{-| Render a badge with the specified style and text
-}
badge : BadgeStyle -> String -> Html msg
badge style label =
    span
        [ css (badgeStyles style)
        ]
        [ text label ]


{-| Badge styles matching Pencil design exactly
-}
badgeStyles : BadgeStyle -> List Style
badgeStyles style =
    let
        baseStyles =
            [ displayFlex
            , alignItems center
            , justifyContent center
            , padding2 (px 4) (px 10)
            , fontFamilies Styles.fontStack
            , Css.fontSize (px 10)
            , fontWeight (int 500)
            , lineHeight (num 1)
            ]

        variantStyles =
            case style of
                Success ->
                    -- fill=$--success-muted, text=$--success
                    [ backgroundColor Styles.colors.successMuted
                    , color Styles.colors.success
                    ]

                Info ->
                    -- fill=$--info-muted, text=$--info
                    [ backgroundColor Styles.colors.infoMuted
                    , color Styles.colors.info
                    ]

                Warning ->
                    -- fill=$--warning-muted, text=$--warning
                    [ backgroundColor Styles.colors.warningMuted
                    , color Styles.colors.warning
                    ]

                Error ->
                    -- fill=$--error-muted, text=$--error
                    [ backgroundColor Styles.colors.errorMuted
                    , color Styles.colors.error
                    ]

                Default ->
                    -- border=$--border-button, text=$--foreground-muted
                    [ backgroundColor transparent
                    , border3 (px 1) solid Styles.colors.borderButton
                    , color Styles.colors.foregroundMuted
                    ]
    in
    baseStyles ++ variantStyles
