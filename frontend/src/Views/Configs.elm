module Views.Configs exposing (view)

import Components.Button as Button
import Css exposing (..)
import Css.Animations as Animations
import Html.Styled exposing (..)
import Html.Styled.Attributes as Attr exposing (css, href, placeholder, selected, type_, value)
import Html.Styled.Events exposing (onClick, onInput)
import Styles
import Time
import Types exposing (ApprovalStatus(..), ConfigFilters, ConfigFormState, ConfigsState, Configuration, Model, Msg(..), PdfModel, Route(..), Visibility(..), allPdfModels, configFormFromConfiguration, defaultPdfModel, emptyConfigFilters, filterConfigurations, hasActiveConfigFilters, initConfigFormState, isAdmin, modelMetadata, pdfModelToDisplayName, routeToPath)


view : Model -> Html Msg
view model =
    div
        [ css
            [ Styles.containerStyle
            , paddingTop Styles.spacing.xxxl
            , minHeight (vh 100)
            ]
        ]
        [ viewHeader model
        , viewContent model
        ]


viewHeader : Model -> Html Msg
viewHeader model =
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
                [ text "Manage your custom model configurations" ]
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
            , if isAdmin model then
                a
                    [ href (routeToPath AdminConfigs)
                    , css
                        [ padding2 Styles.spacing.sm Styles.spacing.base
                        , border3 (px 1) solid Styles.colors.warning
                        , borderRadius Styles.radius.md
                        , color Styles.colors.warning
                        , backgroundColor Styles.colors.warningMuted
                        , textDecoration none
                        , Css.fontSize Styles.fontSize.body
                        , Styles.transitions.base
                        , hover
                            [ backgroundColor Styles.colors.warning
                            , color Styles.colors.surface
                            ]
                        ]
                    ]
                    [ text "⚙️ Admin" ]

              else
                text ""
            , Button.button Button.Ghost "Sign Out" SignOutClicked
            ]
        ]


viewContent : Model -> Html Msg
viewContent model =
    case model.configs.editingConfig of
        Just formState ->
            viewConfigForm formState

        Nothing ->
            if model.configs.showCreateForm then
                viewModelSelector model

            else
                viewConfigList model


viewModelSelector : Model -> Html Msg
viewModelSelector model =
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
                [ text "Select Model" ]
            , Button.button Button.Secondary "Cancel" HideConfigForm
            ]
        , p
            [ css
                [ Styles.textSecondary
                , marginBottom Styles.spacing.xl
                ]
            ]
            [ text "Choose a model to create a custom configuration for:" ]
        , div
            [ css
                [ property "display" "grid"
                , property "grid-template-columns" "repeat(auto-fill, minmax(200px, 1fr))"
                , Styles.gap Styles.spacing.md
                ]
            ]
            (List.map viewModelOption allPdfModels)
        ]


viewModelOption : PdfModel -> Html Msg
viewModelOption pdfModel =
    let
        metadata =
            modelMetadata pdfModel
    in
    div
        [ css
            [ backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.lg
            , padding Styles.spacing.lg
            , cursor pointer
            , Styles.transitions.base
            , hover
                [ backgroundColor Styles.colors.surfaceRaised
                , borderColor Styles.colors.accent
                ]
            ]
        , onClick (ShowCreateConfigForm pdfModel)
        ]
        [ div
            [ css
                [ fontWeight Styles.fontWeights.medium
                , color Styles.colors.textPrimary
                , marginBottom Styles.spacing.xs
                ]
            ]
            [ text (pdfModelToDisplayName pdfModel) ]
        , div
            [ css
                [ Styles.textSmall
                , color Styles.colors.textTertiary
                ]
            ]
            [ text metadata.producer ]
        ]


