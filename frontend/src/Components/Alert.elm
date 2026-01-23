module Components.Alert exposing
    ( AlertType(..)
    , alert
    , alertDismissible
    )

{-| Alert component matching Pencil design (6kR5R)

  - fill=$--active-bg
  - border=$--border-emphasis
  - padding=[18,24]
  - gap=14px
  - info icon + text + close icon

-}

import Components.Icon as Icon
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, type_)
import Html.Styled.Events exposing (onClick)
import Styles


type AlertType
    = Info
    | Success
    | Warning
    | Error


{-| Alert without dismiss button

    alert Info "This is an informational message"

-}
alert : AlertType -> String -> Html msg
alert alertType message =
    div
        [ css (alertStyles alertType)
        ]
        [ alertIcon alertType
        , div [ css alertTextStyles ]
            [ text message ]
        ]


{-| Alert with dismiss button

    alertDismissible Info "This is an alert" DismissAlert

-}
alertDismissible : AlertType -> String -> msg -> Html msg
alertDismissible alertType message onDismiss =
    div
        [ css (alertStyles alertType)
        ]
        [ alertIcon alertType
        , div [ css alertTextStyles ]
            [ text message ]
        , button
            [ type_ "button"
            , onClick onDismiss
            , css closeButtonStyles
            ]
            [ Icon.icon Icon.X Icon.Medium Styles.colors.foregroundSubtle ]
        ]


{-| Get icon for alert type
-}
alertIcon : AlertType -> Html msg
alertIcon alertType =
    let
        ( iconType, iconColor ) =
            case alertType of
                Info ->
                    ( Icon.Info, Styles.colors.info )

                Success ->
                    ( Icon.Check, Styles.colors.success )

                Warning ->
                    ( Icon.Info, Styles.colors.warning )

                Error ->
                    ( Icon.X, Styles.colors.error )
    in
    Icon.icon iconType Icon.Medium iconColor


{-| Alert container styles
-}
alertStyles : AlertType -> List Style
alertStyles alertType =
    let
        ( bgColor, borderColor ) =
            case alertType of
                Info ->
                    ( Styles.colors.infoMuted, Styles.colors.info )

                Success ->
                    ( Styles.colors.successMuted, Styles.colors.success )

                Warning ->
                    ( Styles.colors.warningMuted, Styles.colors.warning )

                Error ->
                    ( Styles.colors.errorMuted, Styles.colors.error )
    in
    [ displayFlex
    , alignItems center
    , property "gap" "14px"
    , padding2 (px 18) (px 24)
    , backgroundColor bgColor
    , border3 (px 1) solid borderColor
    , borderRadius zero
    , Css.width (pct 100)
    ]


{-| Alert text styles
-}
alertTextStyles : List Style
alertTextStyles =
    [ flex (int 1)
    , fontFamilies Styles.fontStack
    , Css.fontSize (px 13)
    , fontWeight (int 400)
    , color Styles.colors.foreground
    , lineHeight (num 1.5)
    ]


{-| Close button styles
-}
closeButtonStyles : List Style
closeButtonStyles =
    [ backgroundColor transparent
    , border zero
    , padding zero
    , cursor pointer
    , displayFlex
    , alignItems center
    , justifyContent center
    , outline none
    , Styles.transitions.base
    , hover
        [ opacity (num 0.7)
        ]
    ]
