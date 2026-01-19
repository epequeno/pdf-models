module Views.AdminConfigs exposing (view)

import Components.Button as Button
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, href, placeholder, type_, value)
import Html.Styled.Events exposing (onClick, onInput)
import Styles
import Time
import Types exposing (AdminConfigsState, ApprovalStatus(..), Configuration, Model, Msg(..), PdfModel, Route(..), Visibility(..), defaultPdfModel, pdfModelToDisplayName, routeToPath)


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
        , viewContent model
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
                [ text "Admin Panel - Review and approve configurations" ]
            ]
        , div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.md
                ]
            ]
            [ a
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
                [ text "My Configs" ]
            , a
                [ href (routeToPath Jobs)
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
                [ text "Dashboard" ]
            , Button.button Button.Ghost "Sign Out" SignOutClicked
            ]
        ]


viewContent : Model -> Html Msg
viewContent model =
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
                [ text "Pending Configurations" ]
            , Button.button Button.Secondary "Refresh" FetchPendingConfigs
            ]
        , case model.adminConfigs.error of
            Just err ->
                viewAlert Styles.colors.error Styles.colors.errorMuted err

            Nothing ->
                if model.adminConfigs.loading then
                    viewLoadingState

                else if List.isEmpty model.adminConfigs.pendingConfigs then
                    viewEmptyState

                else
                    viewPendingConfigCards model
        , viewApproveConfirmation model.adminConfigs.approveConfirmation
        , viewRejectModal model.adminConfigs
        ]



viewPendingConfigCards : Model -> Html Msg
viewPendingConfigCards model =
    div
        [ css
            [ displayFlex
            , flexDirection column
            , Styles.gap Styles.spacing.md
            ]
        ]
        (List.map (viewPendingConfigCard model.currentTime) model.adminConfigs.pendingConfigs)


viewPendingConfigCard : Time.Posix -> Configuration -> Html Msg
viewPendingConfigCard currentTime config =
    div
        [ css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.lg
            , overflow Css.hidden
            , Styles.transitions.base
            , hover [ borderColor Styles.colors.borderStrong ]
            ]
        ]
        [ -- Header with name and model
          div
            [ css
                [ padding Styles.spacing.lg
                , Styles.flexBetween
                , borderBottom3 (px 1) solid Styles.colors.border
                ]
            ]
            [ div
                [ css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.base
                    ]
                ]
                [ span
                    [ css
                        [ fontWeight Styles.fontWeights.medium
                        , color Styles.colors.textPrimary
                        , Css.fontSize Styles.fontSize.h2
                        ]
                    ]
                    [ text config.name ]
                , span
                    [ css
                        [ Css.fontSize Styles.fontSize.caption
                        , fontWeight Styles.fontWeights.medium
                        , color Styles.colors.accent
                        , backgroundColor Styles.colors.accentMuted
                        , padding2 Styles.spacing.xs Styles.spacing.sm
                        , borderRadius Styles.radius.full
                        ]
                    ]
                    [ text (pdfModelToDisplayName config.model) ]
                , viewVisibilityBadge config.visibility
                ]
            , div
                [ css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.sm
                    ]
                ]
                [ Button.button Button.Primary "Approve" (ShowApproveConfirmation config.configId)
                , Button.button Button.Danger "Reject" (ShowRejectModal config.configId)
                ]
            ]
        , -- User info
          div
            [ css
                [ padding Styles.spacing.lg
                , backgroundColor Styles.colors.surfaceRaised
                ]
            ]
            [ div
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.sm
                    ]
                ]
                [ text "SUBMITTED BY" ]
            , div
                [ css
                    [ Styles.textSmall
                    , color Styles.colors.textSecondary
                ]
                ]
                [ text ("User ID: " ++ config.userId) ]
            ]
        , -- Description
          case config.description of
            Just desc ->
                div
                    [ css
                        [ padding Styles.spacing.lg
                        , borderBottom3 (px 1) solid Styles.colors.border
                        ]
                    ]
                    [ div
                        [ css
                            [ Styles.textCaption
                            , marginBottom Styles.spacing.sm
                            ]
                        ]
                        [ text "DESCRIPTION" ]
                    , div
                        [ css
                            [ Styles.textSmall
                            , color Styles.colors.textSecondary
                            ]
                        ]
                        [ text desc ]
                    ]

            Nothing ->
                text ""
        , -- Parameters section
          div
            [ css
                [ padding Styles.spacing.lg
                ]
            ]
            [ div
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.md
                    ]
                ]
                [ text "CONFIGURATION PARAMETERS" ]
            , div
                [ css
                    [ property "display" "grid"
                    , property "grid-template-columns" "repeat(auto-fill, minmax(200px, 1fr))"
                    , Styles.gap Styles.spacing.md
                    ]
                ]
                [ viewParamCard "Inference Parameters" (viewInferenceParams config)
                , viewParamCard "Infrastructure Parameters" (viewInfraParams config)
                , viewParamCard "Resource Estimate" (viewResourceEstimate config)
                ]
            ]
        , -- Footer with timestamp
          div
            [ css
                [ padding Styles.spacing.base
                , backgroundColor Styles.colors.surfaceRaised
                , borderTop3 (px 1) solid Styles.colors.border
                , Styles.textSmall
                , color Styles.colors.textTertiary
                ]
            ]
            [ text ("Submitted " ++ formatRelativeTime currentTime config.createdAt) ]
        ]