viewConfigList : Model -> Html Msg
viewConfigList model =
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
                [ text "My Configurations" ]
            , div
                [ css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.md
                    ]
                ]
                [ Button.button Button.Secondary "Refresh" FetchConfigs
                , Button.button Button.Primary "+ New Config" (ShowCreateConfigForm defaultPdfModel)
                ]
            ]
        , viewFilters model.configs
        , case model.configs.error of
            Just err ->
                viewAlert Styles.colors.error Styles.colors.errorMuted err

            Nothing ->
                if model.configs.loading then
                    viewLoadingState

                else if List.isEmpty model.configs.configurations then
                    viewEmptyState

                else
                    viewConfigCards model
        , viewDeleteConfirmation model.configs.deleteConfirmation
        ]


viewFilters : ConfigsState -> Html Msg
viewFilters configsState =
    div
        [ css
            [ marginBottom Styles.spacing.xl
            , padding Styles.spacing.lg
            , backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.lg
            ]
        ]
        [ div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.lg
                , flexWrap wrap
                ]
            ]
            [ -- Search input
              div
                [ css [ flex (num 1), minWidth (px 200) ] ]
                [ input
                    [ type_ "text"
                    , placeholder "Search configurations..."
                    , value configsState.searchQuery
                    , onInput ConfigSearchChanged
                    , css
                        [ Css.width (pct 100)
                        , padding2 Styles.spacing.sm Styles.spacing.base
                        , backgroundColor Styles.colors.surfaceRaised
                        , border3 (px 1) solid Styles.colors.border
                        , borderRadius Styles.radius.md
                        , color Styles.colors.textPrimary
                        , fontFamilies Styles.fontStack
                        , Css.fontSize Styles.fontSize.body
                        , Styles.transitions.base
                        , hover [ borderColor Styles.colors.borderStrong ]
                        , focus [ borderColor Styles.colors.borderFocus, Styles.focusRing ]
                        , Css.pseudoElement "placeholder" [ color Styles.colors.textTertiary ]
                        ]
                    ]
                    []
                ]
            , -- Status filter
              div
                [ css [ Styles.flexRow, Styles.gap Styles.spacing.sm ] ]
                [ filterPill "Pending" (List.member PendingApproval configsState.filters.approvalStatuses) (ToggleConfigApprovalFilter PendingApproval) Styles.colors.warning
                , filterPill "Approved" (List.member Approved configsState.filters.approvalStatuses) (ToggleConfigApprovalFilter Approved) Styles.colors.success
                , filterPill "Rejected" (List.member Rejected configsState.filters.approvalStatuses) (ToggleConfigApprovalFilter Rejected) Styles.colors.error
                ]
            , -- Clear filters
              if hasActiveConfigFilters configsState.filters || not (String.isEmpty configsState.searchQuery) then
                Button.button Button.Ghost "Clear" ClearConfigFilters

              else
                text ""
            ]
        ]


filterPill : String -> Bool -> Msg -> Color -> Html Msg
filterPill label isActive msg accentColor =
    button
        [ onClick msg
        , css
            [ padding2 Styles.spacing.xs Styles.spacing.md
            , borderRadius Styles.radius.full
            , border3 (px 1) solid
                (if isActive then
                    accentColor

                 else
                    Styles.colors.border
                )
            , backgroundColor
                (if isActive then
                    Styles.colors.overlay

                 else
                    rgba 0 0 0 0
                )
            , color
                (if isActive then
                    accentColor

                 else
                    Styles.colors.textSecondary
                )
            , Css.fontSize Styles.fontSize.small
            , fontFamilies Styles.fontStack
            , cursor pointer
            , Styles.transitions.base
            , hover
                [ borderColor accentColor
                , color accentColor
                ]
            ]
        ]
        [ text label ]


viewConfigCards : Model -> Html Msg
viewConfigCards model =
    let
        filteredConfigs =
            filterConfigurations model.configs.filters model.configs.searchQuery model.configs.configurations
    in
    if List.isEmpty filteredConfigs then
        div
            [ css
                [ padding Styles.spacing.xxl
                , textAlign center
                , color Styles.colors.textSecondary
                ]
            ]
            [ text "No configurations match your filters" ]

    else
        div
            [ css
                [ displayFlex
                , flexDirection column
                , Styles.gap Styles.spacing.md
                ]
            ]
            (List.map (viewConfigCard model.currentTime) filteredConfigs)


