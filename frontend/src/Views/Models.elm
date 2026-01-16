module Views.Models exposing (view)

import Components.Button as Button
import Components.ModelCard exposing (modelCardExpanded)
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (css, href, type_)
import Html.Styled.Events exposing (onClick)
import Styles
import Types
    exposing
        ( Capability
        , ComputeType
        , Model
        , ModelCategory
        , ModelFilters
        , Msg(..)
        , PdfModel
        , Route(..)
        , allCapabilities
        , allCategories
        , allComputeTypes
        , allPdfModels
        , capabilityToString
        , categoryToString
        , computeTypeToString
        , defaultPdfModel
        , filterModels
        , hasActiveFilters
        , routeToPath
        )


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
        , div
            [ css
                [ marginTop Styles.spacing.xxl
                ]
            ]
            [ -- Page header
              div
                [ css
                    [ marginBottom Styles.spacing.xxl
                    ]
                ]
                [ div
                    [ css
                        [ Styles.flexBetween
                        , marginBottom Styles.spacing.sm
                        ]
                    ]
                    [ h1
                        [ css [ Styles.textDisplay ] ]
                        [ text "Model Catalog" ]
                    , button
                        [ onClick OpenModelPalette
                        , css
                            [ backgroundColor Styles.colors.surface
                            , border3 (px 1) solid Styles.colors.border
                            , borderRadius Styles.radius.md
                            , padding2 Styles.spacing.sm Styles.spacing.base
                            , color Styles.colors.textSecondary
                            , cursor pointer
                            , Css.fontSize Styles.fontSize.small
                            , fontFamilies Styles.fontStack
                            , Styles.transitions.fast
                            , hover
                                [ borderColor Styles.colors.borderStrong
                                , color Styles.colors.textPrimary
                                ]
                            ]
                        ]
                        [ text "⌘K Search" ]
                    ]
                , p
                    [ css
                        [ Styles.textSecondary
                        , maxWidth (px 600)
                        , margin zero
                        ]
                    ]
                    [ text "Discover and compare document processing models. Each model has unique strengths for different document types and use cases." ]
                ]

            -- Main content area
            , div
                [ css
                    [ property "display" "grid"
                    , property "grid-template-columns" "240px 1fr"
                    , Styles.gap Styles.spacing.xxl
                    ]
                ]
                [ -- Sidebar with filters
                  viewSidebar model.modelFilters

                -- Model cards
                , viewModelList model
                ]
            ]

        -- Comparison bar (if models selected)
        , if not (List.isEmpty model.comparisonModels) then
            viewComparisonBar model.comparisonModels

          else
            text ""
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
            ]
        , div
            [ css
                [ Styles.flexRow
                , Styles.gap Styles.spacing.md
                ]
            ]
            [ a
                [ href (routeToPath (Upload defaultPdfModel))
                , css
                    [ Styles.flexRow
                    , Styles.gap Styles.spacing.sm
                    , padding2 Styles.spacing.sm Styles.spacing.base
                    , backgroundColor Styles.colors.accent
                    , borderRadius Styles.radius.md
                    , color Styles.colors.textInverse
                    , textDecoration none
                    , Css.fontSize Styles.fontSize.body
                    , fontWeight Styles.fontWeights.medium
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


viewSidebar : ModelFilters -> Html Msg
viewSidebar filters =
    div
        [ css
            [ position sticky
            , top Styles.spacing.xxl
            ]
        ]
        [ -- Categories filter
          div
            [ css [ marginBottom Styles.spacing.xl ] ]
            [ h3
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.md
                    , marginTop zero
                    ]
                ]
                [ text "CATEGORIES" ]
            , div
                [ css [ Styles.flexColumn, Styles.gap Styles.spacing.sm ] ]
                (List.map (viewCategoryFilter filters.categories) allCategories)
            ]

        -- Compute type filter
        , div
            [ css [ marginBottom Styles.spacing.xl ] ]
            [ h3
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.md
                    , marginTop zero
                    ]
                ]
                [ text "COMPUTE TYPE" ]
            , div
                [ css [ Styles.flexColumn, Styles.gap Styles.spacing.sm ] ]
                (List.map (viewComputeTypeFilter filters.computeTypes) allComputeTypes)
            ]

        -- Capabilities filter
        , div
            [ css [ marginBottom Styles.spacing.xl ] ]
            [ h3
                [ css
                    [ Styles.textCaption
                    , marginBottom Styles.spacing.md
                    , marginTop zero
                    ]
                ]
                [ text "CAPABILITIES" ]
            , div
                [ css [ Styles.flexColumn, Styles.gap Styles.spacing.sm ] ]
                (List.map (viewCapabilityFilter filters.capabilities) allCapabilities)
            ]

        -- Clear filters
        , if hasActiveFilters filters then
            button
                [ onClick ClearModelFilters
                , css
                    [ backgroundColor transparent
                    , border zero
                    , color Styles.colors.accent
                    , cursor pointer
                    , Css.fontSize Styles.fontSize.small
                    , padding zero
                    , Styles.transitions.fast
                    , hover [ textDecoration underline ]
                    ]
                ]
                [ text "Clear all filters" ]

          else
            text ""
        ]