viewParamCard : String -> Html msg -> Html msg
viewParamCard title content =
    div
        [ css
            [ backgroundColor Styles.colors.surfaceRaised
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.md
            , padding Styles.spacing.base
            ]
        ]
        [ div
            [ css
                [ Styles.textCaption
                , marginBottom Styles.spacing.sm
                , color Styles.colors.textTertiary
                ]
            ]
            [ text title ]
        , content
        ]


viewInferenceParams : Configuration -> Html msg
viewInferenceParams config =
    div
        [ css
            [ Styles.textSmall
            , color Styles.colors.textSecondary
            ]
        ]
        [ case config.inferenceParams.prompt of
            Just prompt ->
                div [ css [ marginBottom Styles.spacing.xs ] ]
                    [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Prompt: " ]
                    , text (truncateText 50 prompt)
                    ]

            Nothing ->
                text ""
        , case config.inferenceParams.outputFormat of
            Just format ->
                div [ css [ marginBottom Styles.spacing.xs ] ]
                    [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Format: " ]
                    , text format
                    ]

            Nothing ->
                text ""
        , if List.isEmpty config.inferenceParams.customEnvVars then
            text ""

          else
            div []
                [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Custom Vars: " ]
                , text (String.fromInt (List.length config.inferenceParams.customEnvVars))
                ]
        , if config.inferenceParams.prompt == Nothing && config.inferenceParams.outputFormat == Nothing && List.isEmpty config.inferenceParams.customEnvVars then
            span [ css [ color Styles.colors.textTertiary, fontStyle italic ] ] [ text "Default" ]

          else
            text ""
        ]


viewInfraParams : Configuration -> Html msg
viewInfraParams config =
    let
        params =
            config.infraParams
    in
    div
        [ css
            [ Styles.textSmall
            , color Styles.colors.textSecondary
            ]
        ]
        [ case params.cpu of
            Just cpu ->
                div [ css [ marginBottom Styles.spacing.xs ] ]
                    [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "CPU: " ]
                    , text (String.fromInt cpu ++ " units")
                    ]

            Nothing ->
                text ""
        , case params.memoryMib of
            Just mem ->
                div [ css [ marginBottom Styles.spacing.xs ] ]
                    [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Memory: " ]
                    , text (String.fromInt mem ++ " MiB")
                    ]

            Nothing ->
                text ""
        , case params.gpuCount of
            Just gpu ->
                div [ css [ marginBottom Styles.spacing.xs ] ]
                    [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "GPU: " ]
                    , text (String.fromInt gpu)
                    ]

            Nothing ->
                text ""
        , case params.timeoutMinutes of
            Just timeout ->
                div [ css [ marginBottom Styles.spacing.xs ] ]
                    [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Timeout: " ]
                    , text (String.fromInt timeout ++ " min")
                    ]

            Nothing ->
                text ""
        , case params.ephemeralStorageGib of
            Just storage ->
                div [ css [ marginBottom Styles.spacing.xs ] ]
                    [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Storage: " ]
                    , text (String.fromInt storage ++ " GiB")
                    ]

            Nothing ->
                text ""
        , case params.spotEnabled of
            Just True ->
                div [ css [ marginBottom Styles.spacing.xs ] ]
                    [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Spot: " ]
                    , text "Enabled"
                    ]

            _ ->
                text ""
        , if params.cpu == Nothing && params.memoryMib == Nothing && params.gpuCount == Nothing then
            span [ css [ color Styles.colors.textTertiary, fontStyle italic ] ] [ text "Default" ]

          else
            text ""
        ]