viewConfigCard : Time.Posix -> Configuration -> Html Msg
viewConfigCard currentTime config =
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
        [ div
            [ css
                [ padding Styles.spacing.lg
                , Styles.flexBetween
                ]
            ]
            [ div
                [ css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.base
                    ]
                ]
                [ -- Config name
                  span
                    [ css
                        [ fontWeight Styles.fontWeights.medium
                        , color Styles.colors.textPrimary
                        ]
                    ]
                    [ text config.name ]
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
                    [ text (pdfModelToDisplayName config.model) ]
                , -- Approval status badge
                  viewApprovalBadge config.approvalStatus
                , -- Visibility badge
                  viewVisibilityBadge config.visibility
                ]
            , div
                [ css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.sm
                    ]
                ]
                [ Button.button Button.Ghost "Edit" (EditConfig config)
                , Button.button Button.Danger "Delete" (DeleteConfigClicked config.configId)
                ]
            ]
        , -- Description and details
          case config.description of
            Just desc ->
                div
                    [ css
                        [ padding2 zero Styles.spacing.lg
                        , paddingBottom Styles.spacing.lg
                        , Styles.textSmall
                        , color Styles.colors.textSecondary
                        ]
                    ]
                    [ text desc ]

            Nothing ->
                text ""
        , -- Rejection reason if rejected
          case ( config.approvalStatus, config.rejectionReason ) of
            ( Rejected, Just reason ) ->
                div
                    [ css
                        [ padding Styles.spacing.base
                        , backgroundColor Styles.colors.errorMuted
                        , borderTop3 (px 1) solid Styles.colors.error
                        ]
                    ]
                    [ div
                        [ css
                            [ Styles.textCaption
                            , color Styles.colors.error
                            , marginBottom Styles.spacing.xs
                            ]
                        ]
                        [ text "REJECTION REASON" ]
                    , div
                        [ css
                            [ Styles.textSmall
                            , color Styles.colors.error
                            ]
                        ]
                        [ text reason ]
                    ]

            _ ->
                text ""
        , -- Footer with metadata
          div
            [ css
                [ padding Styles.spacing.base
                , backgroundColor Styles.colors.surfaceRaised
                , borderTop3 (px 1) solid Styles.colors.border
                , Styles.flexBetween
                ]
            ]
            [ div
                [ css
                    [ Styles.textSmall
                    , color Styles.colors.textTertiary
                    ]
                ]
                [ text ("Used " ++ String.fromInt config.usageCount ++ " times") ]
            , div
                [ css
                    [ Styles.textSmall
                    , color Styles.colors.textTertiary
                    ]
                ]
                [ text ("Created " ++ formatRelativeTime currentTime config.createdAt) ]
            ]
        ]


viewApprovalBadge : ApprovalStatus -> Html msg
viewApprovalBadge status =
    let
        ( bgColor, textColor, label ) =
            case status of
                PendingApproval ->
                    ( Styles.colors.warningMuted, Styles.colors.warning, "Pending" )

                Approved ->
                    ( Styles.colors.successMuted, Styles.colors.success, "Approved" )

                Rejected ->
                    ( Styles.colors.errorMuted, Styles.colors.error, "Rejected" )
    in
    span
        [ css
            [ Css.fontSize Styles.fontSize.caption
            , fontWeight Styles.fontWeights.medium
            , color textColor
            , backgroundColor bgColor
            , padding2 Styles.spacing.xs Styles.spacing.sm
            , borderRadius Styles.radius.full
            , displayFlex
            , alignItems center
            , Styles.gap Styles.spacing.xs
            ]
        ]
        [ span
            [ css
                [ display inlineBlock
                , Css.width (px 6)
                , Css.height (px 6)
                , borderRadius (pct 50)
                , backgroundColor textColor
                ]
            ]
            []
        , text label
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
            [ text "Loading configurations..." ]
        ]


