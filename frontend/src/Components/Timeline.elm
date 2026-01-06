module Components.Timeline exposing (timeline)

import Css exposing (..)
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
            [ border3 (px 1) solid Styles.colors.border
            , backgroundColor Styles.colors.surface
            , padding Styles.spacing.md
            , property "border-radius" "4px"
            ]
        ]
        [ h3
            [ css
                [ fontSize Styles.fontSize.h2
                , fontWeight Styles.fontWeight.semibold
                , color Styles.colors.textPrimary
                , marginBottom Styles.spacing.md
                ]
            ]
            [ text "Processing Timeline" ]
        , div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "12px"
                ]
            ]
            (List.map (viewEvent currentTime) events)
        ]


buildTimeline : Time.Posix -> Job -> List TimelineEvent
buildTimeline currentTime job =
    let
        -- Event 1: Job submitted
        submittedEvent =
            { label = "Job Submitted"
            , timestamp = Just job.submittedAt
            , status = EventComplete
            , detail = Nothing
            }

        -- Event 2: Processing started
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
                    , detail = Just "Converting PDF to Markdown..."
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
                    , detail = job.error
                    }

        -- Event 3: Job completed
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
                    , detail = job.error
                    }

                _ ->
                    { label = "Completed"
                    , timestamp = Nothing
                    , status = EventPending
                    , detail = Nothing
                    }
    in
    [ submittedEvent, processingEvent, completedEvent ]


viewEvent : Time.Posix -> TimelineEvent -> Html Msg
viewEvent currentTime event =
    div
        [ css
            [ displayFlex
            , property "gap" "12px"
            , alignItems flexStart
            ]
        ]
        [ -- Status indicator (colored circle)
          div
            [ css
                [ width (px 16)
                , height (px 16)
                , property "border-radius" "50%"
                , backgroundColor (eventColor event.status)
                , flexShrink (num 0)
                , marginTop (px 2)
                , case event.status of
                    EventActive ->
                        batch
                            [ property "animation" "pulse 2s cubic-bezier(0.4, 0, 0.6, 1) infinite"
                            ]

                    _ ->
                        batch []
                ]
            ]
            []
        , -- Event details
          div
            [ css
                [ flex (num 1)
                ]
            ]
            [ div
                [ css
                    [ fontWeight Styles.fontWeight.semibold
                    , color
                        (case event.status of
                            EventFailed ->
                                Styles.colors.accentError

                            EventActive ->
                                Styles.colors.accentPrimary

                            EventComplete ->
                                Styles.colors.accentSuccess

                            EventPending ->
                                Styles.colors.textSecondary
                        )
                    , marginBottom (px 4)
                    ]
                ]
                [ text event.label ]
            , case event.timestamp of
                Just _ ->
                    div
                        [ css
                            [ fontSize Styles.fontSize.small
                            , color Styles.colors.textSecondary
                            ]
                        ]
                        [ text (formatTimestamp currentTime event.timestamp) ]

                Nothing ->
                    text ""
            , case event.detail of
                Just detail ->
                    div
                        [ css
                            [ fontSize Styles.fontSize.small
                            , color
                                (if event.status == EventFailed then
                                    Styles.colors.accentError

                                 else
                                    Styles.colors.textSecondary
                                )
                            , marginTop (px 4)
                            , fontFamily monospace
                            ]
                        ]
                        [ text detail ]

                Nothing ->
                    text ""
            ]
        ]


eventColor : EventStatus -> Color
eventColor status =
    case status of
        EventComplete ->
            Styles.colors.accentSuccess

        EventActive ->
            Styles.colors.accentPrimary

        EventPending ->
            Styles.colors.textSecondary

        EventFailed ->
            Styles.colors.accentError


formatTimestamp : Time.Posix -> Maybe Time.Posix -> String
formatTimestamp currentTime maybeTime =
    case maybeTime of
        Just time ->
            let
                currentMillis = Time.posixToMillis currentTime
                timeMillis = Time.posixToMillis time
                diffMillis = currentMillis - timeMillis
                diffSeconds = diffMillis // 1000
                diffMinutes = diffSeconds // 60
                diffHours = diffMinutes // 60
                diffDays = diffHours // 24
            in
            if diffSeconds < 60 then
                if diffSeconds < 10 then
                    "Just now"
                else
                    String.fromInt diffSeconds ++ " seconds ago"
            else if diffMinutes < 60 then
                if diffMinutes == 1 then
                    "1 minute ago"
                else
                    String.fromInt diffMinutes ++ " minutes ago"
            else if diffHours < 24 then
                if diffHours == 1 then
                    "1 hour ago"
                else
                    String.fromInt diffHours ++ " hours ago"
            else if diffDays == 1 then
                "1 day ago"
            else
                String.fromInt diffDays ++ " days ago"

        Nothing ->
            ""
