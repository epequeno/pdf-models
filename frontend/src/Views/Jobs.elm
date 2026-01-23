module Views.Jobs exposing (view)

import Components.AppLayout as AppLayout
import Components.Badge as Badge
import Components.Button as Button
import Components.Icon as Icon
import Components.SearchInput as SearchInput
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
import Html.Styled.Events exposing (onClick)
import Styles
import Time
import Types exposing (Job, JobStatus(..), Model, Msg(..), PdfModel, Route(..), pdfModelToDisplayName, routeToPath)


view : Model -> Html Msg
view model =
    AppLayout.view
        { currentRoute = Jobs
        , userName = "John Doe"
        , userEmail = "john@example.com"
        , showUpgradeCard = True
        , isAdmin = False
        , onSignOut = SignOutClicked
        }
        [ viewJobsContent model
        ]


viewJobsContent : Model -> Html Msg
viewJobsContent model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "32px"
            , height (pct 100)
            , width (pct 100)
            ]
        ]
        [ -- Header section
          viewHeader

        -- Filter bar
        , viewFilterBar

        -- Jobs table or empty state
        , if List.isEmpty model.jobs.jobs && not model.jobs.loading then
            viewEmptyState

          else
            viewJobsTable model

        -- Footer with pagination
        , viewFooter model
        ]


viewHeader : Html Msg
viewHeader =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , property "gap" "4px"
            , width (pct 100)
            , justifyContent spaceBetween
            , alignItems flexStart
            ]
        ]
        [ -- Left side: Breadcrumb, title, subtitle
          div
            [ css
                [ displayFlex
                , flexDirection column
                , property "gap" "4px"
                , flex (int 1)
                ]
            ]
            [ -- Breadcrumb
              div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 11)
                    , fontWeight (int 500)
                    , letterSpacing (px 0.5)
                    , color (hex "666666") -- $--foreground-subtle
                    ]
                ]
                [ text "Dashboard / Jobs" ]

            -- Title
            , div
                [ css
                    [ fontFamilies [ "Playfair Display", .value serif ]
                    , fontSize (px 36)
                    , fontWeight normal
                    , color (hex "FAF8F5") -- $--foreground
                    , marginTop (px 4)
                    ]
                ]
                [ text "Processing Jobs" ]

            -- Subtitle
            , div
                [ css
                    [ fontFamilies Styles.fontStack
                    , fontSize (px 14)
                    , fontWeight normal
                    , color (hex "888888") -- $--foreground-muted
                    ]
                ]
                [ text "View and manage your document processing jobs" ]
            ]

        -- Right side: Action buttons (moved to separate row below header)
        ]


viewFilterBar : Html Msg
viewFilterBar =
    div
        [ css
            [ displayFlex
            , alignItems center
            , property "gap" "12px"
            , width (pct 100)
            , marginTop (px 8)
            ]
        ]
        [ -- Search input
          SearchInput.searchInput
            { placeholder = "Search by filename or job ID..."
            , value = ""
            , onInput = \_ -> NoOp -- TODO: Add search handling
            }
            [ width (px 300) ]

        -- Spacer
        , div [ css [ flex (int 1) ] ] []

        -- Status filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.Sliders
            "Status: All"
            NoOp

        -- Model filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.Layers
            "Model: All"
            NoOp

        -- Date filter button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.Calendar
            "Last 7 days"
            NoOp

        -- Refresh button
        , Button.buttonWithIcon
            Button.Secondary
            Icon.RefreshCw
            "Refresh"
            RefreshClicked

        -- New Job button
        , a
            [ href (routeToPath (Upload Types.Docling))
            , css
                [ displayFlex
                , alignItems center
                , property "gap" "8px"
                , padding2 (px 10) (px 16)
                , backgroundColor (hex "C9A962") -- $--primary
                , color (hex "0F0F0F") -- Dark text on gold background
                , borderRadius (px 8)
                , textDecoration none
                , fontFamilies Styles.fontStack
                , fontSize (px 14)
                , fontWeight (int 500)
                , border zero
                , cursor pointer
                , Styles.transitions.base
                , hover
                    [ backgroundColor (hex "D4B76E") -- Slightly lighter on hover
                    ]
                ]
            ]
            [ Icon.icon Icon.Plus Icon.Medium (hex "0F0F0F")
            , text "New Job"
            ]
        ]


