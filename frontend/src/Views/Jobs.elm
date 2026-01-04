module Views.Jobs exposing (view)

import Browser
import Components.Button as Button
import Components.StatusBadge as StatusBadge
import Components.Timeline as Timeline
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href)
import Styles
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
                    div
                        [ css
                            [ displayFlex
                            , flexDirection column
                            , property "gap" "16px"
                            ]
                        ]
                        (List.map viewJobCard jobsState.jobs)
        ]


viewJobCard : Job -> Html Msg
viewJobCard job =
    div
        [ css
            [ border3 (px 1) solid Styles.colors.border
            , backgroundColor Styles.colors.surface
            , padding Styles.spacing.lg
            , property "border-radius" "4px"
            ]
        ]
        [ -- Header with job ID and status
          div
            [ css
                [ displayFlex
                , justifyContent spaceBetween
                , alignItems center
                , marginBottom Styles.spacing.md
                , paddingBottom Styles.spacing.md
                , borderBottom3 (px 1) solid Styles.colors.border
                ]
            ]
            [ div []
                [ div
                    [ css
                        [ fontWeight Styles.fontWeight.semibold
                        , color Styles.colors.textPrimary
                        , marginBottom (px 4)
                        ]
                    ]
                    [ text ("Job " ++ truncateJobId job.id) ]
                , div
                    [ css
                        [ fontSize Styles.fontSize.small
                        , color Styles.colors.textSecondary
                        , fontFamily monospace
                        ]
                    ]
                    [ text job.s3InputKey ]
                ]
            , div
                [ css
                    [ displayFlex
                    , alignItems center
                    , property "gap" "12px"
                    ]
                ]
                [ StatusBadge.statusBadge job.status
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
        , -- Timeline
          Timeline.timeline job
        , -- Error message if present
          case job.error of
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


truncateJobId : String -> String
truncateJobId jobId =
    if String.length jobId > 12 then
        String.left 8 jobId ++ "..."

    else
        jobId
