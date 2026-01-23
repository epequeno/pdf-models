module Components.ModelPalette exposing (modelPalette)

import Components.PerformanceIndicator exposing (performanceIndicatorCompact)
import Css exposing (..)
import Html.Styled exposing (..)
import Html.Styled.Attributes exposing (autofocus, css, id, placeholder, type_, value)
import Html.Styled.Events exposing (onClick, onInput, onMouseEnter, stopPropagationOn)
import Json.Decode
import Styles
import Types
    exposing
        ( ComputeType(..)
        , ModelFilters
        , Msg(..)
        , PdfModel
        , allPdfModels
        , categoryToString
        , computeTypeToString
        , filterModels
        , modelMetadata
        , pdfModelToDisplayName
        )


{-| Command palette modal for quick model selection
-}
modelPalette :
    { isOpen : Bool
    , searchQuery : String
    , selectedModel : PdfModel
    , hoveredModel : Maybe PdfModel
    , filters : ModelFilters
    }
    -> Html Msg
modelPalette config =
    if not config.isOpen then
        text ""

    else
        let
            filteredModels =
                filterModels config.filters config.searchQuery allPdfModels
        in
        div
            [ css [ Styles.modalOverlay ]
            , onClick CloseModelPalette
            ]
            [ div
                [ css [ paletteContainerStyle ]
                , onClickStopPropagation
                ]
                [ -- Search input
                  div [ css [ searchContainerStyle ] ]
                    [ span [ css [ searchIconStyle ] ] [ text ">" ]
                    , input
                        [ type_ "text"
                        , value config.searchQuery
                        , onInput ModelSearchChanged
                        , placeholder "Search models..."
                        , autofocus True
                        , id "model-palette-search"
                        , css [ searchInputStyle ]
                        ]
                        []
                    , keyboardHint
                    ]

                -- Results list
                , div [ css [ resultsContainerStyle ] ]
                    (if List.isEmpty filteredModels then
                        [ emptyState config.searchQuery ]

                     else
                        List.indexedMap
                            (\index model ->
                                paletteItem
                                    { model = model
                                    , isSelected = model == config.selectedModel
                                    , isHovered = config.hoveredModel == Just model
                                    , index = index
                                    }
                            )
                            filteredModels
                    )

                -- Footer
                , div [ css [ footerStyle ] ]
                    [ footerHint "enter" "select"
                    , footerHint "esc" "close"
                    ]
                ]
            ]


paletteItem :
    { model : PdfModel
    , isSelected : Bool
    , isHovered : Bool
    , index : Int
    }
    -> Html Msg
paletteItem config =
    let
        metadata =
            modelMetadata config.model

        itemStyle =
            batch
                [ Styles.flexBetween
                , padding2 Styles.spacing.md Styles.spacing.lg
                , cursor pointer
                , Styles.transitions.fast
                , backgroundColor
                    (if config.isHovered then
                        Styles.colors.overlay

                     else
                        rgba 0 0 0 0
                    )
                , borderLeft3 (px 2)
                    solid
                    (if config.isSelected then
                        Styles.colors.accent

                     else if config.isHovered then
                        Styles.colors.borderStrong

                     else
                        rgba 0 0 0 0
                    )
                , hover
                    [ backgroundColor Styles.colors.overlay
                    ]
                ]
    in
    div
        [ css [ itemStyle ]
        , onClick (ModelSelected config.model)
        , onMouseEnter (ModelHovered (Just config.model))
        ]
        [ div [ css [ Styles.flexRow, Styles.gap Styles.spacing.md ] ]
            [ -- Model name
              span
                [ css
                    [ fontWeight
                        (if config.isSelected then
                            Styles.fontWeights.semibold

                         else
                            Styles.fontWeights.medium
                        )
                    , color
                        (if config.isSelected then
                            Styles.colors.accent

                         else
                            Styles.colors.textPrimary
                        )
                    ]
                ]
                [ text (modelName config.model) ]

            -- Producer badge
            , span
                [ css
                    [ Css.fontSize Styles.fontSize.caption
                    , color Styles.colors.textTertiary
                    ]
                ]
                [ text metadata.producer ]

            -- Category pill
            , span
                [ css [ Styles.categoryPillStyle (categoryToString metadata.category), Css.fontSize (px 10) ] ]
                [ text (categoryToString metadata.category) ]

            -- Compute type badge
            , computeTypeBadgeSmall metadata.computeType
            ]

        -- Performance indicator
        , div [ css [ Styles.flexRow, Styles.gap Styles.spacing.sm ] ]
            [ performanceIndicatorCompact metadata.performanceTier
            , if config.isSelected then
                span [ css [ color Styles.colors.accent, Css.fontSize (px 12) ] ] [ text "current" ]

              else
                text ""
            ]
        ]