viewCategoryFilter : List ModelCategory -> ModelCategory -> Html Msg
viewCategoryFilter activeCategories category =
    let
        isActive =
            List.member category activeCategories
    in
    label
        [ css
            [ Styles.flexRow
            , Styles.gap Styles.spacing.sm
            , cursor pointer
            , color
                (if isActive then
                    Styles.colors.textPrimary

                 else
                    Styles.colors.textSecondary
                )
            , Styles.transitions.fast
            , hover [ color Styles.colors.textPrimary ]
            ]
        ]
        [ input
            [ type_ "checkbox"
            , onClick (ToggleCategoryFilter category)
            , css
                [ cursor pointer
                , property "accent-color" Styles.colors.accent.value
                ]
            ]
            []
        , text (categoryToString category)
        ]


viewCapabilityFilter : List Capability -> Capability -> Html Msg
viewCapabilityFilter activeCapabilities capability =
    let
        isActive =
            List.member capability activeCapabilities
    in
    label
        [ css
            [ Styles.flexRow
            , Styles.gap Styles.spacing.sm
            , cursor pointer
            , Css.fontSize Styles.fontSize.small
            , color
                (if isActive then
                    Styles.colors.textPrimary

                 else
                    Styles.colors.textSecondary
                )
            , Styles.transitions.fast
            , hover [ color Styles.colors.textPrimary ]
            ]
        ]
        [ input
            [ type_ "checkbox"
            , onClick (ToggleCapabilityFilter capability)
            , css
                [ cursor pointer
                , property "accent-color" Styles.colors.accent.value
                ]
            ]
            []
        , text (capabilityToString capability)
        ]


viewComputeTypeFilter : List ComputeType -> ComputeType -> Html Msg
viewComputeTypeFilter activeComputeTypes computeType =
    let
        isActive =
            List.member computeType activeComputeTypes

        icon =
            case computeType of
                Types.CpuCompute ->
                    "⚙"

                Types.GpuCompute ->
                    "⚡"
    in
    label
        [ css
            [ Styles.flexRow
            , Styles.gap Styles.spacing.sm
            , cursor pointer
            , color
                (if isActive then
                    Styles.colors.textPrimary

                 else
                    Styles.colors.textSecondary
                )
            , Styles.transitions.fast
            , hover [ color Styles.colors.textPrimary ]
            ]
        ]
        [ input
            [ type_ "checkbox"
            , onClick (ToggleComputeTypeFilter computeType)
            , css
                [ cursor pointer
                , property "accent-color" Styles.colors.accent.value
                ]
            ]
            []
        , span [] [ text icon ]
        , text (computeTypeToString computeType)
        ]


