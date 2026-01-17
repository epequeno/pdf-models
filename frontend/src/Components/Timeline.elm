module Components.Timeline exposing (timeline)

import Css exposing (..)
import Css.Animations as Animations
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css)
import Styles
import Time
import Types exposing (..)


type alias TimelineEvent =
    { label : String
    , timestamp : Maybe Time.Posix
    , status : EventStatus
    , detail : Maybe String
    }


type EventStatus
    = EventComplete
    | EventActive
    | EventPending
    | EventFailed


timeline : Time.Posix -> Job -> Html Msg
timeline currentTime job =
    let
        events =
            buildTimeline currentTime job
    in
    div
        [ css
            [ backgroundColor Styles.colors.surfaceRaised
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.lg
            , padding Styles.spacing.xl
            ]
        ]
        [ div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.sm
                , marginBottom Styles.spacing.lg
                ]
            ]
            [ span
                [ css
                    [ Css.fontSize (px 16)
                    , opacity (num 0.7)
                    ]
                ]
                [ text "⏱" ]
            , h3
                [ css
                    [ Styles.textH2
                    , margin zero
                    ]
                ]
                [ text "Processing Timeline" ]
            ]
        , div
            [ css
                [ displayFlex
                , flexDirection column
                ]
            ]
            (List.indexedMap (viewEvent currentTime (List.length events)) events)
        ]


buildTimeline : Time.Posix -> Job -> List TimelineEvent
buildTimeline _ job =
    let
        submittedEvent =
            { label = "Job Submitted"
            , timestamp = Just job.submittedAt
            , status = EventComplete
            , detail = Nothing
            }

        processingEvent =
            case job.status of
                Pending ->
                    { label = "Processing"
                    , timestamp = Nothing
                    , status = EventPending
                    , detail = Just "Waiting to start..."
                    }

                Processing ->
                    { label = "Processing"
                    , timestamp = Nothing
                    , status = EventActive
                    , detail = Just (substatusToString job.substatus)
                    }

                Complete ->
                    { label = "Processing"
                    , timestamp = Nothing
                    , status = EventComplete
                    , detail = Nothing
                    }

                Failed ->
                    { label = "Processing"
                    , timestamp = Nothing
                    , status = EventFailed
                    , detail = Nothing
                    }

        completedEvent =
            case job.status of
                Complete ->
                    { label = "Completed"
                    , timestamp = job.completedAt
                    , status = EventComplete
                    , detail = Just "Ready for download"
                    }

                Failed ->
                    { label = "Failed"
                    , timestamp = job.completedAt
                    , status = EventFailed
                    , detail = Just "See error details below"
                    }

                _ ->
                    { label = "Completed"
                    , timestamp = Nothing
                    , status = EventPending
                    , detail = Nothing
                    }
    in
    [ submittedEvent, processingEvent, completedEvent ]