viewJobsTable : Model -> Html Msg
viewJobsTable model =
    div
        [ css
            [ width (pct 100)
            , border3 (px 1) solid (hex "1F1F1F") -- $--border
            , borderRadius (px 8)
            , overflow hidden
            ]
        ]
        [ -- Table header
          div
            [ css
                [ displayFlex
                , alignItems center
                , width (pct 100)
                , borderBottom3 (px 1) solid (hex "333333") -- $--border-emphasis
                ]
            ]
            [ tableHeaderCell "JOB ID" 120
            , tableHeaderCell "FILENAME" 0 -- flex: 1
            , tableHeaderCell "MODEL" 140
            , tableHeaderCell "STATUS" 120
            , tableHeaderCell "SUBMITTED" 150
            , tableHeaderCell "ACTIONS" 100
            ]

        -- Table rows
        , div []
            (if model.jobs.loading then
                [ viewLoadingRow ]

             else
                List.map (viewJobRow model.currentTime) model.jobs.jobs
            )
        ]


tableHeaderCell : String -> Int -> Html Msg
tableHeaderCell label width =
    div
        [ css
            [ displayFlex
            , alignItems center
            , padding2 (px 14) (px 20)
            , fontFamilies Styles.fontStack
            , fontSize (px 11)
            , fontWeight (int 600)
            , color (hex "C9A962") -- $--primary
            , if width > 0 then
                Css.width (px (toFloat width))

              else
                flex (int 1)
            ]
        ]
        [ text label ]


viewJobRow : Time.Posix -> Job -> Html Msg
viewJobRow currentTime job =
    div
        [ css
            [ displayFlex
            , alignItems center
            , width (pct 100)
            , borderBottom3 (px 1) solid (hex "151515") -- $--border-subtle
            , Styles.transitions.base
            , hover
                [ backgroundColor (rgba 201 169 98 0.063) -- $--active-bg
                ]
            ]
        ]
        [ -- Job ID (truncated)
          tableCell (truncateJobId job.id) 120 [ "JetBrains Mono", "monospace" ] 12 (hex "FAF8F5")

        -- Filename
        , tableCell (displayJobName job) 0 [ "Manrope", "sans-serif" ] 13 (hex "FAF8F5")

        -- Model
        , tableCell (pdfModelShortName job.pdfModel) 140 [ "Manrope", "sans-serif" ] 13 (hex "888888")

        -- Status badge
        , div
            [ css
                [ displayFlex
                , alignItems center
                , padding2 (px 16) (px 20)
                , Css.width (px 120)
                ]
            ]
            [ viewStatusBadge job.status ]

        -- Submitted date
        , tableCell (formatRelativeTime currentTime job.submittedAt) 150 [ "Manrope", "sans-serif" ] 12 (hex "888888")

        -- Actions
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "8px"
                , padding2 (px 16) (px 20)
                , Css.width (px 100)
                ]
            ]
            [ -- Download action (only for completed jobs)
              case job.status of
                Complete ->
                    case job.s3OutputKey of
                        Just _ ->
                            button
                                [ onClick (DownloadResult job.id)
                                , css
                                    [ backgroundColor transparent
                                    , border zero
                                    , padding zero
                                    , cursor pointer
                                    , display inlineBlock
                                    , Styles.transitions.base
                                    , hover
                                        [ property "transform" "scale(1.1)"
                                        ]
                                    ]
                                ]
                                [ Icon.icon Icon.Download Icon.Medium (hex "666666") ]

                        Nothing ->
                            text ""

                _ ->
                    text ""

            -- View details action (could be implemented)
            , button
                [ onClick (ToggleJobExpanded job.id)
                , css
                    [ backgroundColor transparent
                    , border zero
                    , padding zero
                    , cursor pointer
                    , display inlineBlock
                    , Styles.transitions.base
                    , hover
                        [ property "transform" "scale(1.1)"
                        ]
                    ]
                ]
                [ Icon.icon Icon.Eye Icon.Medium (hex "666666") ]
            ]
        ]


tableCell : String -> Int -> List String -> Float -> Color -> Html Msg
tableCell content width fontStack fontSize textColor =
    div
        [ css
            [ displayFlex
            , alignItems center
            , padding2 (px 16) (px 20)
            , fontFamilies (List.map (\f -> qt f) fontStack)
            , Css.fontSize (px fontSize)
            , fontWeight normal
            , color textColor
            , if width > 0 then
                Css.width (px (toFloat width))

              else
                flex (int 1)
            ]
        ]
        [ text content ]


