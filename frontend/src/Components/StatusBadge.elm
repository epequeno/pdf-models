module Components.StatusBadge exposing (statusBadge, statusBadgeLarge)

import Css exposing (..)
import Css.Animations as Animations
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles
import Types exposing (JobStatus(..))


type alias BadgeConfig =
    { dotColor : Color
    , bgColor : Color
    , statusText : String
    , isAnimated : Bool
    }


statusBadge : JobStatus -> Html msg
statusBadge status =
    badgeWithSize False status


statusBadgeLarge : JobStatus -> Html msg
statusBadgeLarge status =
    badgeWithSize True status


badgeWithSize : Bool -> JobStatus -> Html msg
badgeWithSize isLarge status =
    let
        config =
            statusConfig status

        sizeStyles =
            if isLarge then
                [ padding2 Styles.spacing.sm Styles.spacing.md
                , Css.fontSize Styles.fontSize.small
                ]

            else
                [ padding2 Styles.spacing.xs Styles.spacing.md
                , Css.fontSize Styles.fontSize.caption
                ]
    in
    span
        [ css
            ([ displayFlex
             , alignItems center
             , Styles.gap Styles.spacing.sm
             , backgroundColor config.bgColor
             , borderRadius Styles.radius.full
             , fontFamilies Styles.fontStack
             , fontWeight Styles.fontWeights.medium
             , color config.dotColor
             ]
                ++ sizeStyles
            )
        ]
        [ span
            [ css
                ([ display inlineBlock
                 , Css.width (px 6)
                 , Css.height (px 6)
                 , borderRadius (pct 50)
                 , backgroundColor config.dotColor
                 ]
                    ++ (if config.isAnimated then
                            [ animationName pulseAnimation
                            , animationDuration (ms 2000)
                            , property "animation-iteration-count" "infinite"
                            , property "animation-timing-function" "ease-in-out"
                            ]

                        else
                            []
                       )
                )
            ]
            []
        , text config.statusText
        ]


statusConfig : JobStatus -> BadgeConfig
statusConfig status =
    case status of
        Pending ->
            { dotColor = Styles.colors.warning
            , bgColor = Styles.colors.warningMuted
            , statusText = "Pending"
            , isAnimated = False
            }

        Processing ->
            { dotColor = Styles.colors.accent
            , bgColor = Styles.colors.accentMuted
            , statusText = "Processing"
            , isAnimated = True
            }

        Complete ->
            { dotColor = Styles.colors.success
            , bgColor = Styles.colors.successMuted
            , statusText = "Complete"
            , isAnimated = False
            }

        Failed ->
            { dotColor = Styles.colors.error
            , bgColor = Styles.colors.errorMuted
            , statusText = "Failed"
            , isAnimated = False
            }


pulseAnimation : Animations.Keyframes {}
pulseAnimation =
    Animations.keyframes
        [ ( 0, [ Animations.opacity (num 1), Animations.transform [ scale 1 ] ] )
        , ( 50, [ Animations.opacity (num 0.5), Animations.transform [ scale 1.2 ] ] )
        , ( 100, [ Animations.opacity (num 1), Animations.transform [ scale 1 ] ] )
        ]
