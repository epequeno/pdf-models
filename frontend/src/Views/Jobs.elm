module Views.Jobs exposing (view)

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
import Types exposing (Job, JobStatus(..), Model, Msg(..), PdfModel, Route(..), defaultPdfModel, pdfModelToDisplayName, routeToPath)


view : Model -> Html Msg
view model =
    div
        [ css
            [ Styles.containerStyle
            , paddingTop Styles.spacing.xxxl
            , minHeight (vh 100)
            ]
        ]
        [ viewHeader
        , viewStatsBar model
        , div
            [ css
                [ marginTop Styles.spacing.xxl
                ]
            ]
            [ viewJobsSection model
            ]
        ]


viewHeader : Html Msg
viewHeader =
    div
        [ css
            [ Styles.flexBetween
            , marginBottom Styles.spacing.xxl
            ]
        ]
        [ div []
            [ a
                [ href (routeToPath (Upload defaultPdfModel))
                , css
                    [ Styles.textH1
                    , color Styles.colors.textPrimary
                    , textDecoration none
                    , hover [ color Styles.colors.accent ]
                    ]
                ]
                [ text "PDF Models" ]
            , p
                [ css
                    [ Styles.textSecondary
                    , margin zero
                    , marginTop Styles.spacing.xs
                    ]
                ]
                [ text "Monitor your PDF processing jobs" ]
            ]
        , div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.md
                ]
            ]
            [ a
                [ href (routeToPath Models)
                , css
                    [ padding2 Styles.spacing.sm Styles.spacing.base
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textSecondary
                    , textDecoration none
                    , Css.fontSize Styles.fontSize.body
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.overlay
                        , borderColor Styles.colors.borderStrong
                        ]
                    ]
                ]
                [ text "Models" ]
            , a
                [ href (routeToPath Configs)
                , css
                    [ padding2 Styles.spacing.sm Styles.spacing.base
                    , border3 (px 1) solid Styles.colors.border
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textSecondary
                    , textDecoration none
                    , Css.fontSize Styles.fontSize.body
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.overlay
                        , borderColor Styles.colors.borderStrong
                        ]
                    ]
                ]
                [ text "Configs" ]
            , a
                [ href (routeToPath (Upload defaultPdfModel))
                , css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.sm
                    , padding2 Styles.spacing.sm Styles.spacing.base
                    , backgroundColor Styles.colors.accent
                    , color Styles.colors.textInverse
                    , borderRadius Styles.radius.md
                    , textDecoration none
                    , fontWeight Styles.fontWeights.medium
                    , Css.fontSize Styles.fontSize.body
                    , Styles.transitions.base
                    , hover
                        [ backgroundColor Styles.colors.accentHover
                        , color Styles.colors.textInverse
                        ]
                    ]
                ]
                [ span [] [ text "+" ]
                , text "New Job"
                ]
            , Button.button Button.Ghost "Sign Out" SignOutClicked
            ]
        ]


viewStatsBar : Model -> Html Msg
viewStatsBar model =
    let
        jobs =
            model.jobs.jobs

        totalJobs =
            List.length jobs

        processingJobs =
            List.length (List.filter (\j -> j.status == Processing) jobs)

        completedJobs =
            List.length (List.filter (\j -> j.status == Complete) jobs)

        failedJobs =
            List.length (List.filter (\j -> j.status == Failed) jobs)
    in
    div
        [ css
            [ displayFlex
            , Styles.gap Styles.spacing.base
            , flexWrap wrap
            ]
        ]
        [ statCard "Total Jobs" (String.fromInt totalJobs) Nothing
        , statCard "Processing" (String.fromInt processingJobs) (Just Styles.colors.accent)
        , statCard "Completed" (String.fromInt completedJobs) (Just Styles.colors.success)
        , statCard "Failed" (String.fromInt failedJobs) (Just Styles.colors.error)
        ]