viewStatusBadge : JobStatus -> Html Msg
viewStatusBadge status =
    case status of
        Pending ->
            Badge.badge Badge.Info "Pending"

        Processing ->
            Badge.badge Badge.Warning "Processing"

        Complete ->
            Badge.badge Badge.Success "Complete"

        Failed ->
            Badge.badge Badge.Error "Failed"


viewLoadingRow : Html Msg
viewLoadingRow =
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent center
            , padding (px 40)
            , fontFamilies Styles.fontStack
            , fontSize (px 14)
            , color (hex "888888")
            ]
        ]
        [ text "Loading jobs..." ]


viewEmptyState : Html Msg
viewEmptyState =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , alignItems center
            , justifyContent center
            , padding (px 60)
            , backgroundColor (hex "0A0A0A") -- $--background-sidebar
            , border3 (px 1) solid (hex "1F1F1F") -- $--border
            , borderRadius (px 8)
            ]
        ]
        [ div
            [ css
                [ fontSize (px 48)
                , marginBottom (px 16)
                , opacity (num 0.3)
                ]
            ]
            [ text "📄" ]
        , h3
            [ css
                [ fontFamilies [ "Playfair Display", .value serif ]
                , fontSize (px 24)
                , fontWeight normal
                , color (hex "FAF8F5")
                , margin zero
                , marginBottom (px 8)
                ]
            ]
            [ text "No jobs yet" ]
        , p
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 14)
                , color (hex "888888")
                , margin zero
                ]
            ]
            [ text "Upload a document to get started with processing" ]
        ]


viewFooter : Model -> Html Msg
viewFooter model =
    let
        totalJobs =
            List.length model.jobs.jobs

        -- For now, show all jobs (pagination not implemented yet)
        showingCount =
            totalJobs
    in
    div
        [ css
            [ displayFlex
            , alignItems center
            , justifyContent spaceBetween
            , width (pct 100)
            , marginTop (px 8)
            ]
        ]
        [ -- Jobs count
          div
            [ css
                [ fontFamilies Styles.fontStack
                , fontSize (px 12)
                , color (hex "888888") -- $--foreground-muted
                ]
            ]
            [ text ("Showing " ++ String.fromInt showingCount ++ " of " ++ String.fromInt totalJobs ++ " jobs") ]

        -- Pagination controls (placeholder for now)
        , div
            [ css
                [ displayFlex
                , alignItems center
                , property "gap" "4px"
                ]
            ]
            [ -- Previous button (disabled)
              button
                [ css
                    [ padding2 (px 8) (px 12)
                    , backgroundColor transparent
                    , border3 (px 1) solid (hex "1F1F1F")
                    , borderRadius (px 6)
                    , color (hex "666666")
                    , cursor notAllowed
                    , opacity (num 0.5)
                    ]
                ]
                [ Icon.icon Icon.ChevronLeft Icon.Small (hex "666666") ]

            -- Next button (disabled)
            , button
                [ css
                    [ padding2 (px 8) (px 12)
                    , backgroundColor transparent
                    , border3 (px 1) solid (hex "1F1F1F")
                    , borderRadius (px 6)
                    , color (hex "666666")
                    , cursor notAllowed
                    , opacity (num 0.5)
                    ]
                ]
                [ Icon.icon Icon.ChevronRight Icon.Small (hex "666666") ]
            ]
        ]



-- HELPER FUNCTIONS


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
        String.left 4 jobId ++ "..." ++ String.right 4 jobId

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


pdfModelShortName : PdfModel -> String
pdfModelShortName model =
    case model of
        Types.Marker ->
            "Marker"

        Types.Dolphin ->
            "Dolphin"

        Types.Docling ->
            "Docling"

        Types.DeepSeekOcr ->
            "DeepSeek OCR"

        Types.MinerU ->
            "MinerU"

        Types.OlmOcr ->
            "olmocr"

        Types.Docext ->
            "docext"

        Types.DotsOcr ->
            "dots.ocr"

        Types.LightOnOcr ->
            "LightOnOCR-2"

        Types.PaddleOcr ->
            "PaddleOCR"
