module Views.Jobs exposing (view)

import Browser
import Components.Button as Button
import Components.StatusBadge as StatusBadge
import Components.Table as Table
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
import Html.Styled.Events exposing (onClick)
import Styles
import Time
import Types exposing (..)
import Url


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
            [ viewJobsSection model.jobs
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
                [ href "/upload"
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


viewJobsSection : JobsState -> Html Msg
viewJobsSection jobsState =
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
        , case jobsState.error of
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
                if List.isEmpty jobsState.jobs then
                    div
                        [ css
                            [ color Styles.colors.textSecondary
                            , padding Styles.spacing.xxl
                            , textAlign center
                            , backgroundColor Styles.colors.surface
                            , border3 (px 1) solid Styles.colors.border
                            ]
                        ]
                        [ text (if jobsState.loading then "Loading jobs..." else "No jobs yet. Upload a PDF to get started.") ]

                else
                    Table.table
                        [ { header = "Job ID", view = \job -> text (truncateJobId job.id) }
                        , { header = "Submitted", view = \job -> text (formatTime job.submittedAt) }
                        , { header = "Status", view = \job -> StatusBadge.statusBadge job.status }
                        , { header = "Actions", view = viewJobActions }
                        ]
                        jobsState.jobs
        ]


viewJobActions : Job -> Html Msg
viewJobActions job =
    case job.status of
        Complete ->
            case job.s3OutputKey of
                Just _ ->
                    Button.button Button.Primary "Download" (DownloadResult job.id)

                Nothing ->
                    text "—"

        Failed ->
            text "—"

        _ ->
            text "—"


truncateJobId : String -> String
truncateJobId jobId =
    if String.length jobId > 12 then
        String.left 8 jobId ++ "..."

    else
        jobId


formatTime : Time.Posix -> String
formatTime time =
    -- Simple formatting for now - just show "N minutes ago"
    -- In production, you'd use a proper time formatting library
    "recently"