emptyState : String -> Html msg
emptyState query =
    div
        [ css
            [ padding Styles.spacing.xxl
            , textAlign center
            , color Styles.colors.textTertiary
            ]
        ]
        [ div [ css [ marginBottom Styles.spacing.sm ] ] [ text "No models found" ]
        , div [ css [ Css.fontSize Styles.fontSize.caption ] ]
            [ text ("No results for \"" ++ query ++ "\"") ]
        ]


keyboardHint : Html msg
keyboardHint =
    div
        [ css
            [ Styles.flexRow
            , Styles.gap Styles.spacing.xs
            , color Styles.colors.textTertiary
            , Css.fontSize Styles.fontSize.caption
            ]
        ]
        [ kbd "K" ]


footerHint : String -> String -> Html msg
footerHint key action =
    div
        [ css
            [ Styles.flexRow
            , Styles.gap Styles.spacing.xs
            , color Styles.colors.textTertiary
            , Css.fontSize Styles.fontSize.caption
            ]
        ]
        [ kbd key
        , text action
        ]


kbd : String -> Html msg
kbd key =
    span
        [ css
            [ padding2 (px 2) Styles.spacing.xs
            , backgroundColor Styles.colors.surface
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.sm
            , fontFamilies Styles.codeFontStack
            , Css.fontSize (px 10)
            , color Styles.colors.textSecondary
            , textTransform uppercase
            ]
        ]
        [ text key ]


modelName : PdfModel -> String
modelName model =
    let
        fullName =
            pdfModelToDisplayName model
    in
    case String.split " (" fullName of
        name :: _ ->
            name

        _ ->
            fullName


onClickStopPropagation : Attribute Msg
onClickStopPropagation =
    stopPropagationOn "click"
        (Json.Decode.succeed ( ModelHovered Nothing, True ))


paletteContainerStyle : Style
paletteContainerStyle =
    batch
        [ backgroundColor Styles.colors.surfaceRaised
        , border3 (px 1) solid Styles.colors.border
        , borderRadius Styles.radius.xl
        , Styles.shadows.lg
        , maxWidth (px 520)
        , Css.width (pct 90)
        , maxHeight (vh 60)
        , overflow hidden
        , displayFlex
        , flexDirection column
        ]


searchContainerStyle : Style
searchContainerStyle =
    batch
        [ Styles.flexRow
        , padding2 Styles.spacing.md Styles.spacing.lg
        , borderBottom3 (px 1) solid Styles.colors.border
        , Styles.gap Styles.spacing.md
        ]


searchIconStyle : Style
searchIconStyle =
    batch
        [ color Styles.colors.accent
        , fontFamilies Styles.codeFontStack
        , fontWeight Styles.fontWeights.semibold
        ]


searchInputStyle : Style
searchInputStyle =
    batch
        [ flex (num 1)
        , backgroundColor transparent
        , border zero
        , color Styles.colors.textPrimary
        , Css.fontSize Styles.fontSize.body
        , outline none
        , Css.pseudoElement "placeholder"
            [ color Styles.colors.textTertiary
            ]
        ]


resultsContainerStyle : Style
resultsContainerStyle =
    batch
        [ flex (num 1)
        , overflowY auto
        , Styles.customScrollbar
        ]


footerStyle : Style
footerStyle =
    batch
        [ Styles.flexRow
        , justifyContent flexEnd
        , Styles.gap Styles.spacing.lg
        , padding2 Styles.spacing.sm Styles.spacing.lg
        , borderTop3 (px 1) solid Styles.colors.border
        , backgroundColor Styles.colors.surface
        ]


computeTypeBadgeSmall : ComputeType -> Html msg
computeTypeBadgeSmall computeType =
    let
        ( icon, bgColor, textColor ) =
            case computeType of
                CpuCompute ->
                    ( "⚙", Styles.colors.surface, Styles.colors.textTertiary )

                GpuCompute ->
                    ( "⚡", Styles.colors.warningMuted, Styles.colors.warning )
    in
    span
        [ css
            [ Css.fontSize (px 10)
            , padding2 (px 2) Styles.spacing.xs
            , backgroundColor bgColor
            , border3 (px 1) solid Styles.colors.border
            , borderRadius Styles.radius.sm
            , color textColor
            ]
        ]
        [ text (icon ++ " " ++ computeTypeToString computeType) ]
