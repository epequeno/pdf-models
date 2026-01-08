module Views.Jobs exposing (view)

import Browser
import Components.Button as Button
import Components.StatusBadge as StatusBadge
import Components.Timeline as Timeline
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
import Html.Styled.Events exposing (onClick)
import Set exposing (Set)
import Styles
import Time
import Types exposing (..)


view : Model -> Html Msg
view model =
    div
        [ css
            [ Styles.containerStyle
            , paddingTop Styles.spacing.xl
            ]
        ]
        [ viewHeader
        , div
            [ css
                [ marginTop Styles.spacing.xl
                ]
            ]
            [ viewJobsSection model
            ]
        ]


viewHeader : Html Msg
viewHeader =
    div
        [ css
            [ displayFlex
            , justifyContent spaceBetween
            , alignItems center
            , marginBottom Styles.spacing.lg
            ]
        ]
        [ h1
            [ css
                [ Css.fontSize Styles.fontSize.h1
                , fontWeight Styles.fontWeight.semibold
                , color Styles.colors.textPrimary
                ]
            ]
            [ text "PDF Models" ]
        , div [ css [ displayFlex, property "gap" "12px" ] ]
            [ a
                [ href (routeToPath (Upload defaultPdfModel))
                , css
                    [ padding2 Styles.spacing.sm Styles.spacing.md
                    , border3 (px 1) solid Styles.colors.border
                    , color Styles.colors.textSecondary
                    , textDecoration none
                    , fontFamilies Styles.fontStack
                    , Css.fontSize Styles.fontSize.body
                    , hover [ backgroundColor Styles.colors.hover ]
                    ]
                ]
                [ text "Upload" ]
            , Button.button Button.Secondary "Logout" SignOutClicked
            ]
        ]


viewJobsSection : Model -> Html Msg
viewJobsSection model =
    div []
        [ div
            [ css
                [ displayFlex
                , justifyContent spaceBetween
                , alignItems center
                , marginBottom Styles.spacing.md
                ]
            ]
            [ h2
                [ css
                    [ Css.fontSize Styles.fontSize.h2
                    , fontWeight Styles.fontWeight.semibold
                    , color Styles.colors.textPrimary
                    ]
                ]
                [ text "Your Jobs" ]
            , Button.button Button.Secondary "Refresh" RefreshClicked
            ]
        , case model.jobs.downloadError of
            Just downloadErr ->
                div
                    [ css
                        [ backgroundColor (hex "2d1f1f")
                        , border3 (px 1) solid Styles.colors.accentError
                        , padding Styles.spacing.md
                        , marginBottom Styles.spacing.md
                        , displayFlex
                        , justifyContent spaceBetween
                        , alignItems center
                        , property "border-radius" "4px"
                        ]
                    ]
                    [ div
                        [ css [ color Styles.colors.accentError ] ]
                        [ text downloadErr.message ]
                    , Button.button Button.Secondary "Dismiss" ClearDownloadError
                    ]

            Nothing ->
                text ""
        , case model.jobs.error of
            Just err ->
                div
                    [ css
                        [ color Styles.colors.accentError
                        , padding Styles.spacing.md
                        , backgroundColor Styles.colors.surface
                        , border3 (px 1) solid Styles.colors.border
                        ]
                    ]
                    [ text err ]

            Nothing ->
                if List.isEmpty model.jobs.jobs then
                    div
                        [ css
                            [ color Styles.colors.textSecondary
                            , padding Styles.spacing.xxl
                            , textAlign center
                            , backgroundColor Styles.colors.surface
                            , border3 (px 1) solid Styles.colors.border
                            ]
                        ]
                        [ text (if model.jobs.loading then "Loading jobs..." else "No jobs yet. Upload a PDF to get started.") ]

                else
                    div
                        [ css
                            [ displayFlex
                            , flexDirection column
                            , property "gap" "12px"
                            ]
                        ]
                        (List.map (viewJobCard model.currentTime model.jobs.expandedJobIds) model.jobs.jobs)
        ]