viewEmptyState : Html Msg
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
            [ text "⚙️" ]
        , h3
            [ css
                [ Styles.textH2
                , marginBottom Styles.spacing.sm
                ]
            ]
            [ text "No configurations yet" ]
        , p
            [ css
                [ Styles.textSecondary
                , margin zero
                , marginBottom Styles.spacing.xl
                ]
            ]
            [ text "Create a custom configuration to customize how models process your documents" ]
        , Button.button Button.Primary "Create Configuration" (ShowCreateConfigForm defaultPdfModel)
        ]


viewDeleteConfirmation : Maybe String -> Html Msg
viewDeleteConfirmation maybeConfigId =
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
                        [ text "Delete Configuration?" ]
                    , p
                        [ css
                            [ Styles.textSecondary
                            , marginBottom Styles.spacing.xl
                            ]
                        ]
                        [ text "This action cannot be undone. The configuration will be permanently deleted." ]
                    , div
                        [ css
                            [ Styles.flexRow
                            , justifyContent flexEnd
                            , Styles.gap Styles.spacing.md
                            ]
                        ]
                        [ Button.button Button.Secondary "Cancel" CancelDeleteConfig
                        , Button.button Button.Danger "Delete" (ConfirmDeleteConfig configId)
                        ]
                    ]
                ]

        Nothing ->
            text ""


viewConfigForm : ConfigFormState -> Html Msg
viewConfigForm formState =
    let
        isEditing =
            formState.configId /= Nothing

        title =
            if isEditing then
                "Edit Configuration"

            else
                "New Configuration"
    in
    div []
        [ div
            [ css
                [ Styles.flexBetween
                , marginBottom Styles.spacing.xl
                ]
            ]
            [ h2
                [ css
                    [ Styles.textH1
                    , margin zero
                    ]
                ]
                [ text title ]
            , Button.button Button.Secondary "Cancel" HideConfigForm
            ]
        , -- Model info
          div
            [ css
                [ marginBottom Styles.spacing.xl
                , padding Styles.spacing.lg
                , backgroundColor Styles.colors.accentMuted
                , border3 (px 1) solid Styles.colors.accent
                , borderRadius Styles.radius.lg
                ]
            ]
            [ span
                [ css [ Styles.textCaption, marginBottom Styles.spacing.xs, display block ] ]
                [ text "MODEL" ]
            , span
                [ css [ fontWeight Styles.fontWeights.medium, color Styles.colors.accent ] ]
                [ text (pdfModelToDisplayName formState.model) ]
            ]
        , -- Errors
          if not (List.isEmpty formState.errors) then
            div
                [ css
                    [ backgroundColor Styles.colors.errorMuted
                    , border3 (px 1) solid Styles.colors.error
                    , borderRadius Styles.radius.md
                    , padding Styles.spacing.base
                    , marginBottom Styles.spacing.xl
                    ]
                ]
                (List.map
                    (\err ->
                        div [ css [ color Styles.colors.error, Styles.textSmall ] ] [ text err ]
                    )
                    formState.errors
                )

          else
            text ""
        , -- Form sections
          div
            [ css
                [ backgroundColor Styles.colors.surface
                , border3 (px 1) solid Styles.colors.border
                , borderRadius Styles.radius.xl
                , padding Styles.spacing.xxl
                ]
            ]
            [ -- Basic info section
              viewFormSection "Basic Information"
                [ viewTextInput "Name" formState.name ConfigFormNameChanged "My Custom Config" False
                , viewTextareaInput "Description" formState.description ConfigFormDescriptionChanged "Optional description of this configuration" 3
                , viewVisibilitySelector formState.visibility
                ]
            , -- Inference params section
              viewFormSection "Inference Parameters"
                [ viewTextareaInput "Custom Prompt" formState.prompt ConfigFormPromptChanged "Enter custom instructions for the model..." 4
                , viewTextInput "Output Format" formState.outputFormat ConfigFormOutputFormatChanged "markdown, json, html" False
                ]
            , -- Infrastructure params section
              viewFormSection "Infrastructure Parameters"
                [ div
                    [ css
                        [ property "display" "grid"
                        , property "grid-template-columns" "repeat(2, 1fr)"
                        , Styles.gap Styles.spacing.lg
                        ]
                    ]
                    [ viewTextInput "CPU (vCPU units)" formState.cpu ConfigFormCpuChanged "256, 512, 1024, 2048, 4096, 8192, 16384" False
                    , viewTextInput "Memory (MiB)" formState.memoryMib ConfigFormMemoryChanged "512, 1024, 2048, etc." False
                    , viewTextInput "GPU Count" formState.gpuCount ConfigFormGpuChanged "0-4" False
                    , viewTextInput "Timeout (minutes)" formState.timeoutMinutes ConfigFormTimeoutChanged "1-180" False
                    , viewTextInput "Ephemeral Storage (GiB)" formState.ephemeralStorageGib ConfigFormEphemeralStorageChanged "21-200" False
                    , viewTextInput "EBS Volume (GB)" formState.ebsVolumeSizeGb ConfigFormEbsVolumeChanged "30-500" False
                    ]
                , viewCheckbox "Enable Spot Instances" formState.spotEnabled ConfigFormSpotEnabledChanged
                ]
            , -- Submit button
              div
                [ css
                    [ marginTop Styles.spacing.xxl
                    , Styles.flexRow
                    , justifyContent flexEnd
                    , Styles.gap Styles.spacing.md
                    ]
                ]
                [ Button.button Button.Secondary "Cancel" HideConfigForm
                , if formState.saving then
                    Button.buttonDisabled Button.Primary "Saving..."

                  else
                    Button.button Button.Primary
                        (if isEditing then
                            "Update Configuration"

                         else
                            "Create Configuration"
                        )
                        SaveConfig
                ]
            ]
        ]