viewEvent : Time.Posix -> Int -> Int -> TimelineEvent -> Html Msg
viewEvent currentTime totalEvents index event =
    let
        isLast =
            index == totalEvents - 1
    in
    div
        [ css
            [ displayFlex
            , Styles.gap Styles.spacing.base
            , alignItems stretch
            ]
        ]
        [ -- Left side: indicator + connector line
          div
            [ css
                [ displayFlex
                , flexDirection column
                , alignItems center
                , Css.width (px 24)
                ]
            ]
            [ -- Status dot with ring
              div
                [ css
                    ([ Css.width (px 12)
                     , Css.height (px 12)
                     , borderRadius (pct 50)
                     , backgroundColor (eventDotColor event.status)
                     , flexShrink (num 0)
                     , position relative
                     ]
                        ++ (if event.status == EventActive then
                                [ animationName pulseAnimation
                                , animationDuration (ms 2000)
                                , property "animation-iteration-count" "infinite"
                                , property "animation-timing-function" "ease-in-out"
                                , property "box-shadow" "0 0 8px rgba(34, 211, 238, 0.5)"
                                ]

                            else
                                []
                           )
                    )
                ]
                []
            , -- Connector line
              if not isLast then
                div
                    [ css
                        [ Css.width (px 2)
                        , flex (num 1)
                        , minHeight (px 40)
                        , backgroundColor
                            (if event.status == EventComplete then
                                Styles.colors.borderStrong

                             else
                                Styles.colors.border
                            )
                        , marginTop Styles.spacing.sm
                        , marginBottom Styles.spacing.sm
                        ]
                    ]
                    []

              else
                text ""
            ]
        , -- Right side: content
          div
            [ css
                [ flex (num 1)
                , paddingBottom
                    (if isLast then
                        px 0

                     else
                        Styles.spacing.lg
                    )
                ]
            ]
            [ div
                [ css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.sm
                    , marginBottom Styles.spacing.xs
                    ]
                ]
                [ span
                    [ css
                        [ fontWeight Styles.fontWeights.medium
                        , color (eventTextColor event.status)
                        , Css.fontSize Styles.fontSize.body
                        ]
                    ]
                    [ text event.label ]
                , case event.timestamp of
                    Just _ ->
                        span
                            [ css
                                [ Css.fontSize Styles.fontSize.small
                                , color Styles.colors.textTertiary
                                ]
                            ]
                            [ text (formatTimestamp currentTime event.timestamp) ]

                    Nothing ->
                        text ""
                ]
            , case event.detail of
                Just detail ->
                    div
                        [ css
                            [ Css.fontSize Styles.fontSize.small
                            , color
                                (if event.status == EventFailed then
                                    Styles.colors.error

                                 else
                                    Styles.colors.textSecondary
                                )
                            , fontFamilies Styles.codeFontStack
                            , backgroundColor
                                (if event.status == EventFailed then
                                    Styles.colors.errorMuted

                                 else if event.status == EventActive then
                                    Styles.colors.accentMuted

                                 else
                                    rgba 0 0 0 0
                                )
                            , padding2 Styles.spacing.xs Styles.spacing.sm
                            , borderRadius Styles.radius.sm
                            , display inlineBlock
                            , marginTop Styles.spacing.xs
                            ]
                        ]
                        [ text detail ]

                Nothing ->
                    text ""
            ]
        ]


eventDotColor : EventStatus -> Color
eventDotColor status =
    case status of
        EventComplete ->
            Styles.colors.success

        EventActive ->
            Styles.colors.accent

        EventPending ->
            Styles.colors.textTertiary

        EventFailed ->
            Styles.colors.error


eventTextColor : EventStatus -> Color
eventTextColor status =
    case status of
        EventComplete ->
            Styles.colors.success

        EventActive ->
            Styles.colors.accent

        EventPending ->
            Styles.colors.textSecondary

        EventFailed ->
            Styles.colors.error


pulseAnimation : Animations.Keyframes {}
pulseAnimation =
    Animations.keyframes
        [ ( 0, [ Animations.opacity (num 1), Animations.transform [ scale 1 ] ] )
        , ( 50, [ Animations.opacity (num 0.7), Animations.transform [ scale 1.3 ] ] )
        , ( 100, [ Animations.opacity (num 1), Animations.transform [ scale 1 ] ] )
        ]


formatTimestamp : Time.Posix -> Maybe Time.Posix -> String
formatTimestamp currentTime maybeTime =
    case maybeTime of
        Just time ->
            let
                currentMillis =
                    Time.posixToMillis currentTime

                timeMillis =
                    Time.posixToMillis time

                diffMillis =
                    currentMillis - timeMillis

                diffSeconds =
                    diffMillis // 1000

                diffMinutes =
                    diffSeconds // 60

                diffHours =
                    diffMinutes // 60

                diffDays =
                    diffHours // 24
            in
            if diffSeconds < 60 then
                if diffSeconds < 10 then
                    "just now"

                else
                    String.fromInt diffSeconds ++ "s ago"

            else if diffMinutes < 60 then
                String.fromInt diffMinutes ++ "m ago"

            else if diffHours < 24 then
                String.fromInt diffHours ++ "h ago"

            else
                String.fromInt diffDays ++ "d ago"

        Nothing ->
            ""


substatusToString : Maybe String -> String
substatusToString maybeSubstatus =
    case maybeSubstatus of
        Just "downloading" ->
            "Downloading file..."

        Just "loading_models" ->
            "Loading models..."

        Just "converting" ->
            "Converting document..."

        Just "uploading" ->
            "Uploading results..."

        Just other ->
            other ++ "..."

        Nothing ->
            "Processing..."