viewResourceEstimate : Configuration -> Html msg
viewResourceEstimate config =
    let
        params =
            config.infraParams

        -- Simple cost estimation (rough approximation)
        cpuCost =
            Maybe.withDefault 256 params.cpu |> toFloat |> (\c -> c / 1024 * 0.04)

        memoryCost =
            Maybe.withDefault 512 params.memoryMib |> toFloat |> (\m -> m / 1024 * 0.004)

        gpuCost =
            Maybe.withDefault 0 params.gpuCount |> toFloat |> (\g -> g * 0.50)

        hourlyEstimate =
            cpuCost + memoryCost + gpuCost

        hasGpu =
            Maybe.withDefault 0 params.gpuCount > 0
    in
    div
        [ css
            [ Styles.textSmall
            , color Styles.colors.textSecondary
            ]
        ]
        [ div [ css [ marginBottom Styles.spacing.xs ] ]
            [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Est. Cost: " ]
            , text ("~$" ++ String.left 5 (String.fromFloat hourlyEstimate) ++ "/hr")
            ]
        , div [ css [ marginBottom Styles.spacing.xs ] ]
            [ span [ css [ fontWeight Styles.fontWeights.medium ] ] [ text "Compute: " ]
            , text
                (if hasGpu then
                    "GPU Instance"

                 else
                    "Fargate"
                )
            ]
        , div
            [ css
                [ marginTop Styles.spacing.sm
                , padding Styles.spacing.xs
                , backgroundColor
                    (if hasGpu then
                        Styles.colors.warningMuted

                     else
                        Styles.colors.successMuted
                    )
                , borderRadius Styles.radius.sm
                , Css.fontSize Styles.fontSize.caption
                , color
                    (if hasGpu then
                        Styles.colors.warning

                     else
                        Styles.colors.success
                    )
                ]
            ]
            [ text
                (if hasGpu then
                    "⚠️ GPU resources"

                 else
                    "✓ Standard resources"
                )
            ]
        ]


viewVisibilityBadge : Visibility -> Html msg
viewVisibilityBadge visibility =
    let
        ( icon, label ) =
            case visibility of
                Private ->
                    ( "🔒", "Private" )

                Public ->
                    ( "🌐", "Public" )
    in
    span
        [ css
            [ Css.fontSize Styles.fontSize.caption
            , color Styles.colors.textTertiary
            , Styles.flexRow
            , Styles.gap Styles.spacing.xs
            ]
        ]
        [ text icon
        , text label
        ]


viewAlert : Color -> Color -> String -> Html msg
viewAlert textColor bgColor message =
    div
        [ css
            [ backgroundColor bgColor
            , border3 (px 1) solid textColor
            , borderRadius Styles.radius.md
            , padding Styles.spacing.base
            , marginBottom Styles.spacing.lg
            ]
        ]
        [ span
            [ css [ color textColor, Css.fontSize Styles.fontSize.body ] ]
            [ text message ]
        ]


viewLoadingState : Html msg
viewLoadingState =
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
            [ text "..." ]
        , h3
            [ css
                [ Styles.textH2
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ text "Loading pending configurations..." ]
        ]


viewEmptyState : Html msg
viewEmptyState =
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
            [ text "✓" ]
        , h3
            [ css
                [ Styles.textH2
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ text "No pending configurations" ]
        , p
            [ css
                [ Styles.textSecondary
                , margin zero
                ]
            ]
            [ text "All configurations have been reviewed" ]
        ]