viewFormSection : String -> List (Html msg) -> Html msg
viewFormSection title content =
    div
        [ css
            [ marginBottom Styles.spacing.xxl
            ]
        ]
        [ h3
            [ css
                [ Styles.textCaption
                , marginBottom Styles.spacing.lg
                , paddingBottom Styles.spacing.sm
                , borderBottom3 (px 1) solid Styles.colors.border
                ]
            ]
            [ text title ]
        , div [] content
        ]


viewTextInput : String -> String -> (String -> Msg) -> String -> Bool -> Html Msg
viewTextInput label val onChange placeholderText hasError =
    div
        [ css [ marginBottom Styles.spacing.lg ] ]
        [ Html.Styled.label
            [ css
                [ display block
                , marginBottom Styles.spacing.sm
                , Css.fontSize Styles.fontSize.small
                , fontWeight Styles.fontWeights.medium
                , color Styles.colors.textSecondary
                ]
            ]
            [ text label ]
        , input
            [ type_ "text"
            , value val
            , onInput onChange
            , placeholder placeholderText
            , css
                [ Css.width (pct 100)
                , padding2 Styles.spacing.md Styles.spacing.base
                , backgroundColor Styles.colors.surfaceRaised
                , border3 (px 1) solid
                    (if hasError then
                        Styles.colors.error

                     else
                        Styles.colors.border
                    )
                , borderRadius Styles.radius.md
                , color Styles.colors.textPrimary
                , fontFamilies Styles.fontStack
                , Css.fontSize Styles.fontSize.body
                , Styles.transitions.base
                , hover [ borderColor Styles.colors.borderStrong ]
                , focus [ borderColor Styles.colors.borderFocus, Styles.focusRing ]
                , Css.pseudoElement "placeholder" [ color Styles.colors.textTertiary ]
                ]
            ]
            []
        ]