statCard : String -> String -> Maybe Color -> Html msg
statCard label value accentColor =
    div
        [ css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.lg
            , padding Styles.spacing.lg
            , minWidth (px 140)
            , flex (num 1)
            ]
        ]
        [ div
            [ css
                [ Styles.textCaption
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ text label ]
        , div
            [ css
                [ Css.fontSize (px 28)
                , fontWeight Styles.fontWeights.semibold
                , color
                    (case accentColor of
                        Just c ->
                            c

                        Nothing ->
                            Styles.colors.textPrimary
                    )
                , lineHeight (num 1)
                ]
            ]
            [ text value ]
        ]


viewJobsSection : Model -> Html Msg
viewJobsSection model =
    div []
        [ div
            [ css
                [ Styles.flexBetween
                , marginBottom Styles.spacing.lg
                ]
            ]
            [ h2
                [ css
                    [ Styles.textH1
                    , margin zero
                    ]
                ]
                [ text "Recent Jobs" ]
            , Button.button Button.Secondary "Refresh" RefreshClicked
            ]
        , case model.jobs.downloadError of
            Just downloadErr ->
                viewAlert Styles.colors.error Styles.colors.errorMuted downloadErr.message (Just ClearDownloadError)

            Nothing ->
                text ""
        , case model.jobs.error of
            Just err ->
                viewAlert Styles.colors.error Styles.colors.errorMuted err Nothing

            Nothing ->
                if List.isEmpty model.jobs.jobs then
                    viewEmptyState model.jobs.loading

                else
                    div
                        [ css
                            [ displayFlex
                            , flexDirection column
                            , Styles.gap Styles.spacing.md
                            ]
                        ]
                        (List.map (viewJobCard model.currentTime model.jobs.expandedJobIds model.jobs.expandedErrorIds) model.jobs.jobs)
        ]


viewAlert : Color -> Color -> String -> Maybe Msg -> Html Msg
viewAlert textColor bgColor message dismissMsg =
    div
        [ css
            [ backgroundColor bgColor
            , border3 (px 1) solid textColor
            , borderRadius Styles.radius.md
            , padding Styles.spacing.base
            , marginBottom Styles.spacing.lg
            , Styles.flexBetween
            ]
        ]
        [ span
            [ css [ color textColor, Css.fontSize Styles.fontSize.body ] ]
            [ text message ]
        , case dismissMsg of
            Just msg ->
                Button.button Button.Ghost "Dismiss" msg

            Nothing ->
                text ""
        ]


viewEmptyState : Bool -> Html Msg
viewEmptyState isLoading =
    div
        [ css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.lg
            , padding Styles.spacing.massive
            , textAlign center
            ]
        ]
        [ div
            [ css
                [ Css.fontSize (px 48)
                , marginBottom Styles.spacing.lg
                , opacity (num 0.3)
                ]
            ]
            [ text
                (if isLoading then
                    "..."

                 else
                    "📄"
                )
            ]
        , h3
            [ css
                [ Styles.textH2
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ text
                (if isLoading then
                    "Loading jobs..."

                 else
                    "No jobs yet"
                )
            ]
        , p
            [ css
                [ Styles.textSecondary
                , margin zero
                ]
            ]
            [ text
                (if isLoading then
                    "Please wait while we fetch your jobs"

                 else
                    "Upload a PDF to get started with document processing"
                )
            ]
        ]


viewJobCard : Time.Posix -> Set String -> Set String -> Job -> Html Msg
viewJobCard currentTime expandedJobIds expandedErrorIds job =
    let
        isExpanded =
            Set.member job.id expandedJobIds

        isErrorExpanded =
            Set.member job.id expandedErrorIds
    in
    div
        [ css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.lg
            , overflow Css.hidden
            , Styles.transitions.base
            , hover
                [ borderColor Styles.colors.borderStrong
                ]
            ]
        ]
        [ -- Clickable header
          div
            [ css
                [ Styles.flexBetween
                , padding Styles.spacing.lg
                , cursor pointer
                , Styles.transitions.base
                , hover
                    [ backgroundColor Styles.colors.overlay
                    ]
                ]
            , onClick (ToggleJobExpanded job.id)
            ]
            [ div
                [ css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.base
                    ]
                ]
                [ -- Expand indicator
                  span
                    [ css
                        [ color Styles.colors.textTertiary
                        , Css.fontSize Styles.fontSize.small
                        , Css.width (px 16)
                        , Styles.transitions.base
                        , transform
                            (if isExpanded then
                                rotate (deg 90)

                             else
                                rotate (deg 0)
                            )
                        ]
                    ]
                    [ text "▶" ]
                , -- Filename or Job ID
                  span
                    [ css
                        [ fontWeight Styles.fontWeights.medium
                        , color Styles.colors.textPrimary
                        ]
                    ]
                    [ text (displayJobName job) ]
                , -- Model badge
                  span
                    [ css
                        [ Css.fontSize Styles.fontSize.caption
                        , fontWeight Styles.fontWeights.medium
                        , color Styles.colors.accent
                        , backgroundColor Styles.colors.accentMuted
                        , padding2 Styles.spacing.xs Styles.spacing.sm
                        , borderRadius Styles.radius.full
                        ]
                    ]
                    [ text (pdfModelToDisplayName job.pdfModel) ]
                , StatusBadge.statusBadge job.status
                ]
            , div
                [ css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.base
                    ]
                ]
                [ span
                    [ css
                        [ Styles.textSmall
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
                    [ padding Styles.spacing.xl
                    , paddingTop zero
                    , borderTop3 (px 1) solid Styles.colors.border
                    ]
                ]
                [ -- File info
                  div
                    [ css
                        [ marginBottom Styles.spacing.lg
                        , marginTop Styles.spacing.lg
                        , padding Styles.spacing.md
                        , backgroundColor Styles.colors.surfaceRaised
                        , borderRadius Styles.radius.sm
                        ]
                    ]
                    (case job.originalFilename of
                        Just filename ->
                            [ div
                                [ css
                                    [ Styles.textCaption
                                    , marginBottom Styles.spacing.xs
                                    ]
                                ]
                                [ text "ORIGINAL FILE" ]
                            , div
                                [ css
                                    [ fontWeight Styles.fontWeights.medium
                                    , color Styles.colors.textPrimary
                                    , marginBottom Styles.spacing.sm
                                    ]
                                ]
                                [ text filename ]
                            , div
                                [ css
                                    [ Styles.textCaption
                                    , marginBottom Styles.spacing.xs
                                    ]
                                ]
                                [ text "S3 KEY" ]
                            , div
                                [ css
                                    [ Styles.textCode
                                    , overflowX auto
                                    ]
                                ]
                                [ text job.s3InputKey ]
                            ]

                        Nothing ->
                            [ div
                                [ css
                                    [ Styles.textCode
                                    , overflowX auto
                                    ]
                                ]
                                [ text job.s3InputKey ]
                            ]
                    )
                , -- Prompt if present
                  case job.prompt of
                    Just promptText ->
                        div
                            [ css
                                [ marginBottom Styles.spacing.lg
                                , padding Styles.spacing.base
                                , backgroundColor Styles.colors.surfaceRaised
                                , border3 (px 1) solid Styles.colors.border
                                , borderRadius Styles.radius.md
                                ]
                            ]
                            [ div
                                [ css
                                    [ Styles.textCaption
                                    , marginBottom Styles.spacing.sm
                                    ]
                                ]
                                [ text "CUSTOM PROMPT" ]
                            , div
                                [ css
                                    [ Styles.textCode
                                    , whiteSpace preWrap
                                    ]
                                ]
                                [ text promptText ]
                            ]

                    Nothing ->
                        text ""
                , -- Timeline
                  Timeline.timeline currentTime job
                , -- Error message if failed
                  case job.error of
                    Just errorMsg ->
                        let
                            errorSummary =
                                extractErrorSummary errorMsg
                        in
                        div
                            [ css
                                [ marginTop Styles.spacing.lg
                                , backgroundColor Styles.colors.errorMuted
                                , border3 (px 1) solid Styles.colors.error
                                , borderRadius Styles.radius.md
                                , overflow Css.hidden
                                ]
                            ]
                            [ -- Clickable header
                              div
                                [ css
                                    [ padding Styles.spacing.base
                                    , cursor pointer
                                    , Styles.flexBetween
                                    , Styles.transitions.base
                                    , hover
                                        [ backgroundColor (rgba 255 0 0 0.1)
                                        ]
                                    ]
                                , onClick (ToggleErrorExpanded job.id)
                                ]
                                [ div
                                    [ css
                                        [ Styles.flexRow
                                        , Styles.gap Styles.spacing.sm
                                        ]
                                    ]
                                    [ -- Expand indicator
                                      span
                                        [ css
                                            [ color Styles.colors.error
                                            , Css.fontSize Styles.fontSize.small
                                            , Css.width (px 16)
                                            , Styles.transitions.base
                                            , transform
                                                (if isErrorExpanded then
                                                    rotate (deg 90)

                                                 else
                                                    rotate (deg 0)
                                                )
                                            ]
                                        ]
                                        [ text "▶" ]
                                    , span
                                        [ css
                                            [ fontWeight Styles.fontWeights.medium
                                            , color Styles.colors.error
                                            ]
                                        ]
                                        [ text "Error Details" ]
                                    ]
                                , span
                                    [ css
                                        [ Css.fontSize Styles.fontSize.small
                                        , color Styles.colors.error
                                        , opacity (num 0.7)
                                        ]
                                    ]
                                    [ text
                                        (if isErrorExpanded then
                                            "Click to collapse"

                                         else
                                            "Click to expand"
                                        )
                                    ]
                                ]
                            , -- Summary always visible
                              div
                                [ css
                                    [ padding2 zero Styles.spacing.base
                                    , paddingBottom Styles.spacing.base
                                    ]
                                ]
                                [ div
                                    [ css
                                        [ Styles.textCode
                                        , color Styles.colors.error
                                        , Css.fontSize Styles.fontSize.body
                                        ]
                                    ]
                                    [ text errorSummary ]
                                ]
                            , -- Full details (expandable)
                              if isErrorExpanded then
                                div
                                    [ css
                                        [ padding Styles.spacing.base
                                        , paddingTop zero
                                        , borderTop3 (px 1) solid Styles.colors.error
                                        , maxHeight (px 400)
                                        , overflowY auto
                                        ]
                                    ]
                                    [ div
                                        [ css
                                            [ Styles.textCode
                                            , color Styles.colors.error
                                            , whiteSpace preWrap
                                            , Css.fontSize Styles.fontSize.small
                                            , marginTop Styles.spacing.base
                                            ]
                                        ]
                                        [ text errorMsg ]
                                    ]

                              else
                                text ""
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


displayJobName : Job -> String
displayJobName job =
    case job.originalFilename of
        Just filename ->
            if String.length filename > 40 then
                String.left 37 filename ++ "..."

            else
                filename

        Nothing ->
            "Job " ++ truncateJobId job.id


extractErrorSummary : String -> String
extractErrorSummary errorMsg =
    -- Extract the main error type from a Python traceback or error message
    -- Look for common patterns like "AssertionError", "ValueError", etc.
    let
        lines =
            String.lines errorMsg

        -- Try to find the last line that looks like an error (e.g., "AssertionError: message")
        errorLine =
            lines
                |> List.reverse
                |> List.filter (\line -> String.contains "Error" line || String.contains "Exception" line)
                |> List.head

        -- Get the first meaningful line as fallback
        firstLine =
            lines
                |> List.filter (\line -> not (String.isEmpty (String.trim line)))
                |> List.head
                |> Maybe.withDefault "An error occurred"
    in
    case errorLine of
        Just line ->
            let
                trimmed =
                    String.trim line
            in
            if String.length trimmed > 100 then
                String.left 100 trimmed ++ "..."

            else
                trimmed

        Nothing ->
            if String.length firstLine > 100 then
                String.left 100 firstLine ++ "..."

            else
                firstLine