viewApproveConfirmation : Maybe String -> Html Msg
viewApproveConfirmation maybeConfigId =
    case maybeConfigId of
        Just configId ->
            div
                [ css
                    [ position fixed
                    , top zero
                    , left zero
                    , right zero
                    , bottom zero
                    , backgroundColor (rgba 0 0 0 0.7)
                    , displayFlex
                    , alignItems center
                    , justifyContent center
                    , property "z-index" "1000"
                    , property "backdrop-filter" "blur(4px)"
                    ]
                ]
                [ div
                    [ css
                        [ backgroundColor Styles.colors.surfaceRaised
                        , border3 (px 1) solid Styles.colors.border
                        , borderRadius Styles.radius.xl
                        , padding Styles.spacing.xxl
                        , maxWidth (px 400)
                        , Css.width (pct 90)
                        ]
                    ]
                    [ h3
                        [ css
                            [ Styles.textH2
                            , marginBottom Styles.spacing.md
                            ]
                        ]
                        [ text "Approve Configuration?" ]
                    , p
                        [ css
                            [ Styles.textSecondary
                            , marginBottom Styles.spacing.xl
                            ]
                        ]
                        [ text "This will register a new ECS task definition and allow the user to submit jobs with this configuration." ]
                    , div
                        [ css
                            [ Styles.flexRow
                            , justifyContent flexEnd
                            , Styles.gap Styles.spacing.md
                            ]
                        ]
                        [ Button.button Button.Secondary "Cancel" CancelApproveConfig
                        , Button.button Button.Primary "Approve" (ConfirmApproveConfig configId)
                        ]
                    ]
                ]

        Nothing ->
            text ""


viewRejectModal : AdminConfigsState -> Html Msg
viewRejectModal adminState =
    case adminState.rejectingConfigId of
        Just configId ->
            div
                [ css
                    [ position fixed
                    , top zero
                    , left zero
                    , right zero
                    , bottom zero
                    , backgroundColor (rgba 0 0 0 0.7)
                    , displayFlex
                    , alignItems center
                    , justifyContent center
                    , property "z-index" "1000"
                    , property "backdrop-filter" "blur(4px)"
                    ]
                ]
                [ div
                    [ css
                        [ backgroundColor Styles.colors.surfaceRaised
                        , border3 (px 1) solid Styles.colors.border
                        , borderRadius Styles.radius.xl
                        , padding Styles.spacing.xxl
                        , maxWidth (px 500)
                        , Css.width (pct 90)
                        ]
                    ]
                    [ h3
                        [ css
                            [ Styles.textH2
                            , marginBottom Styles.spacing.md
                            ]
                        ]
                        [ text "Reject Configuration" ]
                    , p
                        [ css
                            [ Styles.textSecondary
                            , marginBottom Styles.spacing.lg
                            ]
                        ]
                        [ text "Please provide a reason for rejection. This will be shown to the user." ]
                    , textarea
                        [ value adminState.rejectionReason
                        , onInput RejectReasonChanged
                        , placeholder "Enter rejection reason..."
                        , Attr.rows 4
                        , css
                            [ Css.width (pct 100)
                            , padding Styles.spacing.base
                            , backgroundColor Styles.colors.surfaceRaised
                            , border3 (px 1) solid Styles.colors.border
                            , borderRadius Styles.radius.md
                            , color Styles.colors.textPrimary
                            , fontFamilies Styles.fontStack
                            , Css.fontSize Styles.fontSize.body
                            , marginBottom Styles.spacing.lg
                            , resize vertical
                            , Styles.transitions.base
                            , hover [ borderColor Styles.colors.borderStrong ]
                            , focus [ borderColor Styles.colors.borderFocus, Styles.focusRing ]
                            ]
                        ]
                        []
                    , div
                        [ css
                            [ Styles.flexRow
                            , justifyContent flexEnd
                            , Styles.gap Styles.spacing.md
                            ]
                        ]
                        [ Button.button Button.Secondary "Cancel" CancelRejectConfig
                        , if String.isEmpty (String.trim adminState.rejectionReason) then
                            Button.buttonDisabled Button.Danger "Reject"

                          else
                            Button.button Button.Danger "Reject" (ConfirmRejectConfig configId adminState.rejectionReason)
                        ]
                    ]
                ]

        Nothing ->
            text ""



-- HELPERS


truncateText : Int -> String -> String
truncateText maxLen text =
    if String.length text > maxLen then
        String.left maxLen text ++ "..."

    else
        text


formatRelativeTime : Time.Posix -> Time.Posix -> String
formatRelativeTime now then_ =
    let
        diffMs =
            Time.posixToMillis now - Time.posixToMillis then_

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
        String.fromInt diffDays ++ " day" ++ pluralize diffDays ++ " ago"

    else if diffHours > 0 then
        String.fromInt diffHours ++ " hour" ++ pluralize diffHours ++ " ago"

    else if diffMinutes > 0 then
        String.fromInt diffMinutes ++ " minute" ++ pluralize diffMinutes ++ " ago"

    else
        "just now"


pluralize : Int -> String
pluralize n =
    if n == 1 then
        ""

    else
        "s"