viewTextareaInput : String -> String -> (String -> Msg) -> String -> Int -> Html Msg
viewTextareaInput label val onChange placeholderText rowCount =
    div
        [ css [ marginBottom Styles.spacing.lg ] ]
        [ Html.Styled.label
            [ css
                [ display block
                , marginBottom Styles.spacing.sm
                , Css.fontSize Styles.fontSize.small
                , fontWeight Styles.fontWeights.medium
                , color Styles.colors.textSecondary
                ]
            ]
            [ text label ]
        , textarea
            [ value val
            , onInput onChange
            , placeholder placeholderText
            , Attr.rows rowCount
            , css
                [ Css.width (pct 100)
                , padding Styles.spacing.base
                , backgroundColor Styles.colors.surfaceRaised
                , border3 (px 1) solid Styles.colors.border
                , borderRadius Styles.radius.md
                , color Styles.colors.textPrimary
                , fontFamilies Styles.fontStack
                , Css.fontSize Styles.fontSize.body
                , resize vertical
                , Styles.transitions.base
                , hover [ borderColor Styles.colors.borderStrong ]
                , focus [ borderColor Styles.colors.borderFocus, Styles.focusRing ]
                , Css.pseudoElement "placeholder" [ color Styles.colors.textTertiary ]
                ]
            ]
            []
        ]


viewVisibilitySelector : Visibility -> Html Msg
viewVisibilitySelector currentVisibility =
    div
        [ css [ marginBottom Styles.spacing.lg ] ]
        [ Html.Styled.label
            [ css
                [ display block
                , marginBottom Styles.spacing.sm
                , Css.fontSize Styles.fontSize.small
                , fontWeight Styles.fontWeights.medium
                , color Styles.colors.textSecondary
                ]
            ]
            [ text "Visibility" ]
        , div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.md
                ]
            ]
            [ visibilityOption Private "🔒 Private" "Only you can use this configuration" currentVisibility
            , visibilityOption Public "🌐 Public" "Anyone can discover and fork this configuration" currentVisibility
            ]
        ]


visibilityOption : Visibility -> String -> String -> Visibility -> Html Msg
visibilityOption visibility label description currentVisibility =
    let
        isSelected =
            visibility == currentVisibility
    in
    div
        [ css
            [ flex (num 1)
            , padding Styles.spacing.base
            , backgroundColor
                (if isSelected then
                    Styles.colors.accentMuted

                 else
                    Styles.colors.surfaceRaised
                )
            , border3 (px 1) solid
                (if isSelected then
                    Styles.colors.accent

                 else
                    Styles.colors.border
                )
            , borderRadius Styles.radius.md
            , cursor pointer
            , Styles.transitions.base
            , hover
                [ borderColor
                    (if isSelected then
                        Styles.colors.accent

                     else
                        Styles.colors.borderStrong
                    )
                ]
            ]
        , onClick (ConfigFormVisibilityChanged visibility)
        ]
        [ div
            [ css
                [ fontWeight Styles.fontWeights.medium
                , color
                    (if isSelected then
                        Styles.colors.accent

                     else
                        Styles.colors.textPrimary
                    )
                , marginBottom Styles.spacing.xs
                ]
            ]
            [ text label ]
        , div
            [ css
                [ Styles.textSmall
                , color Styles.colors.textTertiary
                ]
            ]
            [ text description ]
        ]


viewCheckbox : String -> Bool -> (Bool -> Msg) -> Html Msg
viewCheckbox label isChecked onChange =
    div
        [ css
            [ marginTop Styles.spacing.lg
            , Styles.flexRow
            , Styles.gap Styles.spacing.sm
            , cursor pointer
            ]
        , onClick (onChange (not isChecked))
        ]
        [ div
            [ css
                [ Css.width (px 20)
                , Css.height (px 20)
                , borderRadius Styles.radius.sm
                , border3 (px 1) solid
                    (if isChecked then
                        Styles.colors.accent

                     else
                        Styles.colors.border
                    )
                , backgroundColor
                    (if isChecked then
                        Styles.colors.accent

                     else
                        rgba 0 0 0 0
                    )
                , displayFlex
                , alignItems center
                , justifyContent center
                , Styles.transitions.base
                ]
            ]
            [ if isChecked then
                span [ css [ color Styles.colors.textInverse, Css.fontSize (px 12) ] ] [ text "✓" ]

              else
                text ""
            ]
        , span
            [ css
                [ Css.fontSize Styles.fontSize.body
                , color Styles.colors.textPrimary
                ]
            ]
            [ text label ]
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