viewModelList : Model -> Html Msg
viewModelList model =
    let
        filteredModels =
            filterModels model.modelFilters model.modelSearchQuery allPdfModels
    in
    div []
        [ -- Results count
          div
            [ css
                [ Css.fontSize Styles.fontSize.small
                , color Styles.colors.textTertiary
                , marginBottom Styles.spacing.lg
                ]
            ]
            [ text
                (String.fromInt (List.length filteredModels)
                    ++ " model"
                    ++ (if List.length filteredModels /= 1 then
                            "s"

                        else
                            ""
                       )
                    ++ (if hasActiveFilters model.modelFilters then
                            " matching filters"

                        else
                            " available"
                       )
                )
            ]

        -- Model cards
        , div
            [ css [ Styles.flexColumn, Styles.gap Styles.spacing.lg ] ]
            (List.map (viewModelCard model) filteredModels)

        -- Empty state
        , if List.isEmpty filteredModels then
            div
                [ css
                    [ textAlign center
                    , padding Styles.spacing.huge
                    , color Styles.colors.textTertiary
                    ]
                ]
                [ div
                    [ css [ Css.fontSize (px 48), marginBottom Styles.spacing.md, opacity (num 0.5) ] ]
                    [ text "🔍" ]
                , text "No models match your filters"
                , div [ css [ marginTop Styles.spacing.md ] ]
                    [ button
                        [ onClick ClearModelFilters
                        , css
                            [ backgroundColor transparent
                            , border zero
                            , color Styles.colors.accent
                            , cursor pointer
                            , Css.fontSize Styles.fontSize.body
                            , padding zero
                            , hover [ textDecoration underline ]
                            ]
                        ]
                        [ text "Clear filters" ]
                    ]
                ]

          else
            text ""
        ]


viewModelCard : Model -> PdfModel -> Html Msg
viewModelCard model pdfModel =
    let
        -- Get the selected model from the route
        selectedModel =
            case model.route of
                Upload selected ->
                    selected

                _ ->
                    defaultPdfModel
    in
    modelCardExpanded
        { model = pdfModel
        , isSelected = pdfModel == selectedModel
        , isExpanded = model.expandedModelCard == Just pdfModel
        , onSelect = \m -> ModelSelected m
        , onToggleExpand = ToggleModelCardExpanded
        , onToggleComparison = ToggleModelComparison
        , isInComparison = List.member pdfModel model.comparisonModels
        }


viewComparisonBar : List PdfModel -> Html Msg
viewComparisonBar models =
    div
        [ css
            [ position fixed
            , bottom zero
            , left zero
            , right zero
            , backgroundColor Styles.colors.surfaceRaised
            , borderTop3 (px 1) solid Styles.colors.border
            , padding2 Styles.spacing.base Styles.spacing.xxl
            , Styles.flexBetween
            , Styles.shadows.lg
            , property "z-index" "100"
            ]
        ]
        [ div
            [ css [ Styles.flexRow, Styles.gap Styles.spacing.md ] ]
            [ span
                [ css
                    [ color Styles.colors.textSecondary
                    , Css.fontSize Styles.fontSize.small
                    ]
                ]
                [ text
                    (String.fromInt (List.length models)
                        ++ " model"
                        ++ (if List.length models /= 1 then
                                "s"

                            else
                                ""
                           )
                        ++ " selected for comparison"
                    )
                ]
            , button
                [ onClick ClearComparison
                , css
                    [ backgroundColor transparent
                    , border zero
                    , color Styles.colors.textTertiary
                    , cursor pointer
                    , Css.fontSize Styles.fontSize.small
                    , Styles.transitions.fast
                    , hover [ color Styles.colors.textSecondary ]
                    ]
                ]
                [ text "Clear" ]
            ]
        , Button.button Button.Primary "Compare Models" ClearComparison
        ]