viewJobCard : Time.Posix -> Set String -> Job -> Html Msg
viewJobCard currentTime expandedJobIds job =
    let
        isExpanded =
            Set.member job.id expandedJobIds
    in
    div
        [ css
            [ border3 (px 1) solid Styles.colors.border
            , backgroundColor Styles.colors.surface
            , property "border-radius" "4px"
            , overflow Css.hidden
            ]
        ]
        [ -- Clickable header
          div
            [ css
                [ displayFlex
                , justifyContent spaceBetween
                , alignItems center
                , padding Styles.spacing.md
                , cursor pointer
                , hover [ backgroundColor Styles.colors.hover ]
                ]
            , onClick (ToggleJobExpanded job.id)
            ]
            [ div
                [ css
                    [ displayFlex
                    , alignItems center
                    , property "gap" "12px"
                    ]
                ]
                [ -- Expand/collapse indicator
                  span
                    [ css
                        [ color Styles.colors.textSecondary
                        , Css.fontSize Styles.fontSize.small
                        , display inlineBlock
                        , Css.width (px 16)
                        ]
                    ]
                    [ text
                        (if isExpanded then
                            "▼"

                         else
                            "▶"
                        )
                    ]
                , span
                    [ css
                        [ fontWeight Styles.fontWeight.semibold
                        , color Styles.colors.textPrimary
                        ]
                    ]
                    [ text ("Job " ++ truncateJobId job.id) ]
                , span
                    [ css
                        [ fontSize Styles.fontSize.small
                        , color Styles.colors.accentPrimary
                        , backgroundColor Styles.colors.hover
                        , padding2 (px 2) (px 8)
                        , property "border-radius" "4px"
                        ]
                    ]
                    [ text (pdfModelToDisplayName job.pdfModel) ]
                , StatusBadge.statusBadge job.status
                ]
            , div
                [ css
                    [ displayFlex
                    , alignItems center
                    , property "gap" "12px"
                    ]
                ]
                [ span
                    [ css
                        [ fontSize Styles.fontSize.small
                        , color Styles.colors.textSecondary
                        ]
                    ]
                    [ text (formatRelativeTime currentTime job.submittedAt) ]
                , case job.status of
                    Complete ->
                        case job.s3OutputKey of
                            Just _ ->
                                Button.button Button.Primary "Download" (DownloadResult job.id)

                            Nothing ->
                                text ""

                    _ ->
                        text ""
                ]
            ]
        , -- Expanded content
          if isExpanded then
            div
                [ css
                    [ padding Styles.spacing.lg
                    , paddingTop (px 0)
                    , borderTop3 (px 1) solid Styles.colors.border
                    ]
                ]
                [ div
                    [ css
                        [ fontSize Styles.fontSize.small
                        , color Styles.colors.textSecondary
                        , fontFamily monospace
                        , marginBottom Styles.spacing.md
                        , marginTop Styles.spacing.md
                        ]
                    ]
                    [ text job.s3InputKey ]
                , Timeline.timeline currentTime job
                , case job.error of
                    Just errorMsg ->
                        div
                            [ css
                                [ marginTop Styles.spacing.md
                                , padding Styles.spacing.md
                                , backgroundColor (hex "2d1f1f")
                                , border3 (px 1) solid Styles.colors.accentError
                                , property "border-radius" "4px"
                                ]
                            ]
                            [ div
                                [ css
                                    [ fontWeight Styles.fontWeight.semibold
                                    , color Styles.colors.accentError
                                    , marginBottom (px 4)
                                    ]
                                ]
                                [ text "Error Details" ]
                            , div
                                [ css
                                    [ fontSize Styles.fontSize.small
                                    , color Styles.colors.accentError
                                    , fontFamily monospace
                                    , whiteSpace preWrap
                                    ]
                                ]
                                [ text errorMsg ]
                            ]

                    Nothing ->
                        text ""
                ]

          else
            text ""
        ]


formatRelativeTime : Time.Posix -> Time.Posix -> String
formatRelativeTime now submitted =
    let
        diffMs =
            Time.posixToMillis now - Time.posixToMillis submitted

        diffSeconds =
            diffMs // 1000

        diffMinutes =
            diffSeconds // 60

        diffHours =
            diffMinutes // 60

        diffDays =
            diffHours // 24
    in
    if diffDays > 0 then
        String.fromInt diffDays ++ "d ago"

    else if diffHours > 0 then
        String.fromInt diffHours ++ "h ago"

    else if diffMinutes > 0 then
        String.fromInt diffMinutes ++ "m ago"

    else
        "just now"


truncateJobId : String -> String
truncateJobId jobId =
    if String.length jobId > 12 then
        String.left 8 jobId ++ "..."

    else
        jobId
